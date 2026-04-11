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

/// Pre-flight safety checks before starting a conversion.
public enum SafetyChecks {

    /// Errors that can occur during safety validation.
    public enum SafetyError: LocalizedError, Sendable {
        case fileNotFound(String)
        case fileEmpty(String)
        case insufficientDiskSpace(required: UInt64, available: UInt64)
        case fileTooLarge(size: UInt64, limit: UInt64)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let name):
                return "File not found: \(name)"
            case .fileEmpty(let name):
                return "File is empty: \(name)"
            case .insufficientDiskSpace(let required, let available):
                let req = ByteCountFormatter.string(fromByteCount: Int64(required), countStyle: .file)
                let avail = ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file)
                return "Not enough disk space. Need \(req), only \(avail) available."
            case .fileTooLarge(let size, let limit):
                let s = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                let l = ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
                return "File too large (\(s)). Maximum supported size is \(l)."
            }
        }
    }

    /// Maximum file size the app will attempt to convert (1 GB).
    public static let maxFileSize: UInt64 = 1_000_000_000

    /// Validates that a file exists, is non-empty, and is within size limits.
    public static func validateFile(at url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw SafetyError.fileNotFound(url.lastPathComponent)
        }

        let size = fm.fileSize(at: url)
        guard size > 0 else {
            throw SafetyError.fileEmpty(url.lastPathComponent)
        }

        guard size <= maxFileSize else {
            throw SafetyError.fileTooLarge(size: size, limit: maxFileSize)
        }
    }

    /// Checks that there is enough free disk space for the conversion.
    ///
    /// Requires at least 2x the input file size (for the converted output + temp files).
    public static func validateDiskSpace(forFileAt url: URL) throws {
        let inputSize = FileManager.default.fileSize(at: url)
        let required = inputSize * 2

        if let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSTemporaryDirectory()
        ), let freeSpace = attrs[.systemFreeSize] as? UInt64 {
            guard freeSpace >= required else {
                throw SafetyError.insufficientDiskSpace(required: required, available: freeSpace)
            }
        }
    }

    /// Runs all pre-flight checks for a file.
    public static func preflight(url: URL) throws {
        try validateFile(at: url)
        try validateDiskSpace(forFileAt: url)
    }
}
