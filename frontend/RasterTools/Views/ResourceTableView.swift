//
//  ResourceTableView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import SwiftUI
import SwiftData

// MARK: - Generic Table Option Types

struct TableSortOption<T>: Identifiable {
    let id: String
    let label: String
    /// Returns true if `a` should come before `b` (ascending order).
    let comparator: (T, T) -> Bool
    /// Optional grouping — returns the group label for a given item.
    let groupLabel: ((T) -> String?)?

    init(
        id: String,
        label: String,
        comparator: @escaping (T, T) -> Bool,
        groupLabel: ((T) -> String?)? = nil
    ) {
        self.id = id
        self.label = label
        self.comparator = comparator
        self.groupLabel = groupLabel
    }
}

struct TableFilterOption<T>: Identifiable {
    let id: String
    let label: String
    let color: Color
    let test: (T) -> Bool
}

struct TableSelectionAction<T>: Identifiable {
    let id: String
    let icon: String
    /// Receives the currently selected items; return false to disable the button.
    let isEnabled: ([T]) -> Bool
    let action: ([T]) -> Void
}

// MARK: - Resource Table Row

struct ResourceTableRow: View {
    let resource: ProjectResource
    var onDelete: (() -> Void)? = nil
    var isSelected: Bool? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: resource.kind.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(resource.displayLabel)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 4) {
                ForEach(resource.tableBadges, id: \.self) { kind in
                    BadgeCapsule(kind: kind)
                }
            }

            Text(resource.formattedFileSize)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .trailing)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else if let isSelected {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Generic Filter View

struct TableFilterView<T>: View {
    let options: [TableFilterOption<T>]
    @Binding var activeIDs: Set<String>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                BadgeCapsule(label: option.label, color: option.color)
                    .opacity(activeIDs.contains(option.id) ? 1.0 : 0.4)
                    .overlay(
                        MouseClickView(
                            onLeftClick: {
                                if activeIDs.contains(option.id) {
                                    activeIDs.remove(option.id)
                                } else {
                                    activeIDs.insert(option.id)
                                }
                            },
                            onRightClick: {
                                let others = Set(options.map(\.id)).subtracting([option.id])
                                if others.isSubset(of: activeIDs) {
                                    activeIDs.subtract(others)
                                } else {
                                    activeIDs.formUnion(others)
                                }
                            }
                        )
                    )
            }
        }
    }
}

// MARK: - Generic Sorter View

struct TableSorterView<T>: View {
    let options: [TableSortOption<T>]
    @Binding var activeSortID: String
    @Binding var ascending: Bool

