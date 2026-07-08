//
//  PlanetAPI.swift
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
    let footprintRing: [(lon: Double, lat: Double)]   // exterior ring of GeoJSON polygon
}

struct PlanetSceneGroup: Identifiable {
    var id: Date { date }
    let date: Date        // start of the acquired day (noon UTC used as canonical)
    let scenes: [PlanetScene]
    let coveragePercent: Double?   // % of AOI covered by union of scene footprints

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

struct PlanetOrderRecord: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var date: Date           // scene capture date, parsed from order name (YYYYMMDD segment)
    var status: String       // last known PlanetOrderStatus raw value
    var createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, name
        case status = "state"
        case createdAt = "created_on"
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasicFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let yyyymmddFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    init(id: String, name: String, date: Date, status: String, createdAt: Date) {
        self.id = id; self.name = name; self.date = date; self.status = status; self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id     = try c.decode(String.self, forKey: .id)
        name   = try c.decode(String.self, forKey: .name)
        status = try c.decode(String.self, forKey: .status)
        let createdStr = try c.decode(String.self, forKey: .createdAt)
        guard let createdAt = Self.isoFormatter.date(from: createdStr) ?? Self.isoBasicFormatter.date(from: createdStr) else {
            throw DecodingError.dataCorruptedError(forKey: .createdAt, in: c,
                debugDescription: "Could not parse created_on date: \(createdStr)")
        }
        self.createdAt = createdAt
        guard let date = name.components(separatedBy: "-").compactMap({ Self.yyyymmddFormatter.date(from: $0) }).first else {
            throw DecodingError.dataCorruptedError(forKey: .name, in: c,
                debugDescription: "Could not parse scene date from order name: \(name)")
        }
        self.date = date
    }
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
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
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
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingApiKey: return "No Planet API key configured. Set it in Settings."
        case .invalidShapeFile: return "Could not read a valid polygon geometry from the shape file."
        case .httpError(let code, let msg): return "Planet API error \(code): \(msg)"
        case .decodingError(let msg): return "Failed to decode Planet response: \(msg)"
        case .missingShapeFile: return "No shape file selected."
        case .invalidResponse: return "Received an unexpected non-HTTP response from Planet API."
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


struct PlanetAPI {

    // MARK: - Quick Search

    /// Search for PSScene features matching the given parameters.
    /// Returns scenes grouped by day (UTC).
    static func quickSearch(
        geometry: [String: Any],
        startDate: Date,
        endDate: Date,
        cloudCover: Double,
        apiKey: String
    ) async throws -> [PlanetSceneGroup] {
        guard !apiKey.isEmpty else { throw PlanetAPIError.missingApiKey }

        let body: [String: Any] = [
            "item_types": ["PSScene"],
            "filter": [
                "type": "AndFilter",
                "config": [
                    [
                        "type": "GeometryFilter",
                        "field_name": "geometry",
                        "config": geometry,
                    ],
                    [
                        "type": "DateRangeFilter",
                        "field_name": "acquired",
                        "config": [
                            "gte": startDate.isoString,                         // 00:00:00
                            "lte": endDate.addingTimeInterval(86399).isoString, // 23:59:59
                        ],
                    ],
                    [
                        "type": "RangeFilter",
                        "field_name": "cloud_cover",
                        "config": [
                            "lte": cloudCover,
                        ],
                    ],
                    [
                        "type": "AssetFilter",
                        "config": ["ortho_analytic_8b_sr"],
                    ],
                ],
            ],
        ]

        let url = URL(string: "https://api.planet.com/data/v1/quick-search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        if let bodyData = request.httpBody {
            printJSON("quickSearch request", bodyData)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        printJSON("quickSearch response", data)

        let aoiRing = extractRing(from: geometry)
        return try parseSceneGroups(from: data, aoiRing: aoiRing)
    }

    // MARK: - Create Order

    /// Submit an order to Planet. Returns the Planet order ID.
    static func createOrder(_ req: PlanetOrderRequest, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw PlanetAPIError.missingApiKey }

        var tools: [[String: Any]] = [
            ["clip": ["aoi": req.geometry]],
        ]
        if req.composite {
            tools.append(["composite": [:]])
        }
        if req.harmonize {
            tools.append(["harmonize": ["target_sensor": "Sentinel-2"]])
        }

        let body: [String: Any] = [
            "name": req.name,
            "delivery": [
                "archive_filename": "\(req.name).zip",
                "archive_type": "zip",
                "single_archive": true,
            ],
            "products": [
                [
                    "item_ids": req.itemIds,
                    "item_type": req.itemType,
                    "product_bundle": req.productBundle,
                ],
            ],
            "tools": tools,
        ]

        let url = URL(string: "https://api.planet.com/compute/ops/orders/v2")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")
        request.setValue("SmartHab", forHTTPHeaderField: "X-Planet-App")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let orderId = json["id"] as? String
        else {
            throw PlanetAPIError.decodingError("Missing 'id' in order response")
        }
        return orderId
    }

