//
//  PreprocessConfigView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData

struct PreprocessConfigView: View {
    @Bindable var configuration: ToolConfiguration
    @Environment(\.modelContext) private var modelContext
    @Environment(JobRegistry.self) private var registry
    @State private var activeRunner: PreprocessRunner?
    @State private var showingShapePicker = false
    @State private var showingRasterPicker = false
    @State private var rasterSortKey: OutputSortKey = .date
    @State private var rasterSortAscending: Bool = false
    @State private var outputSortKey: OutputSortKey = .date
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
            if configuration.preprocessConfig != nil {
                Text("Select which indices to calculate")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(PreprocessType.allCases, id: \.self) { processType in
                    Toggle(processType.rawValue, isOn: Binding(
                        get: {
                            configuration.preprocessConfig?.processTypes.contains(processType) ?? false
                        },
                        set: { isSelected in
                            guard var types = configuration.preprocessConfig?.processTypes else { return }
                            if isSelected {
                                if !types.contains(processType) { types.append(processType) }
                            } else {
                                types.removeAll { $0 == processType }
                            }
                            configuration.preprocessConfig?.processTypes = types
                            configuration.touch()
                        }
                    ))
                    .toggleStyle(.checkmark)
                }
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
                    ResourceSectionContent(
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
                        rasterPickerSheet(workspace: workspace)
                    }
                }
            }
        }
    }

    private func rasterPickerSheet(workspace: Workspace) -> some View {
        ResourcePickerView(
            workspace: workspace,
            defaultKinds: [.sourceRaster],
            selectableKinds: [.sourceRaster],
            selection: Binding(
                get: { configuration.preprocessConfig?.files ?? [] },
                set: { configuration.preprocessConfig?.files = $0; configuration.touch() }
            ),
            allowsMultiple: true
        )
    }

    @ViewBuilder
    private var outputsSection: some View {
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

    @ViewBuilder
    private var runButton: some View {
        if let runner = activeRunner, runner.isRunning {
            Button("Cancel", role: .destructive) {
                runner.cancel()
            }
        } else {
            Button("Run Preprocessing") {
                let runner = PreprocessRunner()
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
