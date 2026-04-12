// This file is part of MediaGate.
// Copyright © 2025 Kemal Sanlı
//
// MediaGate is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// MediaGate is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
// A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// MediaGate. If not, see <https://www.gnu.org/licenses/>.

import UIKit
import UniformTypeIdentifiers
import MediaGateKit
import SwiftFFmpeg

/// Maximum file size (in bytes) for attempting video conversion in the extension.
/// Files larger than this are queued for the main app.
private let maxVideoSizeForExtension: UInt64 = 15_000_000 // 15 MB

/// Maximum time (in seconds) to attempt a conversion in the extension.
private let extensionConversionTimeout: TimeInterval = 20

/// Action Extension — appears in the share sheet's "Actions" row as "MediaGate ile Kaydet".
///
/// Performs the same conversion logic as the Share Extension:
/// 1. Always copy the file to the shared container first.
/// 2. Attempt in-extension conversion for images and small videos.
/// 3. On success → save to Photos, remove from pending queue.
/// 4. On failure → file remains in pending queue for the main app.
class ActionViewController: UIViewController {

    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let resultIcon = UIImageView()
    private let detailLabel = UILabel()

    private let formatDetector = FormatDetector()
    private let imageConverter = NativeImageConverter()
    private let gallerySaver = GallerySaver()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processInputItems()
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = .systemBackground

        let stack = UIStackView(arrangedSubviews: [spinner, resultIcon, statusLabel, detailLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])

        spinner.startAnimating()
        spinner.color = .label

        resultIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 48)
        resultIcon.isHidden = true

        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.text = NSLocalizedString("Processing…", comment: "")

        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.isHidden = true
    }

    @MainActor
    private func showResult(icon: String, color: UIColor, title: String, detail: String?) {
        spinner.stopAnimating()
        spinner.isHidden = true
        resultIcon.image = UIImage(systemName: icon)
        resultIcon.tintColor = color
        resultIcon.isHidden = false
        statusLabel.text = title
        if let detail {
            detailLabel.text = detail
            detailLabel.isHidden = false
        }
    }

    // MARK: - Processing

    private func processInputItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeRequest()
            return
        }

        let providers = extensionItems
            .compactMap(\.attachments)
            .flatMap { $0 }
            .filter { provider in
                provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.item.identifier)
            }

        guard !providers.isEmpty else {
            Task { @MainActor in
                showResult(icon: "questionmark.circle", color: .systemGray, title: NSLocalizedString("No supported files", comment: ""), detail: nil)
                try? await Task.sleep(for: .seconds(1.5))
                completeRequest()
            }
            return
        }

        Task {
            // Global safety timeout — extension MUST dismiss within 25 seconds
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(25))
                SharedConstants.hasPendingConversions = true
                completeRequest()
            }
            defer { timeoutTask.cancel() }

            var savedCount = 0
            var queuedCount = 0

            for (i, provider) in providers.enumerated() {
                await MainActor.run {
                    statusLabel.text = String.localizedStringWithFormat(
                        NSLocalizedString("Processing %d of %d…", comment: ""), i + 1, providers.count
                    )
                }

                do {
                    let (tempURL, typeHint) = try await loadFileURL(from: provider)

                    // Pre-check: reject files too large
                    let fileSize = FileManager.default.fileSize(at: tempURL)
                    if fileSize > SafetyChecks.maxFileSize {
                        try? FileManager.default.removeItem(at: tempURL)
                        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
                        await showResult(
                            icon: "exclamationmark.triangle.fill", color: .systemOrange,
                            title: NSLocalizedString("File too large", comment: ""),
                            detail: "\(sizeStr) — max 1 GB"
                        )
                        try? await Task.sleep(for: .seconds(2.0))
                        completeRequest()
                        return
                    }

                    // Step 1: Copy to shared container (crash-safe backup)
                    let pending = try saveToSharedContainer(sourceURL: tempURL, typeHint: typeHint)

                    // Step 2: Try in-extension conversion
                    let converted = await attemptConversion(pending: pending)

                    if converted {
                        savedCount += 1
                    } else {
                        queuedCount += 1
                    }
                } catch let actionErr as ActionError {
                    await showResult(
                        icon: "exclamationmark.triangle.fill", color: .systemOrange,
                        title: NSLocalizedString("File too large", comment: ""),
                        detail: actionErr.localizedDescription
                    )
                    try? await Task.sleep(for: .seconds(2.0))
                    completeRequest()
                    return
                } catch {
                    queuedCount += 1
                    print("[ActionExt] Error: \(error.localizedDescription)")
                }
            }

            // Show result
            if queuedCount == 0 && savedCount > 0 {
                await showResult(
                    icon: "checkmark.circle.fill", color: .systemGreen,
                    title: NSLocalizedString("Saved to Photos!", comment: ""),
                    detail: savedCount > 1 ? String.localizedStringWithFormat(NSLocalizedString("%d files", comment: ""), savedCount) : nil
                )
                try? await Task.sleep(for: .seconds(1.2))
            } else if queuedCount > 0 {
                SharedConstants.hasPendingConversions = true
                await showResult(
                    icon: "arrow.triangle.2.circlepath", color: .systemOrange,
                    title: NSLocalizedString("Open MediaGate to convert", comment: ""),
                    detail: NSLocalizedString("File is too large to convert here", comment: "")
                )
                await openMainApp()
                try? await Task.sleep(for: .seconds(2.0))
            }

            completeRequest()
        }
    }

    // MARK: - File Loading

    private func loadFileURL(from provider: NSItemProvider) async throws -> (URL, String?) {
        let typeHint = provider.registeredTypeIdentifiers.first
        let typeIdentifiers = [
            UTType.data.identifier, UTType.image.identifier,
            UTType.movie.identifier, UTType.item.identifier,
        ]
        guard let typeID = typeIdentifiers.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
            throw ActionError.noFileURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, error in
                if let error { continuation.resume(throwing: error); return }
                guard let url else { continuation.resume(throwing: ActionError.noFileURL); return }

                let size = FileManager.default.fileSize(at: url)
                if size > SafetyChecks.maxFileSize {
                    continuation.resume(throwing: ActionError.fileTooLarge(size))
                    return
                }

                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    continuation.resume(returning: (tempURL, typeHint))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Shared Container (crash-safe backup)

    private func saveToSharedContainer(sourceURL: URL, typeHint: String?) throws -> PendingConversion {
        guard let pendingDir = SharedConstants.pendingDirectoryURL else {
            throw ActionError.sharedContainerUnavailable
        }
        let originalFilename = sourceURL.lastPathComponent
        let storedFilename = "\(UUID().uuidString)_\(originalFilename)"
        let destinationURL = pendingDir.appendingPathComponent(storedFilename)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let pending = PendingConversion(
            originalFilename: originalFilename,
            typeIdentifierHint: typeHint,
            storedFilename: storedFilename
        )
        try pending.writeToPendingDirectory()
        try? FileManager.default.removeItem(at: sourceURL)
        return pending
    }

    // MARK: - In-Extension Conversion

    private static let heavyImageFormats: Set<String> = [
        "cr2", "nef", "arw", "dng", "orf", "rw2", "raf", "pef",
        "srw", "x3f", "3fr", "erf", "kdc", "mrw", "dcr",
        "psd", "svg"
    ]

    private static let maxImageSizeForExtension: UInt64 = 5_000_000

    private func attemptConversion(pending: PendingConversion) async -> Bool {
        guard let pendingDir = SharedConstants.pendingDirectoryURL else { return false }
        let sourceURL = pendingDir.appendingPathComponent(pending.storedFilename)
        let format = formatDetector.detect(fileURL: sourceURL)

        do {
            switch format {
            case .nativelySupported:
                let ext = sourceURL.pathExtension.lowercased()
                let videoExts: Set<String> = ["mp4", "mov", "m4v", "hevc"]
                if videoExts.contains(ext) {
                    try await gallerySaver.saveVideo(url: sourceURL)
                } else {
                    try await gallerySaver.saveImage(url: sourceURL)
                }
                cleanupPending(pending)
                return true

            case .image:
                let ext = sourceURL.pathExtension.lowercased()
                let fileSize = FileManager.default.fileSize(at: sourceURL)
                if Self.heavyImageFormats.contains(ext) || fileSize > Self.maxImageSizeForExtension {
                    return false
                }

                let tempDir = try FileManager.default.createConversionTempDirectory(jobID: pending.id.uuidString)
                let outputs = try await imageConverter.convert(input: sourceURL, outputDir: tempDir)
                for url in outputs {
                    try await gallerySaver.saveImage(url: url)
                }
                FileManager.default.cleanupConversionTempDirectory(jobID: pending.id.uuidString)
                cleanupPending(pending)
                return true

            case .video:
                let fileSize = FileManager.default.fileSize(at: sourceURL)
                guard fileSize > 0 && fileSize <= maxVideoSizeForExtension else { return false }
                return await convertSmallVideo(pending: pending, sourceURL: sourceURL)

            case .unsupported:
                return false
            }
        } catch {
            print("[ActionExt] Conversion failed, queued for main app: \(error.localizedDescription)")
            return false
        }
    }

    private func convertSmallVideo(pending: PendingConversion, sourceURL: URL) async -> Bool {
        do {
            let tempDir = try FileManager.default.createConversionTempDirectory(jobID: pending.id.uuidString)
            let outputURL = tempDir.appendingPathComponent(
                sourceURL.deletingPathExtension().lastPathComponent + ".mp4"
            )

            let success = try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    try self.transcodeVideo(input: sourceURL, output: outputURL)
                    return true
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(extensionConversionTimeout))
                    throw ActionError.timeout
                }

                let result = try await group.next() ?? false
                group.cancelAll()
                return result
            }

            if success {
                try await gallerySaver.saveVideo(url: outputURL)
                FileManager.default.cleanupConversionTempDirectory(jobID: pending.id.uuidString)
                cleanupPending(pending)
                return true
            }
            return false
        } catch {
            print("[ActionExt] Video conversion timed out or failed: \(error.localizedDescription)")
            FileManager.default.cleanupConversionTempDirectory(jobID: pending.id.uuidString)
            return false
        }
    }

    nonisolated private func transcodeVideo(input: URL, output: URL) throws {
        let ifmtCtx = try AVFormatContext(url: input.path)
        try ifmtCtx.findStreamInfo()

        guard let videoIdx = ifmtCtx.findBestStream(type: .video) else { return }
        let audioIdx = ifmtCtx.findBestStream(type: .audio)
        let inVideoStream = ifmtCtx.streams[videoIdx]
        let inAudioStream = audioIdx.map { ifmtCtx.streams[$0] }

        guard let decoder = AVCodec.findDecoderById(inVideoStream.codecParameters.codecId) else { return }
        let decoderCtx = AVCodecContext(codec: decoder)
        decoderCtx.setParameters(inVideoStream.codecParameters)
        try decoderCtx.openCodec()

        guard let encoder = AVCodec.findEncoderByName("h264_videotoolbox")
                ?? AVCodec.findEncoderById(.H264) else { return }
        let encoderCtx = AVCodecContext(codec: encoder)
        encoderCtx.width = decoderCtx.width
        encoderCtx.height = decoderCtx.height
        encoderCtx.timebase = inVideoStream.timebase
        encoderCtx.framerate = decoderCtx.framerate
        encoderCtx.bitRate = 0

        if let supported = encoder.supportedPixelFormats, !supported.isEmpty {
            encoderCtx.pixelFormat = supported.contains(decoderCtx.pixelFormat)
                ? decoderCtx.pixelFormat
                : (supported.contains(.NV12) ? .NV12 : supported[0])
        } else {
            encoderCtx.pixelFormat = .YUV420P
        }

        let ofmtCtx = try AVFormatContext(format: nil, filename: output.path)
        if ofmtCtx.outputFormat!.flags.contains(.globalHeader) {
            encoderCtx.flags = encoderCtx.flags.union(.globalHeader)
        }
        try encoderCtx.openCodec()

        guard let outVideoStream = ofmtCtx.addStream() else { return }
        outVideoStream.codecParameters.copy(from: encoderCtx)
        outVideoStream.timebase = encoderCtx.timebase

        let mp4AudioCodecs: Set<AVCodecID> = [.AAC, .MP3, .FLAC]
        var outAudioStream: AVStream?
        if let inAudio = inAudioStream, mp4AudioCodecs.contains(inAudio.codecParameters.codecId) {
            if let stream = ofmtCtx.addStream() {
                stream.codecParameters.copy(from: inAudio.codecParameters)
                stream.codecParameters.codecTag = 0
                stream.timebase = inAudio.timebase
                outAudioStream = stream
            }
        }

        if !ofmtCtx.outputFormat!.flags.contains(.noFile) {
            try ofmtCtx.openOutput(url: output.path, flags: .write)
        }
        try ofmtCtx.writeHeader()

        let pkt = AVPacket()
        let frame = AVFrame()

        while true {
            do { try ifmtCtx.readFrame(into: pkt) }
            catch let err as AVError where err == .eof { break }
            defer { pkt.unref() }

            if pkt.streamIndex == videoIdx {
                do { try decoderCtx.sendPacket(pkt) } catch { continue }
                while true {
                    do { try decoderCtx.receiveFrame(frame) }
                    catch { break }
                    defer { frame.unref() }

                    try encoderCtx.sendFrame(frame)
                    let outPkt = AVPacket()
                    while true {
                        do { try encoderCtx.receivePacket(outPkt) } catch { break }
                        defer { outPkt.unref() }
                        outPkt.streamIndex = 0
                        outPkt.pts = AVMath.rescale(outPkt.pts, encoderCtx.timebase, outVideoStream.timebase, rounding: .nearInf, passMinMax: true)
                        outPkt.dts = AVMath.rescale(outPkt.dts, encoderCtx.timebase, outVideoStream.timebase, rounding: .nearInf, passMinMax: true)
                        outPkt.duration = AVMath.rescale(outPkt.duration, encoderCtx.timebase, outVideoStream.timebase)
                        outPkt.position = -1
                        try ofmtCtx.interleavedWriteFrame(outPkt)
                    }
                }
            } else if let aIdx = audioIdx, pkt.streamIndex == aIdx,
                      let outAudio = outAudioStream, let inAudio = inAudioStream {
                pkt.streamIndex = outAudioStream != nil ? 1 : 0
                pkt.pts = AVMath.rescale(pkt.pts, inAudio.timebase, outAudio.timebase, rounding: .nearInf, passMinMax: true)
                pkt.dts = AVMath.rescale(pkt.dts, inAudio.timebase, outAudio.timebase, rounding: .nearInf, passMinMax: true)
                pkt.duration = AVMath.rescale(pkt.duration, inAudio.timebase, outAudio.timebase)
                pkt.position = -1
                try ofmtCtx.interleavedWriteFrame(pkt)
            }

            try Task.checkCancellation()
        }

        // Flush decoder
        try decoderCtx.sendPacket(nil)
        while true {
            do { try decoderCtx.receiveFrame(frame) } catch { break }
            defer { frame.unref() }
            try encoderCtx.sendFrame(frame)
            let outPkt = AVPacket()
            while true {
                do { try encoderCtx.receivePacket(outPkt) } catch { break }
                defer { outPkt.unref() }
                outPkt.streamIndex = 0
                outPkt.pts = AVMath.rescale(outPkt.pts, encoderCtx.timebase, outVideoStream.timebase, rounding: .nearInf, passMinMax: true)
                outPkt.dts = AVMath.rescale(outPkt.dts, encoderCtx.timebase, outVideoStream.timebase, rounding: .nearInf, passMinMax: true)
                outPkt.duration = AVMath.rescale(outPkt.duration, encoderCtx.timebase, outVideoStream.timebase)
                outPkt.position = -1
                try ofmtCtx.interleavedWriteFrame(outPkt)
            }
        }

        // Flush encoder
        try encoderCtx.sendFrame(nil)
        let flushPkt = AVPacket()
        while true {
            do { try encoderCtx.receivePacket(flushPkt) } catch { break }
            defer { flushPkt.unref() }
            flushPkt.streamIndex = 0
            flushPkt.pts = AVMath.rescale(flushPkt.pts, encoderCtx.timebase, outVideoStream.timebase, rounding: .nearInf, passMinMax: true)
            flushPkt.dts = AVMath.rescale(flushPkt.dts, encoderCtx.timebase, outVideoStream.timebase, rounding: .nearInf, passMinMax: true)
            flushPkt.duration = AVMath.rescale(flushPkt.duration, encoderCtx.timebase, outVideoStream.timebase)
            flushPkt.position = -1
            try ofmtCtx.interleavedWriteFrame(flushPkt)
        }

        try ofmtCtx.writeTrailer()
    }

    // MARK: - Cleanup

    private func cleanupPending(_ job: PendingConversion) {
        guard let dir = SharedConstants.pendingDirectoryURL else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(job.metadataFilename))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(job.storedFilename))
    }

    // MARK: - Open Main App

    @MainActor
    private func openMainApp() async {
        guard let url = URL(string: "mediagate://convert") else { return }
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: selector) { r.perform(selector, with: url); return }
            responder = r.next
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private enum ActionError: LocalizedError {
    case noFileURL
    case sharedContainerUnavailable
    case timeout
    case fileTooLarge(UInt64)

    var errorDescription: String? {
        switch self {
        case .noFileURL: return "No file URL was provided."
        case .sharedContainerUnavailable: return "Shared container not available."
        case .timeout: return "Conversion timed out."
        case .fileTooLarge(let size):
            let s = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            return "File too large (\(s)). Maximum is 1 GB."
        }
    }
}
