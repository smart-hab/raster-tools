//
//  ResourceGallerySheet.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import SwiftUI

struct GalleryRequest: Identifiable {
    let id = UUID()
    let items: [WorkspaceResource]
    let initialIndex: Int
}

struct ResourceGallerySheet: View {
    @Environment(\.dismiss) private var dismiss
    let items: [WorkspaceResource]
    let initialIndex: Int

    @State private var currentIndex: Int

    init(items: [WorkspaceResource], initialIndex: Int = 0) {
        self.items = items
        self.initialIndex = initialIndex
        self._currentIndex = State(initialValue: initialIndex)
    }

    private var current: WorkspaceResource? {
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
        } else if let text = current?.textContent {
            ScrollView([.vertical, .horizontal]) {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
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
                Text(current?.date?.displayString ?? "Unknown")
                    .font(.headline)
                Spacer()
                ForEach(current?.tableBadges ?? [], id: \.self) { kind in
                    BadgeCapsule(kind: kind)
                }
                let fileSize = current?.formattedFileSize ?? ""
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
    private func thumbnailView(for item: WorkspaceResource, index: Int) -> some View {
        let isActive = index == currentIndex
        Group {
            if let path = item.pngPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipped()
            } else if item.isTextPreviewable {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 64)
                    .background(Color.secondary.opacity(0.1))
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
