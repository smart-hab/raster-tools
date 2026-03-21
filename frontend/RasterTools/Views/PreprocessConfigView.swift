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
    @State private var runner = PreprocessRunner()
    @State private var showingShapePicker = false
    @State private var showingRasterPicker = false

    private var workspace: Workspace? { configuration.workspace }

    var body: some View {
        Form {
            configSection
            shapeFileSection
            processesSection
            rasterFilesSection
            outputsSection
            progressSection
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
                } else {
                    ForEach(preprocessConfig.files, id: \.id) { resource in
                        ResourceTableRow(
                            icon: resource.kind.iconName,
                            label: resource.displayLabel,
                            fileSize: resource.formattedFileSize,
                            badges: resource.tableBadges,
                            onDelete: {
                                configuration.preprocessConfig?.files.removeAll { $0.id == resource.id }
                                configuration.touch()
                            }
                        )
                    }
                }
                if let workspace {
                    Button("Add Files...") { showingRasterPicker = true }
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
    }

    @ViewBuilder
    private var progressSection: some View {
        if runner.isRunning || !runner.progress.logs.isEmpty {
            Section("Progress") {
                ToolProgressView(runner: runner)
            }
        }
    }

    @ViewBuilder
    private var runButton: some View {
        if runner.isRunning {
            Button("Cancel", role: .destructive) {
                runner.cancel()
            }
        } else {
            Button("Run Preprocessing") {
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
