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

/// App settings and information.
///
/// Provides quality preferences, version information, and links to
/// the project's license and source code.
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var preserveMetadata: Bool = ConversionSettings.shared.preserveMetadata
    @State private var stripLocation: Bool = ConversionSettings.shared.stripLocation
    @State private var videoQualityPreset: VideoQualityPreset = ConversionSettings.shared.videoQualityPreset
    @State private var compressionQuality: Double = ConversionSettings.shared.compressionQuality
    @State private var compressNativeFormats: Bool = ConversionSettings.shared.compressNativeFormats

    var body: some View {
        NavigationStack {
            List {
                conversionSection
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

    // MARK: - Conversion

    private var conversionSection: some View {
        Section {
            Toggle(String(localized: "Preserve Metadata"), isOn: $preserveMetadata)
                .onChange(of: preserveMetadata) { newValue in
                    ConversionSettings.shared.preserveMetadata = newValue
                }

            if preserveMetadata {
                Toggle(String(localized: "Strip Location Data"), isOn: $stripLocation)
                    .padding(.leading, 16)
                    .onChange(of: stripLocation) { newValue in
                        ConversionSettings.shared.stripLocation = newValue
                    }
            }

            Picker(String(localized: "Video Quality"), selection: $videoQualityPreset) {
                ForEach(VideoQualityPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .onChange(of: videoQualityPreset) { newValue in
                ConversionSettings.shared.videoQualityPreset = newValue
            }

            VStack(alignment: .leading) {
                HStack {
                    Text(String(localized: "Image Quality"))
                    Spacer()
                    Text("\(Int(compressionQuality * 100))%")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $compressionQuality, in: 0.1...1.0, step: 0.05)
                    .onChange(of: compressionQuality) { newValue in
                        ConversionSettings.shared.compressionQuality = newValue
                    }
            }

            Toggle(String(localized: "Compress Compatible Files"), isOn: $compressNativeFormats)
                .onChange(of: compressNativeFormats) { newValue in
                    ConversionSettings.shared.compressNativeFormats = newValue
                }
        } header: {
            Text(String(localized: "Conversion"))
        } footer: {
            Text(String(localized: "Re-encode files already supported by Photos (MP4, JPEG, etc.) to reduce file size"))
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
