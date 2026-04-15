import XCTest
import AVFoundation
@testable import MediaGate
@testable import MediaGateKit

/// Comprehensive conversion tests for all supported video and image formats.
/// Tests verify that video conversion produces both video and audio streams,
/// and that image conversion produces valid output files.
final class ConversionTests: XCTestCase {

    private var outputDir: URL!
    private var videoConverter: FFmpegVideoConverter!
    private var imageConverter: NativeImageConverter!

    override func setUp() {
        super.setUp()
        outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        videoConverter = FFmpegVideoConverter()
        imageConverter = NativeImageConverter()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outputDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func resourceURL(_ name: String) -> URL? {
        Bundle(for: ConversionTests.self).url(forResource: name, withExtension: nil)
    }

    private func verifyMP4HasAudioAndVideo(_ url: URL, file: StaticString = #file, line: UInt = #line) {
        let asset = AVAsset(url: url)
        let videoTracks = asset.tracks(withMediaType: .video)
        let audioTracks = asset.tracks(withMediaType: .audio)

        XCTAssertFalse(videoTracks.isEmpty, "Output MP4 has no video track: \(url.lastPathComponent)", file: file, line: line)
        XCTAssertFalse(audioTracks.isEmpty, "Output MP4 has no audio track: \(url.lastPathComponent)", file: file, line: line)

        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 1000, "Output MP4 is suspiciously small (\(size) bytes): \(url.lastPathComponent)", file: file, line: line)
    }

    private func verifyMP4HasVideo(_ url: URL, file: StaticString = #file, line: UInt = #line) {
        let asset = AVAsset(url: url)
        let videoTracks = asset.tracks(withMediaType: .video)
        XCTAssertFalse(videoTracks.isEmpty, "Output MP4 has no video track: \(url.lastPathComponent)", file: file, line: line)
    }

