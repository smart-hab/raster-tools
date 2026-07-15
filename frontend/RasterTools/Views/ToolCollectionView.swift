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
    @State private var searchDebounce: Task<Void, Never>?

    // AOI coverage is computed lazily off-main; cells show "… AOI" until filled.
    @State private var coverageByDay: [String: Double] = [:]
    @State private var coverageTask: Task<Void, Never>?

    private let planetCache = PlanetCache.shared
    private var project: Project { configuration.project }

    // The displayed month IS the search range: 1st → last day, inclusive.
    // All date math is UTC to stay consistent with PlanetSceneGroup.date and orderMemoryKey.

    private var yearBinding: Binding<Int> {
        Binding(
            get: { Date.utcCalendar.component(.year, from: configuration.searchStartDate) },
            set: { setMonth(year: $0, month: Date.utcCalendar.component(.month, from: configuration.searchStartDate)) }
        )
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { Date.utcCalendar.component(.month, from: configuration.searchStartDate) },
            set: { setMonth(year: Date.utcCalendar.component(.year, from: configuration.searchStartDate), month: $0) }
        )
    }

    private func setMonth(year: Int, month: Int) {
        let start = Date.utcCalendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let end = Date.utcCalendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        configuration.searchStartDate = start
        configuration.searchEndDate = end
        configuration.touch()
    }

    /// Scene groups keyed by UTC "yyyy-MM-dd" for fast per-cell lookup.
    private var groupsByDay: [String: PlanetSceneGroup] {
        Dictionary(sceneGroups.map { (Date.utcFormatter.string(from: $0.date), $0) },
                   uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        Form {
            configSection
            searchParamsSection
            // orderParamsSection  // hidden for now — read-only order params
            if let errorMsg = searchError {
                Section {
                    Label(errorMsg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            orderMemorySection
        }
        .formStyle(.grouped)
        .navigationTitle(configuration.name)
        .onChange(of: configuration.searchStartDate) { scheduleSearch() }
        .onChange(of: configuration.cloudCover) { scheduleSearch() }
        .onChange(of: configuration.shapeFile?.id) { scheduleSearch() }
        .task { scheduleSearch() }
        .sheet(item: $previewGroup) { group in
            SceneGroupPreviewSheet(
                group: group,
                apiKey: AppSettings.shared.planetApiKey,
                status: configuration.orderStatus(for: group.date),
                countdown: OrderQueue.shared.countdown(for: configuration.orderMemoryKey(for: group.date)),
                onQueue: { queueOrder(for: group) },
                onCancel: { cancelOrder(for: group) },
                onFastForward: { OrderQueue.shared.fastForward(configuration: configuration, date: group.date) }
            )
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
            // Output Dir is hidden for now. Collection tool unzips orders into the Project's Source Dir instead.
            /*
            LabeledContent("Output Dir") {
                Button {
                    NSWorkspace.shared.open(AppStorage.outputDirectory(for: project, configuration: configuration))
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
            }
            */
        }
    }

    // MARK: - Search Params

    @ViewBuilder
    private var searchParamsSection: some View {
        Section {
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
                    Slider(value: $configuration.cloudCover, in: 0...1, step: 0.05)
                        .frame(width: 120)
                    Text("\(Int(configuration.cloudCover * 100))%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }

            CalendarView(year: yearBinding, month: monthBinding) { date in
                dayCell(for: date)
            }
            .padding(.vertical, 8)
        } header: {
            HStack {
                Text("Search")
                if isSearching {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if configuration.shapeFile == nil {
                    Text("Select a shape file to search")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
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

    // MARK: - Day Cell

    @ViewBuilder
    private func dayCell(for date: Date) -> some View {
        let day = Date.utcCalendar.component(.day, from: date)
        let group = groupsByDay[Date.utcFormatter.string(from: date)]
        let status = configuration.orderStatus(for: date)
        let tint = dayStatusColor(status)

        Button {
            if let group { previewGroup = group }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(day)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(group == nil ? .secondary : .primary)
                if let group {
                    Text("\(group.scenes.count) scene\(group.scenes.count == 1 ? "" : "s")")
                        .font(.caption2)
                    Text("\(Int(group.averageCloudCover * 100))% cloud")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let cov = coverageByDay[Date.utcFormatter.string(from: date)] {
                        Text("\(Int(cov.rounded()))% AOI")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("… AOI")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(group == nil ? Color.clear : tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(group == nil ? Color.secondary.opacity(0.15) : tint.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
        .disabled(group == nil)
    }

    private func dayStatusColor(_ status: OrderMemoryStatus?) -> Color {
        switch status {
        case .queued:  return .orange
        case .ordered: return .green
        case nil:      return .secondary
        }
    }

    // MARK: - Order Params

    // Order Parameters are hidden for now (read-only). Restore when editable.
    /*
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
    */

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
                            group.addTask {
                                // populate the cache
                                let _ = await planetCache.getOrder(id)
                            }
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

    /// Debounced search trigger. Coalesces rapid input changes (slider drags,
    /// month navigation) into a single request. No shape file → clear results
    /// without hitting the API; the calendar still renders.
    private func scheduleSearch() {
        searchDebounce?.cancel()

        guard configuration.shapeFile?.originalPath != nil else {
            sceneGroups = []
            searchError = nil
            isSearching = false
            return
        }

        searchDebounce = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            await runSearchAsync()
        }
    }

    private func runSearchAsync() async {
        guard let shapePath = configuration.shapeFile?.originalPath else { return }
        isSearching = true
        searchError = nil
        coverageTask?.cancel()
        coverageByDay = [:]

        let startDate = configuration.searchStartDate
        let endDate = configuration.searchEndDate
        let cloudCover = configuration.cloudCover
        let apiKey = AppSettings.shared.planetApiKey

        do {
            let geometry = try loadShapeFileGeometry(from: shapePath)
            let groups = try await PlanetAPI.quickSearch(
                geometry: geometry,
                startDate: startDate,
                endDate: endDate,
                cloudCover: cloudCover,
                apiKey: apiKey
            )
            if Task.isCancelled { return }
            sceneGroups = groups
            isSearching = false
            searchError = groups.isEmpty ? "No scenes found for the given parameters." : nil
            computeCoverage(for: groups, aoiRing: PlanetAPI.aoiRing(from: geometry))
        } catch {
            if Task.isCancelled { return }
            searchError = error.localizedDescription
            isSearching = false
        }
    }

    /// Computes AOI coverage per day off the main actor, publishing each result
    /// as it lands so cells swap "… AOI" for the real value incrementally.
    private func computeCoverage(for groups: [PlanetSceneGroup], aoiRing: [(lon: Double, lat: Double)]) {
        coverageTask?.cancel()
        guard !aoiRing.isEmpty else { return }
        coverageTask = Task {
            for group in groups {
                if Task.isCancelled { return }
                let key = Date.utcFormatter.string(from: group.date)
                let pct = await Task.detached(priority: .utility) {
                    PlanetAPI.coveragePercent(aoiRing: aoiRing, group: group)
                }.value
                if Task.isCancelled { return }
                if let pct { coverageByDay[key] = pct }
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
                    var subtitle = "\(group.scenes.count) scene\(group.scenes.count == 1 ? "" : "s") · \(Int(group.averageCloudCover * 100))% avg cloud"
                    if let cov = group.coveragePercent {
                        subtitle += " · \(Int(cov.rounded()))% AOI coverage"
                    }
                    return Text(subtitle)
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
    var status: OrderMemoryStatus? = nil
    var countdown: Int? = nil
    var onQueue: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var onFastForward: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @FocusState private var doneFocused: Bool

    private var statusLabel: String {
        if status == .queued, let secs = countdown {
            return String(format: "queued %d:%02d", secs / 60, secs % 60)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(group.date.displayString)
                    .font(.headline)
                Text("· \(group.scenes.count) scene\(group.scenes.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)

                BadgeCapsule(label: statusLabel, color: statusColor(status))

                switch status {
                case nil:
                    if let onQueue {
                        Button(action: onQueue) {
                            Image(systemName: "square.and.arrow.down.badge.clock")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .focusable(false)
                    }
                case .queued:
                    if let onFastForward {
                        Button(action: onFastForward) {
                            Image(systemName: "forward.end")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled((countdown ?? 0) <= 5)
                        .focusable(false)
                    }
                    if let onCancel {
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .focusable(false)
                    }
                case .ordered:
                    EmptyView()
                }

                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .focused($doneFocused)
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
        .onAppear { doneFocused = true }
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

