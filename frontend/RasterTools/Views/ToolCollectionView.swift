//
//  ToolCollectionView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-24.
//

import SwiftUI

struct ToolCollectionView: View {
    @Bindable var configuration: ToolCollectionConfiguration

    @State private var showingShapePicker = false
    @State private var isSearching = false

    @State private var searchError: String?
    @State private var sceneGroups: [PlanetSceneGroup] = []
    @State private var previewGroup: PlanetSceneGroup?

    private var project: Project { configuration.project }

    // Source of truth: dates are always midnight UTC.
    // The DatePicker renders in local time, so we translate to/from local midnight.

    private static let localCalendar = Calendar(identifier: .gregorian) // device timezone

    // Translate UTC midnight ↔ local midnight so the calendar highlights the right day.
    private func pickerBinding(for keyPath: ReferenceWritableKeyPath<ToolCollectionConfiguration, Date>) -> Binding<Date> {
        Binding(
            get: {
                let ymd = Date.utcCalendar.dateComponents([.year, .month, .day], from: self.configuration[keyPath: keyPath])
                return Self.localCalendar.date(from: ymd)!
            },
            set: { localDate in
                let ymd = Self.localCalendar.dateComponents([.year, .month, .day], from: localDate)
                self.configuration[keyPath: keyPath] = Date.utcCalendar.date(from: ymd)!
            }
        )
    }