    var body: some View {
        HStack(spacing: 4) {
            Spacer()
            ForEach(options) { option in
                Button {
                    if activeSortID == option.id {
                        ascending.toggle()
                    } else {
                        activeSortID = option.id
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(option.label)
                        if activeSortID == option.id {
                            Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        }
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .foregroundStyle(activeSortID == option.id ? .primary : .secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Selection Mode

enum TableSelectionMode {
    case none, single, multi
}

// MARK: - Generic ResourceTableView

struct ResourceTableView<T, ID: Hashable, RowContent: View>: View {
    let items: [T]
    let itemID: KeyPath<T, ID>
    let sortOptions: [TableSortOption<T>]
    var filterOptions: [TableFilterOption<T>]? = nil
    var selectionActions: [TableSelectionAction<T>] = []
    @Binding var selection: Set<ID>
    var onAdd: (() -> Void)? = nil
    let rowContent: (T, Bool?) -> RowContent
    let selectionMode: TableSelectionMode

    @State private var activeSortID: String
    @State private var sortAscending: Bool
    @State private var activeFilterIDs: Set<String>
    @State private var lastClickedID: ID?

    /// Standard init with selection support (single or multi).
    init(
        items: [T],
        itemID: KeyPath<T, ID>,
        sortOptions: [TableSortOption<T>],
        filterOptions: [TableFilterOption<T>]? = nil,
        selectionActions: [TableSelectionAction<T>] = [],
        selection: Binding<Set<ID>>,
        onAdd: (() -> Void)? = nil,
        initialSortOptionID: String? = nil,
        initialSortAscending: Bool = false,
        @ViewBuilder rowContent: @escaping (T, Bool?) -> RowContent
    ) {
        self.items = items
        self.itemID = itemID
        self.sortOptions = sortOptions
        self.filterOptions = filterOptions
        self.selectionActions = selectionActions
        self._selection = selection
        self.onAdd = onAdd
        self.rowContent = rowContent
        self.selectionMode = .multi
        self._activeSortID = State(initialValue: initialSortOptionID ?? sortOptions.first?.id ?? "")
        self._sortAscending = State(initialValue: initialSortAscending)
        self._activeFilterIDs = State(initialValue: Set(filterOptions?.map(\.id) ?? []))
    }

    /// No-selection init — sorting and filtering still work; row taps are no-ops.
    init(
        items: [T],
        itemID: KeyPath<T, ID>,
        sortOptions: [TableSortOption<T>],
        filterOptions: [TableFilterOption<T>]? = nil,
        initialSortOptionID: String? = nil,
        initialSortAscending: Bool = false,
        @ViewBuilder rowContent: @escaping (T, Bool?) -> RowContent
    ) {
        self.items = items
        self.itemID = itemID
        self.sortOptions = sortOptions
        self.filterOptions = filterOptions
        self.selectionActions = []
        self._selection = .constant(.init())
        self.onAdd = nil
        self.rowContent = rowContent
        self.selectionMode = .none
        self._activeSortID = State(initialValue: initialSortOptionID ?? sortOptions.first?.id ?? "")
        self._sortAscending = State(initialValue: initialSortAscending)
        self._activeFilterIDs = State(initialValue: Set(filterOptions?.map(\.id) ?? []))
    }

    private var activeSort: TableSortOption<T>? {
        sortOptions.first { $0.id == activeSortID }
    }

    private var visibleItems: [T] {
        guard let filterOptions, !filterOptions.isEmpty else { return items }
        let active = filterOptions.filter { activeFilterIDs.contains($0.id) }
        return items.filter { item in active.contains { $0.test(item) } }
    }

    private func groupedItems(_ visible: [T]) -> [(label: String?, items: [T])] {
        guard let sort = activeSort else { return [(nil, visible)] }
        let sorted = visible.sorted { a, b in
            sortAscending ? sort.comparator(a, b) : sort.comparator(b, a)
        }
        guard let grouper = sort.groupLabel else { return [(nil, sorted)] }

        var groups: [(label: String?, items: [T])] = []
        var labelToIndex: [String?: Int] = [:]
        for item in sorted {
            let label = grouper(item)
            if let idx = labelToIndex[label] {
                groups[idx].items.append(item)
            } else {
                labelToIndex[label] = groups.count
                groups.append((label: label, items: [item]))
            }
        }
        return groups
    }

    var body: some View {
        let visible = visibleItems
        let groups = groupedItems(visible)
        let orderedItems = groups.flatMap(\.items)
        let visibleIDs = Set(orderedItems.map { $0[keyPath: itemID] })
        let selectedItems = orderedItems.filter { selection.contains($0[keyPath: itemID]) }

        VStack(spacing: 0) {
            HStack {
                if let filterOptions, filterOptions.count > 1 {
                    TableFilterView(options: filterOptions, activeIDs: $activeFilterIDs)
                        .onAppear {
                            if activeFilterIDs.isEmpty {
                                activeFilterIDs = Set(filterOptions.map(\.id))
                            }
                        }
                        .onChange(of: filterOptions.map(\.id)) { _, newIDs in
                            activeFilterIDs.formUnion(Set(newIDs).subtracting(activeFilterIDs))
                        }
                }
                Spacer()
                TableSorterView(options: sortOptions, activeSortID: $activeSortID, ascending: $sortAscending)
            }
            .padding(.bottom, 4)

            if items.isEmpty {
                ContentUnavailableView("No Items", systemImage: "tray")
            } else {
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(groups.indices, id: \.self) { i in
                            let group = groups[i]
                            if let label = group.label {
                                Text(label).font(.caption).foregroundStyle(.secondary)
                                    .padding(.top, 8)
                            }
                            ForEach(group.items, id: itemID) { item in
                                rowContent(item, selectionMode != .none ? selection.contains(item[keyPath: itemID]) : nil)
                                    .onTapGesture {
                                        if selectionMode != .none {
                                            handleTap(item: item, orderedItems: orderedItems)
                                        }
                                    }
                            }
                        }
                    }
                }
            }

            if selectionMode != .none {
                HStack {
                    if let onAdd {
                        Button { onAdd() } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text(selection.isEmpty ? "\(items.count) items" : "\(selection.count) of \(items.count) selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .opacity(items.isEmpty ? 0 : 1)
                    Spacer()
                    ForEach(selectionActions) { action in
                        Button {
                            action.action(selectedItems)
                        } label: {
                            Image(systemName: action.icon)
                        }
                        .buttonStyle(.plain)
                        .disabled(!action.isEnabled(selectedItems))
                    }
                    Button {
                        if visibleIDs.isSubset(of: selection) {
                            selection.subtract(visibleIDs)
                        } else {
                            selection.formUnion(visibleIDs)
                        }
                    } label: {
                        Image(systemName: visibleIDs.isSubset(of: selection) ? "circle.slash" : "checkmark.circle")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func handleTap(item: T, orderedItems: [T]) {
        let itemIdentity = item[keyPath: itemID]
        let isShift = NSEvent.modifierFlags.contains(.shift)
        if isShift,
           let lastID = lastClickedID,
           let lastIdx = orderedItems.firstIndex(where: { $0[keyPath: itemID] == lastID }),
           let currentIdx = orderedItems.firstIndex(where: { $0[keyPath: itemID] == itemIdentity }) {
            let range = min(lastIdx, currentIdx)...max(lastIdx, currentIdx)
            orderedItems[range].map { $0[keyPath: itemID] }.forEach { selection.insert($0) }
        } else {
            if selection.contains(itemIdentity) {
                selection.remove(itemIdentity)
            } else {
                selection.insert(itemIdentity)
            }
        }
        lastClickedID = itemIdentity
    }
}

// MARK: - ProjectResource badges

extension ProjectResource {
    var tableBadges: [ResourceKind] {
        switch kind {
        case .sourceRaster: return [.sourceRaster] + (udm != nil ? [.udm] : [])
        default:            return [kind]
        }
    }

    var isImagePreviewable: Bool { pngPath != nil }

    var isTextPreviewable: Bool {
        ["txt", "json", "geojson"].contains(fileExtension.lowercased())
    }

    var isPreviewable: Bool { isImagePreviewable || isTextPreviewable }

    var textContent: String? {
        guard isTextPreviewable else { return nil }
        return try? String(contentsOfFile: originalPath, encoding: .utf8)
    }
}

// MARK: - ProjectResource Sort Options

extension TableSortOption where T == ProjectResource {
    static var date: Self {
        TableSortOption(
            id: "date",
            label: "Date",
            comparator: { a, b in
                switch (a.date, b.date) {
                case (nil, nil): return false
                case (nil, _):   return true
                case (_, nil):   return false
                case let (d1?, d2?): return d1 < d2
                }
            },
            groupLabel: { resource in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy"
                return resource.date.map { formatter.string(from: $0) } ?? "Unknown Date"
            }
        )
    }

    static var kind: Self {
        TableSortOption(
            id: "kind",
            label: "Kind",
            comparator: { a, b in
                let kindOrder = a.kind.displayName.localizedCompare(b.kind.displayName)
                if kindOrder != .orderedSame { return kindOrder == .orderedAscending }
                switch (a.date, b.date) {
                case (nil, nil): return false
                case (nil, _):   return true
                case (_, nil):   return false
                case let (d1?, d2?): return d1 < d2
                }
            },
            groupLabel: { $0.kind.displayName }
        )
    }

    static var size: Self {
        TableSortOption(
            id: "size",
            label: "Size",
            comparator: { $0.fileSize < $1.fileSize },
            groupLabel: nil
        )
    }

    static var allCases: [Self] { [.date, .kind, .size] }
}

// MARK: - ProjectResource Filter Options

extension TableFilterOption where T == ProjectResource {
    static func forKinds(_ kinds: [ResourceKind]) -> [Self] {
        kinds.map { kind in
            TableFilterOption(
                id: kind.rawValue,
                label: kind.displayName,
                color: kind.color,
                test: { $0.kind == kind }
            )
        }
    }
}

// MARK: - ProjectResource Selection Actions

extension TableSelectionAction where T == ProjectResource {
    static func gallery(request: Binding<GalleryRequest?>) -> Self {
        TableSelectionAction(
            id: "gallery",
            icon: "photo.on.rectangle.angled",
            isEnabled: { items in items.contains { $0.isPreviewable } },
            action: { items in
                let galleryItems = items.filter { $0.isPreviewable }
                request.wrappedValue = GalleryRequest(items: galleryItems, initialIndex: 0)
            }
        )
    }

    static func delete(
        from collection: Binding<[ProjectResource]>,
        selectionIDs: Binding<Set<UUID>>,
        touch: (() -> Void)? = nil
    ) -> Self {
        TableSelectionAction(
            id: "delete",
            icon: "trash",
            isEnabled: { !$0.isEmpty },
            action: { items in
                for item in items {
                    collection.wrappedValue.removeAll { $0.id == item.id }
                }
                touch?()
                selectionIDs.wrappedValue.removeAll()
            }
        )
    }

    static func deleteOutput(
        context: ModelContext,
        selectionIDs: Binding<Set<UUID>>
    ) -> Self {
        TableSelectionAction(
            id: "delete",
            icon: "trash",
            isEnabled: { !$0.isEmpty },
            action: { items in
                for item in items {
                    deleteOutputResource(item, context: context)
                }
                selectionIDs.wrappedValue.removeAll()
            }
        )
    }
}

// MARK: - Delete helper

func deleteOutputResource(_ resource: ProjectResource, context: ModelContext) {
    try? FileManager.default.removeItem(atPath: resource.originalPath)
    if let pngPath = resource.pngPath {
        try? FileManager.default.removeItem(atPath: pngPath)
    }
    resource.project?.resources.removeAll { $0.id == resource.id }
    context.delete(resource)
}
