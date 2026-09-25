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
    @Relationship(deleteRule: .cascade) var sentinel2Configurations: [ToolSentinel2Configuration]
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
        self.sentinel2Configurations = []
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    func refresh(context: ModelContext) {
        let scanned = ProjectScanner.scan(directory: sourceDirectory)

        var existingByPath: [String: ProjectResource] = [:]
        for resource in resources where resource.originalPath.hasPrefix(sourceDirectory) {
            existingByPath[resource.originalPath] = resource
        }

        let scannedPaths = Set(scanned.map { $0.originalPath })

        for (path, resource) in existingByPath where !scannedPaths.contains(path) {
            resources.removeAll { $0.id == resource.id }
            context.delete(resource)
        }

        for scannedResource in scanned {
            if existingByPath[scannedResource.originalPath] == nil {
                scannedResource.project = self
                context.insert(scannedResource)
                resources.append(scannedResource)
            } else if let existing = existingByPath[scannedResource.originalPath] {
                // Keep stored records in step with the scanner, so a change in how files are
                // classified or dated reaches resources that were registered earlier.
                if existing.kind != scannedResource.kind { existing.kind = scannedResource.kind }
                if existing.date != scannedResource.date { existing.date = scannedResource.date }

                if scannedResource.kind == .planet,
                   existing.udm == nil,
                   let scannedUDM = scannedResource.udm {
                    if let existingUDM = existingByPath[scannedUDM.originalPath] {
                        existing.udm = existingUDM
                    } else if resources.first(where: { $0.originalPath == scannedUDM.originalPath }) == nil {
                        scannedUDM.project = self
                        context.insert(scannedUDM)
                        resources.append(scannedUDM)
                        existing.udm = scannedUDM
                    }
                }
            }
        }

        modifiedAt = Date()
    }

    @discardableResult
    func importShapeFiles(from urls: [URL]) -> Bool {
        var didCopy = false
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ext == "shp" || ext == "geojson" else { continue }
            let destination = URL(fileURLWithPath: sourceDirectory).appending(path: url.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                didCopy = true
            } catch {
                print("Error copying shape file: \(error)")
            }
        }
        return didCopy
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
        let s = sentinel2Configurations.map { ($0 as any ToolConfiguration, SidebarSelection.sentinel2Configuration($0)) }
        return (k + p + c + s).sorted { $0.config.modifiedAt > $1.config.modifiedAt }
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

    // UDM companion — only non-nil for kind == .planet
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
    // TODO: raw value kept so existing stores still decode — replace with a data migration and
    // drop the alias.
    case planet = "sourceRaster" // composite.tif
    case sentinel      // *_13band.tif (stacked by s2_stack)
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
        case .planet:        return "Planet"
        case .sentinel:      return "Sentinel"
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
        case .planet:        return "photo"
        case .sentinel:      return "photo"
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
        case .planet:        return .blue
        case .sentinel:      return .pink
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

    /// Multi-band rasters straight from a provider — the inputs preprocessing accepts.
    static let sourceRasterKinds: [ResourceKind] = [.planet, .sentinel]

    /// Where each spectral band sits in a source raster. This is how preprocessing tells
    /// providers apart, so mixed-source projects can be processed in one run.
    var bandProfile: RasterBandProfile? {
        switch self {
        case .planet:
            // PlanetScope SuperDove 8-band SR; mask bands are UDM2 shadow and cloud.
            return RasterBandProfile(rgb: [6, 4, 2], red: 6, redEdge: 7, nir: 8, maskBands: [3, 6], outputTag: "")
        case .sentinel:
            // Positions in s2_stack's BAND_ORDER: B04 red, B05 red edge, B08 NIR. Mask bands are
            // MSK_CLASSI_B00's opaque-cloud and cirrus layers.
            // TODO: review B08 vs B8A (865 nm, closer to Planet's NIR band) for NDVI.
            return RasterBandProfile(rgb: [4, 3, 2], red: 4, redEdge: 5, nir: 8, maskBands: [1, 2], outputTag: "_s2")
        default:
            return nil
        }
    }
}

/// 1-based band positions for one provider's source rasters.
struct RasterBandProfile {
    let rgb: [Int]
    let red: Int
    let redEdge: Int
    let nir: Int
    /// Cloud-mask bands passed to `mask -b`.
    let maskBands: [Int]
    /// Appended to the date in output filenames, so same-day scenes from different providers
    /// don't collide.
    let outputTag: String
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

    /// `yyyyMMdd` in UTC — the date form used in source folder names and output filenames.
    static let compactUTCFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
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
