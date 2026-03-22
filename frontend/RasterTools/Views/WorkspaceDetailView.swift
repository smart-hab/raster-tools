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
    @State private var sourceSortKey: OutputSortKey = .date
    @State private var sourceSortAscending: Bool = false
    @State private var outputSelection: Set<UUID> = []
    @State private var outputSortKey: OutputSortKey = .date
    @State private var outputSortAscending: Bool = false
    @State private var outputActiveKinds: Set<ResourceKind> = []

    private static let outputKinds: Set<ResourceKind> = [.masked, .clipped, .ndvi, .ndci, .kmeansClassed, .kmeansMean, .kmeansDiff, .output, .unknown]

    private func resources(for kinds: Set<ResourceKind>, producedOnly: Bool = false) -> [WorkspaceResource] {
        workspace.resources
            .filter { kinds.contains($0.kind) && (!producedOnly || $0.producedBy != nil) }
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
            Section("Workspace") {
                LabeledContent("Source Dir") {
                    Text(workspace.sourceDirectory)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
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
            Section("Sources") {
                if allSources.isEmpty {
                    Text("No sources found. Click Refresh to scan the source directory.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Spacer()
                        OutputSortBar(sortKey: $sourceSortKey, ascending: $sourceSortAscending)
                    }
                    let sourceGroups = groupedOutputs(allSources, sortKey: sourceSortKey, ascending: sourceSortAscending)
                    ForEach(sourceGroups, id: \.groupLabel) { group in
                        if let label = group.groupLabel, group.resources.count > 1 {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(group.resources, id: \.id) { resource in
                            ResourceTableRow(
                                icon: resource.kind.iconName,
                                label: resource.date.map { $0.displayString } ?? resource.filename,
                                fileSize: resource.formattedFileSize,
                                badges: badges(for: resource)
                            )
                        }
                    }
                }
            }

            // Outputs section
            let allOutputs = resources(for: WorkspaceDetailView.outputKinds, producedOnly: true)
            let outputKinds = Array(Set(allOutputs.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
            Section("Outputs") {
                if allOutputs.isEmpty {
                    Text("No outputs yet. Run a configuration to generate outputs.")
                        .foregroundStyle(.secondary)
                } else {
                    ResourceSectionContent(
                        resources: allOutputs,
                        filterKinds: outputKinds,
                        activeKinds: $outputActiveKinds,
                        sortKey: $outputSortKey,
                        sortAscending: $outputSortAscending,
                        selection: $outputSelection,
                        rowLabel: { $0.date.map { $0.displayString } ?? $0.filename },
                        onDeleteSelected: { ids in
                            for id in ids {
                                if let resource = allOutputs.first(where: { $0.id == id }) {
                                    deleteOutputResource(resource, context: modelContext)
                                }
                            }
                            outputSelection.removeAll()
                        }
                    )
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
            NewConfigurationSheet(workspace: workspace) {
                showingNewConfigSheet = false
            }
        }
    }

    private func badges(for resource: WorkspaceResource) -> [String] {
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
