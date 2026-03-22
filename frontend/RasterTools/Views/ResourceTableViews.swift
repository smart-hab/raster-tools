//
//  ResourceTableViews.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import SwiftUI

// MARK: - Resource Table Row

struct ResourceTableRow: View {
    let icon: String
    let label: String
    let fileSize: String
    let badges: [ResourceKind]
    var pngPath: String? = nil
    var originalPath: String? = nil
    var onDelete: (() -> Void)? = nil
    var isSelected: Bool? = nil
    var onPreview: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .onTapGesture {
                    if pngPath != nil { onPreview?() }
                }

            Text(label)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 4) {
                ForEach(badges, id: \.self) { kind in
                    BadgeCapsule(kind: kind)
                }
            }

            Text(fileSize)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .trailing)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else if let isSelected {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Image Gallery Sheet

struct GalleryItem {
    var pngPath: String?
    var filename: String
    var date: String?
    var fileSize: String
    var badges: [ResourceKind]
    var originalPath: String?

    init(_ resource: WorkspaceResource) {
        self.pngPath = resource.pngPath
        self.filename = resource.filename
        self.date = resource.date?.displayString
        self.fileSize = resource.formattedFileSize
        self.badges = resource.tableBadges
        self.originalPath = resource.originalPath
    }
}

struct GalleryRequest: Identifiable {
    let id = UUID()
    let items: [GalleryItem]
    let initialIndex: Int
}

struct ImageGallerySheet: View {
    @Environment(\.dismiss) private var dismiss
    let items: [GalleryItem]
    let initialIndex: Int

    @State private var currentIndex: Int

    init(items: [GalleryItem], initialIndex: Int = 0) {
        self.items = items
        self.initialIndex = initialIndex
        self._currentIndex = State(initialValue: initialIndex)
    }

    private var current: GalleryItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left panel: big image + metadata footer
            VStack(spacing: 0) {
                imageView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                metadataFooter
            }

            Divider()

            // Right sidebar: thumbnail strip
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            thumbnailView(for: item, index: index)
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .frame(width: 88)
                .onChange(of: currentIndex) { _, newIndex in
                    withAnimation {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 450)
        .overlay {
            Button("") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { navigatePrevious(); return .handled }
        .onKeyPress(.upArrow) { navigatePrevious(); return .handled }
        .onKeyPress(.rightArrow) { navigateNext(); return .handled }
        .onKeyPress(.downArrow) { navigateNext(); return .handled }
    }

    @ViewBuilder
    private var imageView: some View {
        if let path = current?.pngPath, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Preview not available")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metadataFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(current?.date ?? "Unknown")
                    .font(.headline)
                Spacer()
                ForEach(current?.badges ?? [], id: \.self) { kind in
                    BadgeCapsule(kind: kind)
                }
                let fileSize = current?.fileSize ?? ""
                if !fileSize.isEmpty {
                    Text(fileSize)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(current?.filename ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 8) {
                if let revealPath = current?.originalPath ?? current?.pngPath {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: revealPath)]
                        )
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .focusEffectDisabled()
                }
                Spacer()
            }
        }
        .padding()
    }

    @ViewBuilder
    private func thumbnailView(for item: GalleryItem, index: Int) -> some View {
        let isActive = index == currentIndex
        Group {
            if let path = item.pngPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipped()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 64)
                    .background(Color.secondary.opacity(0.1))
            }
        }
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onTapGesture { currentIndex = index }
    }

    private func navigatePrevious() {
        guard !items.isEmpty else { return }
        currentIndex = (currentIndex - 1 + items.count) % items.count
    }

    private func navigateNext() {
        guard !items.isEmpty else { return }
        currentIndex = (currentIndex + 1) % items.count
    }
}

// MARK: - Selection label

func selectionLabel(_ count: Int, bytes: Int) -> String {
    guard count > 0, bytes > 0 else { return "\(count) selected" }
    let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    return "\(count) selected (\(size))"
}

// MARK: - Resource Section Content

