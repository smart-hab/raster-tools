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
        return sortedOutputs(filtered, sortKey: sortKey, ascending: sortAscending)
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
                    Button(filteredResources.allSatisfy({ r in selection.contains { $0.id == r.id } }) ? "Select None" : "Select All") {
                        if filteredResources.allSatisfy({ r in selection.contains { $0.id == r.id } }) {
                            let filteredIDs = Set(filteredResources.map(\.id))
                            selection.removeAll { filteredIDs.contains($0.id) }
                        } else {
                            for resource in filteredResources {
                                if !selection.contains(where: { $0.id == resource.id }) {
                                    selection.append(resource)
                                }
                            }
                        }
                    }
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .frame(idealWidth: 1000, idealHeight: 750)
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

