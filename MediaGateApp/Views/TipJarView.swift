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
import StoreKit

/// A view that lets users leave optional tips to support the developer.
///
/// Uses StoreKit 2 with three tip tiers. All tips are non-consumable
/// to keep things simple — tipping is a one-time gesture of support.
struct TipJarView: View {

    @StateObject private var viewModel = TipJarViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    tipButtons
                    messageSection
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "Tip Jar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadProducts()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 44))
                .foregroundStyle(.pink)

            Text("MediaGate is free and open source. If you find it useful, a tip helps keep development going.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tip Buttons

    private var tipButtons: some View {
        VStack(spacing: 12) {
            if viewModel.products.isEmpty {
                ProgressView()
                    .padding()
            } else {
                ForEach(viewModel.products, id: \.id) { product in
                    tipButton(for: product)
                }
            }
        }
    }

    private func tipButton(for product: Product) -> some View {
        let tipType = TipProduct(rawValue: product.id)
        return Button {
            Task {
                await viewModel.purchase(product)
            }
        } label: {
            HStack {
                Text(tipType?.emoji ?? "💝")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tipType?.displayName ?? product.displayName)
                        .font(.body.weight(.medium))
                    Text(product.displayPrice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.isPurchasing {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isPurchasing)
    }

    // MARK: - Message

    @ViewBuilder
    private var messageSection: some View {
        if viewModel.showThankYou {
            Text("Thank you for your support!")
                .font(.headline)
                .foregroundStyle(.green)
                .transition(.opacity)
        }

        if let message = viewModel.purchaseMessage, !viewModel.showThankYou {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    TipJarView()
}
