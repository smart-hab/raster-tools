//
//  ToolCreateSheet.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData

struct ToolCreateSheet: View {
    let defaultWorkspace: Workspace
    let onCreated: (any ToolConfiguration) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workspace.modifiedAt, order: .reverse) private var workspaces: [Workspace]

    @State private var configName = ""
    @State private var toolKind: ToolKind = .kmeans
    @State private var selectedWorkspace: Workspace?

    private var workspace: Workspace {
        selectedWorkspace ?? defaultWorkspace
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {

                    Picker("Project", selection: $selectedWorkspace) {
                        Text(defaultWorkspace.name)
                            .tag(Optional<Workspace>.none)
                        if workspaces.count > 1 {
                            Divider()
                            ForEach(workspaces) { ws in
                                Text(ws.name).tag(Optional(ws))
                            }
                        }
                    }

                    Picker("Tool", selection: $toolKind) {
                        ForEach(ToolKind.allCases, id: \.self) { kind in
                            Label(kind.rawValue, systemImage: kind.iconName).tag(kind)
                        }
                    }
                    .onChange(of: toolKind) { _, newKind in
                        if newKind == .collection && configName.isEmpty {
                            configName = workspace.name
                        }
                    }
                    
                    TextField("Name", text: $configName, prompt: Text("My Config"))
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Configuration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
        switch toolKind {
        case .kmeans:
            let config = ToolKmeansConfiguration(name: configName, workspace: workspace)
            modelContext.insert(config)
            workspace.kmeansConfigurations.append(config)
            workspace.modifiedAt = Date()
            onCreated(config)
        case .preprocess:
            let config = ToolPreprocessConfiguration(name: configName, workspace: workspace)
            modelContext.insert(config)
            workspace.preprocessConfigurations.append(config)
            workspace.modifiedAt = Date()
            onCreated(config)
        case .collection:
            let config = ToolCollectionConfiguration(name: configName, workspace: workspace)
            modelContext.insert(config)
            workspace.collectionConfigurations.append(config)
            workspace.modifiedAt = Date()
            onCreated(config)
        }
    }
}
