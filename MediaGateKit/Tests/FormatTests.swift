import XCTest
@testable import MediaGateKit

/// Comprehensive tests for format detection, extension mapping, and magic bytes.
final class FormatTests: XCTestCase {

    // MARK: - Extension Registry

    /// Every video extension must be recognized and mapped to .video category.
    func testAllVideoExtensionsAreRecognized() {
        let videoExtensions = [
            "mpg", "mpeg", "m2v",
            "avi", "divx",
            "wmv", "asf",
            "flv", "f4v",
            "mkv",
            "webm",
            "3gp", "3g2",
            "ts", "m2ts", "mts",
            "vob",
            "ogv",
            "rm", "rmvb",
        ]

        for ext in videoExtensions {
            let info = SupportedFormats.formatInfo(forExtension: ext)
            XCTAssertNotNil(info, "Video extension '\(ext)' not found in SupportedFormats")
            XCTAssertEqual(info?.category, .video, "Extension '\(ext)' should be .video but got \(String(describing: info?.category))")
            XCTAssertEqual(info?.outputExtension, "mp4", "Video extension '\(ext)' should output mp4")
        }
    }

    /// Every image extension must be recognized and mapped to .image category.
    func testAllImageExtensionsAreRecognized() {
        let imageExtensions = [
            "bmp",
            "webp",
            "tiff", "tif",
            "svg",
            "tga",
            "ico",
            "psd",
            "pcx",
            "ppm", "pgm", "pbm",
        ]

        for ext in imageExtensions {
            let info = SupportedFormats.formatInfo(forExtension: ext)
            XCTAssertNotNil(info, "Image extension '\(ext)' not found in SupportedFormats")
            XCTAssertEqual(info?.category, .image, "Extension '\(ext)' should be .image but got \(String(describing: info?.category))")
        }
    }

    /// Every RAW photo extension must be recognized as .image with jpeg output.
    func testAllRAWExtensionsAreRecognized() {
        let rawExtensions = [
            "cr2", "nef", "arw", "dng", "orf", "rw2", "raf", "pef",
            "srw", "x3f", "3fr", "erf", "kdc", "mrw", "dcr",
        ]

        for ext in rawExtensions {
            let info = SupportedFormats.formatInfo(forExtension: ext)
            XCTAssertNotNil(info, "RAW extension '\(ext)' not found in SupportedFormats")
            XCTAssertEqual(info?.category, .image, "RAW extension '\(ext)' should be .image")
            XCTAssertEqual(info?.outputExtension, "jpeg", "RAW extension '\(ext)' should output jpeg")
            XCTAssertEqual(info?.id, "raw", "RAW extension '\(ext)' should have id 'raw'")
        }
    }

    /// Every passthrough extension must be recognized and mapped to .passthrough.
    func testAllPassthroughExtensionsAreRecognized() {
        let passthroughExtensions = [
            "mp4",
            "mov",
            "m4v",
            "hevc",
            "jpg", "jpeg",
            "png",
            "heif", "heic",
            "gif",
            "avif",
        ]

        for ext in passthroughExtensions {
            let info = SupportedFormats.formatInfo(forExtension: ext)
            XCTAssertNotNil(info, "Passthrough extension '\(ext)' not found in SupportedFormats")
            XCTAssertEqual(info?.category, .passthrough, "Extension '\(ext)' should be .passthrough but got \(String(describing: info?.category))")
        }
    }

    /// Extension lookup must be case-insensitive.
    func testExtensionLookupIsCaseInsensitive() {
        let cases = ["MKV", "Mkv", "mkv", "WEBP", "Cr2", "PNG", "MP4"]
        for ext in cases {
            XCTAssertNotNil(
                SupportedFormats.formatInfo(forExtension: ext),
                "Case-insensitive lookup failed for '\(ext)'"
            )
        }
    }

