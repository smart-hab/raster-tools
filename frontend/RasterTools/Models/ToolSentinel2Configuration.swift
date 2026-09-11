//
//  ToolSentinel2Configuration.swift
//  RasterTools
//
//  Created by Marek on 2026-09-02.
//

import Foundation
import SwiftData

/// The Sentinel-2 counterpart to `ToolCollectionConfiguration`.
///
/// It carries the same AOI/date/cloud search parameters, but no ordering fields: CDSE products
/// are downloadable the moment they are found, so there is no queue, no order id, and no remote
/// order lifecycle to track. `downloadEntries` is the direct analogue of Planet's `orderEntries`.
@Model
final class ToolSentinel2Configuration: ToolConfiguration {
    var id: UUID
    var name: String
    var kind: ToolKind { .collectionSentinel2 }
    var project: Project
    var createdAt: Date
    var modifiedAt: Date

    // Sentinel-2 specific config
    @Relationship var shapeFile: ProjectResource?
    var searchStartDate: Date
    var searchEndDate: Date
    var cloudCover: Double

    var namingPattern: String

    /// Stored rather than hard-coded so L2A can be offered later without a schema change.
    /// L1C is the only supported level today — atmospheric correction drops B10 from L2A.
    var productType: String

    var downloadEntries: [String: DownloadMemoryEntry]

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
        self.productType = Sentinel2ProductType.l1c.rawValue
        self.downloadEntries = [:]
    }

    func touch() {
        modifiedAt = Date()
    }

    /// Memory is keyed by the parameters that determine *what* would be downloaded, so changing
    /// the AOI or product level correctly presents a day as not-yet-downloaded.
    func downloadMemoryKey(for date: Date) -> String {
        let dateStr = Date.utcFormatter.string(from: date)
        let sf = shapeFile?.filename ?? ""
        return "\(sf)|\(productType)|\(dateStr)"
    }

    func downloadEntry(for date: Date) -> DownloadMemoryEntry? {
        downloadEntries[downloadMemoryKey(for: date)]
    }

    func setDownloadEntry(_ entry: DownloadMemoryEntry, for date: Date) {
        downloadEntries[downloadMemoryKey(for: date)] = entry
    }

    func removeDownloadEntry(for date: Date) {
        downloadEntries.removeValue(forKey: downloadMemoryKey(for: date))
    }

    func downloadStatus(for date: Date) -> DownloadMemoryStatus? {
        downloadEntry(for: date)?.status
    }
}

struct DownloadMemoryEntry: Codable {
    var status: DownloadMemoryStatus
    var productId: String
    var productName: String
    var sensingDate: Date
    var cloudCover: Double
    var fileSize: Int
    /// Where the extracted product landed, once it has. Nil while downloading or after a failure.
    var localPath: String?
}
