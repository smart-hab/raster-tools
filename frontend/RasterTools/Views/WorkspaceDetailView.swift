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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
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

                // Stats
                let rasters = workspace.resources.filter { $0.kind == .sourceRaster }
                let metadataFiles = workspace.resources.filter { $0.kind == .metadata }
                GroupBox("Resources") {
                    if workspace.resources.isEmpty {
                        Text("No resources found. Click Refresh to scan the source directory.")
                            .foregroundStyle(.secondary)
                            .padding(4)
                    } else {
                        HStack {
                            Label("\(rasters.count) raster\(rasters.count == 1 ? "" : "s")", systemImage: "photo.fill")
                            Spacer()
                            Label("\(metadataFiles.count) metadata file\(metadataFiles.count == 1 ? "" : "s")", systemImage: "doc.text.fill")
                        }
                        .padding(4)

                        Divider()

                        ResourceListView(resources: workspace.resources)
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

    private func refreshResources() {
        let scanned = WorkspaceScanner.scan(directory: workspace.sourceDirectory)
        let scannedPaths = Set(scanned.map { $0.originalPath })
        let existingPaths = Set(workspace.resources.map { $0.originalPath })

        // Remove resources no longer on disk
        for resource in workspace.resources where !scannedPaths.contains(resource.originalPath) {
            workspace.resources.removeAll { $0.originalPath == resource.originalPath }
            modelContext.delete(resource)
        }

        // Add newly discovered resources
        for resource in scanned where !existingPaths.contains(resource.originalPath) {
            resource.workspace = workspace
            modelContext.insert(resource)
            workspace.resources.append(resource)
        }

        workspace.modifiedAt = Date()
    }
}

// MARK: - Resource List

private struct ResourceListView: View {
    let resources: [WorkspaceResource]

    var groupedByDate: [(Date?, [WorkspaceResource])] {
        var byDate: [Date?: [WorkspaceResource]] = [:]
        for resource in resources {
            byDate[resource.date, default: []].append(resource)
        }
        return byDate.sorted { a, b in
            switch (a.key, b.key) {
            case (nil, nil): return false
            case (nil, _): return false
            case (_, nil): return true
            case let (d1?, d2?): return d1 > d2
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groupedByDate, id: \.0) { date, items in
                if let date {
                    Text(date, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    Text("Unknown date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                ForEach(items) { resource in
                    HStack {
                        Image(systemName: resource.kind.iconName)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(resource.filename)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text(resource.kind.rawValue)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                Divider()
            }
        }
        .padding(4)
    }
}
