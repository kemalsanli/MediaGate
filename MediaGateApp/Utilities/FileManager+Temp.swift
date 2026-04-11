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

extension FileManager {

    /// Creates a unique temporary directory for a conversion job.
    ///
    /// - Parameter jobID: A unique identifier (typically a UUID) to namespace the directory.
    /// - Returns: The URL of the created temporary directory.
    func createConversionTempDirectory(jobID: String) throws -> URL {
        let baseTemp = temporaryDirectory.appendingPathComponent("MediaGate", isDirectory: true)
        let jobDir = baseTemp.appendingPathComponent(jobID, isDirectory: true)
        try createDirectory(at: jobDir, withIntermediateDirectories: true)
        return jobDir
    }

    /// Removes the temporary directory for a specific conversion job.
    ///
    /// - Parameter jobID: The unique identifier of the job whose temp files should be cleaned up.
    func cleanupConversionTempDirectory(jobID: String) {
        let baseTemp = temporaryDirectory.appendingPathComponent("MediaGate", isDirectory: true)
        let jobDir = baseTemp.appendingPathComponent(jobID, isDirectory: true)
        try? removeItem(at: jobDir)
    }

    /// Removes all MediaGate temporary files.
    ///
    /// Call this on app launch or when all conversions are complete to reclaim disk space.
    func cleanupAllConversionTempFiles() {
        let baseTemp = temporaryDirectory.appendingPathComponent("MediaGate", isDirectory: true)
        try? removeItem(at: baseTemp)
    }

    /// Returns the total size in bytes of a file at the given URL.
    ///
    /// - Parameter url: The file URL to measure.
    /// - Returns: The file size in bytes, or `0` if the file cannot be read.
    func fileSize(at url: URL) -> UInt64 {
        let attributes = try? attributesOfItem(atPath: url.path)
        return attributes?[.size] as? UInt64 ?? 0
    }

    /// Copies a file using stream-based reading to avoid loading the entire
    /// file into memory. Essential for large video files in the Share Extension.
    ///
    /// - Parameters:
    ///   - source: The source file URL.
    ///   - destination: The destination file URL.
    ///   - bufferSize: The read/write buffer size. Defaults to 1 MB.
    func streamCopy(from source: URL, to destination: URL, bufferSize: Int = 1_048_576) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        while true {
            let chunk = input.readData(ofLength: bufferSize)
            if chunk.isEmpty { break }
            output.write(chunk)
        }
    }
}
