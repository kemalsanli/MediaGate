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
import StoreKit

/// Identifiers for tip jar products.
enum TipProduct: String, CaseIterable, Sendable {
    case small  = "com.kemalsanli.mediagate.tip.small"
    case medium = "com.kemalsanli.mediagate.tip.medium"
    case large  = "com.kemalsanli.mediagate.tip.large"

    var displayName: String {
        switch self {
        case .small:  return String(localized: "Small Tip")
        case .medium: return String(localized: "Medium Tip")
        case .large:  return String(localized: "Big Tip")
        }
    }

    var emoji: String {
        switch self {
        case .small:  return "☕"
        case .medium: return "🍕"
        case .large:  return "🎉"
        }
    }
}

/// Manages StoreKit 2 tip jar purchases.
@MainActor
final class TipJarViewModel: ObservableObject {

    @Published var products: [Product] = []
    @Published var isPurchasing: Bool = false
    @Published var purchaseMessage: String?
    @Published var showThankYou: Bool = false

    /// Loads tip products from the App Store.
    func loadProducts() async {
        do {
            let ids = TipProduct.allCases.map(\.rawValue)
            let storeProducts = try await Product.products(for: Set(ids))
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            purchaseMessage = String(localized: "Could not load tips.")
        }
    }

    /// Initiates a tip purchase.
    ///
    /// - Parameter product: The StoreKit `Product` to purchase.
    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                showThankYou = true
                purchaseMessage = String(localized: "Thank you for your support!")
            case .userCancelled:
                break
            case .pending:
                purchaseMessage = String(localized: "Purchase is pending approval.")
            @unknown default:
                break
            }
        } catch {
            purchaseMessage = String(localized: "Purchase failed. Please try again.")
        }
    }

    // MARK: - Private

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let value):
            return value
        }
    }
}

private enum StoreError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        "Purchase verification failed."
    }
}
