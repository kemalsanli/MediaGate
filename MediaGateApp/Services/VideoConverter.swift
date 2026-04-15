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
import MediaGateKit

/// A type that can transcode video files to MP4 (H.264 + AAC).
protocol VideoConverting: Sendable {
    func convert(input: URL, output: URL, progress: @Sendable @escaping (Double) -> Void) async throws
}

/// Errors specific to video conversion.
enum VideoConversionError: LocalizedError, Sendable {
    case ffmpegFailed(String)
    case noVideoStream
    case noDecoder
    case noEncoder
    case cancelled
    case outputVerificationFailed

    var errorDescription: String? {
        switch self {
        case .ffmpegFailed(let msg): return "Video conversion failed: \(msg)"
        case .noVideoStream: return "No video stream found in the input file."
        case .noDecoder: return "No suitable decoder found for the video format."
        case .noEncoder: return "No suitable H.264 encoder found."
        case .cancelled: return "Video conversion was cancelled."
        case .outputVerificationFailed: return "Conversion produced an empty or invalid output file."
        }
    }
}

private let mp4CompatibleAudioCodecs: Set<AVCodecID> = [.AAC]

/// Determines how audio is handled during conversion.
private enum AudioMode {
    case passthrough
    case transcode(decoderCtx: AVCodecContext, encoderCtx: AVCodecContext, resampler: SwrContext)
    case none
}

/// Converts video files using SwiftFFmpeg with hardware-accelerated encoding.
final class FFmpegVideoConverter: VideoConverting, @unchecked Sendable {

