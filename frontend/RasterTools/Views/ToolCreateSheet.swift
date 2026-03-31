//
//  ToolCreateSheet.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData

struct ToolCreateSheet: View {
    let workspace: Workspace
    let onCreated: (any ToolConfiguration) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var configName = ""
    @State private var toolKind: ToolKind = .kmeans

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {
                    TextField("Name", text: $configName)

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
