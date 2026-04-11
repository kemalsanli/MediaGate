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

/// Quality preset for video conversion output.
///
/// Each case maps to a different bitrate multiplier used during
/// FFmpeg transcoding.
public enum VideoQualityPreset: String, Sendable, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case original

    public var id: String { rawValue }

    /// Human-readable label for display in the UI.
    public var displayName: String {
        switch self {
        case .low:      return String(localized: "Low")
        case .medium:   return String(localized: "Medium")
        case .high:     return String(localized: "High")
        case .original: return String(localized: "Original")
        }
    }
}

/// UserDefaults-backed settings model for conversion preferences.
///
/// Reads and writes all values through the App Group shared
/// ``SharedConstants/sharedDefaults`` so both the main app and the
/// Share Extension see the same configuration.
public final class ConversionSettings: Sendable {

    // MARK: - Singleton

    /// Shared instance used throughout the app and extension.
    public static let shared = ConversionSettings()

    // MARK: - Keys

    private enum Keys {
        static let preserveMetadata     = "settings.preserveMetadata"
        static let stripLocation        = "settings.stripLocation"
        static let compressionQuality   = "settings.compressionQuality"
        static let compressNativeFormats = "settings.compressNativeFormats"
        static let videoQualityPreset   = "settings.videoQualityPreset"
    }

    // MARK: - Defaults

    private enum Defaults {
        static let preserveMetadata: Bool       = true
        static let stripLocation: Bool          = false
        static let compressionQuality: Double   = 0.8
        static let compressNativeFormats: Bool   = false
        static let videoQualityPreset: String   = VideoQualityPreset.medium.rawValue
    }

    // MARK: - Init

    private init() {
        // Register defaults so first reads return the expected values.
        SharedConstants.sharedDefaults?.register(defaults: [
            Keys.preserveMetadata:     Defaults.preserveMetadata,
            Keys.stripLocation:        Defaults.stripLocation,
            Keys.compressionQuality:   Defaults.compressionQuality,
            Keys.compressNativeFormats: Defaults.compressNativeFormats,
            Keys.videoQualityPreset:   Defaults.videoQualityPreset,
        ])
    }

    // MARK: - Properties

    /// Whether to preserve EXIF/GPS metadata during conversion.
    public var preserveMetadata: Bool {
        get { SharedConstants.sharedDefaults?.bool(forKey: Keys.preserveMetadata) ?? Defaults.preserveMetadata }
        set { SharedConstants.sharedDefaults?.set(newValue, forKey: Keys.preserveMetadata) }
    }

    /// Strip GPS location from metadata (only effective when
    /// ``preserveMetadata`` is `true`).
    public var stripLocation: Bool {
        get { SharedConstants.sharedDefaults?.bool(forKey: Keys.stripLocation) ?? Defaults.stripLocation }
        set { SharedConstants.sharedDefaults?.set(newValue, forKey: Keys.stripLocation) }
    }

    /// JPEG quality for images / video bitrate multiplier.
    ///
    /// Clamped to the range `0.1 ... 1.0`.
    public var compressionQuality: Double {
        get {
            let value = SharedConstants.sharedDefaults?.double(forKey: Keys.compressionQuality) ?? Defaults.compressionQuality
            return min(max(value, 0.1), 1.0)
        }
        set {
            let clamped = min(max(newValue, 0.1), 1.0)
            SharedConstants.sharedDefaults?.set(clamped, forKey: Keys.compressionQuality)
        }
    }

    /// When `true`, even natively supported formats (MP4, JPEG, etc.)
    /// are re-encoded/compressed to reduce file size.
    public var compressNativeFormats: Bool {
        get { SharedConstants.sharedDefaults?.bool(forKey: Keys.compressNativeFormats) ?? Defaults.compressNativeFormats }
        set { SharedConstants.sharedDefaults?.set(newValue, forKey: Keys.compressNativeFormats) }
    }

    /// The quality preset used for video transcoding.
    public var videoQualityPreset: VideoQualityPreset {
        get {
            let raw = SharedConstants.sharedDefaults?.string(forKey: Keys.videoQualityPreset) ?? Defaults.videoQualityPreset
            return VideoQualityPreset(rawValue: raw) ?? .medium
        }
        set {
            SharedConstants.sharedDefaults?.set(newValue.rawValue, forKey: Keys.videoQualityPreset)
        }
    }
}
