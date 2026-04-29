//
//  ToolCollectionConfiguration.swift
//  RasterTools
//
//  Created by Marek on 2026-03-24.
//

import Foundation
import SwiftData

@Model
final class ToolCollectionConfiguration: ToolConfiguration {
    var id: UUID
    var name: String
    var kind: ToolKind { .collection }
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

    var orderMemory: [String: String]

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
        self.orderMemory = [:]
    }

    func touch() {
        modifiedAt = Date()
    }

    func orderMemoryKey(for date: Date) -> String {
        let dateStr = Date.utcFormatter.string(from: date)
        let sf = shapeFile?.filename ?? ""
        return "\(sf)|\(itemType)|\(productBundle)|\(harmonized)|\(composite)|\(dateStr)"
    }

    func orderStatus(for date: Date) -> OrderMemoryStatus? {
        orderMemory[orderMemoryKey(for: date)].flatMap(OrderMemoryStatus.init)
    }
}
