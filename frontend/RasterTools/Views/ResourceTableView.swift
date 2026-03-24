//
//  ResourceTableView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import SwiftUI
import SwiftData

// MARK: - Resource Table Row

struct ResourceTableRow: View {
    let icon: String
    let label: String
    let fileSize: String
    let badges: [ResourceKind]
    var pngPath: String? = nil
    var originalPath: String? = nil
    var onDelete: (() -> Void)? = nil
    var isSelected: Bool? = nil
    var onPreview: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .onTapGesture {
                    if pngPath != nil { onPreview?() }
                }

            Text(label)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 4) {
                ForEach(badges, id: \.self) { kind in
                    BadgeCapsule(kind: kind)
                }
            }

            Text(fileSize)
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

// MARK: - Resource Table Filter View

struct ResourceTableFilterView: View {
    let kinds: [ResourceKind]
    @Binding var activeKinds: Set<ResourceKind>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(kinds, id: \.self) { kind in
                BadgeCapsule(kind: kind)
                    .opacity(activeKinds.contains(kind) ? 1.0 : 0.4)
                    .overlay(
                        MouseClickView(
                            onLeftClick: {
                                if activeKinds.contains(kind) {
                                    activeKinds.remove(kind)
                                } else {
                                    activeKinds.insert(kind)
                                }
                            },
                            onRightClick: {
                                let others = Set(kinds).subtracting([kind])
                                if others.isSubset(of: activeKinds) {
                                    activeKinds.subtract(others)
                                } else {
                                    activeKinds.formUnion(others)
                                }
                            }
                        )
                    )
            }
        }
    }
}

// MARK: - Resource Table Soter View

struct ResourceTableSorterView: View {
    @Binding var sortKey: OutputSortKey
    @Binding var ascending: Bool