    private func verifyImageIsValid(_ url: URL, file: StaticString = #file, line: UInt = #line) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 100, "Output image is suspiciously small (\(size) bytes): \(url.lastPathComponent)", file: file, line: line)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            XCTFail("Cannot create image source from: \(url.lastPathComponent)", file: file, line: line)
            return
        }
        let imageCount = CGImageSourceGetCount(source)
        XCTAssertGreaterThan(imageCount, 0, "Image has no frames: \(url.lastPathComponent)", file: file, line: line)

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("Cannot decode image: \(url.lastPathComponent)", file: file, line: line)
            return
        }
        XCTAssertGreaterThan(cgImage.width, 0, "Image has zero width: \(url.lastPathComponent)", file: file, line: line)
        XCTAssertGreaterThan(cgImage.height, 0, "Image has zero height: \(url.lastPathComponent)", file: file, line: line)
    }

    // MARK: - Video: Passthrough Audio (AAC, MP3)

    func testMKV_AAC_PassthroughAudio() async throws {
        guard let input = resourceURL("test_mkv_aac.mkv") else {
            XCTFail("Missing test resource: test_mkv_aac.mkv"); return
        }
        let output = outputDir.appendingPathComponent("output.mp4")
        try await videoConverter.convert(input: input, output: output) { _ in }
        verifyMP4HasAudioAndVideo(output)
    }

    func testFLV_MP3_PassthroughAudio() async throws {
        guard let input = resourceURL("test_flv_mp3.flv") else {
            XCTFail("Missing test resource: test_flv_mp3.flv"); return
        }
        let output = outputDir.appendingPathComponent("output.mp4")
        try await videoConverter.convert(input: input, output: output) { _ in }
        verifyMP4HasAudioAndVideo(output)
    }

    func testThreeGP_AAC_PassthroughAudio() async throws {
        guard let input = resourceURL("test_3gp_aac.3gp") else {
            XCTFail("Missing test resource: test_3gp_aac.3gp"); return
        }
        let output = outputDir.appendingPathComponent("output.mp4")
        try await videoConverter.convert(input: input, output: output) { _ in }
        verifyMP4HasAudioAndVideo(output)
    }

    func testTS_AAC_PassthroughAudio() async throws {
        guard let input = resourceURL("test_ts_aac.ts") else {
            XCTFail("Missing test resource: test_ts_aac.ts"); return
        }
        let output = outputDir.appendingPathComponent("output.mp4")
        try await videoConverter.convert(input: input, output: output) { _ in }
        verifyMP4HasAudioAndVideo(output)
    }

    // MARK: - Video: Transcode Audio (AC3, Opus, PCM, WMA, MP2)

    func testMKV_AC3_TranscodeAudio() async throws {
        guard let input = resourceURL("test_mkv_ac3.mkv") else {
            XCTFail("Missing test resource: test_mkv_ac3.mkv"); return
        }
        let output = outputDir.appendingPathComponent("output.mp4")
        try await videoConverter.convert(input: input, output: output) { _ in }
        verifyMP4HasAudioAndVideo(output)
    }

    func testWebM_Opus_TranscodeAudio() async throws {
        guard let input = resourceURL("test_webm_opus.webm") else {
            XCTFail("Missing test resource: test_webm_opus.webm"); return
        }
        let output = outputDir.appendingPathComponent("output.mp4")
        try await videoConverter.convert(input: input, output: output) { _ in }
        verifyMP4HasAudioAndVideo(output)
    }

    func testAVI_PCM_TranscodeAudio() async throws {
        guard let input = resourceURL("test_avi_pcm.avi") else {
            XCTFail("Missing test resource: test_avi_pcm.avi"); return
        }
        let output = outputDir.appendingPathComponent("output.mp4")
        try await videoConverter.convert(input: input, output: output) { _ in }
        verifyMP4HasAudioAndVideo(output)
    }

    func testWMV_WMA_TranscodeAudio() async throws {
        guard let input = resourceURL("test_wmv_wma.wmv") else {
            XCTFail("Missing test resource: test_wmv_wma.wmv"); return
        }
        let output = outputDir.appendingPathComponent("output.mp4")
        try await videoConverter.convert(input: input, output: output) { _ in }
        verifyMP4HasAudioAndVideo(output)
    }

    func testMPG_MP2_TranscodeAudio() async throws {
        guard let input = resourceURL("test_mpg_mp2.mpg") else {
            XCTFail("Missing test resource: test_mpg_mp2.mpg"); return
        }
        let output = outputDir.appendingPathComponent("output.mp4")
        try await videoConverter.convert(input: input, output: output) { _ in }
        verifyMP4HasAudioAndVideo(output)
    }

    // MARK: - Image Tests

    func testBMP_Conversion() async throws {
        guard let input = resourceURL("test_image.bmp") else {
            XCTFail("Missing test resource: test_image.bmp"); return
        }
        let outputs = try await imageConverter.convert(input: input, outputDir: outputDir)
        XCTAssertFalse(outputs.isEmpty, "BMP conversion produced no output")
        for url in outputs { verifyImageIsValid(url) }
    }

    func testWebP_Conversion() async throws {
        guard let input = resourceURL("test_image.webp") else {
            XCTFail("Missing test resource: test_image.webp"); return
        }
        let outputs = try await imageConverter.convert(input: input, outputDir: outputDir)
        XCTAssertFalse(outputs.isEmpty, "WebP conversion produced no output")
        for url in outputs { verifyImageIsValid(url) }
    }

    func testTIFF_Conversion() async throws {
        guard let input = resourceURL("test_image.tiff") else {
            XCTFail("Missing test resource: test_image.tiff"); return
        }
        let outputs = try await imageConverter.convert(input: input, outputDir: outputDir)
        XCTAssertFalse(outputs.isEmpty, "TIFF conversion produced no output")
        for url in outputs { verifyImageIsValid(url) }
    }

    func testSVG_Conversion() async throws {
        guard let input = resourceURL("test_image.svg") else {
            XCTFail("Missing test resource: test_image.svg"); return
        }
        let outputs = try await imageConverter.convert(input: input, outputDir: outputDir)
        XCTAssertFalse(outputs.isEmpty, "SVG conversion produced no output")
        for url in outputs { verifyImageIsValid(url) }
    }

    func testTGA_Conversion() async throws {
        guard let input = resourceURL("test_image.tga") else {
            XCTFail("Missing test resource: test_image.tga"); return
        }
        let outputs = try await imageConverter.convert(input: input, outputDir: outputDir)
        XCTAssertFalse(outputs.isEmpty, "TGA conversion produced no output")
        for url in outputs { verifyImageIsValid(url) }
    }

    func testICO_Conversion() async throws {
        guard let input = resourceURL("test_image.ico") else {
            XCTFail("Missing test resource: test_image.ico"); return
        }
        let outputs = try await imageConverter.convert(input: input, outputDir: outputDir)
        XCTAssertFalse(outputs.isEmpty, "ICO conversion produced no output")
        for url in outputs { verifyImageIsValid(url) }
    }

    func testPPM_Conversion() async throws {
        guard let input = resourceURL("test_image.ppm") else {
            XCTFail("Missing test resource: test_image.ppm"); return
        }
        let outputs = try await imageConverter.convert(input: input, outputDir: outputDir)
        XCTAssertFalse(outputs.isEmpty, "PPM conversion produced no output")
        for url in outputs { verifyImageIsValid(url) }
    }

    func testPCX_Conversion() async throws {
        guard let input = resourceURL("test_image.pcx") else {
            XCTFail("Missing test resource: test_image.pcx"); return
        }
        let outputs = try await imageConverter.convert(input: input, outputDir: outputDir)
        XCTAssertFalse(outputs.isEmpty, "PCX conversion produced no output")
        for url in outputs { verifyImageIsValid(url) }
    }
}
