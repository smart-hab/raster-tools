//
//  Workspace.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import SwiftData

// MARK: - Workspace

@Model
final class Workspace {
    var id: UUID
    var name: String
    var sourceDirectory: String
    @Relationship(deleteRule: .cascade) var resources: [WorkspaceResource]
    @Relationship(deleteRule: .cascade) var configurations: [ToolConfiguration]
    var createdAt: Date
    var modifiedAt: Date

    init(name: String, sourceDirectory: String) {
        self.id = UUID()
        self.name = name
        self.sourceDirectory = sourceDirectory
        self.resources = []
        self.configurations = []
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Workspace Resource

@Model
final class WorkspaceResource {
    var id: UUID
    var originalPath: String
    var filename: String
    var date: Date?
    var fileExtension: String
    var kind: ResourceKind
    var workspace: Workspace?

    // UDM companion — only non-nil for kind == .sourceRaster
    var udm: WorkspaceResource?

    // Provenance — children/parents for self-referential many-to-many
    var children: [WorkspaceResource]
    @Relationship(inverse: \WorkspaceResource.children) var parents: [WorkspaceResource]

    // Which config produced this resource (nil for source resources)
    var producedBy: ToolConfiguration?

    // File metadata
    var fileSize: Int = 0
    var pngPath: String? = nil

    init(originalPath: String, filename: String, date: Date?, fileExtension: String, kind: ResourceKind,
         fileSize: Int, pngPath: String? = nil) {
        self.id = UUID()
        self.originalPath = originalPath
        self.filename = filename
        self.date = date
        self.fileExtension = fileExtension
        self.kind = kind
        self.children = []
        self.parents = []
        self.fileSize = fileSize
        self.pngPath = pngPath
    }

    var formattedFileSize: String {
        guard fileSize > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    var displayLabel: String {
        if let date {
            return date.displayString
        }
        return filename
    }
}

// MARK: - Date Extension

extension Date {
    var displayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy MMMM d"
        return formatter.string(from: self)
    }
}
