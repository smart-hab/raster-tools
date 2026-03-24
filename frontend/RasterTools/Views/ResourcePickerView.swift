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
    @State private var sortKey: OutputSortKey = .kind
    @State private var sortAscending: Bool = false
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
                resources: selectableResources,
                filterKinds: sortedKinds,
                activeKinds: $activeKinds,
                sortKey: $sortKey,
                sortAscending: $sortAscending,
                selection: $selectionIDs
            )

            if allowsMultiple {
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top)
            }
        }
        .padding()
        .frame(minWidth: 800, minHeight: 600)
        .frame(idealWidth: 1000, idealHeight: 750)
        .onAppear {
            activeKinds = defaultKinds
            selectionIDs = Set(selection.map(\.id))
        }
        .onChange(of: selectionIDs) { _, newIDs in
            selection = workspace.resources.filter { newIDs.contains($0.id) }
            if !allowsMultiple && !newIDs.isEmpty {
                dismiss()
            }
        }
    }
}