    private func textBinding(for keyPath: ReferenceWritableKeyPath<ToolCollectionConfiguration, Date>) -> Binding<String> {
        Binding(
            get: { Date.utcFormatter.string(from: self.configuration[keyPath: keyPath]) },
            set: { if let d = Date.utcFormatter.date(from: $0) { self.configuration[keyPath: keyPath] = d } }
        )
    }

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
        .sheet(item: $previewGroup) { group in
            SceneGroupPreviewSheet(group: group, apiKey: AppSettings.shared.planetApiKey)
        }
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
                .disabled(isSearching || configuration.shapeFile == nil)
            }
        }
    }

    // MARK: - Config Section

    @ViewBuilder
    private var configSection: some View {
        Section("Collection Configuration") {
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
    }

    // MARK: - Search Params

    @ViewBuilder
    private var searchParamsSection: some View {
        Section("Search Parameters") {
            HStack(alignment: .top, spacing: 16) {
                    // Calendars
                    HStack(alignment: .top, spacing: 12) {
                        VStack {
                            DatePicker(
                                "",
                                selection: pickerBinding(for: \.searchStartDate),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.graphical)
                            Text("Start")
                        }
                        VStack {
                            DatePicker(
                                "",
                                selection: pickerBinding(for: \.searchEndDate),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.graphical)
                            Text("End")
                        }
                    }

                    // Controls
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Start", text: textBinding(for: \.searchStartDate))
                            .textFieldStyle(.roundedBorder)
                            // .frame(width: 110)

                        TextField("End", text: textBinding(for: \.searchEndDate))
                            .textFieldStyle(.roundedBorder)
                            // .frame(width: 110)

                        LabeledContent("Shape File") {
                            if let selected = configuration.shapeFile {
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
                                    value: $configuration.cloudCover,
                                    in: 0...1,
                                    step: 0.05
                                )
                                .frame(width: 120)
                                Text("\(Int(configuration.cloudCover * 100))%")
                                    .monospacedDigit()
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sheet(isPresented: $showingShapePicker) {
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
                }
        }
    }

    // MARK: - Order Params

    @ViewBuilder
    private var orderParamsSection: some View {
        Section("Order Parameters") {
            TextField(
                "Naming Pattern",
                text: $configuration.namingPattern
            )
            .textFieldStyle(.roundedBorder)

            Picker(
                "Item Type",
                selection: $configuration.itemType
            ) {
                ForEach(PlanetItemType.allCases, id: \.rawValue) { t in
                    Text(t.rawValue).tag(t.rawValue)
                }
            }

            Picker(
                "Product Bundle",
                selection: $configuration.productBundle
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

            Text("Tokens: {Project} {ConfigName} {Year} {Month} {Day} {Parameters}")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Search Results

    private var sceneGroupFilterOptions: [TableFilterOption<PlanetSceneGroup>] {
        return [
            TableFilterOption(id: "available", label: "Available", color: .secondary,
                test: { self.configuration.orderStatus(for: $0.date) == nil }),
            TableFilterOption(id: "queued",    label: "Queued",    color: .orange,
                test: { self.configuration.orderStatus(for: $0.date) == .queued }),
            TableFilterOption(id: "ordered",   label: "Ordered",   color: .green,
                test: { self.configuration.orderStatus(for: $0.date) == .ordered }),
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
                SceneGroupRow(
                    group: group,
                    status: configuration.orderStatus(for: group.date),
                    countdown: OrderQueue.shared.countdown(for: configuration.orderMemoryKey(for: group.date))
                ) {
                    queueOrder(for: group)
                } onCancel: {
                    cancelOrder(for: group)
                } onFastForward: {
                    OrderQueue.shared.fastForward(configuration: configuration, date: group.date)
                } onPreview: {
                    previewGroup = group
                }
            }
        } header: {
            HStack {
                Text("Search Results (\(sceneGroups.count) days)")
                Spacer()
                Button("Reset Memory") {
                    OrderQueue.shared.resetMemory(for: configuration)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func runSearch() {
        guard let shapePath = configuration.shapeFile?.originalPath else { return }
        isSearching = true
        searchError = nil
        sceneGroups = []

        let startDate = configuration.searchStartDate
        let endDate = configuration.searchEndDate
        let cloudCover = configuration.cloudCover
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
        OrderQueue.shared.queue(configuration: configuration, sceneGroup: group)
    }

    private func cancelOrder(for group: PlanetSceneGroup) {
        OrderQueue.shared.cancel(configuration: configuration, date: group.date)
    }
}

// MARK: - Scene Group Row

private struct SceneGroupRow: View {
    let group: PlanetSceneGroup
    var status: OrderMemoryStatus? = nil
    var countdown: Int? = nil
    let onQueue: () -> Void
    let onCancel: () -> Void
    let onFastForward: () -> Void
    let onPreview: () -> Void

    private var statusLabel: String {
        if status == .queued, let secs = countdown {
            let m = secs / 60
            let s = secs % 60
            return String(format: "queued %d:%02d", m, s)
        }
        return status?.rawValue ?? "available"
    }

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
                Button(action: onPreview) {
                    Text("\(group.scenes.count) scene\(group.scenes.count == 1 ? "" : "s") · \(Int(group.averageCloudCover * 100))% avg cloud cover")
                        .font(.caption)
                        .underline()
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(statusLabel)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor(status).opacity(0.15))
                .foregroundStyle(statusColor(status))
                .clipShape(Capsule())
            switch status {
            case nil:
                Button(action: onQueue) {
                    Image(systemName: "square.and.arrow.down.badge.clock")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            case .queued:
                Button(action: onFastForward) {
                    Image(systemName: "forward.end")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled((countdown ?? 0) <= 5)
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            case .ordered:
                EmptyView()
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Scene Group Preview Sheet

private struct SceneGroupPreviewSheet: View {
    let group: PlanetSceneGroup
    let apiKey: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(group.date.displayString)
                    .font(.headline)
                Text("· \(group.scenes.count) scene\(group.scenes.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                    ForEach(group.scenes) { scene in
                        SceneThumbnailView(scene: scene, apiKey: apiKey)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 520, minHeight: 400)
    }
}

private struct SceneThumbnailView: View {
    let scene: PlanetScene
    let apiKey: String

    var body: some View {
        VStack(alignment: .leading) {
            RemoteImageView {
                guard let url = scene.thumbnailURL else { throw PlanetAPIError.decodingError("No thumbnail URL") }
                return try await PlanetAPI.fetchThumbnail(url: url, apiKey: apiKey)
            }
            .aspectRatio(1, contentMode: .fit)

            Text(scene.id)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(Int(scene.cloudCover * 100))% cloud cover")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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

