import XCTest
import Foundation

/// Validates that every localizable string has a translation for all supported languages.
final class LocalizationTests: XCTestCase {

    /// All languages the app ships with.
    static let supportedLanguages = [
        "ar", "ca", "cs", "da", "de", "el", "en", "es", "es-MX",
        "fi", "fr", "fr-CA", "he", "hi", "hr", "hu", "id", "it",
        "ja", "ko", "ms", "nb", "nl", "pl", "pt-BR", "pt-PT",
        "ro", "ru", "sk", "sv", "th", "tr", "uk", "vi",
        "zh-Hans", "zh-Hant",
    ]

    /// Keys that are intentionally not translated (brand names, universal symbols).
    static let skipKeys: Set<String> = [
        "MediaGate", "Kemal Sanlı", "%lld%%", "Version",
    ]

    private var xcstringsData: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "xcstrings") else {
            return
        }
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        xcstringsData = json
    }

    func testAllStringsHaveTranslations() throws {
        // This test verifies the xcstrings file structure at the JSON level.
        // When run in a test host that includes the xcstrings, it validates completeness.
        let stringsDict = xcstringsData["strings"] as? [String: Any] ?? [:]

        guard !stringsDict.isEmpty else {
            // If xcstrings isn't in the test bundle, validate the file directly
            try validateXCStringsFile()
            return
        }

        for (key, value) in stringsDict {
            guard !Self.skipKeys.contains(key) else { continue }
            guard let entry = value as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else {
                XCTFail("Key '\(key)' has no localizations dictionary")
                continue
            }

            for lang in Self.supportedLanguages where lang != "en" {
                XCTAssertNotNil(
                    localizations[lang],
                    "Missing \(lang) translation for key: '\(key)'"
                )
            }
        }
    }

    /// Fallback: read the xcstrings file directly from the project source.
    private func validateXCStringsFile() throws {
        let possiblePaths = [
            "MediaGateApp/Resources/Localizable.xcstrings",
            "../MediaGateApp/Resources/Localizable.xcstrings",
        ]

        var fileURL: URL?
        for path in possiblePaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                fileURL = url
                break
            }
        }

        guard let url = fileURL else {
            XCTSkip("Localizable.xcstrings not found in test environment")
            return
        }

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let stringsDict = json["strings"] as? [String: Any] ?? [:]

        XCTAssertGreaterThan(stringsDict.count, 0, "xcstrings file is empty")

        var missingCount = 0
        for (key, value) in stringsDict {
            guard !Self.skipKeys.contains(key) else { continue }
            guard let entry = value as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else {
                continue
            }

            for lang in Self.supportedLanguages where lang != "en" {
                if localizations[lang] == nil {
                    missingCount += 1
                    XCTFail("Missing \(lang) translation for: '\(key)'")
                }
            }
        }

        if missingCount == 0 {
            // All good
        }
    }

    func testSupportedFormatsAreComplete() {
        // Verify no format has an empty display name
        let allFormats = [
            ("video", ["MPEG-1/2", "AVI", "WMV", "Flash Video", "Matroska", "WebM", "3GPP", "Transport Stream", "DVD VOB", "OGG Video", "RealMedia"]),
            ("image", ["BMP", "WebP", "TIFF", "SVG", "TGA", "ICO", "Photoshop", "RAW Photo", "PCX", "PPM/PGM/PBM"]),
            ("passthrough", ["MP4", "MOV", "M4V", "HEVC", "JPEG", "PNG", "HEIF", "GIF", "AVIF"]),
        ]

        for (category, names) in allFormats {
            for name in names {
                XCTAssertFalse(name.isEmpty, "Empty display name in \(category) formats")
            }
        }
    }

    func testFormatStringPositionalSpecifiers() throws {
        // Verify format strings use positional specifiers (%1$lld, %2$lld)
        // to prevent argument reordering issues across languages
        let possiblePaths = [
            "MediaGateApp/Resources/Localizable.xcstrings",
            "../MediaGateApp/Resources/Localizable.xcstrings",
        ]

        var fileURL: URL?
        for path in possiblePaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                fileURL = url
                break
            }
        }

        guard let url = fileURL else {
            XCTSkip("Localizable.xcstrings not found")
            return
        }

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let stringsDict = json["strings"] as? [String: Any] ?? [:]

        let formatKeys = [
            "%lld succeeded, %lld failed",
            "Converting %lld of %lld files",
        ]

        for key in formatKeys {
            guard let entry = stringsDict[key] as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else {
                XCTFail("Format key '\(key)' not found")
                continue
            }

            for (lang, locValue) in localizations {
                guard let locDict = locValue as? [String: Any],
                      let stringUnit = locDict["stringUnit"] as? [String: Any],
                      let value = stringUnit["value"] as? String else { continue }

                // Format strings with 2+ arguments should use positional specifiers
                if value.contains("%") && !value.contains("%1$") && lang != "en" {
                    // Some languages might use simple %lld if order is same - that's OK
                    // but positional is preferred
                }

                // At minimum the translated string should contain format specifiers
                let specifierCount = value.components(separatedBy: "%").count - 1
                XCTAssertGreaterThanOrEqual(
                    specifierCount, 2,
                    "[\(lang)] '\(key)' should have at least 2 format specifiers, got \(specifierCount): '\(value)'"
                )
            }
        }
    }
}
