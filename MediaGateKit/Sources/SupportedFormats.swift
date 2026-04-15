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

/// Central registry of all media formats that MediaGate can handle.
///
/// This enum serves as the single source of truth for which file extensions
/// are convertible, which are natively supported (passthrough), and what
/// output format each input maps to.
public enum SupportedFormats {

    /// Metadata about a supported format.
    public struct FormatInfo: Sendable, Identifiable {
        public let id: String
        public let extensions: [String]
        public let displayName: String
        public let category: Category
        public let outputExtension: String

        public init(id: String, extensions: [String], displayName: String, category: Category, outputExtension: String) {
            self.id = id
            self.extensions = extensions
            self.displayName = displayName
            self.category = category
            self.outputExtension = outputExtension
        }

        public enum Category: String, Sendable, CaseIterable {
            case video
            case image
            case passthrough
        }
    }

    // MARK: - Video Formats (→ .mp4)

    public static let convertibleVideos: [FormatInfo] = [
        FormatInfo(id: "mpeg",  extensions: ["mpg", "mpeg", "m2v"],   displayName: "MPEG-1/2",          category: .video, outputExtension: "mp4"),
        FormatInfo(id: "avi",   extensions: ["avi", "divx"],           displayName: "AVI",               category: .video, outputExtension: "mp4"),
        FormatInfo(id: "wmv",   extensions: ["wmv", "asf"],            displayName: "WMV",               category: .video, outputExtension: "mp4"),
        FormatInfo(id: "flv",   extensions: ["flv", "f4v"],            displayName: "Flash Video",       category: .video, outputExtension: "mp4"),
        FormatInfo(id: "mkv",   extensions: ["mkv"],                   displayName: "Matroska",          category: .video, outputExtension: "mp4"),
        FormatInfo(id: "webm",  extensions: ["webm"],                  displayName: "WebM",              category: .video, outputExtension: "mp4"),
        FormatInfo(id: "3gp",   extensions: ["3gp", "3g2"],            displayName: "3GPP",              category: .video, outputExtension: "mp4"),
        FormatInfo(id: "ts",    extensions: ["ts", "m2ts", "mts"],     displayName: "Transport Stream",  category: .video, outputExtension: "mp4"),
        FormatInfo(id: "vob",   extensions: ["vob"],                   displayName: "DVD VOB",           category: .video, outputExtension: "mp4"),
        FormatInfo(id: "ogv",   extensions: ["ogv"],                   displayName: "OGG Video",         category: .video, outputExtension: "mp4"),
        FormatInfo(id: "rm",    extensions: ["rm", "rmvb"],            displayName: "RealMedia",         category: .video, outputExtension: "mp4"),
    ]

    // MARK: - Image Formats (→ .png or .jpeg)

    public static let convertibleImages: [FormatInfo] = [
        FormatInfo(id: "bmp",   extensions: ["bmp"],                          displayName: "BMP",              category: .image, outputExtension: "png"),
        FormatInfo(id: "webp",  extensions: ["webp"],                         displayName: "WebP",             category: .image, outputExtension: "jpeg"),
        FormatInfo(id: "tiff",  extensions: ["tiff", "tif"],                  displayName: "TIFF",             category: .image, outputExtension: "jpeg"),
        FormatInfo(id: "svg",   extensions: ["svg"],                          displayName: "SVG",              category: .image, outputExtension: "png"),
        FormatInfo(id: "tga",   extensions: ["tga"],                          displayName: "TGA",              category: .image, outputExtension: "png"),
        FormatInfo(id: "ico",   extensions: ["ico"],                          displayName: "ICO",              category: .image, outputExtension: "png"),
        FormatInfo(id: "psd",   extensions: ["psd"],                          displayName: "Photoshop",        category: .image, outputExtension: "png"),
        FormatInfo(id: "raw",   extensions: ["cr2", "nef", "arw", "dng", "orf", "rw2", "raf", "pef", "srw", "x3f", "3fr", "erf", "kdc", "mrw", "dcr"], displayName: "RAW Photo", category: .image, outputExtension: "jpeg"),
        FormatInfo(id: "pcx",   extensions: ["pcx"],                          displayName: "PCX",              category: .image, outputExtension: "png"),
        FormatInfo(id: "ppm",   extensions: ["ppm", "pgm", "pbm"],           displayName: "PPM/PGM/PBM",      category: .image, outputExtension: "png"),
    ]

    // MARK: - Passthrough Formats (already supported by Photos)

    public static let passthroughFormats: [FormatInfo] = [
        FormatInfo(id: "mp4",  extensions: ["mp4"],        displayName: "MP4",   category: .passthrough, outputExtension: "mp4"),
        FormatInfo(id: "mov",  extensions: ["mov"],        displayName: "MOV",   category: .passthrough, outputExtension: "mov"),
        FormatInfo(id: "m4v",  extensions: ["m4v"],        displayName: "M4V",   category: .passthrough, outputExtension: "m4v"),
        FormatInfo(id: "hevc", extensions: ["hevc"],       displayName: "HEVC",  category: .passthrough, outputExtension: "hevc"),
        FormatInfo(id: "jpg",  extensions: ["jpg", "jpeg"], displayName: "JPEG", category: .passthrough, outputExtension: "jpeg"),
        FormatInfo(id: "png",  extensions: ["png"],        displayName: "PNG",   category: .passthrough, outputExtension: "png"),
        FormatInfo(id: "heif", extensions: ["heif", "heic"], displayName: "HEIF", category: .passthrough, outputExtension: "heif"),
        FormatInfo(id: "gif",  extensions: ["gif"],        displayName: "GIF",   category: .passthrough, outputExtension: "gif"),
        FormatInfo(id: "avif", extensions: ["avif"],       displayName: "AVIF",  category: .passthrough, outputExtension: "avif"),
    ]

    /// All formats the app can handle (convert + passthrough).
    public static let allFormats: [FormatInfo] = convertibleVideos + convertibleImages + passthroughFormats

    /// All convertible formats (video + image, excluding passthrough).
    public static let allConvertible: [FormatInfo] = convertibleVideos + convertibleImages

    /// A set of all file extensions that should be passed through without conversion.
    public static let passthroughExtensions: Set<String> = {
        Set(passthroughFormats.flatMap(\.extensions))
    }()

    /// A set of all file extensions that can be converted.
    public static let convertibleExtensions: Set<String> = {
        Set(allConvertible.flatMap(\.extensions))
    }()

    /// Looks up format info for a given file extension.
    ///
    /// - Parameter ext: The file extension (without the leading dot), case-insensitive.
    /// - Returns: The matching ``FormatInfo``, or `nil` if the extension is not recognized.
    public static func formatInfo(forExtension ext: String) -> FormatInfo? {
        let lowered = ext.lowercased()
        return allFormats.first { $0.extensions.contains(lowered) }
    }
}
