//
//  ToolPreprocessConfiguration.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import SwiftData

@Model
final class ToolPreprocessConfiguration: ToolConfiguration {
    var id: UUID
    var name: String
    var kind: ToolKind { .preprocess }
    var project: Project
    var createdAt: Date
    var modifiedAt: Date

    // Preprocess specific config
    var processes: [String] // Store as strings for SwiftData compatibility
    @Relationship var shapeFile: ProjectResource?
    @Relationship var files: [ProjectResource]

    init(name: String, project: Project) {
        self.id = UUID()
        self.name = name
        self.project = project
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.processes = [ResourceKind.ndci.rawValue, ResourceKind.ndvi.rawValue]
        self.shapeFile = nil
        self.files = []
    }

    func touch() {
        modifiedAt = Date()
    }

    var processTypes: [ResourceKind] {
        get { processes.compactMap { ResourceKind(rawValue: $0) } }
        set { processes = newValue.map { $0.rawValue } }
    }
}
