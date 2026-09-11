//
//  ToolPreprocessView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData

struct ToolPreprocessView: View {
    @Bindable var configuration: ToolPreprocessConfiguration
    @Environment(\.modelContext) private var modelContext
    @Environment(JobRegistry.self) private var registry
    @State private var activeRunner: ToolPreprocess?
    @State private var showingShapePicker = false
    @State private var showingRasterPicker = false
    private let rasterKinds: [ResourceKind] = [.sourceRaster, .udm]
    @State private var rasterSelection: Set<UUID> = []
    @State private var outputSelection: Set<UUID> = []
    @State private var rasterGalleryRequest: GalleryRequest?
    @State private var outputGalleryRequest: GalleryRequest?

    private var project: Project { configuration.project }

    var body: some View {
        Form {
            configSection
            processesSection
            rasterFilesSection
            outputsSection
        }
        .formStyle(.grouped)
        .navigationTitle(configuration.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                runButton
            }
        }
    }

    @ViewBuilder
    private var configSection: some View {
        Section("Pre-processing Configuration") {
            TextField("Name", text: $configuration.name)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
            LabeledContent("Project") {
                Text(project.name)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Output Dir") {
                Button {
                    NSWorkspace.shared.open(AppStorage.outputDirectory(for: project, configuration: configuration))
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
            }
        }
        
        Section("Pre-processing Shape") {
            LabeledContent("Shape File") {
                if let selected = configuration.shapeFile {
                    Button {
                        showingShapePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: ResourceKind.shapeFile.iconName)
                            Text(selected.filename)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Select File…") { showingShapePicker = true }
                        .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showingShapePicker) {
                shapePickerSheet(project: project)
            }
        }
    }

    private func shapePickerSheet(project: Project) -> some View {
        ResourcePickerView(
            project: project,
            defaultKinds: [.shapeFile],
            selectableKinds: [.shapeFile],
            selection: Binding(
                get: {
                    if let sf = configuration.shapeFile { return [sf] }
                    return []
                },
                set: { resources in
                    configuration.shapeFile = resources.first
                    configuration.touch()
                }
            ),
            selectionMode: .single
        )
    }

    @ViewBuilder
    private var processesSection: some View {
        Section("Processes") {
            Text("Select which indices to calculate")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach([ResourceKind.ndci, .ndvi], id: \.self) { processType in
                    ProcessTile(
                        processType: processType,
                        isSelected: configuration.processTypes.contains(processType)
                    ) {
                        var types = configuration.processTypes
                        if types.contains(processType) {
                            types.removeAll { $0 == processType }
                        } else {
                            types.append(processType)
                        }
                        configuration.processTypes = types
                        configuration.touch()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var rasterFilesSection: some View {
        Section("Raster Files") {
            ResourceTableView(
                    items: configuration.files,
                    itemID: \.id,
                    sortOptions: TableSortOption<ProjectResource>.allCases,
                    filterOptions: TableFilterOption<ProjectResource>.forKinds(rasterKinds),
                    selectionActions: [
                        TableSelectionAction<ProjectResource>.gallery(request: $rasterGalleryRequest),
                        TableSelectionAction<ProjectResource>.delete(
                            from: $configuration.files,
                            selectionIDs: $rasterSelection,
                            touch: { configuration.touch() }
                        )
                    ],
                    selection: $rasterSelection,
                    onAdd: { showingRasterPicker = true },
                    initialSortOptionID: "date"
                ) { resource, isSelected in
                    ResourceTableRow(resource: resource, isSelected: isSelected)
                }
                .sheet(item: $rasterGalleryRequest) { request in
                    ResourceGallerySheet(items: request.items, initialIndex: request.initialIndex)
                }
                .sheet(isPresented: $showingRasterPicker) {
                    ResourcePickerView(
                        project: project,
                        defaultKinds: [.sourceRaster],
                        selectableKinds: [.sourceRaster],
                        selection: $configuration.files,
                        initialSortOptionID: "date"
                    )
                }
        }
    }

    @ViewBuilder
    private var outputsSection: some View {
        let outputs = project.resources.filter { $0.producedByConfigId == configuration.id }
        let outputKinds = Array(Set(outputs.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
        Section("Outputs") {
            ResourceTableView(
                items: outputs,
                    itemID: \.id,
                sortOptions: TableSortOption<ProjectResource>.allCases,
                filterOptions: TableFilterOption<ProjectResource>.forKinds(outputKinds),
                selectionActions: [
                    TableSelectionAction<ProjectResource>.gallery(request: $outputGalleryRequest),
                    TableSelectionAction<ProjectResource>.deleteOutput(context: modelContext, selectionIDs: $outputSelection)
                ],
                selection: $outputSelection,
                initialSortOptionID: "kind"
            ) { resource, isSelected in
                ResourceTableRow(resource: resource, isSelected: isSelected)
            }
            .sheet(item: $outputGalleryRequest) { request in
                ResourceGallerySheet(items: request.items, initialIndex: request.initialIndex)
            }
        }
    }

    @ViewBuilder
    private var runButton: some View {
        if let runner = activeRunner, runner.isRunning {
            Button("Cancel", role: .destructive) {
                runner.cancel()
            }
        } else {
            Button {
                let runner = ToolPreprocess()
                activeRunner = runner
                registry.register(
                    runner: runner,
                    configName: configuration.name,
                    projectName: project.name
                )
                Task {
                    do {
                        try await runner.run(configuration: configuration, context: modelContext)
                    } catch {
                        print("Error running preprocessing: \(error)")
                    }
                }
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                configuration.files.isEmpty ||
                configuration.shapeFile == nil
            )
        }
    }

}

private struct ProcessTile: View {
    let processType: ResourceKind
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: processType.iconName)
                    .font(.system(size: 28))
                Text(processType.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? processType.color.opacity(0.15) : Color.primary.opacity(0.001))
            .foregroundStyle(isSelected ? processType.color : Color.secondary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? processType.color : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
