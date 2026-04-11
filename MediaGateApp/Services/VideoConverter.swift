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
import ffmpegkit

/// A type that can transcode video files to MP4 (H.264 + AAC).
protocol VideoConverting: Sendable {
    /// Transcodes a video file from the input URL to the output URL.
    ///
    /// Uses hardware-accelerated encoding (`h264_videotoolbox`) when available,
    /// falling back to software encoding (`libx264`) if hardware encoding fails.
    ///
    /// - Parameters:
    ///   - input: The source video file URL.
    ///   - output: The destination file URL (should have `.mp4` extension).
    ///   - progress: A closure called periodically with the conversion progress (0.0–1.0).
    func convert(input: URL, output: URL, progress: @Sendable @escaping (Double) -> Void) async throws
}

/// Errors specific to video conversion.
enum VideoConversionError: LocalizedError, Sendable {
    case ffmpegFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .ffmpegFailed(let message):
            return "Video conversion failed: \(message)"
        case .cancelled:
            return "Video conversion was cancelled."
        }
    }
}

/// Converts video files using ffmpeg-kit with hardware-accelerated encoding.
final class FFmpegVideoConverter: VideoConverting, @unchecked Sendable {

    func convert(input: URL, output: URL, progress: @Sendable @escaping (Double) -> Void) async throws {
        // First, probe the input to get duration for progress calculation
        let duration = await probeDuration(of: input)

        // Build the ffmpeg command — try hardware encoding first
        let command = buildCommand(input: input, output: output, useHardware: true)

        let result = try await execute(command: command, duration: duration, progress: progress)

        // If hardware encoding fails, retry with software encoding
        if !result {
            let softwareCommand = buildCommand(input: input, output: output, useHardware: false)
            let softwareResult = try await execute(command: softwareCommand, duration: duration, progress: progress)
            if !softwareResult {
                throw VideoConversionError.ffmpegFailed("Both hardware and software encoding failed.")
            }
        }
    }

    // MARK: - Private

    /// Builds the ffmpeg command string.
    ///
    /// - Parameters:
    ///   - input: Source file URL.
    ///   - output: Destination file URL.
    ///   - useHardware: Whether to use `h264_videotoolbox` (hardware) or `libx264` (software).
    /// - Returns: The ffmpeg command string (without the `ffmpeg` prefix).
    private func buildCommand(input: URL, output: URL, useHardware: Bool) -> String {
        let encoder = useHardware ? "h264_videotoolbox" : "libx264"
        let preset = useHardware ? "" : " -preset fast"
        let bitrateFlag = useHardware ? " -b:v 0" : ""

        return "-i \"\(input.path)\" -c:v \(encoder)\(bitrateFlag)\(preset) -c:a aac -movflags +faststart -y \"\(output.path)\""
    }

    /// Probes the input file to determine its duration in seconds.
    private func probeDuration(of url: URL) async -> Double {
        await withCheckedContinuation { continuation in
            let session = FFprobeKit.execute("-v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \"\(url.path)\"")
            let output = session?.getOutput() ?? ""
            let duration = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            continuation.resume(returning: duration)
        }
    }

    /// Executes an ffmpeg command and reports progress.
    ///
    /// - Parameters:
    ///   - command: The ffmpeg command string.
    ///   - duration: Total duration in seconds for progress calculation.
    ///   - progress: Progress callback (0.0–1.0).
    /// - Returns: `true` if the command succeeded, `false` otherwise.
    private func execute(
        command: String,
        duration: Double,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            let session = FFmpegKit.executeAsync(
                command,
                withCompleteCallback: { session in
                    let returnCode = session?.getReturnCode()
                    let success = ReturnCode.isSuccess(returnCode)
                    continuation.resume(returning: success)
                },
                withLogCallback: nil,
                withStatisticsCallback: { statistics in
                    guard let stats = statistics, duration > 0 else { return }
                    let time = Double(stats.getTime()) / 1000.0
                    let percent = min(time / duration, 1.0)
                    progress(percent)
                }
            )

            if session == nil {
                continuation.resume(throwing: VideoConversionError.ffmpegFailed("Failed to start FFmpeg session."))
            }
        }
    }
}
