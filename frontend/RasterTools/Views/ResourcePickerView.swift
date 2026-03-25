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
    var selectionMode: TableSelectionMode = .multi
    var initialSortOptionID: String? = nil
    var initialSortAscending: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var selectionIDs: Set<UUID> = []

    private var sortedKinds: [ResourceKind] {
        Array(selectableKinds).sorted { $0.rawValue < $1.rawValue }
    }

    private var selectableResources: [WorkspaceResource] {
        workspace.resources.filter { selectableKinds.contains($0.kind) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ResourceTableView(
                items: selectableResources,
                itemID: \.id,
                sortOptions: TableSortOption<WorkspaceResource>.allCases,
                filterOptions: TableFilterOption<WorkspaceResource>.forKinds(sortedKinds),
                selection: $selectionIDs,
                initialSortOptionID: initialSortOptionID,
                initialSortAscending: initialSortAscending
            ) { resource, isSelected in
                ResourceTableRow(
                    icon: resource.kind.iconName,
                    label: resource.displayLabel,
                    fileSize: resource.formattedFileSize,
                    badges: resource.tableBadges,
                    pngPath: resource.pngPath,
                    isSelected: isSelected
                )
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top)
        }
        .padding()
        .frame(minWidth: 800, minHeight: 600)
        .frame(idealWidth: 1000, idealHeight: 750)
        .onAppear {
            selectionIDs = Set(selection.map(\.id))
        }
        .onChange(of: selectionIDs) { oldIDs, newIDs in
            if selectionMode == .single && newIDs.count > 1 {
                let added = newIDs.subtracting(oldIDs)
                selectionIDs = added.isEmpty ? newIDs : added
                return
            }
            selection = workspace.resources.filter { newIDs.contains($0.id) }
        }
    }
}
