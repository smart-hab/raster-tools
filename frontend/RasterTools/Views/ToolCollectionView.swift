//
//  ToolCollectionView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-24.
//

import SwiftUI

struct ToolCollectionView: View {
    @Bindable var configuration: ToolConfiguration
    @Environment(JobRegistry.self) private var registry

    @State private var showingShapePicker = false
    @State private var isSearching = false

    @State private var searchError: String?
    @State private var sceneGroups: [PlanetSceneGroup] = []

    private var workspace: Workspace? { configuration.workspace }
    private var config: CollectionConfiguration? { configuration.collectionConfig }

    var body: some View {
        Form {
            configSection
            searchParamsSection
            orderParamsSection
            if let errorMsg = searchError {
                Section {
                    Label(errorMsg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            if !sceneGroups.isEmpty {
                searchResultsSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle(configuration.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    runSearch()
                } label: {
                    if isSearching {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Searching…")
                        }
                    } else {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSearching || config?.shapeFile == nil)
            }
        }
    }

    // MARK: - Config Section

    @ViewBuilder
    private var configSection: some View {
        Section("Configuration") {
            LabeledContent("Name") {
                Text(configuration.name)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Workspace") {
                if let path = workspace?.sourceDirectory {
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text(path)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Search Params

    @ViewBuilder
    private var searchParamsSection: some View {
        Section("Search Parameters") {
            if let workspace, let config {
                HStack(alignment: .top, spacing: 16) {
                    // Calendars
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 2) {
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { config.searchStartDate },
                                    set: { configuration.collectionConfig?.searchStartDate = $0; configuration.touch() }
                                ),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.graphical)
                            Text("Start")
                        }
                        VStack(spacing: 2) {
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { config.searchEndDate },
                                    set: { configuration.collectionConfig?.searchEndDate = $0; configuration.touch() }
                                ),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.graphical)
                            Text("End")
                        }
                    }

                    // Controls
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Shape File") {
                            if let selected = config.shapeFile {
                                Button { showingShapePicker = true } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: ResourceKind.shapeFile.iconName)
                                        Text(selected.filename)
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button("Select…") { showingShapePicker = true }
                                    .buttonStyle(.plain)
                            }
                        }

                        LabeledContent("Cloud Cover") {
                            HStack {
                                Slider(
                                    value: Binding(
                                        get: { config.cloudCover },
                                        set: { configuration.collectionConfig?.cloudCover = $0; configuration.touch() }
                                    ),
                                    in: 0...1,
                                    step: 0.05
                                )
                                .frame(width: 120)
                                Text("\(Int(config.cloudCover * 100))%")
                                    .monospacedDigit()
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sheet(isPresented: $showingShapePicker) {
                        ResourcePickerView(
                            workspace: workspace,
                            defaultKinds: [.shapeFile],
                            selectableKinds: [.shapeFile],
                            selection: Binding(
                                get: {
                                    if let sf = configuration.collectionConfig?.shapeFile { return [sf] }
                                    return []
                                },
                                set: { resources in
                                    configuration.collectionConfig?.shapeFile = resources.first
                                    configuration.touch()
                                }
                            ),
                            selectionMode: .single
                        )
                    }
                }
            }
        }
    }

    // MARK: - Order Params

    @ViewBuilder
    private var orderParamsSection: some View {
        Section("Order Parameters") {
            if let config {
                TextField(
                    "Naming Pattern",
                    text: Binding(
                        get: { config.namingPattern },
                        set: { configuration.collectionConfig?.namingPattern = $0; configuration.touch() }
                    )
                )

                Picker(
                    "Item Type",
                    selection: Binding(
                        get: { config.itemType },
                        set: { configuration.collectionConfig?.itemType = $0; configuration.touch() }
                    )
                ) {
                    ForEach(PlanetItemType.allCases, id: \.rawValue) { t in
                        Text(t.rawValue).tag(t.rawValue)
                    }
                }

                Picker(
                    "Product Bundle",
                    selection: Binding(
                        get: { config.productBundle },
                        set: { configuration.collectionConfig?.productBundle = $0; configuration.touch() }
                    )
                ) {
                    ForEach(PlanetProductBundle.allCases, id: \.rawValue) { b in
                        Text(b.rawValue).tag(b.rawValue)
                    }
                }

                LabeledContent("Harmonized") {
                    Toggle("", isOn: .constant(true))
                        .disabled(true)
                        .labelsHidden()
                }

                LabeledContent("Composite") {
                    Toggle("", isOn: .constant(true))
                        .disabled(true)
                        .labelsHidden()
                }

                Text("Tokens: {Workspace} {ConfigName} {Year} {Month} {Day} {Parameters}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Search Results

    private var sceneGroupFilterOptions: [TableFilterOption<PlanetSceneGroup>] {
        guard let config else { return [] }
        return [
            TableFilterOption(id: "available", label: "Available", color: .secondary,
                test: { config.orderStatus(for: $0.date) == nil }),
            TableFilterOption(id: "queued",    label: "Queued",    color: .orange,
                test: { config.orderStatus(for: $0.date) == .queued }),
            TableFilterOption(id: "ordered",   label: "Ordered",   color: .green,
                test: { config.orderStatus(for: $0.date) == .ordered }),
        ]
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        Section {
            ResourceTableView(
                items: sceneGroups,
                itemID: \.date,
                sortOptions: TableSortOption<PlanetSceneGroup>.allCases,
                filterOptions: sceneGroupFilterOptions,
                initialSortOptionID: "date",
                initialSortAscending: false
            ) { group, _ in
                SceneGroupRow(group: group, status: config?.orderStatus(for: group.date)) {
                    queueOrder(for: group)
                }
            }
        } header: {
            HStack {
                Text("Search Results (\(sceneGroups.count) days)")
                Spacer()
                Button("Reset Memory") {
                    guard let config = configuration.collectionConfig else { return }
                    var rebuilt: [String: String] = [:]
                    for job in registry.jobs {
                        if let runner = job.runner as? ToolCollection, runner.isRunning {
                            let key = config.orderMemoryKey(for: runner.date)
                            rebuilt[key] = OrderMemoryStatus.queued.rawValue
                        }
                    }
                    config.orderMemory = rebuilt
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func runSearch() {
        guard let config, let shapePath = config.shapeFile?.originalPath else { return }
        isSearching = true
        searchError = nil
        sceneGroups = []

        let startDate = config.searchStartDate
        let endDate = config.searchEndDate
        let cloudCover = config.cloudCover
        let apiKey = AppSettings.shared.planetApiKey

        Task {
            do {
                let geometry = try loadShapeFileGeometry(from: shapePath)
                let groups = try await PlanetAPI.quickSearch(
                    geometry: geometry,
                    startDate: startDate,
                    endDate: endDate,
                    cloudCover: cloudCover,
                    apiKey: apiKey
                )
                await MainActor.run {
                    sceneGroups = groups
                    isSearching = false
                    if groups.isEmpty {
                        searchError = "No scenes found for the given parameters."
                    }
                }
            } catch {
                await MainActor.run {
                    searchError = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    private func queueOrder(for group: PlanetSceneGroup) {
        guard let config else { return }
        let wsName = workspace?.name ?? ""
        let configName = configuration.name
        let runner = ToolCollection(date: group.date, configuration: config, workspaceName: wsName)
        let dateLabel = group.date.displayString
        registry.register(runner: runner, configName: "\(configName) / \(dateLabel)", workspaceName: wsName)
        runner.startCollection(configName: configName, sceneGroup: group)
    }
}

// MARK: - Scene Group Row

private struct SceneGroupRow: View {
    let group: PlanetSceneGroup
    var status: OrderMemoryStatus? = nil
    let onQueue: () -> Void

    private func statusColor(_ status: OrderMemoryStatus?) -> Color {
        switch status {
        case .queued:  return .orange
        case .ordered: return .green
        case nil:      return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.date.displayString)
                    .fontWeight(.medium)
                Text("\(group.scenes.count) scene\(group.scenes.count == 1 ? "" : "s") · \(Int(group.averageCloudCover * 100))% avg cloud cover")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(status?.rawValue ?? "available")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor(status).opacity(0.15))
                .foregroundStyle(statusColor(status))
                .clipShape(Capsule())
            Button(action: onQueue) {
                Image(systemName: "square.and.arrow.down.badge.clock")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(status != nil)
            .opacity(status != nil ? 0.35 : 1.0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - PlanetSceneGroup Sort Options

extension TableSortOption where T == PlanetSceneGroup {
    static var date: Self {
        TableSortOption(id: "date", label: "Date", comparator: { $0.date < $1.date })
    }
    static var cloud: Self {
        TableSortOption(id: "cloud", label: "Cloud", comparator: { $0.averageCloudCover < $1.averageCloudCover })
    }
    static var scenes: Self {
        TableSortOption(id: "scenes", label: "Scenes", comparator: { $0.scenes.count < $1.scenes.count })
    }
    static var allCases: [Self] { [.date, .cloud, .scenes] }
}

