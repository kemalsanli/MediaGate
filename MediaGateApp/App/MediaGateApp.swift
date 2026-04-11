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

import SwiftUI

/// The main entry point for MediaGate.
///
/// Handles two states:
/// - **Idle:** Shows ``HomeView`` with app info and format list.
/// - **Converting:** Shows ``ConversionView`` when the Share Extension
///   triggers conversion via the `mediagate://convert` URL scheme.
@main
struct MediaGateApp: App {

    @StateObject private var conversionViewModel = ConversionViewModel()
    @State private var isConverting = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isConverting {
                    ConversionView(viewModel: conversionViewModel)
                } else {
                    HomeView()
                }
            }
            .onOpenURL { url in
                handleURL(url)
            }
            .onAppear {
                // Clean up any stale temp files from previous sessions
                FileManager.default.cleanupAllConversionTempFiles()
            }
        }
    }

    /// Handles the `mediagate://convert` URL scheme.
    ///
    /// When the Share Extension finishes copying files to the shared
    /// container, it opens this URL to trigger conversion.
    private func handleURL(_ url: URL) {
        guard url.scheme == "mediagate", url.host == "convert" else { return }
        isConverting = true
        conversionViewModel.startConversion()
    }
}
