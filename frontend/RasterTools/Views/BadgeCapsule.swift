//
//  BadgeCapsule.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI

struct BadgeCapsule: View {
    let kind: ResourceKind

    var body: some View {
        Text(kind.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(kind.color.opacity(0.15), in: Capsule())
            .foregroundStyle(kind.color)
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
