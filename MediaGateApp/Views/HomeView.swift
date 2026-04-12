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
import Photos
import MediaGateKit

/// The main screen of MediaGate.
struct HomeView: View {

    @State private var showSettings = false
    @State private var showTipJar = false
    @State private var expandedCategory: FormatCategory?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroSection
                    formatsSection
                    tipJarButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 32)
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
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showTipJar) { TipJarView() }
            .task {
                let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                if status == .notDetermined {
                    await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Color.accentColor)

            Text("Share any unsupported media file to convert and save to Photos")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Formats

    private var formatsSection: some View {
        VStack(spacing: 12) {
            FormatCard(
                category: .video,
                isExpanded: expandedCategory == .video,
                onTap: { toggleCategory(.video) }
            )
            FormatCard(
                category: .image,
                isExpanded: expandedCategory == .image,
                onTap: { toggleCategory(.image) }
            )
            FormatCard(
                category: .passthrough,
                isExpanded: expandedCategory == .passthrough,
                onTap: { toggleCategory(.passthrough) }
            )
        }
    }

    private func toggleCategory(_ cat: FormatCategory) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            expandedCategory = expandedCategory == cat ? nil : cat
        }
    }

    // MARK: - Tip Jar

    private var tipJarButton: some View {
        Button {
            showTipJar = true
        } label: {
            Label("Tip Jar", systemImage: "heart.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color.accentColor.opacity(0.1))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Format Category

enum FormatCategory: String, CaseIterable {
    case video, image, passthrough

    var titleKey: LocalizedStringKey {
        switch self {
        case .video: return "Video"
        case .image: return "Image"
        case .passthrough: return "Passthrough"
        }
    }

    var icon: String {
        switch self {
        case .video: return "film"
        case .image: return "photo"
        case .passthrough: return "arrow.right.circle"
        }
    }

    var output: String {
        switch self {
        case .video: return "MP4"
        case .image: return "PNG / JPEG"
        case .passthrough: return "Photos"
        }
    }

    var tint: Color {
        switch self {
        case .video: return .blue
        case .image: return .green
        case .passthrough: return .purple
        }
    }

    var formats: [SupportedFormats.FormatInfo] {
        switch self {
        case .video: return SupportedFormats.convertibleVideos
        case .image: return SupportedFormats.convertibleImages
        case .passthrough: return SupportedFormats.passthroughFormats
        }
    }

    var extensions: [String] {
        formats.flatMap(\.extensions).map { $0.uppercased() }
    }
}

// MARK: - Format Card

struct FormatCard: View {
    let category: FormatCategory
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header — always visible
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: category.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(category.tint)
                        .frame(width: 36, height: 36)
                        .background(category.tint.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    // Title + output
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.titleKey)
                            .font(.subheadline.weight(.semibold))
                        Text("→ \(category.output)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    // Count badge
                    Text("\(category.extensions.count)")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            // Tags — expanded
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                FlowLayout(spacing: 6) {
                    ForEach(Array(category.extensions.enumerated()), id: \.offset) { index, ext in
                        Text(ext)
                            .font(.caption2.weight(.medium).monospaced())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(category.tint.opacity(0.08))
                            .foregroundStyle(category.tint)
                            .clipShape(Capsule())
                            .transition(
                                .scale(scale: 0.5)
                                .combined(with: .opacity)
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

#Preview {
    HomeView()
}
