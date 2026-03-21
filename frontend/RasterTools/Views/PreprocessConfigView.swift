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
            if let workspace {
                LabeledContent("Output Dir") {
                    Button {
                        NSWorkspace.shared.open(AppStorage.outputDirectory(for: workspace))
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
                } else {
                    HStack {
                        ResourceFilterBar(kinds: rasterKinds, activeKinds: $rasterActiveKinds)
                        Spacer()
                        OutputSortBar(sortKey: $rasterSortKey, ascending: $rasterSortAscending)
                    }
                    let filteredRasters = preprocessConfig.files.filter { rasterActiveKinds.contains($0.kind) }
                    let groups = groupedOutputs(filteredRasters, sortKey: rasterSortKey, ascending: rasterSortAscending)
                    ForEach(groups, id: \.groupLabel) { group in
                        if let label = group.groupLabel, group.resources.count > 1 {
                            Text(label).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(group.resources, id: \.id) { resource in
                            ResourceTableRow(
                                icon: resource.kind.iconName,
                                label: resource.displayLabel,
                                fileSize: resource.formattedFileSize,
                                badges: resource.tableBadges,
                                isSelected: rasterSelection.contains(resource.id)
                            )
                            .onTapGesture {
                                if rasterSelection.contains(resource.id) {
                                    rasterSelection.remove(resource.id)
                                } else {
                                    rasterSelection.insert(resource.id)
                                }
                            }
                        }
                    }
                }
                if let workspace {
                    let visibleRasterIDs = Set(preprocessConfig.files.filter { rasterActiveKinds.contains($0.kind) }.map(\.id))
                    let rasterSelectionBytes = preprocessConfig.files.filter { rasterSelection.contains($0.id) }.reduce(0) { $0 + $1.fileSize }
                    HStack {
                        Button { showingRasterPicker = true } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showingRasterPicker) {
                            rasterPickerSheet(workspace: workspace)
                        }
                        Spacer()
                        Text(selectionLabel(rasterSelection.count, bytes: rasterSelectionBytes))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            let files = preprocessConfig.files
                            for id in rasterSelection {
                                if let resource = files.first(where: { $0.id == id }) {
                                    configuration.preprocessConfig?.files.removeAll { $0.id == resource.id }
                                    configuration.touch()
                                }
                            }
                            rasterSelection.removeAll()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .disabled(rasterSelection.isEmpty)
                        Button {
                            if visibleRasterIDs.isSubset(of: rasterSelection) {
                                rasterSelection.subtract(visibleRasterIDs)
                            } else {
                                rasterSelection.formUnion(visibleRasterIDs)
                            }
                        } label: {
                            Image(systemName: visibleRasterIDs.isSubset(of: rasterSelection) ? "minus.circle" : "checkmark.circle")
                        }
                        .buttonStyle(.plain)
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
                HStack {
                    if outputKinds.count > 1 {
                        ResourceFilterBar(kinds: outputKinds, activeKinds: $outputActiveKinds)
                            .onAppear {
                                if outputActiveKinds.isEmpty { outputActiveKinds = Set(outputKinds) }
                            }
                            .onChange(of: outputKinds) { _, newKinds in
                                let newSet = Set(newKinds)
                                outputActiveKinds.formUnion(newSet.subtracting(outputActiveKinds))
                            }
                    }
                    Spacer()
                    OutputSortBar(sortKey: $outputSortKey, ascending: $outputSortAscending)
                }
                let activeOutputs = outputKinds.count > 1 ? outputs.filter { outputActiveKinds.contains($0.kind) } : outputs
                let groups = groupedOutputs(activeOutputs, sortKey: outputSortKey, ascending: outputSortAscending)
                ForEach(groups, id: \.groupLabel) { group in
                    if let label = group.groupLabel, group.resources.count > 1 {
                        Text(label)
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
                            isSelected: outputSelection.contains(resource.id)
                        )
                        .onTapGesture {
                            if outputSelection.contains(resource.id) {
                                outputSelection.remove(resource.id)
                            } else {
                                outputSelection.insert(resource.id)
                            }
                        }
                    }
                }
                let activeOutputIDs = Set(activeOutputs.map(\.id))
                let outputSelectionBytes = outputs.filter { outputSelection.contains($0.id) }.reduce(0) { $0 + $1.fileSize }
                HStack {
                    Spacer()
                    Text(selectionLabel(outputSelection.count, bytes: outputSelectionBytes))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        for id in outputSelection {
                            if let resource = outputs.first(where: { $0.id == id }) {
                                deleteOutputResource(resource, context: modelContext)
                            }
                        }
                        outputSelection.removeAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .disabled(outputSelection.isEmpty)
                    Button {
                        if activeOutputIDs.isSubset(of: outputSelection) {
                            outputSelection.subtract(activeOutputIDs)
                        } else {
                            outputSelection.formUnion(activeOutputIDs)
                        }
                    } label: {
                        Image(systemName: activeOutputIDs.isSubset(of: outputSelection) ? "minus.circle" : "checkmark.circle")
                    }
                    .buttonStyle(.plain)
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

    private func selectionLabel(_ count: Int, bytes: Int) -> String {
        guard count > 0, bytes > 0 else { return "\(count) selected" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return "\(count) selected (\(size))"
    }
}
