//
//  ContentView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData
import AppKit

enum SidebarSelection: Hashable {
    case workspace(Workspace)
    case configuration(ToolConfiguration)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workspace.modifiedAt, order: .reverse)
    private var workspaces: [Workspace]

    @State private var selection: SidebarSelection?
    @State private var showingNewWorkspaceSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                workspaces: workspaces,
                selection: $selection,
                onAddWorkspace: { showingNewWorkspaceSheet = true }
            )
        } detail: {
            DetailView(selection: selection) { deleteSelection() }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingNewWorkspaceSheet) {
            NewWorkspaceSheet { workspace in
                modelContext.insert(workspace)
                selection = .workspace(workspace)
                showingNewWorkspaceSheet = false
            } onCancel: {
                showingNewWorkspaceSheet = false
            }
        }
    }

    private func deleteSelection() {
        guard let selection else { return }
        self.selection = nil
        switch selection {
        case .workspace(let ws):
            NSWorkspace.shared.open(AppStorage.outputDirectory(for: ws))
            modelContext.delete(ws)
        case .configuration(let config):
            if let workspace = config.workspace {
                NSWorkspace.shared.open(AppStorage.outputDirectory(for: workspace, configuration: config))
            }
            modelContext.delete(config)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    let workspaces: [Workspace]
    @Binding var selection: SidebarSelection?
    let onAddWorkspace: () -> Void
    @Environment(JobRegistry.self) private var registry

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(workspaces) { workspace in
                    WorkspaceSidebarRow(workspace: workspace, selection: $selection)
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
                        CompactJobRow(job: job)
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

struct WorkspaceSidebarRow: View {
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
            NewConfigurationSheet(workspace: workspace) {
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

// MARK: - New Workspace Sheet

struct NewWorkspaceSheet: View {
    let onSave: (Workspace) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var directoryURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Workspace") {
                    TextField("Name", text: $name)

                    if let url = directoryURL {
                        Button(action: selectDirectory) {
                            LabeledContent("Source Directory") {
                                Label(url.lastPathComponent, systemImage: "folder")
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    } else {
                        Button("Choose Source Directory…") { selectDirectory() }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Workspace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createWorkspace() }
                        .disabled(name.isEmpty || directoryURL == nil)
                }
            }
        }
        .frame(width: 460, height: 240)
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select source directory"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            directoryURL = url
            if name.isEmpty {
                name = url.lastPathComponent
            }
        }
    }

    private func createWorkspace() {
        guard let url = directoryURL else { return }
        let workspace = Workspace(name: name, sourceDirectory: url.path(percentEncoded: false))

        let scanned = WorkspaceScanner.scan(directory: workspace.sourceDirectory)
        for resource in scanned {
            resource.workspace = workspace
            workspace.resources.append(resource)
        }

        onSave(workspace)
    }
}

// MARK: - New Configuration Sheet

struct NewConfigurationSheet: View {
    let workspace: Workspace
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var configName = ""
    @State private var toolType: ToolType = .kmeans

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {
                    TextField("Name", text: $configName)

                    Picker("Tool", selection: $toolType) {
                        ForEach(ToolType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.iconName).tag(type)
                        }
                    }
                }

                Section("Workspace") {
                    LabeledContent("Source") {
                        Text(workspace.name)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Configuration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createConfiguration() }
                        .disabled(configName.isEmpty)
                }
            }
        }
        .frame(width: 460, height: 260)
    }

    private func createConfiguration() {
        let config = ToolConfiguration(name: configName, toolType: toolType, workspace: workspace)
        modelContext.insert(config)
        workspace.configurations.append(config)
        workspace.modifiedAt = Date()
        onDismiss()
    }
}

// MARK: - Detail View

struct DetailView: View {
    let selection: SidebarSelection?
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        Group {
            switch selection {
            case .workspace(let ws):
                WorkspaceDetailView(workspace: ws)
            case .configuration(let config):
                switch config.toolType {
                case .kmeans:
                    KMeansConfigView(configuration: config)
                case .preprocess:
                    PreprocessConfigView(configuration: config)
                }
            case nil:
                WelcomeView()
            }
        }
        .toolbar {
            if selection != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var deleteTitle: String {
        switch selection {
        case .workspace(let ws): return "Delete \"\(ws.name)\"?"
        case .configuration(let c): return "Delete \"\(c.name)\"?"
        case nil: return "Delete?"
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    var body: some View {
        ContentUnavailableView(
            "Welcome to RasterTools",
            systemImage: "map.fill",
            description: Text("Select a workspace or configuration from the sidebar, or create a new workspace to get started.")
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Workspace.self, inMemory: true)
}
