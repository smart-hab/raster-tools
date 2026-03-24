//
//  ToolPreprocessView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData

struct ToolPreprocessView: View {
    @Bindable var configuration: ToolConfiguration
    @Environment(\.modelContext) private var modelContext
    @Environment(JobRegistry.self) private var registry
    @State private var activeRunner: ToolPreprocess?
    @State private var showingShapePicker = false
    @State private var showingRasterPicker = false
    @State private var rasterSortKey: OutputSortKey = .date
    @State private var rasterSortAscending: Bool = false
    @State private var outputSortKey: OutputSortKey = .kind
    @State private var outputSortAscending: Bool = false
    private let rasterKinds: [ResourceKind] = [.sourceRaster, .udm]
    @State private var rasterActiveKinds: Set<ResourceKind> = [.sourceRaster, .udm]
    @State private var outputActiveKinds: Set<ResourceKind> = []
    @State private var rasterSelection: Set<UUID> = []
    @State private var outputSelection: Set<UUID> = []

    private var workspace: Workspace? { configuration.workspace }

    var body: some View {
        Form {
            configSection
            shapeFileSection
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
    }

    @ViewBuilder
    private var shapeFileSection: some View {
        Section("Shape File") {
            if let workspace {
                if let selected = configuration.preprocessConfig?.shapeFile {
                    ResourceTableRow(
                        icon: ResourceKind.shapeFile.iconName,
                        label: selected.filename,
                        fileSize: selected.formattedFileSize,
                        badges: selected.tableBadges,
                        onDelete: {
                            configuration.preprocessConfig?.shapeFile = nil
                            configuration.touch()
                        }
                    )
                } else {
                    Text("No shape file selected")
                        .foregroundStyle(.secondary)
                }
                Button("Select Shape File...") { showingShapePicker = true }
                    .sheet(isPresented: $showingShapePicker) {
                        shapePickerSheet(workspace: workspace)
                    }
            }
        }
    }

    private func shapePickerSheet(workspace: Workspace) -> some View {
        ResourcePickerView(
            workspace: workspace,
            defaultKinds: [.shapeFile],
            selectableKinds: [.shapeFile],
            selection: Binding(
                get: {
                    if let sf = configuration.preprocessConfig?.shapeFile { return [sf] }
                    return []
                },
                set: { resources in
                    configuration.preprocessConfig?.shapeFile = resources.first
                    configuration.touch()
                }
            ),
            allowsMultiple: false
        )
    }

    @ViewBuilder
    private var processesSection: some View {
        Section("Processes") {
            if let preprocessConfig = configuration.preprocessConfig {
                Text("Select which indices to calculate")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ForEach([ResourceKind.ndci, .ndvi], id: \.self) { processType in
                        ProcessTile(
                            processType: processType,
                            isSelected: preprocessConfig.processTypes.contains(processType)
                        ) {
                            guard var types = configuration.preprocessConfig?.processTypes else { return }
                            if types.contains(processType) {
                                types.removeAll { $0 == processType }
                            } else {
                                types.append(processType)
                            }
                            configuration.preprocessConfig?.processTypes = types
                            configuration.touch()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var rasterFilesSection: some View {
        Section("Raster Files") {
            if let preprocessConfig = configuration.preprocessConfig {
                if preprocessConfig.files.isEmpty {
                    Text("No raster files selected")
                        .foregroundStyle(.secondary)
                }
                if let workspace {
                    ResourceTableView(
                        resources: preprocessConfig.files,
                        filterKinds: rasterKinds,
                        activeKinds: $rasterActiveKinds,
                        sortKey: $rasterSortKey,
                        sortAscending: $rasterSortAscending,
                        selection: $rasterSelection,
                        onAdd: { showingRasterPicker = true },
                        onDeleteSelected: { ids in
                            for id in ids {
                                configuration.preprocessConfig?.files.removeAll { $0.id == id }
                            }
                            configuration.touch()
                            rasterSelection.removeAll()
                        }
                    )
                    .sheet(isPresented: $showingRasterPicker) {
                        ResourcePickerView(
                            workspace: workspace,
                            defaultKinds: [.sourceRaster],
                            selectableKinds: [.sourceRaster],
                            selection: Binding(
                                get: { configuration.preprocessConfig?.files ?? [] },
                                set: { configuration.preprocessConfig?.files = $0; configuration.touch() }
                            ),
                            allowsMultiple: true,
                            defaultSortKey: .date,
                            defaultSortAscending: false
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var outputsSection: some View {
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

    @ViewBuilder
    private var runButton: some View {
        if let runner = activeRunner, runner.isRunning {
            Button("Cancel", role: .destructive) {
                runner.cancel()
            }
        } else {
            Button("Run Preprocessing") {
                let runner = ToolPreprocess()
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
                        print("Error running preprocessing: \(error)")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                configuration.preprocessConfig?.files.isEmpty != false ||
                configuration.preprocessConfig?.shapeFile == nil
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
