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
                    project.refresh(context: modelContext)
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
        let group = DispatchGroup()
        var urls: [URL] = []
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            if project.importShapeFiles(from: urls) {
                project.refresh(context: modelContext)
            }
        }
        return true
    }
}
