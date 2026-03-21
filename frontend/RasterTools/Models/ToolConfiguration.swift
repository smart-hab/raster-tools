//
//  ToolConfiguration.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import SwiftData

enum ToolType: String, Codable, CaseIterable {
    case kmeans = "K-Means Clustering"
    case preprocess = "Preprocess"

    var iconName: String {
        switch self {
        case .kmeans: return "circle.hexagongrid.fill"
        case .preprocess: return "wand.and.stars"
        }
    }
}

enum PreprocessType: String, Codable, CaseIterable {
    case ndci = "NDCI"
    case ndvi = "NDVI"
}

enum ResourceKind: String, Codable {
    case sourceRaster  // composite.tif
    case udm           // composite_udm2.tif
    case metadata      // composite_metadata.json
    case shapeFile     // .geojson / .shp
    case clipped       // *_clipped.tif (generated)
    case masked        // *_clipped_masked.tif (generated)
    case ndvi          // generated NDVI
    case ndci          // generated NDCI
    case kmeansClassed // *_classed.tif (k-means classification)
    case kmeansMean    // *_mean.tif (k-means mean raster)
    case kmeansDiff    // *_mean_diff_*.tif (k-means difference raster)
    case output        // other generated output files
    case unknown

    var iconName: String {
        switch self {
        case .sourceRaster:  return "photo.fill"
        case .udm:           return "cloud.fill"
        case .metadata:      return "doc.text.fill"
        case .shapeFile:     return "map.fill"
        case .clipped:       return "crop"
        case .masked:        return "sparkles"
        case .ndvi:          return "leaf.fill"
        case .ndci:          return "drop.fill"
        case .kmeansClassed: return "circle.hexagongrid.fill"
        case .kmeansMean:    return "chart.bar.xaxis"
        case .kmeansDiff:    return "plusminus"
        case .output:        return "square.and.arrow.down.fill"
        case .unknown:       return "questionmark.square.fill"
        }
    }
}

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

// MARK: - WorkspaceResource

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
            return date.formatted(.dateTime.month(.wide).day().year())
        }
        return filename
    }
}

// MARK: - Main Configuration

@Model
final class ToolConfiguration {
    var id: UUID
    var name: String
    var toolType: ToolType
    var workspace: Workspace?
    var createdAt: Date
    var modifiedAt: Date

    // K-Means specific properties
    var kmeansConfig: KMeansConfiguration?

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
            self.kmeansConfig = KMeansConfiguration()
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
final class KMeansConfiguration {
    var centersFile: String
    var centroids: Int
    var nTimes: Int
    var seed: Int
    @Relationship var filesFit: [WorkspaceResource]
    @Relationship var filesClassify: [WorkspaceResource]

    init(centersFile: String = "centers.txt",
         centroids: Int = 6,
         nTimes: Int = 10,
         seed: Int = 42,
         filesFit: [WorkspaceResource] = [],
         filesClassify: [WorkspaceResource] = []) {
        self.centersFile = centersFile
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
         processes: [PreprocessType] = [.ndci, .ndvi],
         files: [WorkspaceResource] = []) {
        self.shapeFile = shapeFile
        self.processes = processes.map { $0.rawValue }
        self.files = files
    }

    var processTypes: [PreprocessType] {
        get { processes.compactMap { PreprocessType(rawValue: $0) } }
        set { processes = newValue.map { $0.rawValue } }
    }
}
