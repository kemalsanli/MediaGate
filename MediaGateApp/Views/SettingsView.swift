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

/// App settings and information.
///
/// Provides quality preferences, version information, and links to
/// the project's license and source code.
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                aboutSection
                linksSection
            }
            .navigationTitle(String(localized: "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(String(localized: "Developer"))
                Spacer()
                Text("Kemal Sanlı")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "About"))
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        Section {
            Link(destination: URL(string: "https://github.com/kemalsanli/MediaGate")!) {
                Label(String(localized: "Source Code"), systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Link(destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!) {
                Label(String(localized: "License (GPLv3)"), systemImage: "doc.text")
            }

            Link(destination: URL(string: "https://github.com/kemalsanli/MediaGate/issues")!) {
                Label(String(localized: "Report a Bug"), systemImage: "ladybug")
            }
        } header: {
            Text(String(localized: "Links"))
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
}