    var body: some View {
        HStack(spacing: 4) {
            Spacer()
            ForEach(OutputSortKey.allCases, id: \.self) { key in
                Button {
                    if sortKey == key {
                        ascending.toggle()
                    } else {
                        sortKey = key
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(key.rawValue)
                        if sortKey == key {
                            Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        }
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .foregroundStyle(sortKey == key ? .primary : .secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Resource Table View

/// Encapsulates the repeated filter bar + grouped rows + action bar pattern used across
/// raster input sections and output sections in config and workspace views.
struct ResourceTableView: View {
    let resources: [WorkspaceResource]
    /// Pass the full kind list to show a filter bar; nil hides it.
    let filterKinds: [ResourceKind]?
    @Binding var activeKinds: Set<ResourceKind>
    @Binding var sortKey: OutputSortKey
    @Binding var sortAscending: Bool
    @Binding var selection: Set<UUID>
    var rowLabel: (WorkspaceResource) -> String = { $0.displayLabel }
    var onAdd: (() -> Void)? = nil
    var onDeleteSelected: ((Set<UUID>) -> Void)? = nil

    @State private var galleryRequest: GalleryRequest? = nil
    @State private var lastClickedID: UUID? = nil

    private var visibleResources: [WorkspaceResource] {
        guard let filterKinds, filterKinds.count > 1 else { return resources }
        return resources.filter { activeKinds.contains($0.kind) }
    }

    var body: some View {
        let visibleIDs = Set(visibleResources.map(\.id))
        let selectionBytes = resources.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.fileSize }
        let groups = groupedOutputs(visibleResources, sortKey: sortKey, ascending: sortAscending)
        let orderedResources = groups.flatMap(\.resources)

        VStack(spacing: 0) {
            if !resources.isEmpty {
                HStack {
                    if let filterKinds, filterKinds.count > 1 {
                        ResourceTableFilterView(kinds: filterKinds, activeKinds: $activeKinds)
                            .onAppear {
                                if activeKinds.isEmpty { activeKinds = Set(filterKinds) }
                            }
                            .onChange(of: filterKinds) { _, newKinds in
                                activeKinds.formUnion(Set(newKinds).subtracting(activeKinds))
                            }
                    }
                    Spacer()
                    ResourceTableSorterView(sortKey: $sortKey, ascending: $sortAscending)
                }
                .padding(.bottom, 4)

                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(groups, id: \.groupLabel) { group in
                            if let label = group.groupLabel {
                                Text(label).font(.caption).foregroundStyle(.secondary)
                                    .padding(.top, 8)
                            }
                            ForEach(group.resources, id: \.id) { resource in
                                ResourceTableRow(
                                    icon: resource.kind.iconName,
                                    label: rowLabel(resource),
                                    fileSize: resource.formattedFileSize,
                                    badges: resource.tableBadges,
                                    pngPath: resource.pngPath,
                                    originalPath: resource.originalPath,
                                    isSelected: selection.contains(resource.id),
                                    onPreview: {
                                        galleryRequest = GalleryRequest(items: [GalleryItem(resource)], initialIndex: 0)
                                    }
                                )
                                .onTapGesture {
                                    let isShift = NSEvent.modifierFlags.contains(.shift)
                                    if isShift, let lastID = lastClickedID,
                                       let lastIdx = orderedResources.firstIndex(where: { $0.id == lastID }),
                                       let currentIdx = orderedResources.firstIndex(where: { $0.id == resource.id }) {
                                        let range = min(lastIdx, currentIdx)...max(lastIdx, currentIdx)
                                        let rangeIDs = orderedResources[range].map(\.id)
                                        rangeIDs.forEach { selection.insert($0) }
                                    } else {
                                        if selection.contains(resource.id) {
                                            selection.remove(resource.id)
                                        } else {
                                            selection.insert(resource.id)
                                        }
                                    }
                                    lastClickedID = resource.id
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                if let onAdd {
                    Button { onAdd() } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(selectionLabel(selection.count, bytes: selectionBytes))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                let selectedWithPNG = orderedResources.filter { selection.contains($0.id) && $0.pngPath != nil }
                Button {
                    let items = orderedResources.filter { selection.contains($0.id) }.map { GalleryItem($0) }
                    galleryRequest = GalleryRequest(items: items, initialIndex: 0)
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .buttonStyle(.plain)
                .disabled(selectedWithPNG.isEmpty)
                if let onDeleteSelected {
                    Button {
                        onDeleteSelected(selection)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .disabled(selection.isEmpty)
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
        .sheet(item: $galleryRequest) { request in
            ResourceGallerySheet(items: request.items, initialIndex: request.initialIndex)
        }
    }
}

// MARK: - WorkspaceResource badges

extension WorkspaceResource {
    var tableBadges: [ResourceKind] {
        switch kind {
        case .sourceRaster: return [.sourceRaster] + (udm != nil ? [.udm] : [])
        default:            return [kind]
        }
    }
}

// MARK: - Selection label

func selectionLabel(_ count: Int, bytes: Int) -> String {
    guard count > 0, bytes > 0 else { return "\(count) selected" }
    let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    return "\(count) selected (\(size))"
}

// MARK: - Grouping and Sorting

enum OutputSortKey: String, CaseIterable {
    case date, kind, size
}

private func compareDate(_ a: WorkspaceResource, _ b: WorkspaceResource, ascending: Bool) -> ComparisonResult {
    switch (a.date, b.date) {
    case (nil, nil): return .orderedSame
    case (nil, _):   return ascending ? .orderedAscending : .orderedDescending
    case (_, nil):   return ascending ? .orderedDescending : .orderedAscending
    case let (d1?, d2?):
        if d1 < d2 { return ascending ? .orderedAscending : .orderedDescending }
        if d1 > d2 { return ascending ? .orderedDescending : .orderedAscending }
        return .orderedSame
    }
}

private func compareKind(_ a: WorkspaceResource, _ b: WorkspaceResource, ascending: Bool) -> ComparisonResult {
    let cmp = a.kind.displayName.localizedCompare(b.kind.displayName)
    if cmp == .orderedSame { return .orderedSame }
    return (ascending ? cmp == .orderedAscending : cmp == .orderedDescending) ? .orderedAscending : .orderedDescending
}

func sortedOutputs(
    _ outputs: [WorkspaceResource],
    sortKey: OutputSortKey,
    ascending: Bool
) -> [WorkspaceResource] {
    return outputs.sorted { a, b in
        switch sortKey {
        case .date:
            let d = compareDate(a, b, ascending: ascending)
            return (d == .orderedSame ? compareKind(a, b, ascending: ascending) : d) == .orderedAscending
        case .kind:
            let k = compareKind(a, b, ascending: ascending)
            return (k == .orderedSame ? compareDate(a, b, ascending: ascending) : k) == .orderedAscending
        case .size:
            return ascending ? a.fileSize < b.fileSize : a.fileSize > b.fileSize
        }
    }
}

func groupedOutputs(
    _ outputs: [WorkspaceResource],
    sortKey: OutputSortKey,
    ascending: Bool
) -> [(groupLabel: String?, resources: [WorkspaceResource])] {
    let sorted = sortedOutputs(outputs, sortKey: sortKey, ascending: ascending)

    switch sortKey {
    case .date:
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        var groups: [(groupLabel: String?, resources: [WorkspaceResource])] = []
        var labelToIndex: [String: Int] = [:]
        for resource in sorted {
            let label = resource.date.map { formatter.string(from: $0) } ?? "Unknown Date"
            if let idx = labelToIndex[label] {
                groups[idx].resources.append(resource)
            } else {
                labelToIndex[label] = groups.count
                groups.append((groupLabel: label, resources: [resource]))
            }
        }
        return groups
    case .kind:
        var groups: [(groupLabel: String?, resources: [WorkspaceResource])] = []
        var kindToIndex: [ResourceKind: Int] = [:]
        for resource in sorted {
            if let idx = kindToIndex[resource.kind] {
                groups[idx].resources.append(resource)
            } else {
                kindToIndex[resource.kind] = groups.count
                groups.append((groupLabel: resource.kind.displayName, resources: [resource]))
            }
        }
        return groups
    case .size:
        return [(groupLabel: nil, resources: sorted)]
    }
}
// MARK: - Delete helper

func deleteOutputResource(_ resource: WorkspaceResource, context: ModelContext) {
    try? FileManager.default.removeItem(atPath: resource.originalPath)
    if let pngPath = resource.pngPath {
        try? FileManager.default.removeItem(atPath: pngPath)
    }
    resource.workspace?.resources.removeAll { $0.id == resource.id }
    context.delete(resource)
}

// MARK: - Resource Filter Click Handler (left + right)

struct MouseClickView: NSViewRepresentable {
    let onLeftClick: () -> Void
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> ClickableNSView {
        let view = ClickableNSView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: ClickableNSView, context: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
    }
}

class ClickableNSView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onLeftClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}
