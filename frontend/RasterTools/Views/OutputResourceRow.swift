//
//  OutputResourceRow.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import SwiftUI
import SwiftData

// MARK: - Sort model

enum OutputSortKey: String, CaseIterable {
    case date, kind, size
}

// MARK: - Grouping helper

func groupOutputsByKind(_ outputs: [WorkspaceResource]) -> [(kind: ResourceKind, resources: [WorkspaceResource])] {
    let groups = groupedOutputs(outputs, sortKey: .date, ascending: false)
    return groups.compactMap { group in
        guard group.groupLabel != nil else { return nil }
        // Find the kind from the first resource
        guard let kind = group.resources.first?.kind else { return nil }
        return (kind: kind, resources: group.resources)
    }
}

func groupedOutputs(
    _ outputs: [WorkspaceResource],
    sortKey: OutputSortKey,
    ascending: Bool
) -> [(groupLabel: String?, resources: [WorkspaceResource])] {
    let sorted = outputs.sorted { a, b in
        switch sortKey {
        case .date:
            switch (a.date, b.date) {
            case (nil, nil): return false
            case (nil, _): return ascending
            case (_, nil): return !ascending
            case let (d1?, d2?): return ascending ? d1 < d2 : d1 > d2
            }
        case .kind:
            let cmp = a.kind.displayName.localizedCompare(b.kind.displayName)
            return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
        case .size:
            return ascending ? a.fileSize < b.fileSize : a.fileSize > b.fileSize
        }
    }

    switch sortKey {
    case .date:
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy MMMM d"
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

// MARK: - Filter bar

struct ResourceFilterBar: View {
    let kinds: [ResourceKind]
    @Binding var activeKinds: Set<ResourceKind>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(kinds, id: \.self) { kind in
                Button {
                    if activeKinds.contains(kind) {
                        activeKinds.remove(kind)
                    } else {
                        activeKinds.insert(kind)
                    }
                } label: {
                    BadgeCapsule(label: kind.filterBadgeLabel)
                }
                .buttonStyle(.plain)
                .opacity(activeKinds.contains(kind) ? 1.0 : 0.4)
            }
        }
    }
}

// MARK: - Sort bar

struct OutputSortBar: View {
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
                        ascending = key == .kind
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
                .foregroundStyle(sortKey == key ? .primary : .secondary)
            }
        }
        .padding(.vertical, 2)
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

// MARK: - Output Resource Row

struct OutputResourceRow: View {
    let resource: WorkspaceResource
    let onDelete: () -> Void

    @State private var showingPreview = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: resource.kind.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(resource.displayLabel)
                HStack(spacing: 4) {
                    Text(resource.filename)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if !resource.formattedFileSize.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(resource.formattedFileSize)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if resource.pngPath != nil {
                Button {
                    showingPreview = true
                } label: {
                    Image(systemName: "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingPreview) {
                    if let pngPath = resource.pngPath {
                        PNGPreviewView(resource: resource, pngPath: pngPath, onDelete: onDelete)
                    }
                }
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - PNG Preview

struct PNGPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let resource: WorkspaceResource
    let pngPath: String
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let image = NSImage(contentsOfFile: pngPath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Preview not available")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            metadataFooter
        }
        .frame(minWidth: 500, minHeight: 400)
        .overlay {
            Button("") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
        }
    }

    private var metadataFooter: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(URL(fileURLWithPath: resource.originalPath).lastPathComponent)
                    .font(.headline)

                HStack(spacing: 8) {
                    if let date = resource.date {
                        Text(date.displayString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !resource.formattedFileSize.isEmpty {
                        Text(resource.formattedFileSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        ForEach(resource.tableBadges, id: \.self) { badge in
                            BadgeCapsule(label: badge)
                        }
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: resource.originalPath)]
                    )
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .help("Reveal in Finder")

                if let onDelete {
                    Button(role: .destructive) {
                        dismiss()
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .help("Delete")
                }
            }
        }
        .padding()
    }
}
