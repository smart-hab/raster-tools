//
//  SidebarView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData

// MARK: - SidebarView

struct SidebarView: View {
    let workspaces: [Workspace]
    @Binding var selection: SidebarSelection?
    let onAddWorkspace: () -> Void
    @Environment(JobRegistry.self) private var registry

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(workspaces) { workspace in
                    SidebarWorkspaceRow(workspace: workspace, selection: $selection)
                }
            }
            .navigationTitle("RasterTools")
            .toolbar {
                ToolbarItem {
                    Button(action: onAddWorkspace) {
                        Label("Add Workspace", systemImage: "plus")
                    }
                }
            }

            if !registry.jobs.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    ForEach(registry.jobs.reversed()) { job in
                        SidebarToolRunnerRow(job: job)
                        if job.id != registry.jobs.first?.id {
                            Divider()
                                .padding(.leading, 34)
                        }
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }
}

// MARK: - SidebarWorkspaceRow

struct SidebarWorkspaceRow: View {
    @Environment(\.modelContext) private var modelContext
    let workspace: Workspace
    @Binding var selection: SidebarSelection?

    @State private var isExpanded = true
    @State private var showingNewConfigSheet = false
    @State private var showingDeleteConfirmation = false

    var sortedConfigs: [ToolConfiguration] {
        workspace.configurations.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(sortedConfigs) { config in
                Label(config.name, systemImage: config.toolType.iconName)
                    .tag(SidebarSelection.configuration(config))
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            NSWorkspace.shared.open(AppStorage.outputDirectory(for: workspace, configuration: config))
                            selection = nil
                            modelContext.delete(config)
                        }
                    }
            }
        } label: {
            // Use a custom label so tapping the text selects the workspace
            // while the DisclosureGroup chevron still handles expand/collapse
            Label(workspace.name, systemImage: "folder.fill")
                .badge(workspace.configurations.count)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = .workspace(workspace)
                }
                .contextMenu {
                    Button {
                        showingNewConfigSheet = true
                    } label: {
                        Label("Add Configuration", systemImage: "plus")
                    }
                    Divider()
                    Button("Delete Workspace", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
        }
        .tag(SidebarSelection.workspace(workspace))
        .sheet(isPresented: $showingNewConfigSheet) {
            ToolCreateSheet(workspace: workspace) {
                showingNewConfigSheet = false
            }
        }
        .confirmationDialog(
            "Delete \"\(workspace.name)\"?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                NSWorkspace.shared.open(AppStorage.outputDirectory(for: workspace))
                if case .workspace(let ws) = selection, ws.id == workspace.id {
                    selection = nil
                }
                modelContext.delete(workspace)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the workspace and all its configurations. This action cannot be undone.")
        }
    }
}

// MARK: - SidebarToolRunnerRow

struct SidebarToolRunnerRow: View {
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
            ToolRunnerSheet(job: job)
        }
    }
}