/// Encapsulates the repeated filter bar + grouped rows + action bar pattern used across
/// raster input sections and output sections in config and workspace views.
struct ResourceSectionContent: View {
    let resources: [WorkspaceResource]
    /// Pass the full kind list to show a filter bar; nil hides it.
    let filterKinds: [ResourceKind]?
    @Binding var activeKinds: Set<ResourceKind>
    @Binding var sortKey: OutputSortKey
    @Binding var sortAscending: Bool
    @Binding var selection: Set<UUID>
    var rowLabel: (WorkspaceResource) -> String = { $0.displayLabel }
    var onAdd: (() -> Void)? = nil
    var onDeleteSelected: ((Set<UUID>) -> Void)? = nil

    @State private var galleryRequest: GalleryRequest? = nil

    private var visibleResources: [WorkspaceResource] {
        guard let filterKinds, filterKinds.count > 1 else { return resources }
        return resources.filter { activeKinds.contains($0.kind) }
    }

    var body: some View {
        let visibleIDs = Set(visibleResources.map(\.id))
        let selectionBytes = resources.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.fileSize }
        let groups = groupedOutputs(visibleResources, sortKey: sortKey, ascending: sortAscending)
        let orderedResources = groups.flatMap(\.resources)

        VStack(spacing: 0) {
            if !resources.isEmpty {
                HStack {
                    if let filterKinds, filterKinds.count > 1 {
                        ResourceFilterBar(kinds: filterKinds, activeKinds: $activeKinds)
                            .onAppear {
                                if activeKinds.isEmpty { activeKinds = Set(filterKinds) }
                            }
                            .onChange(of: filterKinds) { _, newKinds in
                                activeKinds.formUnion(Set(newKinds).subtracting(activeKinds))
                            }
                    }
                    Spacer()
                    OutputSortBar(sortKey: $sortKey, ascending: $sortAscending)
                }
                ForEach(groups, id: \.groupLabel) { group in
                    if let label = group.groupLabel, group.resources.count > 1 {
                        Text(label).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(group.resources, id: \.id) { resource in
                        ResourceTableRow(
                            icon: resource.kind.iconName,
                            label: rowLabel(resource),
                            fileSize: resource.formattedFileSize,
                            badges: resource.tableBadges,
                            pngPath: resource.pngPath,
                            originalPath: resource.originalPath,
                            isSelected: selection.contains(resource.id),
                            onPreview: {
                                galleryRequest = GalleryRequest(items: [GalleryItem(resource)], initialIndex: 0)
                            }
                        )
                        .onTapGesture {
                            if selection.contains(resource.id) {
                                selection.remove(resource.id)
                            } else {
                                selection.insert(resource.id)
                            }
                        }
                    }
                }
            }

            HStack {
                if let onAdd {
                    Button { onAdd() } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(selectionLabel(selection.count, bytes: selectionBytes))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                let selectedWithPNG = orderedResources.filter { selection.contains($0.id) && $0.pngPath != nil }
                Button {
                    let items = orderedResources.filter { selection.contains($0.id) }.map { GalleryItem($0) }
                    galleryRequest = GalleryRequest(items: items, initialIndex: 0)
                } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.plain)
                .disabled(selectedWithPNG.isEmpty)
                Button {
                    onDeleteSelected?(selection)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(selection.isEmpty)
                Button {
                    if visibleIDs.isSubset(of: selection) {
                        selection.subtract(visibleIDs)
                    } else {
                        selection.formUnion(visibleIDs)
                    }
                } label: {
                    Image(systemName: visibleIDs.isSubset(of: selection) ? "minus.circle" : "checkmark.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $galleryRequest) { request in
            ImageGallerySheet(items: request.items, initialIndex: request.initialIndex)
        }
    }
}

// MARK: - WorkspaceResource badges

extension WorkspaceResource {
    var tableBadges: [ResourceKind] {
        switch kind {
        case .sourceRaster: return [.sourceRaster] + (udm != nil ? [.udm] : [])
        default:            return [kind]
        }
    }
}
