//
//  ToolSentinel2View.swift
//  RasterTools
//
//  Created by Marek on 2026-09-02.
//

import SwiftUI
import SwiftData

/// The Sentinel-2 collector, deliberately laid out like `ToolCollectionPlanetView`: the same
/// config → search → calendar → memory table flow.
///
/// It is shorter because CDSE has no ordering step. There is no countdown, no order id, and no
/// remote status to poll — picking a day downloads it.
struct ToolSentinel2View: View {
    @Bindable var configuration: ToolSentinel2Configuration

    @Environment(JobRegistry.self) private var registry
    @Environment(\.modelContext) private var modelContext

    @State private var showingShapePicker = false
    @State private var isSearching = false
    @State private var downloadSelection: Set<String> = []
    @State private var pendingRemoval: [Sentinel2SceneRecord] = []

    @State private var searchError: String?
    @State private var sceneGroups: [Sentinel2SceneGroup] = []
    @State private var aoiRing: GeoRing = []
    @State private var previewGroup: Sentinel2SceneGroup?
    @State private var searchDebounce: Task<Void, Never>?

    // AOI coverage is computed lazily off-main; cells show "… AOI" until filled.
    @State private var coverageByDay: [String: Double] = [:]
    @State private var coverageTask: Task<Void, Never>?

    private var project: Project { configuration.project }

