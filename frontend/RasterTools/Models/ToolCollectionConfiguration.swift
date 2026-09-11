//
//  ToolCollectionConfiguration.swift
//  RasterTools
//
//  Created by Marek on 2026-03-24.
//

import Foundation
import SwiftData

/// The Planet collector's configuration.
///
/// The class name predates the Sentinel-2 collector and is kept deliberately: it is the
/// persisted SwiftData entity name, and renaming it would require a custom migration stage for
/// no behavioural gain. Everything user-facing says "Planet"; see `ToolSentinel2Configuration`
/// for the other provider.
@Model
final class ToolCollectionConfiguration: ToolConfiguration {
    var id: UUID
    var name: String
    var kind: ToolKind { .collectionPlanet }
    var project: Project
    var createdAt: Date
    var modifiedAt: Date

    // Collection specific config
    @Relationship var shapeFile: ProjectResource?
    var searchStartDate: Date
    var searchEndDate: Date
    var cloudCover: Double

    var namingPattern: String
    var itemType: String
    var productBundle: String
    var harmonized: Bool
    var composite: Bool

    var orderEntries: [String: OrderMemoryEntry]

    init(name: String, project: Project) {
        self.id = UUID()
        self.name = name
        self.project = project
        self.createdAt = Date()
        self.modifiedAt = Date()

        let now = Date()
        let monthStart = Date.utcCalendar.date(from: Date.utcCalendar.dateComponents([.year, .month], from: now))!
        let monthEnd = Date.utcCalendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!

        self.shapeFile = nil
        self.searchStartDate = monthStart
        self.searchEndDate = monthEnd
        self.cloudCover = 0.2
        self.namingPattern = "{ConfigName}-{Year}{Month}{Day}-{Parameters}"
        self.itemType = PlanetItemType.psScene.rawValue
        self.productBundle = PlanetProductBundle.analytic8bSrUdm2.rawValue
        self.harmonized = true
        self.composite = true
        self.orderEntries = [:]
    }

    func touch() {
        modifiedAt = Date()
    }

    func orderMemoryKey(for date: Date) -> String {
        let dateStr = Date.utcFormatter.string(from: date)
        let sf = shapeFile?.filename ?? ""
        return "\(sf)|\(itemType)|\(productBundle)|\(harmonized)|\(composite)|\(dateStr)"
    }

    func orderEntry(for date: Date) -> OrderMemoryEntry? {
        orderEntries[orderMemoryKey(for: date)]
    }

    func setOrderEntry(_ entry: OrderMemoryEntry, for date: Date) {
        orderEntries[orderMemoryKey(for: date)] = entry
    }

    func removeOrderEntry(for date: Date) {
        orderEntries.removeValue(forKey: orderMemoryKey(for: date))
    }

    func orderStatus(for date: Date) -> OrderMemoryStatus? {
        orderEntry(for: date)?.status
    }
}

struct OrderMemoryEntry: Codable {
    var status: OrderMemoryStatus
    var orderId: String?
}
