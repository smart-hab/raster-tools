//
//  Project.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Project

@Model
final class Project {
    var id: UUID
    var name: String
    var sourceDirectory: String
    @Relationship(deleteRule: .cascade) var resources: [ProjectResource]
    @Relationship(deleteRule: .cascade) var kmeansConfigurations: [ToolKmeansConfiguration]
    @Relationship(deleteRule: .cascade) var preprocessConfigurations: [ToolPreprocessConfiguration]
    @Relationship(deleteRule: .cascade) var collectionConfigurations: [ToolCollectionConfiguration]
    var createdAt: Date
    var modifiedAt: Date

    init(name: String, sourceDirectory: String) {
        self.id = UUID()
        self.name = name
        self.sourceDirectory = sourceDirectory
        self.resources = []
        self.kmeansConfigurations = []
        self.preprocessConfigurations = []
        self.collectionConfigurations = []
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    static func create(name: String, sourceDirectory: String) -> Project {
        let project = Project(name: name, sourceDirectory: sourceDirectory)
        let scanned = ProjectScanner.scan(directory: sourceDirectory)
        for resource in scanned {
            resource.project = project
            project.resources.append(resource)
        }
        return project
    }

    var allConfigurations: [(config: any ToolConfiguration, selection: SidebarSelection)] {
        let k = kmeansConfigurations.map { ($0 as any ToolConfiguration, SidebarSelection.kmeansConfiguration($0)) }
        let p = preprocessConfigurations.map { ($0 as any ToolConfiguration, SidebarSelection.preprocessConfiguration($0)) }
        let c = collectionConfigurations.map { ($0 as any ToolConfiguration, SidebarSelection.collectionConfiguration($0)) }
        return (k + p + c).sorted { $0.config.modifiedAt > $1.config.modifiedAt }
    }
}

// MARK: - Project   Resource

@Model
final class ProjectResource {
    var id: UUID
    var originalPath: String
    var filename: String
    var date: Date?
    var fileExtension: String
    var kind: ResourceKind
    var project: Project?

    // UDM companion — only non-nil for kind == .sourceRaster
    var udm: ProjectResource?

    // Provenance — children/parents for self-referential many-to-many
    var children: [ProjectResource]
    @Relationship(inverse: \ProjectResource.children) var parents: [ProjectResource]

    // Which config produced this resource (nil for source resources)
    var producedByConfigId: UUID?

    // File metadata
    var fileSize: Int = 0
    var pngPath: String? = nil

    init(originalPath: String, filename: String, date: Date?, fileExtension: String, kind: ResourceKind,
         fileSize: Int, pngPath: String? = nil,
         parents: [ProjectResource] = [], producedByConfigId: UUID? = nil, project: Project? = nil) {
        self.id = UUID()
        self.originalPath = originalPath
        self.filename = filename
        self.date = date
        self.fileExtension = fileExtension
        self.kind = kind
        self.children = []
        self.parents = parents
        self.fileSize = fileSize
        self.pngPath = pngPath
        self.producedByConfigId = producedByConfigId
        self.project = project
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

// MARK: - Resource Kind

enum ResourceKind: String, Codable {
    case sourceRaster  // composite.tif
    case udm           // composite_udm2.tif
    case metadata      // composite_metadata.json
    case shapeFile     // .geojson / .shp
    case clipped       // *_clipped.tif (generated)
    case masked        // *_clipped_masked.tif (generated)
    case ndvi          // generated NDVI
    case ndci          // generated NDCI
    case kmeansCenters // centers.txt (k-means fitted model)
    case kmeansClassed // *_classed.tif (k-means classification)
    case kmeansMean    // mean.tif (k-means mean raster)
    case kmeansDiff    // mean_diff_*.tif (k-means difference raster)
    case unknown

    var displayName: String {
        switch self {
        case .sourceRaster:  return "Source"
        case .udm:           return "UDM2"
        case .metadata:      return "Metadata"
        case .shapeFile:     return "Shape"
        case .clipped:       return "Clipped"
        case .masked:        return "Masked"
        case .ndvi:          return "NDVI"
        case .ndci:          return "NDCI"
        case .kmeansCenters: return "Centers"
        case .kmeansClassed: return "Classed"
        case .kmeansMean:    return "Mean"
        case .kmeansDiff:    return "Diff"
        case .unknown:       return "Unknown"
        }
    }

    var iconName: String {
        switch self {
        case .sourceRaster:  return "photo"
        case .udm:           return "cloud.fill"
        case .metadata:      return "doc.text.fill"
        case .shapeFile:     return "globe.europe.africa.fill"
        case .clipped:       return "crop"
        case .masked:        return "rectangle.pattern.checkered"
        case .ndvi:          return "leaf.fill"
        case .ndci:          return "drop.fill"
        case .kmeansCenters: return "target"
        case .kmeansClassed: return "circle.hexagongrid.fill"
        case .kmeansMean:    return "square.3.layers.3d"
        case .kmeansDiff:    return "plus.forwardslash.minus"
        case .unknown:       return "questionmark.square.fill"
        }
    }

    var color: Color {
        switch self {
        case .sourceRaster:  return .secondary
        case .udm:           return .yellow
        case .metadata:      return .secondary
        case .shapeFile:     return .brown
        case .clipped:       return .orange
        case .masked:        return .red
        case .ndvi:          return .green
        case .ndci:          return .teal
        case .kmeansCenters: return .secondary
        case .kmeansClassed: return .indigo
        case .kmeansMean:    return .secondary
        case .kmeansDiff:    return .purple
        case .unknown:       return .secondary
        }
    }
}

// MARK: - Date Extension

extension Date {
    var displayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy MMMM d"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: self)
    }

    var isoString: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(identifier: "UTC")
        return iso.string(from: self)
    }

    static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
