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
/// each file, then opens the main app via the `mediagate://convert` URL scheme.
///
/// ## Important
/// Share Extensions have strict memory (~120 MB) and time (~30 s) limits.
/// This class does **not** perform any transcoding — it only copies files
/// and hands off to the main app.
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        processInputItems()
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
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.data.identifier) }

        guard !providers.isEmpty else {
            completeRequest()
            return
        }

        Task {
            await processProviders(providers)
            await openMainApp()
            completeRequest()
        }
    }

    /// Copies each received file to the shared container and writes metadata.
    private func processProviders(_ providers: [NSItemProvider]) async {
        for provider in providers {
            do {
                let (url, typeHint) = try await loadFileURL(from: provider)
                try await copyToSharedContainer(sourceURL: url, typeHint: typeHint)
            } catch {
                // Log but continue — don't fail the entire batch for one bad file
                print("ShareExtension: Failed to process item — \(error.localizedDescription)")
            }
        }
    }

    /// Loads the file URL from an NSItemProvider.
    private func loadFileURL(from provider: NSItemProvider) async throws -> (URL, String?) {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.data.identifier) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: ShareError.noFileURL)
                    return
                }

                // Copy to a temporary location because the provided URL is only
                // valid for the duration of this callback
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: tempURL)

                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    let typeHint = provider.registeredTypeIdentifiers.first
                    continuation.resume(returning: (tempURL, typeHint))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Copies the file to the App Group shared container and writes metadata.
    private func copyToSharedContainer(sourceURL: URL, typeHint: String?) async throws {
        guard let pendingDir = SharedConstants.pendingDirectoryURL else {
            throw ShareError.sharedContainerUnavailable
        }

        let originalFilename = sourceURL.lastPathComponent
        let storedFilename = "\(UUID().uuidString)_\(originalFilename)"
        let destinationURL = pendingDir.appendingPathComponent(storedFilename)

        // Stream-copy to avoid memory spikes with large files
        try FileManager.default.streamCopy(from: sourceURL, to: destinationURL)

        // Write the metadata sidecar
        let pending = PendingConversion(
            originalFilename: originalFilename,
            typeIdentifierHint: typeHint,
            storedFilename: storedFilename
        )
        try pending.writeToPendingDirectory()

        // Clean up the temp file
        try? FileManager.default.removeItem(at: sourceURL)
    }

    // MARK: - URL Scheme

    /// Opens the main app via the `mediagate://convert` URL scheme.
    @MainActor
    private func openMainApp() async {
        guard let url = SharedConstants.convertURL as URL? else { return }

        // Share Extensions cannot open URLs directly using UIApplication.shared.open.
        // Instead, we use the responder chain to find a method that can open URLs.
        var responder: UIResponder? = self
        while let r = responder {
            if let application = r as? UIApplication {
                application.open(url)
                return
            }
            responder = r.next
        }

        // Fallback: use the openURL selector on the shared application proxy
        let selector = sel_registerName("openURL:")
        var target: UIResponder? = self
        while let r = target {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            target = r.next
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
