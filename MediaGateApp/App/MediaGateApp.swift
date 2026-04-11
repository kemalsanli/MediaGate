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
import MediaGateKit

/// The main entry point for MediaGate.
///
/// Handles two states:
/// - **Idle:** Shows ``HomeView`` with app info and format list.
/// - **Converting:** Shows ``ConversionView`` when pending conversions
///   are detected — either via the URL scheme or when the app returns
///   to the foreground.
@main
struct MediaGateApp: App {

    @StateObject private var conversionViewModel = ConversionViewModel()
    @State private var isConverting = false
    @Environment(\.scenePhase) private var scenePhase

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
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    checkForPendingConversions()
                }
            }
            .onAppear {
                FileManager.default.cleanupAllConversionTempFiles()
            }
        }
    }

    /// Handles the `mediagate://convert` URL scheme.
    private func handleURL(_ url: URL) {
        guard url.scheme == "mediagate", url.host == "convert" else { return }
        startConversionIfNeeded()
    }

    /// Checks App Group UserDefaults for pending conversions queued by the
    /// Share Extension. This is the primary handoff mechanism since the
    /// URL scheme trick from extensions is unreliable on modern iOS.
    private func checkForPendingConversions() {
        guard SharedConstants.hasPendingConversions else { return }
        startConversionIfNeeded()
    }

    private func startConversionIfNeeded() {
        guard !isConverting else { return }
        SharedConstants.hasPendingConversions = false
        isConverting = true
        conversionViewModel.startConversion()
    }
}
