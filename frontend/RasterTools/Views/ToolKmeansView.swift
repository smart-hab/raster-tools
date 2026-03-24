//
//  ToolKmeansView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData

struct ToolKmeansView: View {
    @Bindable var configuration: ToolConfiguration
    @Environment(\.modelContext) private var modelContext
    @Environment(JobRegistry.self) private var registry
    @State private var activeRunner: ToolKmeans?
    @State private var showingFitPicker = false
    @State private var showingClassifyPicker = false
    @State private var fitSortKey: OutputSortKey = .kind
    @State private var fitSortAscending: Bool = false
    @State private var classifySortKey: OutputSortKey = .kind
    @State private var classifySortAscending: Bool = false
    @State private var outputSortKey: OutputSortKey = .kind
    @State private var outputSortAscending: Bool = false

    private let inputKinds: [ResourceKind] = [.clipped, .masked, .ndvi, .ndci]
    @State private var fitActiveKinds: Set<ResourceKind> = [.clipped, .masked, .ndvi, .ndci]
    @State private var classifyActiveKinds: Set<ResourceKind> = [.clipped, .masked, .ndvi, .ndci]
    @State private var outputActiveKinds: Set<ResourceKind> = []
    @State private var fitSelection: Set<UUID> = []
    @State private var classifySelection: Set<UUID> = []
    @State private var outputSelection: Set<UUID> = []

    private var workspace: Workspace? { configuration.workspace }

    private var centersResource: WorkspaceResource? {
        workspace?.resources.first { $0.kind == .kmeansCenters && $0.producedBy?.id == configuration.id }
    }

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
                if let kmeansConfig = configuration.kmeansConfig {
                    LabeledContent("Centers") {
                        Button("Reset") {
                            if let resource = centersResource {
                                deleteOutputResource(resource, context: modelContext)
                            }
                        }
                        .disabled(centersResource == nil)
                    }

                    LabeledContent("Centroids") {
                        Stepper(value: Binding(
                            get: { kmeansConfig.centroids },
                            set: { newValue in
                                configuration.kmeansConfig?.centroids = newValue
                                configuration.touch()
                            }
                        ), in: 2...20) {
                            Text("\(kmeansConfig.centroids)")
                                .monospacedDigit()
                        }
                    }

                    LabeledContent("Iterations") {
                        Stepper(value: Binding(
                            get: { kmeansConfig.nTimes },
                            set: { newValue in
                                configuration.kmeansConfig?.nTimes = newValue
                                configuration.touch()
                            }
                        ), in: 1...100) {
                            Text("\(kmeansConfig.nTimes)")
                                .monospacedDigit()
                        }
                    }

                    LabeledContent("Random Seed") {
                        TextField("", value: Binding(
                            get: { kmeansConfig.seed },
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
                        ResourceTableView(
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
                        ResourceTableView(
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
                    ResourceTableView(
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
                        let runner = ToolKmeans()
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
