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

/// Displays conversion progress for one or more files.
///
/// Shown when the app is opened via the `mediagate://convert` URL scheme.
/// Each file appears in a list with its current conversion status.
struct ConversionView: View {

    @ObservedObject var viewModel: ConversionViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isComplete {
                    completionSummary
                } else {
                    headerBar
                    fileList
                    cancelButton
                }
            }
            .navigationTitle(String(localized: "Converting"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        Group {
            if viewModel.totalCount > 0 {
                Text("Converting \(viewModel.currentIndex + 1) of \(viewModel.totalCount) files")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: - File List

    private var fileList: some View {
        List(viewModel.files) { file in
            fileRow(file)
        }
        .listStyle(.plain)
    }

    private func fileRow(_ file: ConversionFileState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.filename)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(file.conversionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            statusView(for: file.status)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusView(for status: ConversionFileState.Status) -> some View {
        switch status {
        case .waiting:
            Text("Waiting...")
                .font(.caption)
                .foregroundStyle(.tertiary)

        case .converting(let percent):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: percent)
                    .tint(.accentColor)
                Text("\(Int(percent * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .completed:
            Label(String(localized: "Saved to Photos"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

        case .failed(let error):
            Label(error, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    // MARK: - Completion Summary

    private var completionSummary: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: viewModel.failCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(viewModel.failCount == 0 ? .green : .orange)

            if viewModel.failCount == 0 {
                Text("All files converted successfully!")
                    .font(.headline)
            } else {
                Text("\(viewModel.successCount) succeeded, \(viewModel.failCount) failed")
                    .font(.headline)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Cancel

    private var cancelButton: some View {
        Group {
            if viewModel.isActive {
                Button(role: .destructive) {
                    viewModel.cancelConversion()
                } label: {
                    Text("Cancel All")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(14)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }
}
