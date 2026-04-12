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
/// Each file appears in a list with its current conversion status.
/// On completion, a summary with a "Done" button is shown.
struct ConversionView: View {

    @ObservedObject var viewModel: ConversionViewModel
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isComplete {
                    completionSummary
                } else if viewModel.totalCount == 0 && !viewModel.isActive {
                    emptyState
                } else {
                    headerBar
                    fileList
                    cancelButton
                }
            }
            .navigationTitle("Converting")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No files to convert")
                .font(.headline)
            Button("Done") { onDismiss() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
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
            Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

        case .failed(let error):
            VStack(alignment: .leading, spacing: 4) {
                Label("Failed", systemImage: "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Completion Summary

    private var completionSummary: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)

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

                // Show error details for failed files
                let failedFiles = viewModel.files.filter {
                    if case .failed = $0.status { return true }
                    return false
                }
                if !failedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(failedFiles) { file in
                            if case .failed(let error) = file.status {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.filename)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 24)
                }

                Button("Done") { onDismiss() }
                    .font(.body.weight(.medium))
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Cancel

    private var cancelButton: some View {
        Group {
            if viewModel.isActive {
                Button(role: .destructive) {
                    viewModel.cancelConversion()
                    onDismiss()
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
