//
//  ToolKmeansConfiguration.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import SwiftData

@Model
final class ToolKmeansConfiguration: ToolConfiguration {
    var id: UUID
    var name: String
    var kind: ToolKind { .kmeans }
    var workspace: Workspace
    var createdAt: Date
    var modifiedAt: Date

    // K-Means specific config
    var centroids: Int
    var nTimes: Int
    var seed: Int
    @Relationship var filesFit: [WorkspaceResource]
    @Relationship var filesClassify: [WorkspaceResource]

    init(name: String, workspace: Workspace) {
        self.id = UUID()
        self.name = name
        self.workspace = workspace
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.centroids = 6
        self.nTimes = 10
        self.seed = 42
        self.filesFit = []
        self.filesClassify = []
    }

    func touch() {
        modifiedAt = Date()
    }
}
