//
//  ProjectDetailView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project

    @State private var showingNewConfigSheet = false
    @State private var sourceSortID: String = "date"
    @State private var sourceSortAscending: Bool = false
    @State private var outputSelection: Set<UUID> = []
    @State private var outputGalleryRequest: GalleryRequest?

    private static let outputKinds: Set<ResourceKind> = [.masked, .clipped, .ndvi, .ndci, .kmeansCenters, .kmeansClassed, .kmeansMean, .kmeansDiff, .unknown]

    private func resources(for kinds: Set<ResourceKind>, producedOnly: Bool = false) -> [ProjectResource] {
        project.resources
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
                TextField("Name", text: $project.name)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                LabeledContent("Source Dir") {
                    FolderPathButton(path: project.sourceDirectory)
                }
                LabeledContent("Output Dir") {
                    Button {
                        NSWorkspace.shared.open(AppStorage.outputDirectory(for: project))
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
                    Text("No shape files found. Drag/drop files here to add them to the source directory.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shapes, id: \.id) { resource in
                        ResourceTableRow(resource: resource)
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleShapeFileDrop(providers: providers)
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
                            options: TableSortOption<ProjectResource>.allCases,
                            activeSortID: $sourceSortID,
                            ascending: $sourceSortAscending
                        )
                    }
                    let activeSort = TableSortOption<ProjectResource>.allCases.first { $0.id == sourceSortID }
                    let sorted = allSources.sorted { a, b in
                        sourceSortAscending
                            ? (activeSort?.comparator(a, b) ?? false)
                            : (activeSort?.comparator(b, a) ?? false)
                    }
                    ForEach(sorted, id: \.id) { resource in
                        ResourceTableRow(resource: resource)
                    }
                }
            }

            // Outputs section
            let allOutputs = resources(for: ProjectDetailView.outputKinds, producedOnly: true)
            let outputKinds = Array(Set(allOutputs.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
            Section("Outputs") {
                ResourceTableView(
                    items: allOutputs,
                    itemID: \.id,
                    sortOptions: TableSortOption<ProjectResource>.allCases,
                    filterOptions: TableFilterOption<ProjectResource>.forKinds(outputKinds),
                    selectionActions: [
                        TableSelectionAction<ProjectResource>.gallery(request: $outputGalleryRequest),
                        TableSelectionAction<ProjectResource>.deleteOutput(context: modelContext, selectionIDs: $outputSelection)
                    ],
                    selection: $outputSelection,
                    initialSortOptionID: "kind",
                    initialSortAscending: true
                ) { resource, isSelected in
                    ResourceTableRow(resource: resource, isSelected: isSelected)
                }
                .sheet(item: $outputGalleryRequest) { request in
                    ResourceGallerySheet(items: request.items, initialIndex: request.initialIndex)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(project.name)
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
            ToolCreateSheet(defaultProject: project) { _ in
                showingNewConfigSheet = false
            }
        }
    }


    private func handleShapeFileDrop(providers: [NSItemProvider]) -> Bool {
        var didDrop = false
        
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                let fileExtension = url.pathExtension.lowercased()
                guard fileExtension == "geojson" || fileExtension == "shp" else { return }
                
                let filename = url.lastPathComponent
                let destinationPath = (project.sourceDirectory as NSString).appendingPathComponent(filename)
                let destinationURL = URL(fileURLWithPath: destinationPath)
                
                do {
                    // Copy the file to the source directory
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    didDrop = true
                    
                    // Refresh resources on the main thread
                    DispatchQueue.main.async {
                        refreshResources()
                    }
                } catch {
                    print("Error copying file: \(error)")
                }
            }
        }
        
        return didDrop
    }

    private func refreshResources() {
        let scanned = ProjectScanner.scan(directory: project.sourceDirectory)

        var existingByPath: [String: ProjectResource] = [:]
        for resource in project.resources where resource.originalPath.hasPrefix(project.sourceDirectory) {
            existingByPath[resource.originalPath] = resource
        }

        let scannedPaths = Set(scanned.map { $0.originalPath })

        for (path, resource) in existingByPath where !scannedPaths.contains(path) {
            project.resources.removeAll { $0.id == resource.id }
            modelContext.delete(resource)
        }

        for scannedResource in scanned {
            if existingByPath[scannedResource.originalPath] == nil {
                scannedResource.project = project
                modelContext.insert(scannedResource)
                project.resources.append(scannedResource)
            } else if let existing = existingByPath[scannedResource.originalPath],
                      scannedResource.kind == .sourceRaster,
                      existing.udm == nil,
                      let scannedUDM = scannedResource.udm {
                if let existingUDM = existingByPath[scannedUDM.originalPath] {
                    existing.udm = existingUDM
                } else if project.resources.first(where: { $0.originalPath == scannedUDM.originalPath }) == nil {
                    scannedUDM.project = project
                    modelContext.insert(scannedUDM)
                    project.resources.append(scannedUDM)
                    existing.udm = scannedUDM
                }
            }
        }

        project.modifiedAt = Date()
    }
}
