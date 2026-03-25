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
    let onCreated: (ToolConfiguration) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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
                    .onChange(of: toolType) { _, newType in
                        if newType == .collection && configName.isEmpty {
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
        let config = ToolConfiguration(name: configName, toolType: toolType, workspace: workspace)
        modelContext.insert(config)
        workspace.configurations.append(config)
        workspace.modifiedAt = Date()
        onCreated(config)
    }
}
