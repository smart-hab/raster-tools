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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Source directory header
                GroupBox("Source Directory") {
                    HStack {
                        Text(workspace.sourceDirectory)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Button("Refresh") {
                            refreshResources()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(4)
                }

                // Shapes section
                let shapes = resources(for: [.shapeFile])
                ResourceTableSection(label: "Shapes", isEmpty: shapes.isEmpty,
                                     emptyMessage: "No shape files found.") {
                    ForEach(shapes, id: \.id) { resource in
                        ResourceTableRow(
                            icon: resource.kind.iconName,
                            label: resource.filename,
                            fileSize: resource.formattedFileSize,
                            badges: badges(for: resource)
                        )
                    }
                }

                // Sources section
                let sources = resources(for: [.sourceRaster])
                ResourceTableSection(label: "Sources", isEmpty: sources.isEmpty,
                                     emptyMessage: "No sources found. Click Refresh to scan the source directory.") {
                    ForEach(sources, id: \.id) { resource in
                        ResourceTableRow(
                            icon: resource.kind.iconName,
                            label: resource.date.map { $0.formatted(.dateTime.month(.wide).day().year()) } ?? resource.filename,
                            fileSize: resource.formattedFileSize,
                            badges: badges(for: resource)
                        )
                    }
                }

                // Outputs section
                let outputGroups = groupOutputsByKind(resources(for: WorkspaceDetailView.outputKinds, producedOnly: true))
                ResourceTableSection(label: "Outputs", isEmpty: outputGroups.isEmpty,
                                     emptyMessage: "No outputs yet. Run a configuration to generate outputs.") {
                    ForEach(outputGroups, id: \.kind) { group in
                        if outputGroups.count > 1 {
                            Text(group.kind.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                                .padding(.bottom, 2)
                        }
                        ForEach(group.resources, id: \.id) { resource in
                            ResourceTableRow(
                                icon: resource.kind.iconName,
                                label: resource.date.map { $0.formatted(.dateTime.month(.wide).day().year()) } ?? resource.filename,
                                fileSize: resource.formattedFileSize,
                                badges: badges(for: resource),
                                pngPath: resource.pngPath,
                                originalPath: resource.originalPath,
                                onDelete: { deleteOutputResource(resource, context: modelContext) }
                            )
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle(workspace.name)
        .toolbar {
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

// MARK: - Resource Table Section

private struct ResourceTableSection<Content: View>: View {
    let label: String
    let isEmpty: Bool
    let emptyMessage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox(label) {
            if isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .padding(4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(4)
            }
        }
    }
}

