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
import Photos

/// A type that can save media files to the user's photo library.
public protocol GallerySaving: Sendable {
    func saveVideo(url: URL) async throws
    func saveImage(url: URL) async throws
}

/// Errors specific to gallery saving.
public enum GallerySaveError: LocalizedError, Sendable {
    case permissionDenied
    case saveFailed(String)
    case fileInvalid(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Photo library access was denied. Please grant access in Settings → Privacy → Photos."
        case .saveFailed(let reason):
            return "Failed to save to Photos: \(reason)"
        case .fileInvalid(let name):
            return "Converted file is invalid or empty: \(name)"
        }
    }
}

/// Saves converted media to the user's Photos library using PhotoKit.
public struct GallerySaver: GallerySaving {

    public init() {}

    public func saveVideo(url: URL) async throws {
        try validateFile(at: url)
        try await ensureAccess()

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: options)
            }
        } catch {
            throw GallerySaveError.saveFailed(error.localizedDescription)
        }
    }

    public func saveImage(url: URL) async throws {
        try validateFile(at: url)
        try await ensureAccess()

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: url, options: options)
            }
        } catch {
            throw GallerySaveError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func validateFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw GallerySaveError.fileInvalid(url.lastPathComponent)
        }
        let size = FileManager.default.fileSize(at: url)
        guard size > 0 else {
            throw GallerySaveError.fileInvalid("\(url.lastPathComponent) (0 bytes)")
        }
    }

    private func ensureAccess() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard newStatus == .authorized || newStatus == .limited else {
                throw GallerySaveError.permissionDenied
            }
        default:
            throw GallerySaveError.permissionDenied
        }
    }
}
