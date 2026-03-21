//
//  KMeansConfigView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData

struct KMeansConfigView: View {
    @Bindable var configuration: ToolConfiguration
    @Environment(\.modelContext) private var modelContext
    @State private var runner = KMeansRunner()
    @State private var showingFitPicker = false
    @State private var showingClassifyPicker = false

    private var workspace: Workspace? { configuration.workspace }

    var body: some View {
        Form {
            Section("Configuration") {
                LabeledContent("Name") {
                    Text(configuration.name)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Workspace") {
                    Text(workspace?.sourceDirectory ?? "")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                }
            }

            Section("K-Means Parameters") {
                if configuration.kmeansConfig != nil {
                    LabeledContent("Centers File") {
                        TextField("centers.txt", text: Binding(
                            get: { configuration.kmeansConfig?.centersFile ?? "centers.txt" },
                            set: { newValue in
                                configuration.kmeansConfig?.centersFile = newValue
                                configuration.touch()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Centroids") {
                        Stepper(value: Binding(
                            get: { configuration.kmeansConfig?.centroids ?? 6 },
                            set: { newValue in
                                configuration.kmeansConfig?.centroids = newValue
                                configuration.touch()
                            }
                        ), in: 2...20) {
                            Text("\(configuration.kmeansConfig?.centroids ?? 6)")
                                .monospacedDigit()
                        }
                    }

                    LabeledContent("Iterations") {
                        Stepper(value: Binding(
                            get: { configuration.kmeansConfig?.nTimes ?? 10 },
                            set: { newValue in
                                configuration.kmeansConfig?.nTimes = newValue
                                configuration.touch()
                            }
                        ), in: 1...100) {
                            Text("\(configuration.kmeansConfig?.nTimes ?? 10)")
                                .monospacedDigit()
                        }
                    }

                    LabeledContent("Random Seed") {
                        TextField("42", value: Binding(
                            get: { configuration.kmeansConfig?.seed ?? 42 },
                            set: { newValue in
                                configuration.kmeansConfig?.seed = newValue
                                configuration.touch()
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }

            Section("Fit Rasters") {
                if let kmeansConfig = configuration.kmeansConfig {
                    if kmeansConfig.filesFit.isEmpty {
                        Text("No raster files selected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(kmeansConfig.filesFit, id: \.id) { resource in
                            ResourceTableRow(
                                icon: resource.kind.iconName,
                                label: resource.displayLabel,
                                fileSize: resource.formattedFileSize,
                                badges: resource.tableBadges,
                                onDelete: {
                                    configuration.kmeansConfig?.filesFit.removeAll { $0.id == resource.id }
                                    configuration.touch()
                                }
                            )
                        }
                    }
                    if let workspace {
                        Button("Add Files...") { showingFitPicker = true }
                            .sheet(isPresented: $showingFitPicker) {
                                ResourcePickerView(
                                    workspace: workspace,
                                    defaultKinds: [.clipped, .masked],
                                    selectableKinds: [.sourceRaster, .clipped, .masked, .ndvi, .ndci],
                                    selection: Binding(
                                        get: { configuration.kmeansConfig?.filesFit ?? [] },
                                        set: { configuration.kmeansConfig?.filesFit = $0; configuration.touch() }
                                    ),
                                    allowsMultiple: true
                                )
                            }
                    }
                }
            }

            Section("Classify Rasters") {
                if let kmeansConfig = configuration.kmeansConfig {
                    if kmeansConfig.filesClassify.isEmpty {
                        Text("No raster files selected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(kmeansConfig.filesClassify, id: \.id) { resource in
                            ResourceTableRow(
                                icon: resource.kind.iconName,
                                label: resource.displayLabel,
                                fileSize: resource.formattedFileSize,
                                badges: resource.tableBadges,
                                onDelete: {
                                    configuration.kmeansConfig?.filesClassify.removeAll { $0.id == resource.id }
                                    configuration.touch()
                                }
                            )
                        }
                    }
                    if let workspace {
                        Button("Add Files...") { showingClassifyPicker = true }
                            .sheet(isPresented: $showingClassifyPicker) {
                                ResourcePickerView(
                                    workspace: workspace,
                                    defaultKinds: [.clipped, .masked],
                                    selectableKinds: [.sourceRaster, .clipped, .masked, .ndvi, .ndci],
                                    selection: Binding(
                                        get: { configuration.kmeansConfig?.filesClassify ?? [] },
                                        set: { configuration.kmeansConfig?.filesClassify = $0; configuration.touch() }
                                    ),
                                    allowsMultiple: true
                                )
                            }
                    }
                }
            }

            // Outputs produced by this configuration
            let outputs = workspace?.resources.filter { $0.producedBy?.id == configuration.id } ?? []
            let outputGroups = groupOutputsByKind(outputs)
            if !outputGroups.isEmpty {
                Section("Outputs") {
                    ForEach(outputGroups, id: \.kind) { group in
                        if outputGroups.count > 1 {
                            Text(group.kind.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(group.resources, id: \.id) { resource in
                            ResourceTableRow(
                                icon: resource.kind.iconName,
                                label: resource.displayLabel,
                                fileSize: resource.formattedFileSize,
                                badges: resource.tableBadges,
                                pngPath: resource.pngPath,
                                onDelete: { deleteOutputResource(resource, context: modelContext) }
                            )
                        }
                    }
                }
            }

            if runner.isRunning || !runner.progress.logs.isEmpty {
                Section("Progress") {
                    ToolProgressView(runner: runner)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(configuration.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if runner.isRunning {
                    Button("Cancel", role: .destructive) {
                        runner.cancel()
                    }
                } else {
                    Button("Run K-Means") {
                        Task {
                            do {
                                try await runner.run(configuration: configuration, context: modelContext)
                            } catch {
                                print("Error running K-Means: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(configuration.kmeansConfig?.filesFit.isEmpty != false)
                }
            }
        }
    }
}