    func convert(
        input: URL,
        output: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try self.transcode(inputPath: input.path, outputPath: output.path, progress: progress)

            // Verify output file is valid
            let outputSize = FileManager.default.fileSize(at: output)
            guard outputSize > 0 else {
                try? FileManager.default.removeItem(at: output)
                throw VideoConversionError.outputVerificationFailed
            }
        }.value
    }

    // MARK: - Transcoding Pipeline

    private func transcode(
        inputPath: String,
        outputPath: String,
        progress: @Sendable @escaping (Double) -> Void
    ) throws {
        // 1. Open input — will throw if file is corrupt or unreadable
        let ifmtCtx: AVFormatContext
        do {
            ifmtCtx = try AVFormatContext(url: inputPath)
            try ifmtCtx.findStreamInfo()
        } catch {
            throw VideoConversionError.ffmpegFailed("Cannot open input: \(error.localizedDescription)")
        }

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
        do {
            try decoderCtx.openCodec()
        } catch {
            throw VideoConversionError.ffmpegFailed("Cannot open decoder: \(error.localizedDescription)")
        }

        // 4. Create output context
        let ofmtCtx: AVFormatContext
        do {
            ofmtCtx = try AVFormatContext(format: nil, filename: outputPath)
        } catch {
            throw VideoConversionError.ffmpegFailed("Cannot create output: \(error.localizedDescription)")
        }

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

        // 7. Determine audio mode and add output audio stream
        let audioMode: AudioMode
        var outAudioStream: AVStream?

        if let inAudio = inAudioStream {
            if mp4CompatibleAudioCodecs.contains(inAudio.codecParameters.codecId) {
                // Passthrough — codec is already MP4-compatible
                audioMode = .passthrough
                if let stream = ofmtCtx.addStream() {
                    stream.codecParameters.copy(from: inAudio.codecParameters)
                    stream.codecParameters.codecTag = 0
                    stream.timebase = inAudio.timebase
                    outAudioStream = stream
                }
            } else {
                // Transcode incompatible audio to AAC
                do {
                    let (audioDecCtx, audioEncCtx, resampler) = try setupAudioTranscoding(
                        inputStream: inAudio,
                        globalHeader: ofmtCtx.outputFormat!.flags.contains(.globalHeader)
                    )
                    audioMode = .transcode(decoderCtx: audioDecCtx, encoderCtx: audioEncCtx, resampler: resampler)
                    if let stream = ofmtCtx.addStream() {
                        stream.codecParameters.copy(from: audioEncCtx)
                        stream.timebase = audioEncCtx.timebase
                        outAudioStream = stream
                    }
                } catch {
                    // If audio transcoding setup fails, proceed without audio
                    audioMode = .none
                }
            }
        } else {
            audioMode = .none
        }

        // 8. Open output and write header
        do {
            if !ofmtCtx.outputFormat!.flags.contains(.noFile) {
                try ofmtCtx.openOutput(url: outputPath, flags: .write)
            }
            try ofmtCtx.writeHeader()
        } catch {
            throw VideoConversionError.ffmpegFailed("Cannot write output header: \(error.localizedDescription)")
        }

        // 9. Transcode loop
        let pkt = AVPacket()
        let frame = AVFrame()
        var lastProgress = 0.0
        var audioFifo: [[Float]] = []
        var nextAudioPts: Int64 = 0

        if case .transcode(_, let audioEncCtx, _) = audioMode {
            let channels = audioEncCtx.channelLayout.channelCount
            audioFifo = Array(repeating: [], count: channels)
        }

        while true {
            try Task.checkCancellation()

            do {
                try ifmtCtx.readFrame(into: pkt)
            } catch let err as AVError where err == .eof {
                break
            } catch {
                // Skip unreadable packets instead of crashing
                continue
            }
            defer { pkt.unref() }

            if pkt.streamIndex == videoIdx {
                do {
                    try processVideoPacket(pkt, decoderCtx: decoderCtx, encoderCtx: encoderCtx,
                                           frame: frame, outStream: outVideoStream, ofmtCtx: ofmtCtx)
                } catch {
                    // Log but continue — a single bad frame shouldn't kill the conversion
                    continue
                }

                if totalDuration > 0 {
                    let time = Double(pkt.pts) * inVideoStream.timebase.toDouble
                    let pct = min(max(time / totalDuration, 0), 1.0)
                    if pct - lastProgress > 0.005 {
                        lastProgress = pct
                        progress(pct)
                    }
                }
            } else if let aIdx = audioIdx, pkt.streamIndex == aIdx,
                      let outAudio = outAudioStream, let inAudio = inAudioStream {
                switch audioMode {
                case .passthrough:
                    do {
                        pkt.streamIndex = 1
                        let inTb = inAudio.timebase
                        let outTb = outAudio.timebase
                        pkt.pts = AVMath.rescale(pkt.pts, inTb, outTb, rounding: .nearInf, passMinMax: true)
                        pkt.dts = AVMath.rescale(pkt.dts, inTb, outTb, rounding: .nearInf, passMinMax: true)
                        pkt.duration = AVMath.rescale(pkt.duration, inTb, outTb)
                        pkt.position = -1
                        try ofmtCtx.interleavedWriteFrame(pkt)
                    } catch {
                        // Skip bad audio packets
                        continue
                    }

                case .transcode(let audioDecCtx, let audioEncCtx, let resampler):
                    do {
                        try processAudioPacketTranscode(
                            pkt,
                            decoderCtx: audioDecCtx,
                            encoderCtx: audioEncCtx,
                            resampler: resampler,
                            outStream: outAudio,
                            ofmtCtx: ofmtCtx,
                            audioFifo: &audioFifo,
                            nextAudioPts: &nextAudioPts
                        )
                    } catch {
                        continue
                    }

                case .none:
                    break
                }
            }
        }

        // 10. Flush video
        do { try flushDecoder(decoderCtx: decoderCtx, encoderCtx: encoderCtx,
                              frame: frame, outStream: outVideoStream, ofmtCtx: ofmtCtx) } catch {}
        do { try flushEncoder(encoderCtx: encoderCtx, outStream: outVideoStream, ofmtCtx: ofmtCtx) } catch {}

        // 11. Flush audio transcoding
        if case .transcode(let audioDecCtx, let audioEncCtx, let resampler) = audioMode,
           let outAudio = outAudioStream {
            do {
                try flushAudioTranscoding(
                    decoderCtx: audioDecCtx,
                    encoderCtx: audioEncCtx,
                    resampler: resampler,
                    outStream: outAudio,
                    ofmtCtx: ofmtCtx,
                    audioFifo: &audioFifo,
                    nextAudioPts: &nextAudioPts
                )
            } catch {}
        }

        // 12. Finalize
        do {
            try ofmtCtx.writeTrailer()
        } catch {
            throw VideoConversionError.ffmpegFailed("Cannot finalize output: \(error.localizedDescription)")
        }

        progress(1.0)
    }

    // MARK: - Video Encoder Setup

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

        do {
            try ctx.openCodec()
        } catch {
            throw VideoConversionError.ffmpegFailed("Cannot open encoder: \(error.localizedDescription)")
        }

        return ctx
    }

    // MARK: - Audio Transcoding Setup

    private func setupAudioTranscoding(
        inputStream: AVStream,
        globalHeader: Bool
    ) throws -> (AVCodecContext, AVCodecContext, SwrContext) {
        // Decoder
        guard let audioDecoder = AVCodec.findDecoderById(inputStream.codecParameters.codecId) else {
            throw VideoConversionError.ffmpegFailed("No audio decoder found for codec.")
        }
        let audioDecoderCtx = AVCodecContext(codec: audioDecoder)
        audioDecoderCtx.setParameters(inputStream.codecParameters)
        try audioDecoderCtx.openCodec()

        // Determine input channel layout — default to stereo if unset
        var inputLayout = audioDecoderCtx.channelLayout
        if inputLayout.channelCount == 0 {
            inputLayout = .default(for: 2)
        }

        // Encoder — AAC
        guard let audioEncoder = AVCodec.findEncoderById(.AAC) else {
            throw VideoConversionError.ffmpegFailed("No AAC encoder found.")
        }
        let audioEncoderCtx = AVCodecContext(codec: audioEncoder)
        audioEncoderCtx.sampleFormat = .floatPlanar

        // Match input sample rate if standard, else 44100
        let inputRate = audioDecoderCtx.sampleRate
        let standardRates = [44100, 48000, 32000, 22050, 16000, 96000, 88200, 24000, 12000, 11025, 8000]
        audioEncoderCtx.sampleRate = standardRates.contains(inputRate) ? inputRate : 44100

        // Downmix surround to stereo, keep mono if mono
        let inputChannels = inputLayout.channelCount
        let outputChannels = inputChannels <= 1 ? 1 : 2
        audioEncoderCtx.channelLayout = .default(for: outputChannels)

        audioEncoderCtx.bitRate = outputChannels == 1 ? 96_000 : 128_000
        audioEncoderCtx.timebase = AVRational(num: 1, den: Int32(audioEncoderCtx.sampleRate))

        if globalHeader {
            audioEncoderCtx.flags = audioEncoderCtx.flags.union(.globalHeader)
        }

        try audioEncoderCtx.openCodec()

        // Resampler
        let resampler = try SwrContext(
            inputChannelLayout: inputLayout,
            inputSampleFormat: audioDecoderCtx.sampleFormat,
            inputSampleRate: audioDecoderCtx.sampleRate,
            outputChannelLayout: audioEncoderCtx.channelLayout,
            outputSampleFormat: audioEncoderCtx.sampleFormat,
            outputSampleRate: audioEncoderCtx.sampleRate
        )
        try resampler.initialize()

        return (audioDecoderCtx, audioEncoderCtx, resampler)
    }

    // MARK: - Video Processing

    private func processVideoPacket(
        _ pkt: AVPacket, decoderCtx: AVCodecContext, encoderCtx: AVCodecContext,
        frame: AVFrame, outStream: AVStream, ofmtCtx: AVFormatContext
    ) throws {
        do { try decoderCtx.sendPacket(pkt) }
        catch let err as AVError where err == .tryAgain { return }

        while true {
            do { try decoderCtx.receiveFrame(frame) }
            catch let err as AVError where err == .tryAgain || err == .eof { break }
            defer { frame.unref() }
            try encodeAndWrite(encoderCtx: encoderCtx, frame: frame, outStream: outStream, ofmtCtx: ofmtCtx)
        }
    }

    private func encodeAndWrite(
        encoderCtx: AVCodecContext, frame: AVFrame?, outStream: AVStream, ofmtCtx: AVFormatContext
    ) throws {
        try encoderCtx.sendFrame(frame)
        let outPkt = AVPacket()
        while true {
            do { try encoderCtx.receivePacket(outPkt) }
            catch let err as AVError where err == .tryAgain || err == .eof { break }
            defer { outPkt.unref() }
            outPkt.streamIndex = 0
            outPkt.pts = AVMath.rescale(outPkt.pts, encoderCtx.timebase, outStream.timebase, rounding: .nearInf, passMinMax: true)
            outPkt.dts = AVMath.rescale(outPkt.dts, encoderCtx.timebase, outStream.timebase, rounding: .nearInf, passMinMax: true)
            outPkt.duration = AVMath.rescale(outPkt.duration, encoderCtx.timebase, outStream.timebase)
            outPkt.position = -1
            try ofmtCtx.interleavedWriteFrame(outPkt)
        }
    }

    // MARK: - Audio Transcoding

    private func processAudioPacketTranscode(
        _ pkt: AVPacket,
        decoderCtx: AVCodecContext,
        encoderCtx: AVCodecContext,
        resampler: SwrContext,
        outStream: AVStream,
        ofmtCtx: AVFormatContext,
        audioFifo: inout [[Float]],
        nextAudioPts: inout Int64
    ) throws {
        do { try decoderCtx.sendPacket(pkt) }
        catch let err as AVError where err == .tryAgain { return }

        let frame = AVFrame()
        while true {
            do { try decoderCtx.receiveFrame(frame) }
            catch let err as AVError where err == .tryAgain || err == .eof { break }
            defer { frame.unref() }

            guard frame.sampleCount > 0 else { continue }

            let outCount = try resampler.getOutSamples(Int64(frame.sampleCount))
            guard outCount > 0 else { continue }

            let outChannels = encoderCtx.channelLayout.channelCount
            let outSamples = AVSamples(
                channelCount: outChannels,
                sampleCount: outCount,
                sampleFormat: encoderCtx.sampleFormat
            )

            // Resample decoded frame into output buffer
            let converted = try frame.extendedData.withMemoryRebound(to: UnsafePointer<UInt8>?.self) { srcBuf in
                try resampler.convert(
                    dst: outSamples.data.baseAddress!,
                    dstCount: outCount,
                    src: srcBuf.baseAddress!,
                    srcCount: frame.sampleCount
                )
            }

            guard converted > 0 else { continue }

            // Append resampled audio to FIFO
            for ch in 0..<outChannels {
                guard let ptr = outSamples.data[ch] else { continue }
                ptr.withMemoryRebound(to: Float.self, capacity: converted) { floatPtr in
                    audioFifo[ch].append(contentsOf: UnsafeBufferPointer(start: floatPtr, count: converted))
                }
            }

            // Encode complete frames from FIFO
            try drainAudioFifo(
                encoderCtx: encoderCtx,
                outStream: outStream,
                ofmtCtx: ofmtCtx,
                audioFifo: &audioFifo,
                nextAudioPts: &nextAudioPts
            )
        }
    }

    private func drainAudioFifo(
        encoderCtx: AVCodecContext,
        outStream: AVStream,
        ofmtCtx: AVFormatContext,
        audioFifo: inout [[Float]],
        nextAudioPts: inout Int64
    ) throws {
        let frameSize = encoderCtx.frameSize
        let channels = encoderCtx.channelLayout.channelCount

        while audioFifo[0].count >= frameSize {
            let outFrame = AVFrame()
            outFrame.sampleFormat = encoderCtx.sampleFormat
            outFrame.sampleRate = encoderCtx.sampleRate
            outFrame.channelLayout = encoderCtx.channelLayout
            outFrame.sampleCount = frameSize
            try outFrame.allocBuffer()

            for ch in 0..<channels {
                guard let dst = outFrame.data[ch] else { continue }
                dst.withMemoryRebound(to: Float.self, capacity: frameSize) { floatDst in
                    for i in 0..<frameSize {
                        floatDst[i] = audioFifo[ch][i]
                    }
                }
                audioFifo[ch].removeFirst(frameSize)
            }

            outFrame.pts = nextAudioPts
            nextAudioPts += Int64(frameSize)

            try encodeAndWriteAudio(
                encoderCtx: encoderCtx, frame: outFrame,
                outStream: outStream, ofmtCtx: ofmtCtx
            )
        }
    }

    private func encodeAndWriteAudio(
        encoderCtx: AVCodecContext, frame: AVFrame?, outStream: AVStream, ofmtCtx: AVFormatContext
    ) throws {
        try encoderCtx.sendFrame(frame)
        let outPkt = AVPacket()
        while true {
            do { try encoderCtx.receivePacket(outPkt) }
            catch let err as AVError where err == .tryAgain || err == .eof { break }
            defer { outPkt.unref() }
            outPkt.streamIndex = 1
            outPkt.pts = AVMath.rescale(outPkt.pts, encoderCtx.timebase, outStream.timebase, rounding: .nearInf, passMinMax: true)
            outPkt.dts = AVMath.rescale(outPkt.dts, encoderCtx.timebase, outStream.timebase, rounding: .nearInf, passMinMax: true)
            outPkt.duration = AVMath.rescale(outPkt.duration, encoderCtx.timebase, outStream.timebase)
            outPkt.position = -1
            try ofmtCtx.interleavedWriteFrame(outPkt)
        }
    }

    private func flushAudioTranscoding(
        decoderCtx: AVCodecContext,
        encoderCtx: AVCodecContext,
        resampler: SwrContext,
        outStream: AVStream,
        ofmtCtx: AVFormatContext,
        audioFifo: inout [[Float]],
        nextAudioPts: inout Int64
    ) throws {
        // Flush decoder
        try decoderCtx.sendPacket(nil)
        let frame = AVFrame()
        while true {
            do { try decoderCtx.receiveFrame(frame) }
            catch let err as AVError where err == .eof { break }
            defer { frame.unref() }

            guard frame.sampleCount > 0 else { continue }

            let outCount = try resampler.getOutSamples(Int64(frame.sampleCount))
            guard outCount > 0 else { continue }

            let outChannels = encoderCtx.channelLayout.channelCount
            let outSamples = AVSamples(
                channelCount: outChannels,
                sampleCount: outCount,
                sampleFormat: encoderCtx.sampleFormat
            )

            let converted = try frame.extendedData.withMemoryRebound(to: UnsafePointer<UInt8>?.self) { srcBuf in
                try resampler.convert(
                    dst: outSamples.data.baseAddress!,
                    dstCount: outCount,
                    src: srcBuf.baseAddress!,
                    srcCount: frame.sampleCount
                )
            }

            if converted > 0 {
                for ch in 0..<outChannels {
                    guard let ptr = outSamples.data[ch] else { continue }
                    ptr.withMemoryRebound(to: Float.self, capacity: converted) { floatPtr in
                        audioFifo[ch].append(contentsOf: UnsafeBufferPointer(start: floatPtr, count: converted))
                    }
                }
            }
        }

        // Flush resampler (get buffered samples)
        let outChannels = encoderCtx.channelLayout.channelCount
        let delay = resampler.getDelay(Int64(encoderCtx.sampleRate))
        if delay > 0 {
            let outSamples = AVSamples(
                channelCount: outChannels,
                sampleCount: delay,
                sampleFormat: encoderCtx.sampleFormat
            )
            var emptyPtr: UnsafePointer<UInt8>? = nil
            let flushed = try resampler.convert(
                dst: outSamples.data.baseAddress!,
                dstCount: delay,
                src: &emptyPtr,
                srcCount: 0
            )
            if flushed > 0 {
                for ch in 0..<outChannels {
                    guard let ptr = outSamples.data[ch] else { continue }
                    ptr.withMemoryRebound(to: Float.self, capacity: flushed) { floatPtr in
                        audioFifo[ch].append(contentsOf: UnsafeBufferPointer(start: floatPtr, count: flushed))
                    }
                }
            }
        }

        // Drain remaining complete frames
        try drainAudioFifo(
            encoderCtx: encoderCtx,
            outStream: outStream,
            ofmtCtx: ofmtCtx,
            audioFifo: &audioFifo,
            nextAudioPts: &nextAudioPts
        )

        // Encode remaining samples (pad with silence if needed)
        let remaining = audioFifo[0].count
        if remaining > 0 {
            let frameSize = encoderCtx.frameSize
            let outFrame = AVFrame()
            outFrame.sampleFormat = encoderCtx.sampleFormat
            outFrame.sampleRate = encoderCtx.sampleRate
            outFrame.channelLayout = encoderCtx.channelLayout
            outFrame.sampleCount = frameSize
            try outFrame.allocBuffer()

            for ch in 0..<outChannels {
                guard let dst = outFrame.data[ch] else { continue }
                dst.withMemoryRebound(to: Float.self, capacity: frameSize) { floatDst in
                    for i in 0..<remaining {
                        floatDst[i] = audioFifo[ch][i]
                    }
                    // Pad with silence
                    for i in remaining..<frameSize {
                        floatDst[i] = 0.0
                    }
                }
                audioFifo[ch].removeAll()
            }

            outFrame.pts = nextAudioPts
            try encodeAndWriteAudio(
                encoderCtx: encoderCtx, frame: outFrame,
                outStream: outStream, ofmtCtx: ofmtCtx
            )
        }

        // Flush encoder
        try encoderCtx.sendFrame(nil)
        let outPkt = AVPacket()
        while true {
            do { try encoderCtx.receivePacket(outPkt) }
            catch let err as AVError where err == .eof { break }
            defer { outPkt.unref() }
            outPkt.streamIndex = 1
            outPkt.pts = AVMath.rescale(outPkt.pts, encoderCtx.timebase, outStream.timebase, rounding: .nearInf, passMinMax: true)
            outPkt.dts = AVMath.rescale(outPkt.dts, encoderCtx.timebase, outStream.timebase, rounding: .nearInf, passMinMax: true)
            outPkt.duration = AVMath.rescale(outPkt.duration, encoderCtx.timebase, outStream.timebase)
            outPkt.position = -1
            try ofmtCtx.interleavedWriteFrame(outPkt)
        }
    }

    // MARK: - Video Flushing

    private func flushDecoder(
        decoderCtx: AVCodecContext, encoderCtx: AVCodecContext,
        frame: AVFrame, outStream: AVStream, ofmtCtx: AVFormatContext
    ) throws {
        try decoderCtx.sendPacket(nil)
        while true {
            do { try decoderCtx.receiveFrame(frame) }
            catch let err as AVError where err == .eof { break }
            defer { frame.unref() }
            try encodeAndWrite(encoderCtx: encoderCtx, frame: frame, outStream: outStream, ofmtCtx: ofmtCtx)
        }
    }

    private func flushEncoder(
        encoderCtx: AVCodecContext, outStream: AVStream, ofmtCtx: AVFormatContext
    ) throws {
        try encoderCtx.sendFrame(nil)
        let outPkt = AVPacket()
        while true {
            do { try encoderCtx.receivePacket(outPkt) }
            catch let err as AVError where err == .eof { break }
            defer { outPkt.unref() }
            outPkt.streamIndex = 0
            outPkt.pts = AVMath.rescale(outPkt.pts, encoderCtx.timebase, outStream.timebase, rounding: .nearInf, passMinMax: true)
            outPkt.dts = AVMath.rescale(outPkt.dts, encoderCtx.timebase, outStream.timebase, rounding: .nearInf, passMinMax: true)
            outPkt.duration = AVMath.rescale(outPkt.duration, encoderCtx.timebase, outStream.timebase)
            outPkt.position = -1
            try ofmtCtx.interleavedWriteFrame(outPkt)
        }
    }
}
