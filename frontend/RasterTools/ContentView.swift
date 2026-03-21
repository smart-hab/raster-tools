//
//  ContentView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ToolConfiguration.modifiedAt, order: .reverse) 
    private var configurations: [ToolConfiguration]
    
    @State private var selectedConfiguration: ToolConfiguration?
    @State private var showingNewConfigSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                configurations: configurations,
                selectedConfiguration: $selectedConfiguration,
                onAddConfiguration: {
                    showingNewConfigSheet = true
                },
                onDeleteConfigurations: deleteConfigurations
            )
        } detail: {
            DetailView(configuration: selectedConfiguration) {
                if let configuration = selectedConfiguration {
                    selectedConfiguration = nil
                    modelContext.delete(configuration)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingNewConfigSheet) {
            NewConfigurationSheet(
                onSave: { name, toolType, workspace in
                    createConfiguration(name: name, toolType: toolType, workspace: workspace)
                    showingNewConfigSheet = false
                },
                onCancel: {
                    showingNewConfigSheet = false
                }
            )
        }
    }

    private func createConfiguration(name: String, toolType: ToolType, workspace: String) {
        withAnimation {
            let newConfig = ToolConfiguration(
                name: name,
                toolType: toolType,
                workspacePath: workspace
            )
            modelContext.insert(newConfig)
            selectedConfiguration = newConfig
        }
    }
    
    private func deleteConfigurations(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(configurations[index])
            }
        }
    }
}

struct SidebarView: View {
    let configurations: [ToolConfiguration]
    @Binding var selectedConfiguration: ToolConfiguration?
    let onAddConfiguration: () -> Void
    let onDeleteConfigurations: (IndexSet) -> Void

    var body: some View {
        List(selection: $selectedConfiguration) {
            Section("Configurations") {
                ForEach(configurations) { config in
                    NavigationLink(value: config) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(config.name, systemImage: config.toolType.iconName)
                                Spacer()
                            }
                            Text(config.workspacePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .onDelete(perform: onDeleteConfigurations)
            }
        }
        .navigationTitle("RasterTools")
        .toolbar {
            ToolbarItem {
                Button {
                    onAddConfiguration()
                } label: {
                    Label("Add Configuration", systemImage: "plus")
                }
            }
        }
    }
}

struct NewConfigurationSheet: View {
    let onSave: (String, ToolType, String) -> Void
    let onCancel: () -> Void

    @State private var toolType: ToolType = .kmeans
    @State private var configName = ""
    @State private var workspaceURL: URL? = nil

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
                    if let url = workspaceURL {
                        LabeledContent("Folder") {
                            HStack {
                                Label(url.lastPathComponent, systemImage: "folder")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button("Change") { selectWorkspace() }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    } else {
                        Button("Choose Folder…") { selectWorkspace() }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Configuration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onSave(configName, toolType, workspaceURL!.path(percentEncoded: false))
                    }
                    .disabled(configName.isEmpty || workspaceURL == nil)
                }
            }
        }
        .frame(width: 460, height: 280)
    }

    private func selectWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select workspace folder"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            workspaceURL = url

            if configName.isEmpty {
                let prefix = toolType == .kmeans ? "kmeans" : "preprocess"
                configName = "\(prefix)_\(url.lastPathComponent)"
            }

        }
    }
}

struct DetailView: View {
    let configuration: ToolConfiguration?
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        Group {
            if let configuration {
                switch configuration.toolType {
                case .kmeans:
                    KMeansConfigView(configuration: configuration)
                case .preprocess:
                    PreprocessConfigView(configuration: configuration)
                }
            } else {
                WelcomeView()
            }
        }
        .toolbar {
            if configuration != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete \"\(configuration?.name ?? "")\"?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

struct WelcomeView: View {
    var body: some View {
        ContentUnavailableView(
            "Welcome to RasterTools",
            systemImage: "map.fill",
            description: Text("Select a tool from the sidebar or create a new configuration to get started.")
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ToolConfiguration.self, inMemory: true)
}
