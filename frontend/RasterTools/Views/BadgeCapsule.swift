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
