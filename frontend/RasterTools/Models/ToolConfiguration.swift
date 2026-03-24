//
//  ToolConfiguration.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import SwiftData

// MARK: - Tool Type Enumeration

enum ToolType: String, Codable, CaseIterable {
    case kmeans = "K-Means Clustering"
    case preprocess = "Preprocess"

    var iconName: String {
        switch self {
        case .kmeans: return "circle.hexagongrid.fill"
        case .preprocess: return "wand.and.rays"
        }
    }
}

// MARK: - Tool Configuration (Base Model)

@Model
final class ToolConfiguration {
    var id: UUID
    var name: String
    var toolType: ToolType
    var workspace: Workspace?
    var createdAt: Date
    var modifiedAt: Date

    // K-Means specific properties
    var kmeansConfig: KmeansConfiguration?

    // Preprocess specific properties
    var preprocessConfig: PreprocessConfiguration?

    init(name: String, toolType: ToolType, workspace: Workspace) {
        self.id = UUID()
        self.name = name
        self.toolType = toolType
        self.workspace = workspace
        self.createdAt = Date()
        self.modifiedAt = Date()

        // Initialize the appropriate config
        switch toolType {
        case .kmeans:
            self.kmeansConfig = KmeansConfiguration()
        case .preprocess:
            self.preprocessConfig = PreprocessConfiguration()
        }
    }

    func touch() {
        modifiedAt = Date()
    }
}

// MARK: - K-Means Configuration

@Model
final class KmeansConfiguration {
    var centroids: Int
    var nTimes: Int
    var seed: Int
    @Relationship var filesFit: [WorkspaceResource]
    @Relationship var filesClassify: [WorkspaceResource]

    init(centroids: Int = 6,
         nTimes: Int = 10,
         seed: Int = 42,
         filesFit: [WorkspaceResource] = [],
         filesClassify: [WorkspaceResource] = []) {
        self.centroids = centroids
        self.nTimes = nTimes
        self.seed = seed
        self.filesFit = filesFit
        self.filesClassify = filesClassify
    }
}

// MARK: - Preprocess Configuration

@Model
final class PreprocessConfiguration {
    var processes: [String] // Store as strings for SwiftData compatibility
    @Relationship var shapeFile: WorkspaceResource?
    @Relationship var files: [WorkspaceResource]

    init(shapeFile: WorkspaceResource? = nil,
         processes: [ResourceKind] = [.ndci, .ndvi],
         files: [WorkspaceResource] = []) {
        self.shapeFile = shapeFile
        self.processes = processes.map { $0.rawValue }
        self.files = files
    }

    var processTypes: [ResourceKind] {
        get { processes.compactMap { ResourceKind(rawValue: $0) } }
        set { processes = newValue.map { $0.rawValue } }
    }
}
