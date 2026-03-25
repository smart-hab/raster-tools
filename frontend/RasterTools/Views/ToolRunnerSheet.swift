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
            if runner.isRunning {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(runner.progress.statusText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if let text = runner.progress.logText {
                            Text(text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: runner.progress.progress) {
                        Text(runner.progress.progressText ?? "\(Int(runner.progress.progress * 100))%")
                            .font(.caption)
                    }
                }
            } else if let error = runner.error {
                Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if !runner.progress.logs.isEmpty {

                Label("Completed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
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
