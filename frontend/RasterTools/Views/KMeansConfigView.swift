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
    @Environment(JobRegistry.self) private var registry
    @State private var activeRunner: KMeansRunner?
    @State private var showingFitPicker = false
    @State private var showingClassifyPicker = false
    @State private var fitSortKey: OutputSortKey = .date
    @State private var fitSortAscending: Bool = false
    @State private var classifySortKey: OutputSortKey = .date
    @State private var classifySortAscending: Bool = false
    @State private var outputSortKey: OutputSortKey = .date
    @State private var outputSortAscending: Bool = false

    private let inputKinds: [ResourceKind] = [.clipped, .masked, .ndvi, .ndci]
    @State private var fitActiveKinds: Set<ResourceKind> = [.clipped, .masked, .ndvi, .ndci]
    @State private var classifyActiveKinds: Set<ResourceKind> = [.clipped, .masked, .ndvi, .ndci]
    @State private var outputActiveKinds: Set<ResourceKind> = []
    @State private var fitSelection: Set<UUID> = []
    @State private var classifySelection: Set<UUID> = []
    @State private var outputSelection: Set<UUID> = []

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
                if let workspace {
                    LabeledContent("Output Dir") {
                        Button {
                            NSWorkspace.shared.open(AppStorage.outputDirectory(for: workspace, configuration: configuration))
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("K-Means Parameters") {
                if configuration.kmeansConfig != nil {
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
                        TextField("", value: Binding(
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
                    }
                    if let workspace {
                        ResourceSectionContent(
                            resources: kmeansConfig.filesFit,
                            filterKinds: inputKinds,
                            activeKinds: $fitActiveKinds,
                            sortKey: $fitSortKey,
                            sortAscending: $fitSortAscending,
                            selection: $fitSelection,
                            onAdd: { showingFitPicker = true },
                            onDeleteSelected: { ids in
                                for id in ids {
                                    configuration.kmeansConfig?.filesFit.removeAll { $0.id == id }
                                }
                                configuration.touch()
                                fitSelection.removeAll()
                            }
                        )
                        .sheet(isPresented: $showingFitPicker) {
                            ResourcePickerView(
                                workspace: workspace,
                                defaultKinds: [.clipped, .masked, .ndvi, .ndci],
                                selectableKinds: [.clipped, .masked, .ndvi, .ndci],
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
                    }
                    if let workspace {
                        ResourceSectionContent(
                            resources: kmeansConfig.filesClassify,
                            filterKinds: inputKinds,
                            activeKinds: $classifyActiveKinds,
                            sortKey: $classifySortKey,
                            sortAscending: $classifySortAscending,
                            selection: $classifySelection,
                            onAdd: { showingClassifyPicker = true },
                            onDeleteSelected: { ids in
                                for id in ids {
                                    configuration.kmeansConfig?.filesClassify.removeAll { $0.id == id }
                                }
                                configuration.touch()
                                classifySelection.removeAll()
                            }
                        )
                        .sheet(isPresented: $showingClassifyPicker) {
                            ResourcePickerView(
                                workspace: workspace,
                                defaultKinds: [.clipped, .masked, .ndvi, .ndci],
                                selectableKinds: [.clipped, .masked, .ndvi, .ndci],
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
            if !outputs.isEmpty {
                let outputKinds = Array(Set(outputs.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
                Section("Outputs") {
                    ResourceSectionContent(
                        resources: outputs,
                        filterKinds: outputKinds,
                        activeKinds: $outputActiveKinds,
                        sortKey: $outputSortKey,
                        sortAscending: $outputSortAscending,
                        selection: $outputSelection,
                        onDeleteSelected: { ids in
                            for id in ids {
                                if let resource = outputs.first(where: { $0.id == id }) {
                                    deleteOutputResource(resource, context: modelContext)
                                }
                            }
                            outputSelection.removeAll()
                        }
                    )
                }
            }

        }
        .formStyle(.grouped)
        .navigationTitle(configuration.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let runner = activeRunner, runner.isRunning {
                    Button("Cancel", role: .destructive) {
                        runner.cancel()
                    }
                } else {
                    Button("Run K-Means") {
                        let runner = KMeansRunner()
                        activeRunner = runner
                        registry.register(
                            runner: runner,
                            configName: configuration.name,
                            workspaceName: workspace?.name ?? ""
                        )
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
