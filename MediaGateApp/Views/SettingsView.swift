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

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var preserveMetadata: Bool = ConversionSettings.shared.preserveMetadata
    @State private var stripLocation: Bool = ConversionSettings.shared.stripLocation
    @State private var videoQualityPreset: VideoQualityPreset = ConversionSettings.shared.videoQualityPreset
    @State private var compressionQuality: Double = ConversionSettings.shared.compressionQuality
    @State private var compressNativeFormats: Bool = ConversionSettings.shared.compressNativeFormats
    @AppStorage("selectedLanguage") private var savedLanguage: String = "system"
    @State private var pendingLanguage: String = ""
    @State private var showTipJar = false

    private static let supportedLanguages: [(code: String, name: String)] = [
        ("system", "—"),
        ("ar", "العربية"), ("ca", "Català"), ("cs", "Čeština"), ("da", "Dansk"),
        ("de", "Deutsch"), ("el", "Ελληνικά"), ("en", "English"), ("es", "Español"),
        ("es-MX", "Español (México)"), ("fi", "Suomi"), ("fr", "Français"),
        ("fr-CA", "Français (Canada)"), ("he", "עברית"), ("hi", "हिन्दी"),
        ("hr", "Hrvatski"), ("hu", "Magyar"), ("id", "Bahasa Indonesia"),
        ("it", "Italiano"), ("ja", "日本語"), ("ko", "한국어"),
        ("ms", "Bahasa Melayu"), ("nb", "Norsk Bokmål"), ("nl", "Nederlands"),
        ("pl", "Polski"), ("pt-BR", "Português (Brasil)"),
        ("pt-PT", "Português (Portugal)"), ("ro", "Română"), ("ru", "Русский"),
        ("sk", "Slovenčina"), ("sv", "Svenska"), ("th", "ไทย"), ("tr", "Türkçe"),
        ("uk", "Українська"), ("vi", "Tiếng Việt"),
        ("zh-Hans", "中文（简体）"), ("zh-Hant", "中文（繁體）"),
    ]

    var body: some View {
        NavigationStack {
            List {
                conversionSection
                languageSection
                aboutSection
                licensesSection
                linksSection
                tipJarSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        applyLanguageIfChanged()
                        dismiss()
                    }
                }
            }
            .onAppear {
                pendingLanguage = savedLanguage
            }
            .sheet(isPresented: $showTipJar) {
                TipJarView()
            }
        }
    }

    private func applyLanguageIfChanged() {
        guard pendingLanguage != savedLanguage else { return }
        savedLanguage = pendingLanguage
        if pendingLanguage == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([pendingLanguage], forKey: "AppleLanguages")
        }
    }

    // MARK: - Conversion

    private var conversionSection: some View {
        Section {
            Toggle("Preserve Metadata", isOn: $preserveMetadata)
                .onChange(of: preserveMetadata) { newValue in
                    ConversionSettings.shared.preserveMetadata = newValue
                }

            if preserveMetadata {
                Toggle("Strip Location Data", isOn: $stripLocation)
                    .padding(.leading, 16)
                    .onChange(of: stripLocation) { newValue in
                        ConversionSettings.shared.stripLocation = newValue
                    }
            }

            Picker("Video Quality", selection: $videoQualityPreset) {
                ForEach(VideoQualityPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .onChange(of: videoQualityPreset) { newValue in
                ConversionSettings.shared.videoQualityPreset = newValue
            }

            VStack(alignment: .leading) {
                HStack {
                    Text("Image Quality")
                    Spacer()
                    Text("\(Int(compressionQuality * 100))%")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $compressionQuality, in: 0.1...1.0, step: 0.05)
                    .onChange(of: compressionQuality) { newValue in
                        ConversionSettings.shared.compressionQuality = newValue
                    }
            }

            Toggle("Compress Compatible Files", isOn: $compressNativeFormats)
                .onChange(of: compressNativeFormats) { newValue in
                    ConversionSettings.shared.compressNativeFormats = newValue
                }
        } header: {
            Text("Conversion")
        } footer: {
            Text("Re-encode files already supported by Photos (MP4, JPEG, etc.) to reduce file size")
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        Section {
            Picker("Language", selection: $pendingLanguage) {
                Text("System Default").tag("system")
                ForEach(Self.supportedLanguages.filter { $0.code != "system" }, id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
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
                Text("Developer")
                Spacer()
                Text("Kemal Sanlı")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Licenses

    private var licensesSection: some View {
        Section {
            NavigationLink {
                LicensesDetailView()
            } label: {
                Label("Licenses", systemImage: "doc.text")
            }
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        Section {
            Link(destination: URL(string: "https://github.com/kemalsanli/MediaGate")!) {
                Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Link(destination: URL(string: "https://github.com/kemalsanli/MediaGate/issues")!) {
                Label("Report a Bug", systemImage: "ladybug")
            }
        } header: {
            Text("Links")
        }
    }

    // MARK: - Tip Jar

    private var tipJarSection: some View {
        Section {
            Button {
                showTipJar = true
            } label: {
                Label("Tip Jar", systemImage: "heart.fill")
                    .foregroundStyle(Color.accentColor)
            }
        } footer: {
            Text("MediaGate is free and open source. If you find it useful, a tip helps keep development going.")
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Licenses Detail

struct LicensesDetailView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MediaGate")
                        .font(.headline)
                    Text("Copyright © 2025–2026 Kemal Sanlı")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("GNU General Public License v3.0")
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FFmpeg")
                        .font(.headline)
                    Link("ffmpeg.org", destination: URL(string: "https://ffmpeg.org")!)
                        .font(.caption)
                    Text("FFmpeg is a collection of libraries and tools to process multimedia content. Licensed under GNU LGPL 2.1+ / GNU GPL 2+.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SwiftFFmpeg")
                        .font(.headline)
                    Link("sunlubo → tylerjonesio → kemalsanli", destination: URL(string: "https://github.com/kemalsanli/SwiftFFmpeg")!)
                        .font(.caption)
                    Text("A Swift wrapper for the FFmpeg API. Created by sunlubo, maintained by Tyler Jones, forked for MediaGate. Licensed under Apache 2.0.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ffmpeg-libav-spm")
                        .font(.headline)
                    Link("Tyler Jones", destination: URL(string: "https://github.com/tylerjonesio/ffmpeg-libav-spm")!)
                        .font(.caption)
                    Text("Swift Package Manager distribution of FFmpeg libraries for Apple platforms. Makes FFmpeg available via SPM without manual framework setup.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full license texts are available in the source repository and at gnu.org/licenses.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
}
