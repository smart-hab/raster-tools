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
                            NSWorkspace.shared.open(AppStorage.outputDirectory(for: workspace))
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)
                    }
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
                        HStack {
                            Button("Add Files...") { showingFitPicker = true }
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
                            Button(visibleFitIDs.isSubset(of: fitSelection) ? "Select None" : "Select All") {
                                if visibleFitIDs.isSubset(of: fitSelection) {
                                    fitSelection.subtract(visibleFitIDs)
                                } else {
                                    fitSelection.formUnion(visibleFitIDs)
                                }
                            }
                            Button("Delete") {
                                for id in fitSelection {
                                    configuration.kmeansConfig?.filesFit.removeAll { $0.id == id }
                                    configuration.touch()
                                }
                                fitSelection.removeAll()
                            }
                            .disabled(fitSelection.isEmpty)
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
                        HStack {
                            Button("Add Files...") { showingClassifyPicker = true }
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
                            Button(visibleClassifyIDs.isSubset(of: classifySelection) ? "Select None" : "Select All") {
                                if visibleClassifyIDs.isSubset(of: classifySelection) {
                                    classifySelection.subtract(visibleClassifyIDs)
                                } else {
                                    classifySelection.formUnion(visibleClassifyIDs)
                                }
                            }
                            Button("Delete") {
                                for id in classifySelection {
                                    configuration.kmeansConfig?.filesClassify.removeAll { $0.id == id }
                                    configuration.touch()
                                }
                                classifySelection.removeAll()
                            }
                            .disabled(classifySelection.isEmpty)
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
                    HStack {
                        Spacer()
                        Button(activeOutputIDs.isSubset(of: outputSelection) ? "Select None" : "Select All") {
                            if activeOutputIDs.isSubset(of: outputSelection) {
                                outputSelection.subtract(activeOutputIDs)
                            } else {
                                outputSelection.formUnion(activeOutputIDs)
                            }
                        }
                        Button("Delete") {
                            for id in outputSelection {
                                if let resource = outputs.first(where: { $0.id == id }) {
                                    deleteOutputResource(resource, context: modelContext)
                                }
                            }
                            outputSelection.removeAll()
                        }
                        .disabled(outputSelection.isEmpty)
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
