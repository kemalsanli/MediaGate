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

@main
struct MediaGateApp: App {

    @StateObject private var conversionViewModel = ConversionViewModel()
    @State private var isConverting = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selectedLanguage") private var selectedLanguage: String = "system"

    private var activeLocale: Locale {
        selectedLanguage == "system" ? .autoupdatingCurrent : Locale(identifier: selectedLanguage)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isConverting {
                    ConversionView(viewModel: conversionViewModel) {
                        isConverting = false
                        conversionViewModel.reset()
                    }
                } else {
                    HomeView()
                }
            }
            .onOpenURL { url in
                guard url.scheme == "mediagate", url.host == "convert" else { return }
                startConversionIfNeeded()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    checkForPendingConversions()
                }
            }
            .environment(\.locale, activeLocale)
            .onAppear {
                FileManager.default.cleanupAllConversionTempFiles()
                checkForPendingConversions()
            }
            .task {
                await TipJarAvailability.shared.check()
            }
        }
    }

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
