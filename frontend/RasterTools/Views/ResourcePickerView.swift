//
//  ResourcePickerView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import SwiftUI
import SwiftData

struct ResourcePickerView: View {
    let workspace: Workspace
    let defaultKinds: Set<ResourceKind>
    let selectableKinds: Set<ResourceKind>
    @Binding var selection: [WorkspaceResource]
    var allowsMultiple: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var activeKinds: Set<ResourceKind> = []

    private var filteredResources: [WorkspaceResource] {
        workspace.resources.filter { resource in
            guard activeKinds.contains(resource.kind) else { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Kind toggle bar
            if selectableKinds.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectableKinds).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { kind in
                            Toggle(isOn: Binding(
                                get: { activeKinds.contains(kind) },
                                set: { on in
                                    if on { activeKinds.insert(kind) }
                                    else { activeKinds.remove(kind) }
                                }
                            )) {
                                Label(kind.displayName, systemImage: kind.iconName)
                                    .font(.caption)
                            }
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                Divider()
            }

            // Resource list
            if filteredResources.isEmpty {
                ContentUnavailableView(
                    "No Resources",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("No resources of the selected types found in this workspace.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredResources, id: \.id) { resource in
                        ResourcePickerRow(
                            resource: resource,
                            isSelected: selection.contains { $0.id == resource.id },
                            allowsMultiple: allowsMultiple
                        ) {
                            toggle(resource)
                            if !allowsMultiple { dismiss() }
                        }
                    }
                }
                .listStyle(.inset)
            }

            if allowsMultiple {
                Divider()

                HStack {
                    Text("\(selection.count) selected")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            activeKinds = defaultKinds
        }
    }

    private func toggle(_ resource: WorkspaceResource) {
        if allowsMultiple {
            if let idx = selection.firstIndex(where: { $0.id == resource.id }) {
                selection.remove(at: idx)
            } else {
                selection.append(resource)
            }
        } else {
            selection = [resource]
        }
    }
}

private struct ResourcePickerRow: View {
    let resource: WorkspaceResource
    let isSelected: Bool
    let allowsMultiple: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ResourceTableRow(
                icon: resource.kind.iconName,
                label: resource.displayLabel,
                fileSize: resource.formattedFileSize,
                badges: resource.tableBadges,
                isSelected: Optional(isSelected)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ResourceKind display name

extension ResourceKind {
    var displayName: String {
        switch self {
        case .sourceRaster: return "Source"
        case .udm: return "UDM"
        case .metadata: return "Metadata"
        case .shapeFile: return "Shape"
        case .clipped: return "Clipped"
        case .masked: return "Masked"
        case .ndvi: return "NDVI"
        case .ndci: return "NDCI"
        case .kmeansClassed: return "Classified"
        case .kmeansMean: return "Mean"
        case .kmeansDiff: return "Difference"
        case .output: return "Output"
        case .unknown: return "Unknown"
        }
    }
}
