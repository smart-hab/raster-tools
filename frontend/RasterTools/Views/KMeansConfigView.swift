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
                    } else {
                        HStack {
                            ResourceFilterBar(kinds: inputKinds, activeKinds: $fitActiveKinds)
                            Spacer()
                            OutputSortBar(sortKey: $fitSortKey, ascending: $fitSortAscending)
                        }
                        let filtered = kmeansConfig.filesFit.filter { fitActiveKinds.contains($0.kind) }
                        let groups = groupedOutputs(filtered, sortKey: fitSortKey, ascending: fitSortAscending)
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
                                    isSelected: fitSelection.contains(resource.id)
                                )
                                .onTapGesture {
                                    if fitSelection.contains(resource.id) {
                                        fitSelection.remove(resource.id)
                                    } else {
                                        fitSelection.insert(resource.id)
                                    }
                                }
                            }
                        }
                    }
                    if let workspace {
                        let visibleFitIDs = Set(kmeansConfig.filesFit.filter { fitActiveKinds.contains($0.kind) }.map(\.id))
                        let fitSelectionBytes = kmeansConfig.filesFit.filter { fitSelection.contains($0.id) }.reduce(0) { $0 + $1.fileSize }
                        HStack {
                            Button { showingFitPicker = true } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.plain)
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
                            Spacer()
                            Text(selectionLabel(fitSelection.count, bytes: fitSelectionBytes))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                for id in fitSelection {
                                    configuration.kmeansConfig?.filesFit.removeAll { $0.id == id }
                                    configuration.touch()
                                }
                                fitSelection.removeAll()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .disabled(fitSelection.isEmpty)
                            Button {
                                if visibleFitIDs.isSubset(of: fitSelection) {
                                    fitSelection.subtract(visibleFitIDs)
                                } else {
                                    fitSelection.formUnion(visibleFitIDs)
                                }
                            } label: {
                                Image(systemName: visibleFitIDs.isSubset(of: fitSelection) ? "minus.circle" : "checkmark.circle")
                            }
                            .buttonStyle(.plain)
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
                        HStack {
                            ResourceFilterBar(kinds: inputKinds, activeKinds: $classifyActiveKinds)
                            Spacer()
                            OutputSortBar(sortKey: $classifySortKey, ascending: $classifySortAscending)
                        }
                        let filtered = kmeansConfig.filesClassify.filter { classifyActiveKinds.contains($0.kind) }
                        let groups = groupedOutputs(filtered, sortKey: classifySortKey, ascending: classifySortAscending)
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
                                    isSelected: classifySelection.contains(resource.id)
                                )
                                .onTapGesture {
                                    if classifySelection.contains(resource.id) {
                                        classifySelection.remove(resource.id)
                                    } else {
                                        classifySelection.insert(resource.id)
                                    }
                                }
                            }
                        }
                    }
                    if let workspace {
                        let visibleClassifyIDs = Set(kmeansConfig.filesClassify.filter { classifyActiveKinds.contains($0.kind) }.map(\.id))
                        let classifySelectionBytes = kmeansConfig.filesClassify.filter { classifySelection.contains($0.id) }.reduce(0) { $0 + $1.fileSize }
                        HStack {
                            Button { showingClassifyPicker = true } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.plain)
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
                            Spacer()
                            Text(selectionLabel(classifySelection.count, bytes: classifySelectionBytes))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                for id in classifySelection {
                                    configuration.kmeansConfig?.filesClassify.removeAll { $0.id == id }
                                    configuration.touch()
                                }
                                classifySelection.removeAll()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .disabled(classifySelection.isEmpty)
                            Button {
                                if visibleClassifyIDs.isSubset(of: classifySelection) {
                                    classifySelection.subtract(visibleClassifyIDs)
                                } else {
                                    classifySelection.formUnion(visibleClassifyIDs)
                                }
                            } label: {
                                Image(systemName: visibleClassifyIDs.isSubset(of: classifySelection) ? "minus.circle" : "checkmark.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Outputs produced by this configuration
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

    private func selectionLabel(_ count: Int, bytes: Int) -> String {
        guard count > 0, bytes > 0 else { return "\(count) selected" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return "\(count) selected (\(size))"
    }
}
