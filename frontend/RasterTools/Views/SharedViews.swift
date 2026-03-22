//
//  SharedViews.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData

// MARK: - Compact Job Row

struct CompactJobRow: View {
    let job: Job
    @State private var showingDetail = false
    @Environment(JobRegistry.self) private var registry

    private var statusIcon: some View {
        Group {
            if job.runner.isRunning {
                ProgressView()
                    .controlSize(.small)
            } else if job.runner.error != nil {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .frame(width: 16, height: 16)
    }

    private var fileFraction: String {
        let p = job.runner.progress
        if job.runner.isRunning {
            if p.totalFiles > 0 {
                return "\(p.completedFiles)/\(p.totalFiles)"
            }
            return ""
        }
        if job.runner.error != nil { return "Error" }
        return "Done"
    }

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: 8) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(job.workspaceName) / \(job.configName)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if !fileFraction.isEmpty {
                            Text(fileFraction)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Text(job.runner.progress.currentStep)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button {
                    if job.runner.isRunning {
                        job.runner.cancel()
                    }
                    registry.remove(job)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            ToolProgressDetailSheet(job: job)
        }
    }
}

// MARK: - Tool Progress Detail Sheet

struct ToolProgressDetailSheet: View {
    let job: Job
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ToolProgressView(runner: job.runner)
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

// MARK: - Badge Capsule

struct BadgeCapsule: View {
    let label: String

    private var color: Color {
        switch label {
        case "source":  return .secondary
        case "udm2":    return .blue
        case "shape":   return .green
        case "clipped": return .orange
        case "masked":  return .red
        case "ndvi":    return .teal
        case "ndci":    return .purple
        default:        return .secondary
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - File Selection

struct FileSelectionView: View {
    let availableFiles: [String]
    @Binding var selectedFiles: [String]
    
    var body: some View {
        List {
            ForEach(availableFiles, id: \.self) { file in
                Toggle(file, isOn: Binding(
                    get: { selectedFiles.contains(file) },
                    set: { isSelected in
                        if isSelected {
                            selectedFiles.append(file)
                        } else {
                            selectedFiles.removeAll { $0 == file }
                        }
                    }
                ))
                .toggleStyle(.checkmark)
            }
        }
        .frame(maxHeight: 200)
    }
}

// MARK: - Tool Progress View

struct ToolProgressView: View {
    @Bindable var runner: ToolRunner
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status header
            if runner.isRunning {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(runner.progress.currentStep)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if let file = runner.progress.currentFile {
                            Text(file)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                
                // Progress bar
                if runner.progress.totalFiles > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: runner.progress.progress) {
                            Text("\(runner.progress.completedFiles) of \(runner.progress.totalFiles) files")
                                .font(.caption)
                        }
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
