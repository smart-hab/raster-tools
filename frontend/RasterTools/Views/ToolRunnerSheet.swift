//
//  ToolRunnerSheet.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData


// MARK: - Tool Progress Detail Sheet

struct ToolRunnerSheet: View {
    let job: Job
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ToolRunnerDetailsView(runner: job.runner)
                    .padding()
            }
            .navigationTitle("\(job.workspaceName) / \(job.configName)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

// MARK: - Tool Progress View

struct ToolRunnerDetailsView: View {
    @Bindable var runner: ToolRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status header
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(runner.progress.statusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let error = runner.error {
                        Text(error.localizedDescription)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }

                Spacer()

                let progressLabel = runner.isRunning
                    ? (runner.progress.progressText ?? "\(Int(runner.progress.progress * 100))%")
                    : ""
                if !progressLabel.isEmpty {
                    Text(progressLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Group {
                    if runner.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else if runner.error != nil {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .frame(width: 16, height: 16)
            }

            if runner.isRunning {
                ProgressView(value: runner.progress.progress) {
                    EmptyView()
                }
            }

            // Logs
            if !runner.progress.logs.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(runner.progress.logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
            }
        }
    }
}