    /// Unknown extensions should return nil.
    func testUnknownExtensionsReturnNil() {
        let unknowns = ["xyz", "docx", "pdf", "mp3", "aac", "zip", "tar", "exe", ""]
        for ext in unknowns {
            XCTAssertNil(
                SupportedFormats.formatInfo(forExtension: ext),
                "Extension '\(ext)' should not be recognized"
            )
        }
    }

    // MARK: - Format Collections

    /// Verify total format counts match expectations.
    func testFormatCounts() {
        XCTAssertEqual(SupportedFormats.convertibleVideos.count, 11, "Should have 11 video formats")
        XCTAssertEqual(SupportedFormats.convertibleImages.count, 10, "Should have 10 image formats")
        XCTAssertEqual(SupportedFormats.passthroughFormats.count, 9, "Should have 9 passthrough formats")
        XCTAssertEqual(SupportedFormats.allFormats.count, 30, "Should have 30 total formats")
    }

    /// Verify extension sets contain all expected entries.
    func testConvertibleExtensionSetIsComplete() {
        let expected: Set<String> = [
            // Video
            "mpg", "mpeg", "m2v", "avi", "divx", "wmv", "asf", "flv", "f4v",
            "mkv", "webm", "3gp", "3g2", "ts", "m2ts", "mts", "vob", "ogv", "rm", "rmvb",
            // Image
            "bmp", "webp", "tiff", "tif", "svg", "tga", "ico", "psd",
            "cr2", "nef", "arw", "dng", "orf", "rw2", "raf", "pef",
            "srw", "x3f", "3fr", "erf", "kdc", "mrw", "dcr",
            "pcx", "ppm", "pgm", "pbm",
        ]

        for ext in expected {
            XCTAssertTrue(
                SupportedFormats.convertibleExtensions.contains(ext),
                "Convertible set missing '\(ext)'"
            )
        }
    }

    func testPassthroughExtensionSetIsComplete() {
        let expected: Set<String> = [
            "mp4", "mov", "m4v", "hevc", "jpg", "jpeg", "png", "heif", "heic", "gif", "avif",
        ]

        for ext in expected {
            XCTAssertTrue(
                SupportedFormats.passthroughExtensions.contains(ext),
                "Passthrough set missing '\(ext)'"
            )
        }
    }

    /// No extension should appear in both convertible and passthrough sets.
    func testNoOverlapBetweenConvertibleAndPassthrough() {
        let overlap = SupportedFormats.convertibleExtensions.intersection(SupportedFormats.passthroughExtensions)
        XCTAssertTrue(overlap.isEmpty, "Extensions appear in both convertible and passthrough: \(overlap)")
    }

    /// Every format must have a non-empty display name.
    func testAllFormatsHaveDisplayNames() {
        for format in SupportedFormats.allFormats {
            XCTAssertFalse(format.displayName.isEmpty, "Format '\(format.id)' has empty display name")
        }
    }

    /// Every format must have at least one extension.
    func testAllFormatsHaveExtensions() {
        for format in SupportedFormats.allFormats {
            XCTAssertFalse(format.extensions.isEmpty, "Format '\(format.id)' has no extensions")
        }
    }

    /// Every format must have a non-empty output extension.
    func testAllFormatsHaveOutputExtension() {
        for format in SupportedFormats.allFormats {
            XCTAssertFalse(format.outputExtension.isEmpty, "Format '\(format.id)' has empty output extension")
        }
    }