    // The displayed month IS the search range: 1st → last day, inclusive. All date math is UTC,
    // matching Sentinel2SceneGroup.date and downloadMemoryKey.

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
    private var groupsByDay: [String: Sentinel2SceneGroup] {
        Dictionary(sceneGroups.map { (Date.utcFormatter.string(from: $0.date), $0) },
                   uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        Form {
            configSection
            searchParamsSection
            if let errorMsg = searchError {
                Section {
                    Label(errorMsg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            downloadMemorySection
        }
        .formStyle(.grouped)
        .navigationTitle(configuration.name)
        .onChange(of: configuration.searchStartDate) { scheduleSearch() }
        .onChange(of: configuration.cloudCover) { scheduleSearch() }
        .onChange(of: configuration.shapeFile?.id) { scheduleSearch() }
        .task { scheduleSearch() }
        .sheet(item: $previewGroup) { group in
            Sentinel2GroupPreviewSheet(
                group: group,
                status: configuration.downloadStatus(for: group.date),
                onDownload: { products in
                    previewGroup = nil
                    download(products: products)
                }
            )
        }
        .confirmationDialog(
            "Remove \(pendingRemoval.count == 1 ? "1 scene" : "\(pendingRemoval.count) scenes") from memory?",
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
            LabeledContent("Product") {
                Text(Sentinel2ProductType(rawValue: configuration.productType)?.displayName
                     ?? configuration.productType)
                    .foregroundStyle(.secondary)
            }
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
                if !AppSettings.shared.hasCDSECredentials {
                    Text("Set Copernicus credentials in Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                } else if configuration.shapeFile == nil {
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
        let status = configuration.downloadStatus(for: date)
        let tint = dayStatusColor(status)

        Button {
            if let group { previewGroup = group }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(day)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(group == nil ? .secondary : .primary)
                if let group {
                    Text("\(group.products.count) scene\(group.products.count == 1 ? "" : "s")")
                        .font(.caption2)
                    // CDSE reports cloud cover as a percentage already, unlike Planet's fraction.
                    Text("\(Int(group.averageCloudCover.rounded()))% cloud")
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

    private func dayStatusColor(_ status: DownloadMemoryStatus?) -> Color {
        switch status {
        case .downloading: return .orange
        case .downloaded:  return .green
        case .failed:      return .red
        case nil:          return .secondary
        }
    }

    // MARK: - Download Memory

    private var downloadRecords: [Sentinel2SceneRecord] {
        configuration.downloadEntries
            .map { Sentinel2SceneRecord(key: $0.key, entry: $0.value) }
            .sorted { $0.sensingDate > $1.sensingDate }
    }

    @ViewBuilder
    private var downloadMemorySection: some View {
        Section("Downloaded Scenes") {
            ResourceTableView(
                items: downloadRecords,
                itemID: \.id,
                sortOptions: [
                    TableSortOption(
                        id: "date",
                        label: "Date",
                        comparator: { $0.sensingDate < $1.sensingDate },
                        groupLabel: { record in
                            let f = DateFormatter()
                            f.dateFormat = "yyyy"
                            f.timeZone = TimeZone(identifier: "UTC")
                            return f.string(from: record.sensingDate)
                        }
                    ),
                    TableSortOption(
                        id: "cloud",
                        label: "Cloud",
                        comparator: { $0.cloudCover < $1.cloudCover }
                    ),
                    TableSortOption(
                        id: "status",
                        label: "Status",
                        comparator: { $0.status.rawValue < $1.status.rawValue },
                        groupLabel: { $0.status.displayName }
                    )
                ],
                filterOptions: DownloadMemoryStatus.allCases.map { status in
                    TableFilterOption(
                        id: status.rawValue,
                        label: status.displayName,
                        color: status.color,
                        test: { $0.status == status }
                    )
                },
                selectionActions: [
                    TableSelectionAction<Sentinel2SceneRecord>(
                        id: "reveal",
                        icon: "folder",
                        isEnabled: { $0.contains { $0.localPath != nil } },
                        action: { selected in
                            for path in selected.compactMap(\.localPath) {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            }
                        }
                    ),
                    TableSelectionAction<Sentinel2SceneRecord>(
                        id: "remove",
                        icon: "trash",
                        isEnabled: { !$0.isEmpty },
                        action: { pendingRemoval = $0 }
                    )
                ],
                selection: $downloadSelection,
                initialSortOptionID: "date",
                initialSortAscending: false
            ) { record, isSelected in
                Sentinel2SceneRow(record: record, isSelected: isSelected)
            }
        }
    }

    // MARK: - Actions

    /// Debounced search trigger. Coalesces rapid input changes (slider drags, month navigation)
    /// into a single request. No shape file → clear results without hitting the API; the calendar
    /// still renders.
    private func scheduleSearch() {
        searchDebounce?.cancel()

        guard configuration.shapeFile?.originalPath != nil else {
            sceneGroups = []
            aoiRing = []
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
        // The config stores cloud cover as a 0–1 fraction (shared with the Planet tool's slider);
        // CDSE's cloudCover attribute is a percentage.
        let maxCloudCover = configuration.cloudCover * 100
        let productType = configuration.productType

        do {
            let geometry = try loadShapeFileGeometry(from: shapePath)
            let ring = extractRing(from: geometry)
            let groups = try await Sentinel2API.search(
                aoiRing: ring,
                startDate: startDate,
                endDate: endDate,
                productType: productType,
                maxCloudCover: maxCloudCover
            )
            if Task.isCancelled { return }
            sceneGroups = groups
            aoiRing = ring
            isSearching = false
            searchError = groups.isEmpty ? "No products found for the given parameters." : nil
            computeCoverage(for: groups, aoiRing: ring)
        } catch {
            if Task.isCancelled { return }
            searchError = error.localizedDescription
            isSearching = false
        }
    }

    /// Computes AOI coverage per day off the main actor, publishing each result as it lands so
    /// cells swap "… AOI" for the real value incrementally.
    private func computeCoverage(for groups: [Sentinel2SceneGroup], aoiRing: GeoRing) {
        coverageTask?.cancel()
        guard !aoiRing.isEmpty else { return }
        coverageTask = Task {
            for group in groups {
                if Task.isCancelled { return }
                let key = Date.utcFormatter.string(from: group.date)
                let footprints = group.products.map(\.footprintRing)
                let pct = await Task.detached(priority: .utility) {
                    aoiCoveragePercent(aoiRing: aoiRing, footprints: footprints)
                }.value
                if Task.isCancelled { return }
                if let pct { coverageByDay[key] = pct }
            }
        }
    }

    private func download(products: [Sentinel2Product]) {
        guard !products.isEmpty else { return }
        let tool = ToolSentinel2Download()
        registry.register(runner: tool, configName: configuration.name, projectName: project.name)
        tool.start(
            products: products,
            configuration: configuration,
            project: project,
            context: modelContext
        )
    }

    private func removeFromMemory(_ records: [Sentinel2SceneRecord]) {
        for record in records {
            configuration.downloadEntries.removeValue(forKey: record.key)
        }
        configuration.touch()
        downloadSelection = []
        pendingRemoval = []
    }
}

// MARK: - Memory Table Row Model

/// A flattened `downloadEntries` entry, for the memory table. The dictionary key is carried
/// along so a row can be removed without re-deriving it from a possibly-changed configuration.
struct Sentinel2SceneRecord: Identifiable, Hashable {
    let key: String
    let productName: String
    let sensingDate: Date
    let cloudCover: Double
    let fileSize: Int
    let status: DownloadMemoryStatus
    let localPath: String?

    var id: String { key }

    init(key: String, entry: DownloadMemoryEntry) {
        self.key = key
        self.productName = entry.productName
        self.sensingDate = entry.sensingDate
        self.cloudCover = entry.cloudCover
        self.fileSize = entry.fileSize
        self.status = entry.status
        self.localPath = entry.localPath
    }
}

extension DownloadMemoryStatus {
    var displayName: String {
        switch self {
        case .downloading: return "Downloading"
        case .downloaded:  return "Downloaded"
        case .failed:      return "Failed"
        }
    }

    var color: Color {
        switch self {
        case .downloading: return .orange
        case .downloaded:  return .green
        case .failed:      return .red
        }
    }
}

struct Sentinel2SceneRow: View {
    let record: Sentinel2SceneRecord
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: record.status == .downloaded ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(record.status.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(record.sensingDate.displayString)
                    .lineLimit(1)
                Text(record.productName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text("\(Int(record.cloudCover.rounded()))% cloud")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if record.fileSize > 0 {
                Text(ByteCountFormatter.string(fromByteCount: Int64(record.fileSize), countStyle: .file))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

// MARK: - Preview Sheet

/// Lists the products acquired on one day so the user can pick which to download.
/// Lowest cloud cover is preselected — CDSE tiles for a single day over one AOI are usually
/// alternatives, not complements.
struct Sentinel2GroupPreviewSheet: View {
    let group: Sentinel2SceneGroup
    let status: DownloadMemoryStatus?
    let onDownload: ([Sentinel2Product]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            List(group.products) { product in
                HStack(alignment: .top, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { selected.contains(product.id) },
                        set: { on in
                            if on { selected.insert(product.id) } else { selected.remove(product.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name)
                                .font(.callout)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            HStack(spacing: 8) {
                                Text("\(Int(product.cloudCover.rounded()))% cloud")
                                if product.contentLength > 0 {
                                    Text(ByteCountFormatter.string(
                                        fromByteCount: Int64(product.contentLength),
                                        countStyle: .file
                                    ))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .navigationTitle(group.date.displayString)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if let status {
                        Label(status.displayName, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(status.color)
                    }
                    Spacer()
                    Text("Products are ~800 MB each.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Download") {
                        onDownload(group.products.filter { selected.contains($0.id) })
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .frame(width: 560, height: 360)
        .onAppear {
            if let best = group.best { selected = [best.id] }
        }
    }
}
