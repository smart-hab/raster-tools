//
//  ResourcePickerView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import SwiftUI
import SwiftData

struct ResourcePickerView: View {
    let workspace: Workspace
    let defaultKinds: Set<ResourceKind>
    let selectableKinds: Set<ResourceKind>
    @Binding var selection: [WorkspaceResource]
    var allowsMultiple: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var activeKinds: Set<ResourceKind> = []
    @State private var sortKey: OutputSortKey = .date
    @State private var sortAscending: Bool = false

    private var sortedKinds: [ResourceKind] {
        Array(selectableKinds).sorted { $0.rawValue < $1.rawValue }
    }

    private var filteredResources: [WorkspaceResource] {
        let filtered = workspace.resources.filter { activeKinds.contains($0.kind) }
        return filtered.sorted { a, b in
            switch sortKey {
            case .date:
                switch (a.date, b.date) {
                case (nil, nil):
                    let cmp = a.kind.displayName.localizedCompare(b.kind.displayName)
                    return sortAscending ? cmp == .orderedAscending : cmp == .orderedDescending
                case (nil, _): return sortAscending
                case (_, nil): return !sortAscending
                case let (d1?, d2?) where d1 == d2:
                    let cmp = a.kind.displayName.localizedCompare(b.kind.displayName)
                    return sortAscending ? cmp == .orderedAscending : cmp == .orderedDescending
                case let (d1?, d2?): return sortAscending ? d1 < d2 : d1 > d2
                }
            case .kind:
                let kindCmp = a.kind.displayName.localizedCompare(b.kind.displayName)
                if kindCmp != .orderedSame {
                    return sortAscending ? kindCmp == .orderedAscending : kindCmp == .orderedDescending
                }
                switch (a.date, b.date) {
                case (nil, nil): return false
                case (nil, _): return sortAscending
                case (_, nil): return !sortAscending
                case let (d1?, d2?): return sortAscending ? d1 < d2 : d1 > d2
                }
            case .size:
                return sortAscending ? a.fileSize < b.fileSize : a.fileSize > b.fileSize
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter + sort bar
            HStack {
                ResourceFilterBar(kinds: sortedKinds, activeKinds: $activeKinds)
                Spacer()
                OutputSortBar(sortKey: $sortKey, ascending: $sortAscending)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()

            // Resource list
            if filteredResources.isEmpty {
                ContentUnavailableView(
                    "No Resources",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("No resources of the selected types found in this workspace.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredResources, id: \.id) { resource in
                        ResourcePickerRow(
                            resource: resource,
                            isSelected: selection.contains { $0.id == resource.id },
                            allowsMultiple: allowsMultiple
                        ) {
                            toggle(resource)
                            if !allowsMultiple { dismiss() }
                        }
                    }
                }
                .listStyle(.inset)
            }

            if allowsMultiple {
                Divider()

                HStack {
                    Text("\(selection.count) selected")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            activeKinds = defaultKinds
        }
    }

    private func toggle(_ resource: WorkspaceResource) {
        if allowsMultiple {
            if let idx = selection.firstIndex(where: { $0.id == resource.id }) {
                selection.remove(at: idx)
            } else {
                selection.append(resource)
            }
        } else {
            selection = [resource]
        }
    }
}

private struct ResourcePickerRow: View {
    let resource: WorkspaceResource
    let isSelected: Bool
    let allowsMultiple: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ResourceTableRow(
                icon: resource.kind.iconName,
                label: resource.displayLabel,
                fileSize: resource.formattedFileSize,
                badges: resource.tableBadges,
                isSelected: Optional(isSelected)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ResourceKind display name

extension ResourceKind {
    var displayName: String {
        switch self {
        case .sourceRaster: return "Source"
        case .udm: return "UDM"
        case .metadata: return "Metadata"
        case .shapeFile: return "Shape"
        case .clipped: return "Clipped"
        case .masked: return "Masked"
        case .ndvi: return "NDVI"
        case .ndci: return "NDCI"
        case .kmeansClassed: return "Classified"
        case .kmeansMean: return "Mean"
        case .kmeansDiff: return "Difference"
        case .output: return "Output"
        case .unknown: return "Unknown"
        }
    }
}
