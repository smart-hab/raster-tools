//
//  ToolConfiguration.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import SwiftData

// MARK: - Collection Configuration helpers (non-model types)

private extension Calendar {
    static var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }
}

// MARK: - Tool Type Enumeration

enum ToolType: String, Codable, CaseIterable {
    case kmeans = "K-Means Clustering"
    case preprocess = "Preprocess"
    case collection = "Collection"

    var iconName: String {
        switch self {
        case .kmeans: return "circle.hexagongrid.fill"
        case .preprocess: return "wand.and.rays"
        case .collection: return "square.and.arrow.down.on.square"
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

    // Collection specific properties
    var collectionConfig: CollectionConfiguration?

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
        case .collection:
            self.collectionConfig = CollectionConfiguration()
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

// MARK: - Collection Configuration

@Model
final class CollectionConfiguration {
    // Search params
    @Relationship var shapeFile: WorkspaceResource?
    var searchStartDate: Date
    var searchEndDate: Date
    var cloudCover: Double

    // Order params
    var namingPattern: String
    var itemType: String
    var productBundle: String
    var harmonized: Bool
    var composite: Bool

    // Order memory: key → OrderMemoryStatus.rawValue
    var orderMemory: [String: String]

    init() {
        let calendar = Calendar.utc
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!

        self.shapeFile = nil
        self.searchStartDate = monthStart
        self.searchEndDate = monthEnd
        self.cloudCover = 0.2
        self.namingPattern = "{ConfigName}-{Year}{Month}{Day}-{Parameters}"
        self.itemType = PlanetItemType.psScene.rawValue
        self.productBundle = PlanetProductBundle.analytic8bSrUdm2.rawValue
        self.harmonized = true
        self.composite = true
        self.orderMemory = [:]
    }

    func orderMemoryKey(for date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: date)
        let sf = shapeFile?.filename ?? ""
        return "\(sf)|\(itemType)|\(productBundle)|\(harmonized)|\(composite)|\(dateStr)"
    }

    func orderStatus(for date: Date) -> OrderMemoryStatus? {
        orderMemory[orderMemoryKey(for: date)].flatMap(OrderMemoryStatus.init)
    }
}
