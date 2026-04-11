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
    /// A conversion job has started.
    case started(filename: String, index: Int, total: Int)

    /// Progress update for the current file (0.0–1.0).
    case progress(filename: String, percent: Double)

    /// A single file conversion completed successfully.
    case completed(filename: String)

    /// A single file conversion failed.
    case failed(filename: String, error: String)

    /// All files have been processed.
    case allDone(successCount: Int, failCount: Int)
}

/// Orchestrates the full conversion pipeline: detect format, convert if needed,
/// save to Photos, and clean up temporary files.
///
/// The pipeline processes files sequentially to manage memory usage, emitting
/// ``ConversionEvent`` values via an `AsyncStream`.
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

    /// Processes all pending conversions from the shared container.
    ///
    /// - Returns: An `AsyncStream` of ``ConversionEvent`` values.
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

            // Clean up the pending files for this job
            cleanupPendingJob(job)
        }

        // Clean up all temp files
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
        let format = formatDetector.detect(fileURL: sourceURL)

        switch format {
        case .nativelySupported:
            // Save directly — no conversion needed
            let ext = sourceURL.pathExtension.lowercased()
            let videoExts = Set(["mp4", "mov", "m4v", "hevc"])
            if videoExts.contains(ext) {
                try await gallerySaver.saveVideo(url: sourceURL)
            } else {
                try await gallerySaver.saveImage(url: sourceURL)
            }
            progress(1.0)

        case .video(let info):
            let tempDir = try FileManager.default.createConversionTempDirectory(jobID: job.id.uuidString)
            let outputURL = tempDir.appendingPathComponent(
                sourceURL.deletingPathExtension().lastPathComponent + ".\(info.outputExtension)"
            )
            try await videoConverter.convert(input: sourceURL, output: outputURL, progress: progress)
            try await gallerySaver.saveVideo(url: outputURL)

        case .image(_):
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

    /// Removes the pending conversion metadata and media file from the shared container.
    private func cleanupPendingJob(_ job: PendingConversion) {
        guard let pendingDir = SharedConstants.pendingDirectoryURL else { return }
        let metadataURL = pendingDir.appendingPathComponent(job.metadataFilename)
        let mediaURL = pendingDir.appendingPathComponent(job.storedFilename)
        try? FileManager.default.removeItem(at: metadataURL)
        try? FileManager.default.removeItem(at: mediaURL)
    }
}
