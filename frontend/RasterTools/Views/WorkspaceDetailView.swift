//
//  WorkspaceDetailView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import SwiftUI
import SwiftData

struct WorkspaceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let workspace: Workspace

    @State private var showingNewConfigSheet = false
    @State private var sourceSortID: String = "date"
    @State private var sourceSortAscending: Bool = false
    @State private var outputSelection: Set<UUID> = []
    @State private var outputGalleryRequest: GalleryRequest?

    private static let outputKinds: Set<ResourceKind> = [.masked, .clipped, .ndvi, .ndci, .kmeansCenters, .kmeansClassed, .kmeansMean, .kmeansDiff, .unknown]

    private func resources(for kinds: Set<ResourceKind>, producedOnly: Bool = false) -> [WorkspaceResource] {
        workspace.resources
            .filter { kinds.contains($0.kind) && (!producedOnly || $0.producedByConfigId != nil) }
            .sorted {
                switch ($0.date, $1.date) {
                case (nil, nil): return false
                case (nil, _): return false
                case (_, nil): return true
                case let (d1?, d2?): return d1 > d2
                }
            }
    }

    var body: some View {
        Form {
            Section("Project") {
                LabeledContent("Name") {
                    Text(workspace.name)
                }
                LabeledContent("Source Dir") {
                    FolderPathButton(path: workspace.sourceDirectory)
                }
                LabeledContent("Output Dir") {
                    Button {
                        NSWorkspace.shared.open(AppStorage.outputDirectory(for: workspace))
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                }
            }

            // Shapes section
            let shapes = resources(for: [.shapeFile])
            Section("Shapes") {
                if shapes.isEmpty {
                    Text("No shape files found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shapes, id: \.id) { resource in
                        ResourceTableRow(
                            icon: resource.kind.iconName,
                            label: resource.filename,
                            fileSize: resource.formattedFileSize,
                            badges: badges(for: resource)
                        )
                    }
                }
            }

            // Sources section
            let allSources = resources(for: [.sourceRaster])
            Section("Rasters") {
                if allSources.isEmpty {
                    Text("No sources found. Click Refresh to scan the source directory.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Spacer()
                        TableSorterView(
                            options: TableSortOption<WorkspaceResource>.allCases,
                            activeSortID: $sourceSortID,
                            ascending: $sourceSortAscending
                        )
                    }
                    let activeSort = TableSortOption<WorkspaceResource>.allCases.first { $0.id == sourceSortID }
                    let sorted = allSources.sorted { a, b in
                        sourceSortAscending
                            ? (activeSort?.comparator(a, b) ?? false)
                            : (activeSort?.comparator(b, a) ?? false)
                    }
                    ForEach(sorted, id: \.id) { resource in
                        ResourceTableRow(
                            icon: resource.kind.iconName,
                            label: resource.date.map { $0.displayString } ?? resource.filename,
                            fileSize: resource.formattedFileSize,
                            badges: badges(for: resource)
                        )
                    }
                }
            }

            // Outputs section
            let allOutputs = resources(for: WorkspaceDetailView.outputKinds, producedOnly: true)
            let outputKinds = Array(Set(allOutputs.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
            Section("Outputs") {
                ResourceTableView(
                    items: allOutputs,
                    itemID: \.id,
                    sortOptions: TableSortOption<WorkspaceResource>.allCases,
                    filterOptions: TableFilterOption<WorkspaceResource>.forKinds(outputKinds),
                    selectionActions: [
                        TableSelectionAction<WorkspaceResource>.gallery(request: $outputGalleryRequest),
                        TableSelectionAction<WorkspaceResource>.deleteOutput(context: modelContext, selectionIDs: $outputSelection)
                    ],
                    selection: $outputSelection,
                    initialSortOptionID: "kind",
                    initialSortAscending: true
                ) { resource, isSelected in
                    ResourceTableRow(
                        icon: resource.kind.iconName,
                        label: resource.date.map { $0.displayString } ?? resource.filename,
                        fileSize: resource.formattedFileSize,
                        badges: resource.tableBadges,
                        pngPath: resource.pngPath,
                        isSelected: isSelected
                    )
                }
                .sheet(item: $outputGalleryRequest) { request in
                    ResourceGallerySheet(items: request.items, initialIndex: request.initialIndex)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(workspace.name)
        .toolbar {
            ToolbarItem {
                Button {
                    refreshResources()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            ToolbarItem {
                Button {
                    showingNewConfigSheet = true
                } label: {
                    Label("Add Configuration", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewConfigSheet) {
            ToolCreateSheet(defaultWorkspace: workspace) { _ in
                showingNewConfigSheet = false
            }
        }
    }

    private func badges(for resource: WorkspaceResource) -> [ResourceKind] {
        resource.tableBadges
    }

    private func refreshResources() {
        let scanned = WorkspaceScanner.scan(directory: workspace.sourceDirectory)

        var existingByPath: [String: WorkspaceResource] = [:]
        for resource in workspace.resources where resource.originalPath.hasPrefix(workspace.sourceDirectory) {
            existingByPath[resource.originalPath] = resource
        }

        let scannedPaths = Set(scanned.map { $0.originalPath })

        for (path, resource) in existingByPath where !scannedPaths.contains(path) {
            workspace.resources.removeAll { $0.id == resource.id }
            modelContext.delete(resource)
        }

        for scannedResource in scanned {
            if existingByPath[scannedResource.originalPath] == nil {
                scannedResource.workspace = workspace
                modelContext.insert(scannedResource)
                workspace.resources.append(scannedResource)
            } else if let existing = existingByPath[scannedResource.originalPath],
                      scannedResource.kind == .sourceRaster,
                      existing.udm == nil,
                      let scannedUDM = scannedResource.udm {
                if let existingUDM = existingByPath[scannedUDM.originalPath] {
                    existing.udm = existingUDM
                } else if workspace.resources.first(where: { $0.originalPath == scannedUDM.originalPath }) == nil {
                    scannedUDM.workspace = workspace
                    modelContext.insert(scannedUDM)
                    workspace.resources.append(scannedUDM)
                    existing.udm = scannedUDM
                }
            }
        }

        workspace.modifiedAt = Date()
    }
}
