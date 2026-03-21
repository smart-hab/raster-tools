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
    let badges: [String]
    var pngPath: String? = nil
    var originalPath: String? = nil
    var onDelete: (() -> Void)? = nil
    var isSelected: Bool? = nil

    @State private var showingPreview = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .onTapGesture {
                    if pngPath != nil { showingPreview = true }
                }

            Text(label)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 4) {
                ForEach(badges, id: \.self) { badge in
                    BadgeCapsule(label: badge)
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
        .sheet(isPresented: $showingPreview) {
            if let path = pngPath {
                PNGPreviewSheet(
                    pngPath: path,
                    filename: label,
                    fileSize: fileSize,
                    badges: badges,
                    originalPath: originalPath,
                    onDelete: onDelete
                )
            }
        }
    }
}

// MARK: - PNG Preview Sheet

struct PNGPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pngPath: String
    var filename: String = ""
    var fileSize: String = ""
    var badges: [String] = []
    var originalPath: String? = nil
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
                if !filename.isEmpty {
                    Text(filename)
                        .font(.headline)
                }

                HStack(spacing: 8) {
                    if !fileSize.isEmpty {
                        Text(fileSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        ForEach(badges, id: \.self) { badge in
                            BadgeCapsule(label: badge)
                        }
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    let path = originalPath ?? pngPath
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: path)]
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

// MARK: - WorkspaceResource badges

extension WorkspaceResource {
    var tableBadges: [String] {
        switch kind {
        case .sourceRaster: return ["source"] + (udm != nil ? ["udm2"] : [])
        case .shapeFile:    return ["shape"]
        case .clipped:      return ["clipped"]
        case .masked:       return ["masked"]
        case .ndci:          return ["ndci"]
        case .ndvi:          return ["ndvi"]
        case .kmeansClassed: return ["classified"]
        case .kmeansMean:    return ["mean"]
        case .kmeansDiff:    return ["difference"]
        case .output, .unknown:
            return [producedBy?.toolType.rawValue.lowercased() ?? kind.rawValue]
        default:            return [kind.rawValue]
        }
    }
}
