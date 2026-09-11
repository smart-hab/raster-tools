//
//  ToolCreateSheet.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData

struct ToolCreateSheet: View {
    let defaultProject: Project
    let onCreated: (any ToolConfiguration) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.modifiedAt, order: .reverse) private var projects: [Project]

    @State private var configName = ""
    @State private var toolKind: ToolKind = .kmeans
    @State private var selectedProject: Project?

    private var project: Project {
        selectedProject ?? defaultProject
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {

                    Picker("Project", selection: $selectedProject) {
                        Text(defaultProject.name)
                            .tag(Optional<Project>.none)
                        if projects.count > 1 {
                            Divider()
                            ForEach(projects) { project in
                                Text(project.name).tag(Optional(project))
                            }
                        }
                    }

                    Picker("Tool", selection: $toolKind) {
                        ForEach(ToolKind.allCases, id: \.self) { kind in
                            Label(kind.rawValue, systemImage: kind.iconName).tag(kind)
                        }
                    }
                    .onChange(of: toolKind) { _, newKind in
                        if newKind.isCollector && configName.isEmpty {
                            configName = project.name
                        }
                    }
                    
                    TextField("Name", text: $configName, prompt: Text("My Config"))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
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
            let config = ToolKmeansConfiguration(name: configName, project: project)
            modelContext.insert(config)
            project.kmeansConfigurations.append(config)
            project.modifiedAt = Date()
            onCreated(config)
        case .preprocess:
            let config = ToolPreprocessConfiguration(name: configName, project: project)
            modelContext.insert(config)
            project.preprocessConfigurations.append(config)
            project.modifiedAt = Date()
            onCreated(config)
        case .collectionPlanet:
            let config = ToolCollectionConfiguration(name: configName, project: project)
            modelContext.insert(config)
            project.collectionConfigurations.append(config)
            project.modifiedAt = Date()
            onCreated(config)
        case .collectionSentinel2:
            let config = ToolSentinel2Configuration(name: configName, project: project)
            modelContext.insert(config)
            project.sentinel2Configurations.append(config)
            project.modifiedAt = Date()
            onCreated(config)
        }
    }
}
