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

/// File signature lookup table for identifying media formats by their
/// leading bytes (magic numbers).
///
/// When a file extension is missing or misleading, magic bytes provide
/// a reliable way to determine the actual format.
public enum MagicBytes {

    /// A single signature entry: the byte pattern and its offset from file start.
    public struct Signature: Sendable {
        public let bytes: [UInt8]
        public let offset: Int

        public init(_ bytes: [UInt8], offset: Int = 0) {
            self.bytes = bytes
            self.offset = offset
        }
    }

    /// Known file signatures mapped to their format identifier strings.
    ///
    /// The key is a human-readable format name that aligns with
    /// ``SupportedFormats/FormatInfo/identifier``.
    public static let signatures: [(format: String, signature: Signature)] = [
        // Video formats
        ("avi",   Signature([0x52, 0x49, 0x46, 0x46])),           // RIFF
        ("flv",   Signature([0x46, 0x4C, 0x56])),                 // FLV
        ("mkv",   Signature([0x1A, 0x45, 0xDF, 0xA3])),           // EBML (Matroska/WebM)
        ("webm",  Signature([0x1A, 0x45, 0xDF, 0xA3])),           // EBML (same header as MKV)
        ("wmv",   Signature([0x30, 0x26, 0xB2, 0x75])),           // ASF/WMV
        ("mpg",   Signature([0x00, 0x00, 0x01, 0xBA])),           // MPEG-PS
        ("mpg",   Signature([0x00, 0x00, 0x01, 0xB3])),           // MPEG-1 video
        ("ts",    Signature([0x47])),                               // MPEG-TS sync byte
        ("3gp",   Signature([0x66, 0x74, 0x79, 0x70, 0x33, 0x67], offset: 4)), // ftyp3g
        ("rm",    Signature([0x2E, 0x52, 0x4D, 0x46])),           // .RMF
        ("ogg",   Signature([0x4F, 0x67, 0x67, 0x53])),           // OggS
        ("vob",   Signature([0x00, 0x00, 0x01, 0xBA])),           // VOB (same as MPEG-PS)

        // Native/passthrough video
        ("mp4",   Signature([0x66, 0x74, 0x79, 0x70], offset: 4)), // ftyp (MP4/MOV/M4V)
        ("mov",   Signature([0x66, 0x74, 0x79, 0x70, 0x71, 0x74], offset: 4)), // ftypqt

        // Image formats
        ("bmp",   Signature([0x42, 0x4D])),                        // BM
        ("webp",  Signature([0x57, 0x45, 0x42, 0x50], offset: 8)), // WEBP at offset 8 in RIFF
        ("tiff",  Signature([0x49, 0x49, 0x2A, 0x00])),           // TIFF little-endian
        ("tiff",  Signature([0x4D, 0x4D, 0x00, 0x2A])),           // TIFF big-endian
        ("svg",   Signature([0x3C, 0x73, 0x76, 0x67])),           // <svg
        ("svg",   Signature([0x3C, 0x3F, 0x78, 0x6D, 0x6C])),    // <?xml (SVG often starts with XML declaration)
        ("ico",   Signature([0x00, 0x00, 0x01, 0x00])),           // ICO
        ("psd",   Signature([0x38, 0x42, 0x50, 0x53])),           // 8BPS
        ("tga",   Signature([])),                                   // TGA has no reliable magic bytes
        ("ppm",   Signature([0x50, 0x36])),                        // P6 (binary PPM)
        ("pgm",   Signature([0x50, 0x35])),                        // P5 (binary PGM)
        ("pbm",   Signature([0x50, 0x34])),                        // P4 (binary PBM)

        // RAW photo formats
        ("cr2",   Signature([0x49, 0x49, 0x2A, 0x00])),           // Canon CR2 (TIFF-based)
        ("nef",   Signature([0x4D, 0x4D, 0x00, 0x2A])),           // Nikon NEF (TIFF-based)
        ("arw",   Signature([0x49, 0x49, 0x2A, 0x00])),           // Sony ARW (TIFF-based)
        ("dng",   Signature([0x49, 0x49, 0x2A, 0x00])),           // Adobe DNG (TIFF-based)

        // Native/passthrough images
        ("png",   Signature([0x89, 0x50, 0x4E, 0x47])),           // PNG
        ("jpeg",  Signature([0xFF, 0xD8, 0xFF])),                  // JPEG
        ("gif",   Signature([0x47, 0x49, 0x46])),                  // GIF
        ("heif",  Signature([0x66, 0x74, 0x79, 0x70, 0x68, 0x65], offset: 4)), // ftyphe (HEIF/HEIC)
    ]

    /// Reads the first bytes of a file and attempts to identify its format.
    ///
    /// - Parameter url: The file URL to inspect.
    /// - Returns: The format identifier string, or `nil` if no match is found.
    public static func identify(fileURL url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let headerData = handle.readData(ofLength: 32)
        guard !headerData.isEmpty else { return nil }
        let header = Array(headerData)

        for (format, sig) in signatures {
            guard !sig.bytes.isEmpty else { continue }
            let end = sig.offset + sig.bytes.count
            guard header.count >= end else { continue }

            let slice = Array(header[sig.offset..<end])
            if slice == sig.bytes {
                return format
            }
        }
        return nil
    }
}
