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

/// Shared constants between the main app and the Share Extension.
///
/// Both targets reference these values to communicate via the App Group
/// shared container and the custom URL scheme.
public enum SharedConstants {

    /// The App Group identifier used for sharing data between the main app
    /// and the Share Extension.
    public static let appGroupIdentifier = "group.com.kemalsanli.mediagate"

    /// The URL scheme the Share Extension uses to wake the main app.
    public static let urlScheme = "mediagate"

    /// The URL the Share Extension opens to trigger conversion in the main app.
    public static let convertURL = URL(string: "mediagate://convert")!

    /// The directory name within the shared container where pending conversions
    /// are stored.
    public static let pendingDirectoryName = "PendingConversions"

    /// Returns the shared container URL for the App Group.
    public static var sharedContainerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    /// Returns the directory URL where pending conversion files are stored.
    ///
    /// Creates the directory if it does not exist.
    public static var pendingDirectoryURL: URL? {
        guard let container = sharedContainerURL else { return nil }
        let url = container.appendingPathComponent(pendingDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Shared UserDefaults backed by the App Group container.
    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    /// Flag set by the Share Extension to signal that there are files
    /// waiting to be converted. The main app clears this after processing.
    public static var hasPendingConversions: Bool {
        get { sharedDefaults?.bool(forKey: "hasPendingConversions") ?? false }
        set { sharedDefaults?.set(newValue, forKey: "hasPendingConversions") }
    }
}
