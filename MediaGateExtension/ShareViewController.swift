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

import UIKit
import UniformTypeIdentifiers
import MediaGateKit

/// The Share Extension's principal class.
///
/// Receives files shared from other apps, copies them to the App Group
/// shared container, writes a ``PendingConversion`` metadata sidecar for
/// each file, then signals the main app.
///
/// ## Important
/// Share Extensions have strict memory (~120 MB) and time (~30 s) limits.
/// This class does **not** perform any transcoding — it only copies files
/// and hands off to the main app.
class ShareViewController: UIViewController {

    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let checkmark = UIImageView()
    private let fileCountLabel = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processInputItems()
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = .systemBackground

        let stack = UIStackView(arrangedSubviews: [spinner, checkmark, statusLabel, fileCountLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])

        spinner.startAnimating()
        spinner.color = .label

        checkmark.image = UIImage(systemName: "checkmark.circle.fill")
        checkmark.tintColor = .systemGreen
        checkmark.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 48)
        checkmark.isHidden = true

        statusLabel.text = NSLocalizedString("Preparing files…", comment: "")
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center

        fileCountLabel.font = .preferredFont(forTextStyle: .subheadline)
        fileCountLabel.textColor = .secondaryLabel
        fileCountLabel.textAlignment = .center
        fileCountLabel.isHidden = true
    }

    @MainActor
    private func showSuccess(fileCount: Int) {
        spinner.stopAnimating()
        spinner.isHidden = true
        checkmark.isHidden = false
        statusLabel.text = NSLocalizedString("Ready to convert!", comment: "")
        fileCountLabel.text = String.localizedStringWithFormat(
            NSLocalizedString("%d file(s) queued", comment: ""),
            fileCount
        )
        fileCountLabel.isHidden = false
    }

    @MainActor
    private func showError(_ message: String) {
        spinner.stopAnimating()
        spinner.isHidden = true
        checkmark.image = UIImage(systemName: "xmark.circle.fill")
        checkmark.tintColor = .systemRed
        checkmark.isHidden = false
        statusLabel.text = message
    }

    // MARK: - Processing

    private func processInputItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeRequest()
            return
        }

        let providers = extensionItems
            .compactMap(\.attachments)
            .flatMap { $0 }
            .filter { provider in
                provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.item.identifier)
            }

        guard !providers.isEmpty else {
            Task { @MainActor in
                showError(NSLocalizedString("No supported files found.", comment: ""))
                try? await Task.sleep(for: .seconds(1.5))
                completeRequest()
            }
            return
        }

        Task {
            let count = await processProviders(providers)

            if count > 0 {
                // Signal the main app that there are pending conversions
                SharedConstants.hasPendingConversions = true

                await showSuccess(fileCount: count)

                // Try to open the main app via URL scheme (best-effort)
                await openMainApp()

                // Brief pause so the user sees the confirmation
                try? await Task.sleep(for: .seconds(1.2))
            } else {
                await showError(NSLocalizedString("Could not process files.", comment: ""))
                try? await Task.sleep(for: .seconds(1.5))
            }

            completeRequest()
        }
    }

    /// Copies each received file to the shared container and writes metadata.
    ///
    /// - Returns: The number of files successfully queued.
    private func processProviders(_ providers: [NSItemProvider]) async -> Int {
        var successCount = 0

        for (index, provider) in providers.enumerated() {
            await MainActor.run {
                fileCountLabel.text = String.localizedStringWithFormat(
                    NSLocalizedString("Processing %d of %d…", comment: ""),
                    index + 1, providers.count
                )
                fileCountLabel.isHidden = false
            }

            do {
                let (url, typeHint) = try await loadFileURL(from: provider)
                try copyToSharedContainer(sourceURL: url, typeHint: typeHint)
                successCount += 1
            } catch {
                print("ShareExtension: Failed to process item — \(error.localizedDescription)")
            }
        }

        return successCount
    }

    /// Loads the file URL from an NSItemProvider.
    ///
    /// Tries multiple type identifiers in order: data (broadest), then image,
    /// movie, and item as fallbacks.
    private func loadFileURL(from provider: NSItemProvider) async throws -> (URL, String?) {
        let typeHint = provider.registeredTypeIdentifiers.first

        let typeIdentifiers = [
            UTType.data.identifier,
            UTType.image.identifier,
            UTType.movie.identifier,
            UTType.item.identifier,
        ]

        // Find the first type identifier the provider supports
        guard let typeID = typeIdentifiers.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
            throw ShareError.noFileURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: ShareError.noFileURL)
                    return
                }

                // The provided URL is only valid during this callback — copy it
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)

                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    continuation.resume(returning: (tempURL, typeHint))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Copies the file to the App Group shared container and writes metadata.
    private func copyToSharedContainer(sourceURL: URL, typeHint: String?) throws {
        guard let pendingDir = SharedConstants.pendingDirectoryURL else {
            throw ShareError.sharedContainerUnavailable
        }

        let originalFilename = sourceURL.lastPathComponent
        let storedFilename = "\(UUID().uuidString)_\(originalFilename)"
        let destinationURL = pendingDir.appendingPathComponent(storedFilename)

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let pending = PendingConversion(
            originalFilename: originalFilename,
            typeIdentifierHint: typeHint,
            storedFilename: storedFilename
        )
        try pending.writeToPendingDirectory()

        // Clean up the temp copy
        try? FileManager.default.removeItem(at: sourceURL)
    }

    // MARK: - Open Main App

    /// Best-effort attempt to open the main app via the URL scheme.
    ///
    /// This uses the responder chain trick which may not work on all iOS
    /// versions. The main app also checks for pending items on foreground,
    /// so conversion will start even if this fails.
    @MainActor
    private func openMainApp() async {
        guard let url = URL(string: "mediagate://convert") else { return }

        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
    }

    // MARK: - Completion

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - Errors

private enum ShareError: LocalizedError {
    case noFileURL
    case sharedContainerUnavailable

    var errorDescription: String? {
        switch self {
        case .noFileURL:
            return "No file URL was provided by the host app."
        case .sharedContainerUnavailable:
            return "Could not access the shared App Group container."
        }
    }
}
