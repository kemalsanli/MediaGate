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

/// A model representing a file that the Share Extension has received and
/// placed into the shared container for the main app to convert.
///
/// The Share Extension writes one `PendingConversion` per received file
/// as a JSON sidecar alongside the actual media file.
public struct PendingConversion: Codable, Sendable, Identifiable {

    /// Unique identifier for this conversion job.
    public let id: UUID

    /// The original filename as received from the host app.
    public let originalFilename: String

    /// The UTType identifier hint provided by the host app, if available.
    public let typeIdentifierHint: String?

    /// Timestamp when the file was received by the Share Extension.
    public let receivedAt: Date

    /// The filename of the media file in the shared container's pending directory.
    public let storedFilename: String

    public init(
        id: UUID = UUID(),
        originalFilename: String,
        typeIdentifierHint: String?,
        receivedAt: Date = Date(),
        storedFilename: String
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.typeIdentifierHint = typeIdentifierHint
        self.receivedAt = receivedAt
        self.storedFilename = storedFilename
    }

    /// The JSON sidecar filename for this pending conversion.
    public var metadataFilename: String {
        "\(id.uuidString).json"
    }

    /// Writes this model as JSON to the pending directory.
    public func writeToPendingDirectory() throws {
        guard let dir = SharedConstants.pendingDirectoryURL else {
            throw PendingConversionError.sharedContainerUnavailable
        }
        let data = try JSONEncoder().encode(self)
        let fileURL = dir.appendingPathComponent(metadataFilename)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Reads all pending conversions from the shared container.
    public static func loadAll() throws -> [PendingConversion] {
        guard let dir = SharedConstants.pendingDirectoryURL else {
            throw PendingConversionError.sharedContainerUnavailable
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )
        return contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(PendingConversion.self, from: data)
            }
            .sorted { $0.receivedAt < $1.receivedAt }
    }
}

/// Errors that can occur when working with pending conversions.
public enum PendingConversionError: LocalizedError, Sendable {
    case sharedContainerUnavailable

    public var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable:
            return "The shared App Group container is not available."
        }
    }
}