    // MARK: - List Orders

    /// Fetch all orders from the Planet Orders API (follows pagination).
    static func listOrders(apiKey: String) async throws -> [PlanetOrderRecord] {
        guard !apiKey.isEmpty else { throw PlanetAPIError.missingApiKey }

        var orders: [PlanetOrderRecord] = []
        var nextURL: URL? = URL(string: "https://api.planet.com/compute/ops/orders/v2")

        while let url = nextURL {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(basicAuthHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            try checkResponse(response, data: data)

            let page = try JSONDecoder().decode(OrderListJSON.self, from: data)
            orders.append(contentsOf: page.orders)

            // Follow pagination
            if let nextStr = page.links?.next, let next = URL(string: nextStr) {
                nextURL = next
            } else {
                nextURL = nil
            }
        }

        return orders
    }

    // MARK: - Order Status

    /// Poll the status of an existing order.
    static func getOrderStatus(id: String, apiKey: String) async throws -> PlanetOrderStatus {
        guard !apiKey.isEmpty else { throw PlanetAPIError.missingApiKey }

        let url = URL(string: "https://api.planet.com/compute/ops/orders/v2/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        let order = try JSONDecoder().decode(PlanetOrderRecord.self, from: data)
        return PlanetOrderStatus(rawValue: order.status) ?? .unknown
    }

    // MARK: - Get Order Record

    /// Fetch a single order by ID and return a full PlanetOrderRecord.
    static func getOrderRecord(id: String, apiKey: String) async throws -> PlanetOrderRecord {
        guard !apiKey.isEmpty else { throw PlanetAPIError.missingApiKey }

        let url = URL(string: "https://api.planet.com/compute/ops/orders/v2/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        return try JSONDecoder().decode(PlanetOrderRecord.self, from: data)
    }

    // MARK: - Order Results (Download URLs)

    /// Fetch the download results for a completed order.
    static func getOrderResults(id: String, apiKey: String) async throws -> [PlanetDownloadResult] {
        guard !apiKey.isEmpty else { throw PlanetAPIError.missingApiKey }

        let url = URL(string: "https://api.planet.com/compute/ops/orders/v2/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        let orderResults = try JSONDecoder().decode(OrderResultsJSON.self, from: data)
        return (orderResults.links?.results ?? []).map { PlanetDownloadResult(name: $0.name, location: $0.location) }
    }

    // MARK: - Order Manifest

    /// GETs the manifest URL and returns the list of relative file paths it contains.
    /// The manifest itself is never written to disk.
    static func getManifest(url: String, apiKey: String) async throws -> [PlanetManifestFile] {
        guard let manifestURL = URL(string: url) else {
            throw PlanetAPIError.decodingError("Invalid manifest URL")
        }
        var request = URLRequest(url: manifestURL)
        request.httpMethod = "GET"
        request.setValue(basicAuthHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let files = json["files"] as? [[String: Any]]
        else {
            throw PlanetAPIError.decodingError("Invalid manifest structure")
        }
        return files.compactMap { file -> PlanetManifestFile? in
            guard
                let path = file["path"] as? String,
                let digests = file["digests"] as? [String: Any],
                let sha256 = digests["sha256"] as? String
            else { return nil }
            return PlanetManifestFile(path: path, sha256: sha256)
        }
    }

    // MARK: - List Subscriptions

    /// Fetch all Planet subscriptions for the authenticated user.
    static func listSubscriptions(apiKey: String) async throws -> [PlanetSubscription] {
        guard !apiKey.isEmpty else { throw PlanetAPIError.missingApiKey }

        let url = URL(string: "https://api.planet.com/auth/v1/experimental/public/my/subscriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        printJSON("listSubscriptions response", data)
        return try JSONDecoder().decode([PlanetSubscription].self, from: data)
    }

    // MARK: - Thumbnail

    /// Fetch thumbnail image data using the URL from `_links.thumbnail` in the search response.
    static func fetchThumbnail(url thumbnailURL: String, apiKey: String) async throws -> Data {
        guard !apiKey.isEmpty else { throw PlanetAPIError.missingApiKey }
        guard let url = URL(string: thumbnailURL) else {
            throw PlanetAPIError.decodingError("Invalid thumbnail URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(basicAuthHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
        return data
    }

    // MARK: - Private Decodable Types

    private struct OrderListJSON: Decodable {
        let orders: [PlanetOrderRecord]
        let links: Links?

        struct Links: Decodable {
            let next: String?
            enum CodingKeys: String, CodingKey { case next = "_next" }
        }

        enum CodingKeys: String, CodingKey {
            case orders
            case links = "_links"
        }
    }

    private struct OrderResultsJSON: Decodable {
        let links: Links?

        struct Links: Decodable {
            let results: [ResultJSON]?
        }

        struct ResultJSON: Decodable {
            let name: String
            let location: String
        }

        enum CodingKeys: String, CodingKey { case links = "_links" }
    }

    // MARK: - Helpers

    private static func printJSON(_ label: String, _ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted)
        else {
            print("[PlanetAPI] \(label): failed to serialize JSON")
            return
        }
        print("[PlanetAPI] \(label):\n\(String(decoding: pretty, as: UTF8.self))")
    }

    private static func basicAuthHeader(apiKey: String) -> String {
        let credentials = "\(apiKey):"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private static func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PlanetAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PlanetAPIError.httpError(http.statusCode, body)
        }
    }

    private static func parseSceneGroups(from data: Data, aoiRing: [(lon: Double, lat: Double)]) throws -> [PlanetSceneGroup] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = json["features"] as? [[String: Any]]
        else {
            throw PlanetAPIError.decodingError("Expected FeatureCollection with 'features'")
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        var scenes: [PlanetScene] = []
        for feature in features {
            guard
                let id = feature["id"] as? String,
                let props = feature["properties"] as? [String: Any],
                let acquiredStr = props["acquired"] as? String,
                let acquired = iso.date(from: acquiredStr) ?? isoBasic.date(from: acquiredStr)
            else { continue }
            let cloudCover = props["cloud_cover"] as? Double ?? 0.0
            let thumbnailURL = (feature["_links"] as? [String: Any])?["thumbnail"] as? String
            let footprint = extractRing(from: feature["geometry"] as? [String: Any])
            scenes.append(PlanetScene(id: id, acquiredAt: acquired, cloudCover: cloudCover, thumbnailURL: thumbnailURL, footprintRing: footprint))
        }

        // Group by calendar day (UTC)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        var grouped: [Date: [PlanetScene]] = [:]
        for scene in scenes {
            let dayStart = calendar.startOfDay(for: scene.acquiredAt)
            grouped[dayStart, default: []].append(scene)
        }

        return grouped
            .map { date, group in
                let rings = group.map(\.footprintRing).filter { !$0.isEmpty }
                let coverage = aoiRing.isEmpty ? nil : gridCoveragePercent(aoi: aoiRing, scenes: rings)
                return PlanetSceneGroup(date: date, scenes: group, coveragePercent: coverage)
            }
            .sorted { $0.date < $1.date }
    }

    private static func extractRing(from geometry: [String: Any]?) -> [(lon: Double, lat: Double)] {
        guard let geometry else { return [] }
        let type = geometry["type"] as? String
        if type == "Polygon", let coords = geometry["coordinates"] as? [[[Double]]],
           let ring = coords.first {
            return ring.compactMap { p in p.count >= 2 ? (p[0], p[1]) : nil }
        }
        if type == "MultiPolygon", let coords = geometry["coordinates"] as? [[[[Double]]]],
           let ring = coords.first?.first {
            return ring.compactMap { p in p.count >= 2 ? (p[0], p[1]) : nil }
        }
        return []
    }
}

// MARK: - Coverage Computation

/// Estimates what fraction of the AOI polygon is covered by the union of scene footprint polygons.
/// Uses grid sampling in lat/lon space (sufficient for percentage ratios on small areas).
/// Returns a value in [0, 100].
private func gridCoveragePercent(
    aoi: [(lon: Double, lat: Double)],
    scenes: [[(lon: Double, lat: Double)]],
    gridSize: Int = 150
) -> Double {
    guard !aoi.isEmpty, !scenes.isEmpty else { return 0 }
    let lons = aoi.map(\.lon)
    let lats = aoi.map(\.lat)
    guard let minLon = lons.min(), let maxLon = lons.max(),
          let minLat = lats.min(), let maxLat = lats.max() else { return 0 }
    let dLon = (maxLon - minLon) / Double(gridSize)
    let dLat = (maxLat - minLat) / Double(gridSize)
    guard dLon > 0, dLat > 0 else { return 0 }

    var aoiCells = 0
    var coveredCells = 0
    for i in 0..<gridSize {
        for j in 0..<gridSize {
            let lon = minLon + (Double(i) + 0.5) * dLon
            let lat = minLat + (Double(j) + 0.5) * dLat
            guard pointInRing((lon, lat), aoi) else { continue }
            aoiCells += 1
            if scenes.contains(where: { pointInRing((lon, lat), $0) }) {
                coveredCells += 1
            }
        }
    }
    guard aoiCells > 0 else { return 0 }
    return 100.0 * Double(coveredCells) / Double(aoiCells)
}

/// Ray-casting point-in-polygon test.
private func pointInRing(_ point: (lon: Double, lat: Double), _ ring: [(lon: Double, lat: Double)]) -> Bool {
    var inside = false
    var j = ring.count - 1
    for i in 0..<ring.count {
        let xi = ring[i].lon, yi = ring[i].lat
        let xj = ring[j].lon, yj = ring[j].lat
        if ((yi > point.lat) != (yj > point.lat)) &&
            (point.lon < (xj - xi) * (point.lat - yi) / (yj - yi) + xi) {
            inside = !inside
        }
        j = i
    }
    return inside
}
