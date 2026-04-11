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

import Foundation
import MediaGateKit

/// Events emitted by the conversion pipeline as it processes files.
enum ConversionEvent: Sendable {
    case started(filename: String, index: Int, total: Int)
    case progress(filename: String, percent: Double)
    case completed(filename: String)
    case failed(filename: String, error: String)
    case allDone(successCount: Int, failCount: Int)
}

/// Orchestrates the full conversion pipeline with safety checks.
///
/// Every file goes through: preflight → detect → convert → save → cleanup.
/// Errors are caught per-file so one bad file doesn't stop the batch.
final class ConversionPipeline: Sendable {

    private let formatDetector: FormatDetecting
    private let videoConverter: VideoConverting
    private let imageConverter: ImageConverting
    private let gallerySaver: GallerySaving

    init(
        formatDetector: FormatDetecting = FormatDetector(),
        videoConverter: VideoConverting = FFmpegVideoConverter(),
        imageConverter: ImageConverting = NativeImageConverter(),
        gallerySaver: GallerySaving = GallerySaver()
    ) {
        self.formatDetector = formatDetector
        self.videoConverter = videoConverter
        self.imageConverter = imageConverter
        self.gallerySaver = gallerySaver
    }

    func processAll() -> AsyncStream<ConversionEvent> {
        AsyncStream { continuation in
            Task {
                await self.run(continuation: continuation)
                continuation.finish()
            }
        }
    }

    // MARK: - Private

    private func run(continuation: AsyncStream<ConversionEvent>.Continuation) async {
        let pending: [PendingConversion]
        do {
            pending = try PendingConversion.loadAll()
        } catch {
            continuation.yield(.allDone(successCount: 0, failCount: 0))
            return
        }

        guard !pending.isEmpty else {
            continuation.yield(.allDone(successCount: 0, failCount: 0))
            return
        }

        var successCount = 0
        var failCount = 0
        let total = pending.count

        for (index, job) in pending.enumerated() {
            let filename = job.originalFilename
            continuation.yield(.started(filename: filename, index: index, total: total))

            do {
                try await processOne(job: job) { percent in
                    continuation.yield(.progress(filename: filename, percent: percent))
                }
                continuation.yield(.completed(filename: filename))
                successCount += 1
            } catch {
                continuation.yield(.failed(filename: filename, error: error.localizedDescription))
                failCount += 1
            }

            cleanupPendingJob(job)
        }

        FileManager.default.cleanupAllConversionTempFiles()
        continuation.yield(.allDone(successCount: successCount, failCount: failCount))
    }

    private func processOne(
        job: PendingConversion,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        guard let pendingDir = SharedConstants.pendingDirectoryURL else {
            throw PendingConversionError.sharedContainerUnavailable
        }

        let sourceURL = pendingDir.appendingPathComponent(job.storedFilename)

        // === Safety checks ===
        try SafetyChecks.preflight(url: sourceURL)

        let format = formatDetector.detect(fileURL: sourceURL)

        switch format {
        case .nativelySupported:
            try await saveNativeFile(url: sourceURL)
            progress(1.0)

        case .video(let info):
            let tempDir = try FileManager.default.createConversionTempDirectory(jobID: job.id.uuidString)
            let outputURL = tempDir.appendingPathComponent(
                sourceURL.deletingPathExtension().lastPathComponent + ".\(info.outputExtension)"
            )

            do {
                try await videoConverter.convert(input: sourceURL, output: outputURL, progress: progress)
                try await gallerySaver.saveVideo(url: outputURL)
            } catch {
                // Clean up partial output on failure
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }

        case .image:
            let tempDir = try FileManager.default.createConversionTempDirectory(jobID: job.id.uuidString)
            let outputURLs = try await imageConverter.convert(input: sourceURL, outputDir: tempDir)
            for url in outputURLs {
                try await gallerySaver.saveImage(url: url)
            }
            progress(1.0)

        case .unsupported(let ext):
            throw ImageConversionError.unsupportedFormat(ext)
        }
    }

    /// Saves a natively-supported file, using magic bytes (not extension) to
    /// determine whether it's a video or image.
    private func saveNativeFile(url: URL) async throws {
        let magicHint = MagicBytes.identify(fileURL: url)
        let videoFormats: Set<String> = ["mp4", "mov", "m4v"]
        let isVideo = magicHint.map { videoFormats.contains($0) } ?? false

        // Fallback to extension if magic bytes don't help
        let ext = url.pathExtension.lowercased()
        let videoExts: Set<String> = ["mp4", "mov", "m4v", "hevc"]

        if isVideo || videoExts.contains(ext) {
            try await gallerySaver.saveVideo(url: url)
        } else {
            try await gallerySaver.saveImage(url: url)
        }
    }

    private func cleanupPendingJob(_ job: PendingConversion) {
        guard let pendingDir = SharedConstants.pendingDirectoryURL else { return }
        try? FileManager.default.removeItem(at: pendingDir.appendingPathComponent(job.metadataFilename))
        try? FileManager.default.removeItem(at: pendingDir.appendingPathComponent(job.storedFilename))
    }
}
