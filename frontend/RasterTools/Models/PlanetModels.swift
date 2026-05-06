//
//  PlanetModels.swift
//  RasterTools
//
//  Created by Marek on 2026-03-24.
//

import Foundation
import SwiftUI

// MARK: - Enums

enum OrderMemoryStatus: String, Codable {
    case queued   // job running, countdown in progress
    case ordered  // order successfully submitted to Planet API
}

enum PlanetItemType: String, CaseIterable, Codable {
    case psScene = "PSScene"
}

enum PlanetProductBundle: String, CaseIterable, Codable {
    case analytic8bSrUdm2 = "analytic_8b_sr_udm2"
}

enum PlanetOrderStatus: String, Codable, CaseIterable {
    case queued
    case running
    case success
    case failed
    case cancelled
    case unknown

    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .success:   return .green
        case .running:   return .blue
        case .queued:    return .orange
        case .failed:    return .red
        case .cancelled: return .gray
        case .unknown:   return .secondary
        }
    }
}

// MARK: - Scene Types

struct PlanetScene: Identifiable {
    let id: String
    let acquiredAt: Date
    let cloudCover: Double
    let thumbnailURL: String?
}

struct PlanetSceneGroup: Identifiable {
    var id: Date { date }
    let date: Date        // start of the acquired day (noon UTC used as canonical)
    let scenes: [PlanetScene]

    var averageCloudCover: Double {
        guard !scenes.isEmpty else { return 0 }
        return scenes.map(\.cloudCover).reduce(0, +) / Double(scenes.count)
    }
}

// MARK: - Order Request

struct PlanetOrderRequest {
    let name: String
    let geometry: [String: Any]
    let itemIds: [String]
    let itemType: String
    let productBundle: String
    let harmonize: Bool
    let composite: Bool
}

// MARK: - Persistent Order Record (stored in SwiftData)

struct PlanetOrderRecord: Codable, Identifiable {
    var id: String           // Planet order ID
    var name: String
    var date: Date           // the scene date this order represents
    var status: String       // last known PlanetOrderStatus raw value
    var createdAt: Date
}

// MARK: - Subscription

struct PlanetSubscription: Identifiable, Decodable {
    struct Plan: Decodable {
        let id: Int
        let name: String
    }

    let id: Int
    let state: String
    let plan: Plan
    let quotaUsed: Double
    let quotaSqkm: Double

    var isActive: Bool { state == "active" }
    var fraction: Double { quotaSqkm > 0 ? min(quotaUsed / quotaSqkm, 1.0) : 0 }

    enum CodingKeys: String, CodingKey {
        case id, state, plan
        case quotaUsed = "quota_used"
        case quotaSqkm = "quota_sqkm"
    }
}

// MARK: - Download Result

struct PlanetDownloadResult {
    let name: String       // relative path from Planet (e.g. "order/scene/file.tif")
    let location: String   // signed download URL
}

struct PlanetManifestFile {
    let path: String
    let sha256: String
}

// MARK: - Naming Pattern Resolver

func resolveNamingPattern(
    _ pattern: String,
    configName: String,
    projectName: String,
    itemType: String,
    productBundle: String,
    harmonized: Bool,
    composite: Bool,
    date: Date
) -> String {
    let calendar = Calendar.current
    let year = String(format: "%04d", calendar.component(.year, from: date))
    let month = String(format: "%02d", calendar.component(.month, from: date))
    let day = String(format: "%02d", calendar.component(.day, from: date))

    var paramParts: [String] = [itemType]
    if harmonized { paramParts.append("harmonized") }
    if composite { paramParts.append("composite") }
    paramParts.append(productBundle)
    let parameters = paramParts.joined(separator: "_")

    return pattern
        .replacingOccurrences(of: "{Project}", with: projectName)
        .replacingOccurrences(of: "{ConfigName}", with: configName)
        .replacingOccurrences(of: "{Year}", with: year)
        .replacingOccurrences(of: "{Month}", with: month)
        .replacingOccurrences(of: "{Day}", with: day)
        .replacingOccurrences(of: "{Parameters}", with: parameters)
}

// MARK: - GeoJSON Geometry Loader

enum PlanetAPIError: LocalizedError {
    case missingApiKey
    case invalidShapeFile
    case httpError(Int, String)
    case decodingError(String)
    case missingShapeFile

    var errorDescription: String? {
        switch self {
        case .missingApiKey: return "No Planet API key configured. Set it in Settings."
        case .invalidShapeFile: return "Could not read a valid polygon geometry from the shape file."
        case .httpError(let code, let msg): return "Planet API error \(code): \(msg)"
        case .decodingError(let msg): return "Failed to decode Planet response: \(msg)"
        case .missingShapeFile: return "No shape file selected."
        }
    }
}

func loadShapeFileGeometry(from path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw PlanetAPIError.invalidShapeFile
    }
    // FeatureCollection
    if let features = json["features"] as? [[String: Any]],
       let first = features.first,
       let geometry = first["geometry"] as? [String: Any] {
        return geometry
    }
    // Feature
    if let geometry = json["geometry"] as? [String: Any] {
        return geometry
    }
    // Bare geometry
    if let type = json["type"] as? String,
       (type == "Polygon" || type == "MultiPolygon") {
        return json
    }
    throw PlanetAPIError.invalidShapeFile
}
