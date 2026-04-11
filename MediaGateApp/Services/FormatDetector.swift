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
import UniformTypeIdentifiers

/// The detected media format of a file.
enum MediaFormat: Sendable {
    /// A video format that needs transcoding to MP4.
    case video(SupportedFormats.FormatInfo)

    /// An image format that needs conversion to PNG or JPEG.
    case image(SupportedFormats.FormatInfo)

    /// A format already supported by Photos — save directly, no transcoding needed.
    case nativelySupported

    /// An unrecognized format that MediaGate cannot handle.
    case unsupported(String)
}

/// A type that can identify the media format of a file.
protocol FormatDetecting: Sendable {
    /// Inspects the file at the given URL and determines its media format.
    ///
    /// Detection uses a two-pass strategy:
    /// 1. Check the UTType from the file extension.
    /// 2. Validate with magic bytes (first 16–32 bytes of the file).
    /// 3. If there is a conflict, magic bytes take precedence.
    ///
    /// - Parameter fileURL: The local file URL to inspect.
    /// - Returns: The detected ``MediaFormat``.
    func detect(fileURL: URL) -> MediaFormat
}

/// Default implementation of ``FormatDetecting`` that combines file extension
/// lookup with magic byte validation.
struct FormatDetector: FormatDetecting {

    func detect(fileURL: URL) -> MediaFormat {
        let ext = fileURL.pathExtension.lowercased()

        // Step 1: Try extension-based lookup
        let extensionFormat = SupportedFormats.formatInfo(forExtension: ext)

        // Step 2: Try magic bytes
        let magicFormat: SupportedFormats.FormatInfo? = {
            guard let magicID = MagicBytes.identify(fileURL: fileURL) else { return nil }
            return SupportedFormats.allFormats.first { $0.id == magicID }
        }()

        // Step 3: Resolve — magic bytes win on conflict
        let resolved = magicFormat ?? extensionFormat

        guard let format = resolved else {
            return .unsupported(ext.isEmpty ? "unknown" : ext)
        }

        switch format.category {
        case .passthrough:
            return .nativelySupported
        case .video:
            return .video(format)
        case .image:
            return .image(format)
        }
    }
}
