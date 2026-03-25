//
//  BadgeCapsule.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI

struct BadgeCapsule: View {
    let label: String
    let color: Color

    init(kind: ResourceKind) {
        self.label = kind.displayName
        self.color = kind.color
    }

    init(label: String, color: Color) {
        self.label = label
        self.color = color
    }

    var body: some View {
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}


// MARK: - Folder Path Button

struct FolderPathButton: View {
    let path: String

    var body: some View {
        Button {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Text(path)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}


// MARK: - Click Handler (left + right)

struct MouseClickView: NSViewRepresentable {
    let onLeftClick: () -> Void
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> ClickableNSView {
        let view = ClickableNSView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: ClickableNSView, context: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
    }
}

class ClickableNSView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onLeftClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}
