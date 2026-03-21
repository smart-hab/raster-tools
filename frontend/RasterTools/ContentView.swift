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
    @State private var newConfigToolType: ToolType = .kmeans
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                configurations: configurations,
                selectedConfiguration: $selectedConfiguration,
                onAddConfiguration: { toolType in
                    newConfigToolType = toolType
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
                toolType: newConfigToolType,
                onSave: { name, workspace in
                    createConfiguration(name: name, toolType: newConfigToolType, workspace: workspace)
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
    let onAddConfiguration: (ToolType) -> Void
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
                Menu {
                    ForEach(ToolType.allCases, id: \.self) { toolType in
                        Button {
                            onAddConfiguration(toolType)
                        } label: {
                            Label(toolType.rawValue, systemImage: toolType.iconName)
                        }
                    }
                } label: {
                    Label("Add Configuration", systemImage: "plus")
                }
            }
        }
    }
}

struct NewConfigurationSheet: View {
    let toolType: ToolType
    let onSave: (String, String) -> Void
    let onCancel: () -> Void
    
    @State private var configName = ""
    @State private var workspacePath = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Tool") {
                        Label(toolType.rawValue, systemImage: toolType.iconName)
                    }
                }
                
                Section("Configuration") {
                    TextField("Configuration Name", text: $configName)
                        .textFieldStyle(.roundedBorder)
                    
                    HStack {
                        TextField("Workspace Path", text: $workspacePath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        
                        Button("Choose...") {
                            selectWorkspace()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Configuration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onSave(configName, workspacePath)
                    }
                    .disabled(configName.isEmpty || workspacePath.isEmpty)
                }
            }
        }
        .frame(width: 500, height: 300)
    }
    
    private func selectWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select workspace directory for \(toolType.rawValue)"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            workspacePath = url.path(percentEncoded: false)

            // Auto-suggest a config name if empty
            if configName.isEmpty {
                let prefix = toolType == .kmeans ? "kmeans" : "preprocess"
                configName = "\(prefix)_\(url.lastPathComponent)"
            }

            // Prompt for the parent folder so the app retains access after relaunch
            let parentURL = url.deletingLastPathComponent()
            self.requestParentFolderAccess(for: parentURL)
        }
    }

    private func requestParentFolderAccess(for parentURL: URL) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = parentURL
        panel.prompt = "Grant Access"
        panel.message = "Allow RasterTools to access \"\(parentURL.lastPathComponent)\" so it can read files after relaunch."

        panel.begin { response in
            guard response == .OK, let granted = panel.url else { return }
            BookmarkManager.shared.saveBookmark(for: granted)
            _ = granted.startAccessingSecurityScopedResource()
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
