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
import SwiftUI
import MediaGateKit

/// The state of a single file being converted.
struct ConversionFileState: Identifiable, Sendable {
    let id = UUID()
    let filename: String
    var status: Status

    enum Status: Sendable {
        case waiting
        case converting(percent: Double)
        case completed
        case failed(error: String)
    }

    /// The display string for the conversion type (e.g., "MKV → MP4").
    var conversionLabel: String {
        let ext = (filename as NSString).pathExtension.uppercased()
        let format = SupportedFormats.formatInfo(forExtension: ext.lowercased())
        let output = format?.outputExtension.uppercased() ?? "MP4"
        return "\(ext) → \(output)"
    }
}

/// Drives the conversion progress UI.
///
/// Listens to ``ConversionEvent`` values from the ``ConversionPipeline``
/// and updates the published state for SwiftUI to render.
@MainActor
final class ConversionViewModel: ObservableObject {

    @Published var files: [ConversionFileState] = []
    @Published var currentIndex: Int = 0
    @Published var totalCount: Int = 0
    @Published var isActive: Bool = false
    @Published var isComplete: Bool = false
    @Published var successCount: Int = 0
    @Published var failCount: Int = 0

    private let pipeline: ConversionPipeline
    private var conversionTask: Task<Void, Never>?

    init(pipeline: ConversionPipeline = ConversionPipeline()) {
        self.pipeline = pipeline
    }

    /// Starts processing all pending conversions.
    func startConversion() {
        guard !isActive else { return }
        isActive = true
        isComplete = false

        conversionTask = Task {
            let stream = pipeline.processAll()
            for await event in stream {
                handleEvent(event)
            }
        }
    }

    /// Cancels any in-progress conversion.
    func cancelConversion() {
        conversionTask?.cancel()
        conversionTask = nil
        isActive = false
        FileManager.default.cleanupAllConversionTempFiles()
    }

    /// Resets all state so the view model can be reused for a new conversion.
    func reset() {
        cancelConversion()
        files = []
        currentIndex = 0
        totalCount = 0
        isComplete = false
        successCount = 0
        failCount = 0
    }

    // MARK: - Private

    private func handleEvent(_ event: ConversionEvent) {
        switch event {
        case .started(let filename, let index, let total):
            totalCount = total
            currentIndex = index

            // Populate file list on first event
            if files.isEmpty {
                files = (0..<total).map { i in
                    ConversionFileState(
                        filename: filename,
                        status: i == index ? .converting(percent: 0) : .waiting
                    )
                }
            }

            if index < files.count {
                files[index] = ConversionFileState(filename: filename, status: .converting(percent: 0))
            }

        case .progress(let filename, let percent):
            if let idx = files.firstIndex(where: { $0.filename == filename }) {
                files[idx] = ConversionFileState(filename: filename, status: .converting(percent: percent))
            }

        case .completed(let filename):
            if let idx = files.firstIndex(where: { $0.filename == filename }) {
                files[idx] = ConversionFileState(filename: filename, status: .completed)
            }

        case .failed(let filename, let error):
            if let idx = files.firstIndex(where: { $0.filename == filename }) {
                files[idx] = ConversionFileState(filename: filename, status: .failed(error: error))
            }

        case .allDone(let success, let fail):
            successCount = success
            failCount = fail
            isActive = false
            isComplete = true
        }
    }
}
