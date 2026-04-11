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
    /// Saves a video file to the Photos library.
    ///
    /// - Parameter url: The local file URL of the video to save.
    func saveVideo(url: URL) async throws

    /// Saves an image file to the Photos library.
    ///
    /// - Parameter url: The local file URL of the image to save.
    func saveImage(url: URL) async throws
}


/// Errors specific to gallery saving.
public enum GallerySaveError: LocalizedError, Sendable {
    case permissionDenied
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Photo library access was denied. Please grant access in Settings."
        case .saveFailed(let reason):
            return "Failed to save to Photos: \(reason)"
        }
    }
}

/// Saves converted media to the user's Photos library using PhotoKit.
public struct GallerySaver: GallerySaving {

    public init() {}

    /// Requests photo library access if not already granted.
    ///
    /// - Returns: `true` if access is authorized.
    private func requestAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    public func saveVideo(url: URL) async throws {
        guard await requestAccess() else {
            throw GallerySaveError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: url, options: nil)
        }
    }

    public func saveImage(url: URL) async throws {
        guard await requestAccess() else {
            throw GallerySaveError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: url, options: nil)
        }
    }
}
