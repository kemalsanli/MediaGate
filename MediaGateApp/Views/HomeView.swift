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

/// The main screen of MediaGate.
///
/// Displays a brief explanation of how to use the app, an expandable list
/// of supported formats, and navigation to the Tip Jar and Settings.
struct HomeView: View {

    @State private var showFormats = false
    @State private var showSettings = false
    @State private var showTipJar = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    heroSection
                    formatSection
                    tipJarButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("MediaGate")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .fontWeight(.medium)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showTipJar) {
                TipJarView()
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.accent)

            Text("Share any unsupported media file to convert and save to Photos")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Supported Formats

    private var formatSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showFormats.toggle()
                }
            } label: {
                HStack {
                    Label(String(localized: "Supported Formats"), systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showFormats ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if showFormats {
                VStack(alignment: .leading, spacing: 16) {
                    formatGroup(title: String(localized: "Video"), formats: SupportedFormats.convertibleVideos)
                    formatGroup(title: String(localized: "Image"), formats: SupportedFormats.convertibleImages)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func formatGroup(title: String, formats: [SupportedFormats.FormatInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 80), spacing: 8)
            ], spacing: 8) {
                ForEach(formats) { format in
                    Text(format.displayName)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Tip Jar Button

    private var tipJarButton: some View {
        Button {
            showTipJar = true
        } label: {
            Label(String(localized: "Tip Jar"), systemImage: "heart.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color.accentColor.opacity(0.1))
                .foregroundStyle(.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView()
}
