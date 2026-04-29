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
    let projects: [Project]
    @Binding var selection: SidebarSelection?
    let onAddProject: () -> Void
    @Environment(JobRegistry.self) private var registry

    @State private var projectForNewConfig: Project?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Sources") {
                    Label("Planet.com", systemImage: "globe")
                        .tag(SidebarSelection.planet)
                }
                Section("Projects") {
                    if projects.isEmpty {
                        Text("No projects yet. Click + to add one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(projects.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) { project in
                            SidebarProjectRow(project: project, selection: $selection) {
                                projectForNewConfig = project
                            }
                        }
                    }
                }
            }
            .sheet(item: $projectForNewConfig) { project in
                ToolCreateSheet(defaultProject: project) { config in
                    projectForNewConfig = nil
                    if let c = config as? ToolKmeansConfiguration {
                        selection = .kmeansConfiguration(c)
                    } else if let c = config as? ToolPreprocessConfiguration {
                        selection = .preprocessConfiguration(c)
                    } else if let c = config as? ToolCollectionConfiguration {
                        selection = .collectionConfiguration(c)
                    }
                }
            }
            .navigationTitle("RasterTools")
            .toolbar {
                ToolbarItem {
                    Button(action: onAddProject) {
                        Label("Create Project", systemImage: "plus")
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

// MARK: - SidebarProjectRow

struct SidebarProjectRow: View {
    @Environment(\.modelContext) private var modelContext
    let project: Project
    @Binding var selection: SidebarSelection?
    let onAddConfig: () -> Void

    @State private var isExpanded = true
    @State private var showingDeleteConfirmation = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(project.allConfigurations, id: \.selection) { config, sel in
                Label(config.name, systemImage: config.kind.iconName)
                    .tag(sel)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            NSWorkspace.shared.open(AppStorage.outputDirectory(for: project, configuration: config))
                            selection = nil
                            switch sel {
                            case .kmeansConfiguration(let c): modelContext.delete(c)
                            case .preprocessConfiguration(let c): modelContext.delete(c)
                            case .collectionConfiguration(let c): modelContext.delete(c)
                            default: break
                            }
                        }
                    }
            }
        } label: {
            // Use a custom label so tapping the text selects the project
            // while the DisclosureGroup chevron still handles expand/collapse
            Label(project.name, systemImage: "folder.fill")
                .badge(project.allConfigurations.count)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = .project(project)
                }
                .contextMenu {
                    Button {
                        onAddConfig()
                    } label: {
                        Label("Add Configuration", systemImage: "plus")
                    }
                    Divider()
                    Button("Delete Project", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
        }
        .tag(SidebarSelection.project(project))
        .confirmationDialog(
            "Delete \"\(project.name)\"?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                NSWorkspace.shared.open(AppStorage.outputDirectory(for: project))
                if case .project(let ws) = selection, ws.id == project.id {
                    selection = nil
                }
                modelContext.delete(project)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the project and all its configurations. This action cannot be undone.")
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

    private var progressLabel: String {
        if job.runner.isRunning {
            return job.runner.progress.progressText ?? "\(Int(job.runner.progress.progress * 100))%"
        }
        return ""
    }

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: 8) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.projectName.isEmpty ? job.configName : "\(job.projectName) / \(job.configName)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(job.runner.progress.statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if !progressLabel.isEmpty {
                    Text(progressLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
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