    /// Format IDs must be unique.
    func testFormatIDsAreUnique() {
        let ids = SupportedFormats.allFormats.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "Duplicate format IDs found: \(ids.filter { id in ids.filter { $0 == id }.count > 1 })")
    }

    // MARK: - FormatDetector

    /// FormatDetector should resolve extensions to correct MediaFormat cases.
    func testFormatDetectorByExtension() {
        let detector = FormatDetector()
        let tempDir = FileManager.default.temporaryDirectory

        // Video
        let mkvURL = tempDir.appendingPathComponent("test.mkv")
        FileManager.default.createFile(atPath: mkvURL.path, contents: Data([0x00]), attributes: nil)
        if case .video(let info) = detector.detect(fileURL: mkvURL) {
            XCTAssertEqual(info.id, "mkv")
        } else {
            XCTFail("Expected .video for .mkv")
        }
        try? FileManager.default.removeItem(at: mkvURL)

        // Image
        let bmpURL = tempDir.appendingPathComponent("test.bmp")
        FileManager.default.createFile(atPath: bmpURL.path, contents: Data([0x00]), attributes: nil)
        if case .image(let info) = detector.detect(fileURL: bmpURL) {
            XCTAssertEqual(info.id, "bmp")
        } else {
            XCTFail("Expected .image for .bmp")
        }
        try? FileManager.default.removeItem(at: bmpURL)

        // Passthrough
        let mp4URL = tempDir.appendingPathComponent("test.mp4")
        FileManager.default.createFile(atPath: mp4URL.path, contents: Data([0x00]), attributes: nil)
        if case .nativelySupported = detector.detect(fileURL: mp4URL) {
            // OK
        } else {
            XCTFail("Expected .nativelySupported for .mp4")
        }
        try? FileManager.default.removeItem(at: mp4URL)

        // Unsupported
        let unknownURL = tempDir.appendingPathComponent("test.xyz")
        FileManager.default.createFile(atPath: unknownURL.path, contents: Data([0x00]), attributes: nil)
        if case .unsupported(let ext) = detector.detect(fileURL: unknownURL) {
            XCTAssertEqual(ext, "xyz")
        } else {
            XCTFail("Expected .unsupported for .xyz")
        }
        try? FileManager.default.removeItem(at: unknownURL)
    }

    /// Magic bytes should correctly identify formats.
    func testMagicBytesIdentification() {
        let tempDir = FileManager.default.temporaryDirectory

        let testCases: [(filename: String, bytes: [UInt8], expected: String)] = [
            ("test.dat", [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "png"),
            ("test.dat", [0xFF, 0xD8, 0xFF, 0xE0], "jpeg"),
            ("test.dat", [0x47, 0x49, 0x46, 0x38, 0x39, 0x61], "gif"),
            ("test.dat", [0x42, 0x4D, 0x00, 0x00], "bmp"),
            ("test.dat", [0x38, 0x42, 0x50, 0x53], "psd"),
            ("test.dat", [0x46, 0x4C, 0x56, 0x01], "flv"),
            ("test.dat", [0x1A, 0x45, 0xDF, 0xA3], "mkv"),  // EBML
            ("test.dat", [0x30, 0x26, 0xB2, 0x75], "wmv"),
            ("test.dat", [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00], "avi"),
            ("test.dat", [0x2E, 0x52, 0x4D, 0x46], "rm"),
            ("test.dat", [0x4F, 0x67, 0x67, 0x53], "ogg"),
            ("test.dat", [0x00, 0x00, 0x01, 0x00], "ico"),
        ]

        for (filename, bytes, expected) in testCases {
            let url = tempDir.appendingPathComponent(filename)
            var data = Data(bytes)
            // Pad to 32 bytes (MagicBytes reads 32)
            while data.count < 32 { data.append(0x00) }
            FileManager.default.createFile(atPath: url.path, contents: data, attributes: nil)

            let result = MagicBytes.identify(fileURL: url)
            XCTAssertEqual(result, expected, "Magic bytes for \(expected) failed, got \(String(describing: result))")

            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Total Extension Count

    /// Verify the total number of distinct extensions matches what we advertise.
    func testTotalExtensionCount() {
        let allExtensions = SupportedFormats.allFormats.flatMap(\.extensions)
        let uniqueExtensions = Set(allExtensions)
        // 20 video + 27 image + 11 passthrough = 58
        XCTAssertEqual(uniqueExtensions.count, 58, "Expected 58 unique extensions, got \(uniqueExtensions.count)")
    }
}
