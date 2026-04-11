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
import SwiftFFmpeg

/// A type that can transcode video files to MP4 (H.264 + AAC).
protocol VideoConverting: Sendable {
    /// Transcodes a video file from the input URL to the output URL.
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
    case noVideoStream
    case noDecoder
    case noEncoder
    case cancelled

    var errorDescription: String? {
        switch self {
        case .ffmpegFailed(let msg): return "Video conversion failed: \(msg)"
        case .noVideoStream: return "No video stream found in the input file."
        case .noDecoder: return "No suitable decoder found for the video format."
        case .noEncoder: return "No suitable H.264 encoder found."
        case .cancelled: return "Video conversion was cancelled."
        }
    }
}

/// Audio codec IDs that can be muxed directly into MP4 without re-encoding.
private let mp4CompatibleAudioCodecs: Set<AVCodecID> = [.AAC, .MP3, .FLAC]

/// Converts video files using SwiftFFmpeg with hardware-accelerated encoding.
///
/// Pipeline: demux → decode → encode (H.264 VideoToolbox) → mux (MP4).
/// Audio is remuxed (copied) when the codec is MP4-compatible, skipped otherwise.
final class FFmpegVideoConverter: VideoConverting, @unchecked Sendable {

    func convert(
        input: URL,
        output: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try self.transcode(inputPath: input.path, outputPath: output.path, progress: progress)
        }.value
    }

    // MARK: - Transcoding Pipeline

    private func transcode(
        inputPath: String,
        outputPath: String,
        progress: @Sendable @escaping (Double) -> Void
    ) throws {
        // 1. Open input
        let ifmtCtx = try AVFormatContext(url: inputPath)
        try ifmtCtx.findStreamInfo()
        let totalDuration = Double(ifmtCtx.duration) / Double(AVTimestamp.timebase)

        // 2. Find streams
        guard let videoIdx = ifmtCtx.findBestStream(type: .video) else {
            throw VideoConversionError.noVideoStream
        }
        let audioIdx = ifmtCtx.findBestStream(type: .audio)

        let inVideoStream = ifmtCtx.streams[videoIdx]
        let inAudioStream = audioIdx.map { ifmtCtx.streams[$0] }

        // 3. Set up video decoder
        guard let decoder = AVCodec.findDecoderById(inVideoStream.codecParameters.codecId) else {
            throw VideoConversionError.noDecoder
        }
        let decoderCtx = AVCodecContext(codec: decoder)
        decoderCtx.setParameters(inVideoStream.codecParameters)
        try decoderCtx.openCodec()

        // 4. Create output context (needed to check globalHeader)
        let ofmtCtx = try AVFormatContext(format: nil, filename: outputPath)

        // 5. Set up video encoder
        let encoderCtx = try setupEncoder(
            decoderCtx: decoderCtx,
            timebase: inVideoStream.timebase,
            globalHeader: ofmtCtx.outputFormat!.flags.contains(.globalHeader)
        )

        // 6. Add output video stream
        guard let outVideoStream = ofmtCtx.addStream() else {
            throw VideoConversionError.ffmpegFailed("Failed to create output video stream.")
        }
        outVideoStream.codecParameters.copy(from: encoderCtx)
        outVideoStream.timebase = encoderCtx.timebase

        // 7. Add output audio stream (passthrough for compatible codecs)
        var outAudioStream: AVStream?
        if let inAudio = inAudioStream,
           mp4CompatibleAudioCodecs.contains(inAudio.codecParameters.codecId) {
            if let stream = ofmtCtx.addStream() {
                stream.codecParameters.copy(from: inAudio.codecParameters)
                stream.codecParameters.codecTag = 0
                stream.timebase = inAudio.timebase
                outAudioStream = stream
            }
        }

        // 8. Open output file and write header
        if !ofmtCtx.outputFormat!.flags.contains(.noFile) {
            try ofmtCtx.openOutput(url: outputPath, flags: .write)
        }
        try ofmtCtx.writeHeader()

        // 9. Transcode loop
        let pkt = AVPacket()
        let frame = AVFrame()
        var lastProgress = 0.0

        while true {
            do {
                try ifmtCtx.readFrame(into: pkt)
            } catch let err as AVError where err == .eof {
                break
            }
            defer { pkt.unref() }

            if pkt.streamIndex == videoIdx {
                try processVideoPacket(
                    pkt, decoderCtx: decoderCtx, encoderCtx: encoderCtx,
                    frame: frame, outStream: outVideoStream, ofmtCtx: ofmtCtx
                )
                // Progress
                if totalDuration > 0 {
                    let time = Double(pkt.pts) * inVideoStream.timebase.toDouble
                    let pct = min(max(time / totalDuration, 0), 1.0)
                    if pct - lastProgress > 0.005 {
                        lastProgress = pct
                        progress(pct)
                    }
                }
            } else if let aIdx = audioIdx, pkt.streamIndex == aIdx,
                      let outAudio = outAudioStream,
                      let inAudio = inAudioStream {
                // Audio passthrough: rescale timestamps and write
                let outIdx = outAudioStream != nil ? 1 : 0
                pkt.streamIndex = outIdx
                let inTb = inAudio.timebase
                let outTb = outAudio.timebase
                pkt.pts = AVMath.rescale(pkt.pts, inTb, outTb, rounding: .nearInf, passMinMax: true)
                pkt.dts = AVMath.rescale(pkt.dts, inTb, outTb, rounding: .nearInf, passMinMax: true)
                pkt.duration = AVMath.rescale(pkt.duration, inTb, outTb)
                pkt.position = -1
                try ofmtCtx.interleavedWriteFrame(pkt)
            }
        }

        // 10. Flush decoder and encoder
        try flushDecoder(decoderCtx: decoderCtx, encoderCtx: encoderCtx,
                         frame: frame, outStream: outVideoStream, ofmtCtx: ofmtCtx)
        try flushEncoder(encoderCtx: encoderCtx, outStream: outVideoStream, ofmtCtx: ofmtCtx)

        // 11. Finalize
        try ofmtCtx.writeTrailer()
        progress(1.0)
    }

    // MARK: - Encoder Setup

    private func setupEncoder(
        decoderCtx: AVCodecContext,
        timebase: AVRational,
        globalHeader: Bool
    ) throws -> AVCodecContext {
        guard let encoder = AVCodec.findEncoderByName("h264_videotoolbox")
                ?? AVCodec.findEncoderByName("libx264")
                ?? AVCodec.findEncoderById(.H264) else {
            throw VideoConversionError.noEncoder
        }

        let ctx = AVCodecContext(codec: encoder)
        ctx.width = decoderCtx.width
        ctx.height = decoderCtx.height
        ctx.timebase = timebase
        ctx.framerate = decoderCtx.framerate

        // Pick pixel format: prefer decoder's format, fallback to common formats
        if let supported = encoder.supportedPixelFormats, !supported.isEmpty {
            if supported.contains(decoderCtx.pixelFormat) {
                ctx.pixelFormat = decoderCtx.pixelFormat
            } else if supported.contains(.NV12) {
                ctx.pixelFormat = .NV12
            } else if supported.contains(.YUV420P) {
                ctx.pixelFormat = .YUV420P
            } else {
                ctx.pixelFormat = supported[0]
            }
        } else {
            ctx.pixelFormat = .YUV420P
        }

        if encoder.name == "h264_videotoolbox" {
            ctx.bitRate = 0
        } else {
            let pixels = Int64(ctx.width) * Int64(ctx.height)
            ctx.bitRate = max(pixels * 4, 1_000_000)
        }

        if globalHeader {
            ctx.flags = ctx.flags.union(.globalHeader)
        }

        try ctx.openCodec()
        return ctx
    }

    // MARK: - Video Processing

    private func processVideoPacket(
        _ pkt: AVPacket,
        decoderCtx: AVCodecContext,
        encoderCtx: AVCodecContext,
        frame: AVFrame,
        outStream: AVStream,
        ofmtCtx: AVFormatContext
    ) throws {
        do { try decoderCtx.sendPacket(pkt) }
        catch let err as AVError where err == .tryAgain { return }

        while true {
            do {
                try decoderCtx.receiveFrame(frame)
            } catch let err as AVError where err == .tryAgain || err == .eof {
                break
            }
            defer { frame.unref() }

            try encodeAndWrite(encoderCtx: encoderCtx, frame: frame,
                               outStream: outStream, ofmtCtx: ofmtCtx)
        }
    }

    private func encodeAndWrite(
        encoderCtx: AVCodecContext,
        frame: AVFrame?,
        outStream: AVStream,
        ofmtCtx: AVFormatContext
    ) throws {
        try encoderCtx.sendFrame(frame)

        let outPkt = AVPacket()
        while true {
            do {
                try encoderCtx.receivePacket(outPkt)
            } catch let err as AVError where err == .tryAgain || err == .eof {
                break
            }
            defer { outPkt.unref() }

            outPkt.streamIndex = 0
            outPkt.pts = AVMath.rescale(outPkt.pts, encoderCtx.timebase, outStream.timebase,
                                        rounding: .nearInf, passMinMax: true)
            outPkt.dts = AVMath.rescale(outPkt.dts, encoderCtx.timebase, outStream.timebase,
                                        rounding: .nearInf, passMinMax: true)
            outPkt.duration = AVMath.rescale(outPkt.duration, encoderCtx.timebase, outStream.timebase)
            outPkt.position = -1

            try ofmtCtx.interleavedWriteFrame(outPkt)
        }
    }

    // MARK: - Flushing

    private func flushDecoder(
        decoderCtx: AVCodecContext,
        encoderCtx: AVCodecContext,
        frame: AVFrame,
        outStream: AVStream,
        ofmtCtx: AVFormatContext
    ) throws {
        try decoderCtx.sendPacket(nil)
        while true {
            do { try decoderCtx.receiveFrame(frame) }
            catch let err as AVError where err == .eof { break }
            defer { frame.unref() }
            try encodeAndWrite(encoderCtx: encoderCtx, frame: frame,
                               outStream: outStream, ofmtCtx: ofmtCtx)
        }
    }

    private func flushEncoder(
        encoderCtx: AVCodecContext,
        outStream: AVStream,
        ofmtCtx: AVFormatContext
    ) throws {
        try encoderCtx.sendFrame(nil)
        let outPkt = AVPacket()
        while true {
            do { try encoderCtx.receivePacket(outPkt) }
            catch let err as AVError where err == .eof { break }
            defer { outPkt.unref() }

            outPkt.streamIndex = 0
            outPkt.pts = AVMath.rescale(outPkt.pts, encoderCtx.timebase, outStream.timebase,
                                        rounding: .nearInf, passMinMax: true)
            outPkt.dts = AVMath.rescale(outPkt.dts, encoderCtx.timebase, outStream.timebase,
                                        rounding: .nearInf, passMinMax: true)
            outPkt.duration = AVMath.rescale(outPkt.duration, encoderCtx.timebase, outStream.timebase)
            outPkt.position = -1

            try ofmtCtx.interleavedWriteFrame(outPkt)
        }
    }
}
