//
//  ToolKmeansView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData

struct ToolKmeansView: View {
    @Bindable var configuration: ToolKmeansConfiguration
    @Environment(\.modelContext) private var modelContext
    @Environment(JobRegistry.self) private var registry
    @State private var activeRunner: ToolKmeans?
    @State private var showingFitPicker = false
    @State private var showingClassifyPicker = false
    @State private var fitSelection: Set<UUID> = []
    @State private var classifySelection: Set<UUID> = []
    @State private var outputSelection: Set<UUID> = []
    @State private var fitGalleryRequest: GalleryRequest?
    @State private var classifyGalleryRequest: GalleryRequest?
    @State private var outputGalleryRequest: GalleryRequest?

    private let inputKinds: [ResourceKind] = [.clipped, .masked, .ndvi, .ndci]

    private var workspace: Workspace { configuration.workspace }

    private var centersResource: WorkspaceResource? {
        workspace.resources.first { $0.kind == .kmeansCenters && $0.producedByConfigId == configuration.id }
    }

    var body: some View {
        Form {
            Section("K-Means Configuration") {
                LabeledContent("Name") {
                    Text(configuration.name)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Project") {
                    Text(workspace.name)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Output Dir") {
                    Button {
                        NSWorkspace.shared.open(AppStorage.outputDirectory(for: workspace, configuration: configuration))
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("K-Means Parameters") {
                LabeledContent("Centers") {
                    Button("Reset") {
                        if let resource = centersResource {
                            deleteOutputResource(resource, context: modelContext)
                        }
                    }
                    .disabled(centersResource == nil)
                }

                LabeledContent("Centroids") {
                    Stepper(value: $configuration.centroids, in: 2...20) {
                        Text("\(configuration.centroids)")
                            .monospacedDigit()
                    }
                }

                LabeledContent("Iterations") {
                    Stepper(value: $configuration.nTimes, in: 1...100) {
                        Text("\(configuration.nTimes)")
                            .monospacedDigit()
                    }
                }

                LabeledContent("Random Seed") {
                    TextField("", value: $configuration.seed, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("Fit Rasters") {
                ResourceTableView(
                    items: configuration.filesFit,
                    itemID: \.id,
                    sortOptions: TableSortOption<WorkspaceResource>.allCases,
                    filterOptions: TableFilterOption<WorkspaceResource>.forKinds(inputKinds),
                    selectionActions: [
                        TableSelectionAction<WorkspaceResource>.gallery(request: $fitGalleryRequest),
                        TableSelectionAction<WorkspaceResource>.delete(
                            from: $configuration.filesFit,
                            selectionIDs: $fitSelection,
                            touch: { configuration.touch() }
                        )
                    ],
                    selection: $fitSelection,
                    onAdd: { showingFitPicker = true }
                ) { resource, isSelected in
                    ResourceTableRow(
                        icon: resource.kind.iconName,
                        label: resource.displayLabel,
                        fileSize: resource.formattedFileSize,
                        badges: resource.tableBadges,
                        pngPath: resource.pngPath,
                        isSelected: isSelected
                    )
                }
                .sheet(item: $fitGalleryRequest) { request in
                    ResourceGallerySheet(items: request.items, initialIndex: request.initialIndex)
                }
                .sheet(isPresented: $showingFitPicker) {
                    ResourcePickerView(
                        workspace: workspace,
                        defaultKinds: [.clipped, .masked, .ndvi, .ndci],
                        selectableKinds: [.clipped, .masked, .ndvi, .ndci],
                        selection: $configuration.filesFit,
                        initialSortOptionID: "kind",
                        initialSortAscending: true
                    )
                }
            }

            Section("Classify Rasters") {
                ResourceTableView(
                    items: configuration.filesClassify,
                    itemID: \.id,
                    sortOptions: TableSortOption<WorkspaceResource>.allCases,
                    filterOptions: TableFilterOption<WorkspaceResource>.forKinds(inputKinds),
                    selectionActions: [
                        TableSelectionAction<WorkspaceResource>.gallery(request: $classifyGalleryRequest),
                        TableSelectionAction<WorkspaceResource>.delete(
                            from: $configuration.filesClassify,
                            selectionIDs: $classifySelection,
                            touch: { configuration.touch() }
                        )
                    ],
                    selection: $classifySelection,
                    onAdd: { showingClassifyPicker = true }
                ) { resource, isSelected in
                    ResourceTableRow(
                        icon: resource.kind.iconName,
                        label: resource.displayLabel,
                        fileSize: resource.formattedFileSize,
                        badges: resource.tableBadges,
                        pngPath: resource.pngPath,
                        isSelected: isSelected
                    )
                }
                .sheet(item: $classifyGalleryRequest) { request in
                    ResourceGallerySheet(items: request.items, initialIndex: request.initialIndex)
                }
                .sheet(isPresented: $showingClassifyPicker) {
                    ResourcePickerView(
                        workspace: workspace,
                        defaultKinds: [.clipped, .masked, .ndvi, .ndci],
                        selectableKinds: [.clipped, .masked, .ndvi, .ndci],
                        selection: $configuration.filesClassify,
                        initialSortOptionID: "kind",
                        initialSortAscending: true
                    )
                }
            }

            // Outputs produced by this configuration
            let outputs = workspace.resources.filter { $0.producedByConfigId == configuration.id }
            let outputKinds = Array(Set(outputs.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
            Section("Outputs") {
                ResourceTableView(
                    items: outputs,
                        itemID: \.id,
                    sortOptions: TableSortOption<WorkspaceResource>.allCases,
                    filterOptions: TableFilterOption<WorkspaceResource>.forKinds(outputKinds),
                    selectionActions: [
                        TableSelectionAction<WorkspaceResource>.gallery(request: $outputGalleryRequest),
                        TableSelectionAction<WorkspaceResource>.deleteOutput(context: modelContext, selectionIDs: $outputSelection)
                    ],
                    selection: $outputSelection,
                    initialSortOptionID: "kind",
                    initialSortAscending: true
                ) { resource, isSelected in
                    ResourceTableRow(
                        icon: resource.kind.iconName,
                        label: resource.displayLabel,
                        fileSize: resource.formattedFileSize,
                        badges: resource.tableBadges,
                        pngPath: resource.pngPath,
                        isSelected: isSelected
                    )
                }
                .sheet(item: $outputGalleryRequest) { request in
                    ResourceGallerySheet(items: request.items, initialIndex: request.initialIndex)
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
                    Button {
                        let runner = ToolKmeans()
                        activeRunner = runner
                        registry.register(
                            runner: runner,
                            configName: configuration.name,
                            workspaceName: workspace.name
                        )
                        Task {
                            do {
                                try await runner.run(configuration: configuration, context: modelContext)
                            } catch {
                                print("Error running K-Means: \(error)")
                            }
                        }
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(configuration.filesFit.isEmpty)
                }
            }
        }
    }

}
