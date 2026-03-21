//
//  OutputResourceRow.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import SwiftUI
import SwiftData

// MARK: - Grouping helper

func groupOutputsByKind(_ outputs: [WorkspaceResource]) -> [(kind: ResourceKind, resources: [WorkspaceResource])] {
    let sorted = outputs.sorted {
        switch ($0.date, $1.date) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case let (d1?, d2?): return d1 > d2
        }
    }
    var groups: [(kind: ResourceKind, resources: [WorkspaceResource])] = []
    var seen: Set<ResourceKind> = []
    for resource in sorted {
        if !seen.contains(resource.kind) {
            seen.insert(resource.kind)
            groups.append((kind: resource.kind, resources: []))
        }
        let idx = groups.firstIndex { $0.kind == resource.kind }!
        groups[idx].resources.append(resource)
    }
    return groups
}

// MARK: - Delete helper

func deleteOutputResource(_ resource: WorkspaceResource, context: ModelContext) {
    try? FileManager.default.removeItem(atPath: resource.originalPath)
    if let pngPath = resource.pngPath {
        try? FileManager.default.removeItem(atPath: pngPath)
    }
    resource.workspace?.resources.removeAll { $0.id == resource.id }
    context.delete(resource)
}

// MARK: - Output Resource Row

struct OutputResourceRow: View {
    let resource: WorkspaceResource
    let onDelete: () -> Void

    @State private var showingPreview = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: resource.kind.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(resource.displayLabel)
                HStack(spacing: 4) {
                    Text(resource.filename)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if !resource.formattedFileSize.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(resource.formattedFileSize)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if resource.pngPath != nil {
                Button {
                    showingPreview = true
                } label: {
                    Image(systemName: "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingPreview) {
                    if let pngPath = resource.pngPath {
                        PNGPreviewView(resource: resource, pngPath: pngPath, onDelete: onDelete)
                    }
                }
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - PNG Preview

struct PNGPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let resource: WorkspaceResource
    let pngPath: String
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let image = NSImage(contentsOfFile: pngPath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Preview not available")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            metadataFooter
        }
        .frame(minWidth: 500, minHeight: 400)
        .overlay {
            Button("") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
        }
    }

    private var metadataFooter: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(URL(fileURLWithPath: resource.originalPath).lastPathComponent)
                    .font(.headline)

                HStack(spacing: 8) {
                    if let date = resource.date {
                        Text(date.formatted(.dateTime.month(.wide).day().year()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !resource.formattedFileSize.isEmpty {
                        Text(resource.formattedFileSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        ForEach(resource.tableBadges, id: \.self) { badge in
                            BadgeCapsule(label: badge)
                        }
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: resource.originalPath)]
                    )
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .help("Reveal in Finder")

                if let onDelete {
                    Button(role: .destructive) {
                        dismiss()
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .help("Delete")
                }
            }
        }
        .padding()
    }
}
