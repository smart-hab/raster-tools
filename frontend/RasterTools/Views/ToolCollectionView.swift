//
//  ToolCollectionView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-24.
//

import SwiftUI
import SwiftData

struct ToolCollectionView: View {
    @Bindable var configuration: ToolCollectionConfiguration

    @Environment(JobRegistry.self) private var registry
    @Environment(\.modelContext) private var modelContext

    @State private var showingShapePicker = false
    @State private var isSearching = false
    @State private var showingAddOrder = false
    @State private var orderMemorySelection: Set<String> = []
    @State private var pendingRemoval: [PlanetOrderRecord] = []

    @State private var searchError: String?
    @State private var sceneGroups: [PlanetSceneGroup] = []
    @State private var previewGroup: PlanetSceneGroup?

    private let planetCache = PlanetCache.shared
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
            orderMemorySection
        }
        .formStyle(.grouped)
        .navigationTitle(configuration.name)
        .sheet(item: $previewGroup) { group in
            SceneGroupPreviewSheet(group: group, apiKey: AppSettings.shared.planetApiKey)
        }
        .sheet(isPresented: $showingAddOrder) {
            AddOrderSheet(configuration: configuration)
        }
        .confirmationDialog(
            "Remove \(pendingRemoval.count == 1 ? "1 order" : "\(pendingRemoval.count) orders") from memory?",
            isPresented: Binding(get: { !pendingRemoval.isEmpty }, set: { if !$0 { pendingRemoval = [] } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { removeFromMemory(pendingRemoval) }
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
            Text("Search Results")
        }
    }

    // MARK: - Order Memory

    private var orderMemoryItems: [PlanetOrderRecord] {
        configuration.orderEntries.map { key, entry in
            if let orderId = entry.orderId, let record = planetCache.cache[orderId] {
                return record
            }
            let dateStr = key.components(separatedBy: "|").last ?? key
            let date = Date.utcFormatter.date(from: dateStr) ?? Date()
            let status = entry.orderId == nil ? OrderMemoryStatus.queued.rawValue : PlanetOrderStatus.unknown.rawValue
            let id = entry.orderId ?? key
            return PlanetOrderRecord(id: id, name: dateStr, date: date, status: status, createdAt: date)
        }
    }

    private var orderMemoryIds: [String] {
        configuration.orderEntries.values.compactMap(\.orderId)
    }

    @ViewBuilder
    private var orderMemorySection: some View {
        Section {
            ResourceTableView(
                items: orderMemoryItems,
                itemID: \.id,
                sortOptions: [
                    TableSortOption(
                        id: "date",
                        label: "Date",
                        comparator: { $0.date < $1.date },
                        groupLabel: { order in
                            let f = DateFormatter()
                            f.dateFormat = "yyyy"
                            return f.string(from: order.date)
                        }
                    ),
                    TableSortOption(
                        id: "status",
                        label: "Status",
                        comparator: { $0.status < $1.status },
                        groupLabel: { PlanetOrderStatus(rawValue: $0.status)?.displayName ?? $0.status.capitalized }
                    )
                ],
                filterOptions: PlanetOrderStatus.allCases.map { status in
                    TableFilterOption(
                        id: status.rawValue,
                        label: status.displayName,
                        color: status.color,
                        test: { $0.status == status.rawValue }
                    )
                },
                selectionActions: [
                    TableSelectionAction<PlanetOrderRecord>(
                        id: "download",
                        icon: "arrow.down.to.line.compact",
                        isEnabled: { selected in
                            selected.contains { $0.status == PlanetOrderStatus.success.rawValue }
                        },
                        action: { selected in
                            downloadAndUnzip(orders: selected)
                        }
                    ),
                    TableSelectionAction<PlanetOrderRecord>(
                        id: "remove",
                        icon: "trash",
                        isEnabled: { !$0.isEmpty },
                        action: { selected in
                            pendingRemoval = selected
                        }
                    )
                ],
                selection: $orderMemorySelection,
                onAdd: { showingAddOrder = true },
                initialSortOptionID: "date",
                initialSortAscending: false
            ) { order, isSelected in
                OrderMemoryRow(
                    order: order,
                    isSelected: isSelected,
                    countdown: OrderQueue.shared.countdown(for: configuration.orderMemoryKey(for: order.date)),
                    onCancel: { OrderQueue.shared.cancel(configuration: configuration, date: order.date) },
                    onFastForward: { OrderQueue.shared.fastForward(configuration: configuration, date: order.date) }
                )
            }
            .task(id: orderMemoryIds.sorted().joined()) {
                while !Task.isCancelled {
                    await withTaskGroup(of: Void.self) { group in
                        for id in orderMemoryIds {
                            group.addTask { await planetCache.getOrder(id) }
                        }
                    }
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        } header: {
            Text("Ordered Scenes")
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

    private func downloadAndUnzip(orders: [PlanetOrderRecord]) {
        let tool = ToolPlanetUnzip()
        registry.register(runner: tool, configName: configuration.name, projectName: project.name)
        tool.start(orders: orders, project: project, context: modelContext)
    }

    private func removeFromMemory(_ records: [PlanetOrderRecord]) {
        OrderQueue.shared.resetMemory(for: configuration, recordIds: Set(records.map(\.id)))
        orderMemorySelection = []
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

// MARK: - Order Memory Row

struct OrderMemoryRow: View {
    let order: PlanetOrderRecord
    var isSelected: Bool = false
    var isSelectionDisabled: Bool = false
    var countdown: Int? = nil
    var onCancel: (() -> Void)? = nil
    var onFastForward: (() -> Void)? = nil

    private var status: PlanetOrderStatus {
        PlanetOrderStatus(rawValue: order.status) ?? .unknown
    }

    private var isLocallyQueued: Bool {
        status == .queued && onCancel != nil
    }

    private var statusLabel: String {
        if isLocallyQueued, let secs = countdown {
            let m = secs / 60
            let s = secs % 60
            return String(format: "queued %d:%02d", m, s)
        }
        return status.displayName
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(order.date.displayString)
                    .fontWeight(.medium)
                Text(order.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            BadgeCapsule(label: statusLabel, color: status.color)

            if isLocallyQueued {
                Button(action: { onFastForward?() }) {
                    Image(systemName: "forward.end")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled((countdown ?? 0) <= 5)
                Button(action: { onCancel?() }) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        isSelectionDisabled
                            ? Color.secondary.opacity(0.4)
                            : (isSelected ? Color.accentColor : Color.secondary)
                    )
                    .frame(width: 16)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Add Order Sheet

struct AddOrderSheet: View {
    let configuration: ToolCollectionConfiguration
    @Environment(\.dismiss) private var dismiss

    @State private var orders: [PlanetOrderRecord] = []
    @State private var selection: Set<String> = []
    @State private var isLoading = false
    @State private var error: String?

    private var memorizedOrderIds: Set<String> {
        Set(configuration.orderEntries.values.compactMap(\.orderId))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error {
                ContentUnavailableView(
                    "Could Not Load Orders",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ResourceTableView(
                    items: orders,
                    itemID: \.id,
                    sortOptions: [
                        TableSortOption(
                            id: "date",
                            label: "Date",
                            comparator: { $0.date < $1.date },
                            groupLabel: { order in
                                let f = DateFormatter()
                                f.dateFormat = "yyyy"
                                return f.string(from: order.date)
                            }
                        ),
                        TableSortOption(
                            id: "status",
                            label: "Status",
                            comparator: { $0.status < $1.status },
                            groupLabel: { PlanetOrderStatus(rawValue: $0.status)?.displayName ?? $0.status.capitalized }
                        )
                    ],
                    filterOptions: PlanetOrderStatus.allCases.map { status in
                        TableFilterOption(
                            id: status.rawValue,
                            label: status.displayName,
                            color: status.color,
                            test: { $0.status == status.rawValue }
                        )
                    },
                    selection: $selection,
                    disableSelection: { memorizedOrderIds.contains($0.id) },
                    initialSortOptionID: "date",
                    initialSortAscending: false
                ) { order, isSelected in
                    OrderMemoryRow(order: order, isSelected: isSelected, isSelectionDisabled: memorizedOrderIds.contains(order.id))
                }
                .padding()
            }

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                let newCount = selection.subtracting(memorizedOrderIds).count
                Button(newCount > 0 ? "Add \(newCount) to Memory" : "Add to Memory") {
                    addToMemory()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selection.subtracting(memorizedOrderIds).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 800, minHeight: 550)
        .task { await fetchOrders() }
    }

    private func fetchOrders() async {
        isLoading = true
        error = nil
        do {
            let fetched = try await PlanetAPI.listOrders(apiKey: AppSettings.shared.planetApiKey)
            orders = fetched
            selection = memorizedOrderIds.intersection(fetched.map(\.id))
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func addToMemory() {
        let newIds = selection.subtracting(memorizedOrderIds)
        let orderById = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })
        for id in newIds {
            guard let order = orderById[id] else { continue }
            let key = configuration.orderMemoryKey(for: order.date)
            configuration.orderEntries[key] = OrderMemoryEntry(status: .ordered, orderId: order.id)
        }
        configuration.touch()
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

