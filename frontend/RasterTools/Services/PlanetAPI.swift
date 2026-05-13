//
//  PlanetAPI.swift
//  RasterTools
//
//  Created by Marek on 2026-03-24.
//

import Foundation

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

        return try parseSceneGroups(from: data)
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

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ordersJSON = json["orders"] as? [[String: Any]] else {
                throw PlanetAPIError.decodingError("Expected 'orders' array in response")
            }

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoBasic = ISO8601DateFormatter()
            isoBasic.formatOptions = [.withInternetDateTime]

            for o in ordersJSON {
                guard let id = o["id"] as? String,
                      let name = o["name"] as? String,
                      let state = o["state"] as? String,
                      let createdStr = o["created_on"] as? String,
                      let createdAt = iso.date(from: createdStr) ?? isoBasic.date(from: createdStr)
                else { continue }
                orders.append(PlanetOrderRecord(id: id, name: name, date: createdAt, status: state, createdAt: createdAt))
            }

            // Follow pagination
            if let links = json["_links"] as? [String: Any],
               let nextStr = links["_next"] as? String,
               let next = URL(string: nextStr) {
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

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let stateStr = json["state"] as? String
        else {
            throw PlanetAPIError.decodingError("Missing 'state' in order response")
        }
        return PlanetOrderStatus(rawValue: stateStr) ?? .unknown
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

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlanetAPIError.decodingError("Invalid order response")
        }

        // Results live under _links.results
        guard
            let links = json["_links"] as? [String: Any],
            let results = links["results"] as? [[String: Any]]
        else {
            return []
        }

        return results.compactMap { r in
            guard let name = r["name"] as? String, let location = r["location"] as? String else { return nil }
            return PlanetDownloadResult(name: name, location: location)
        }
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

    private static func parseSceneGroups(from data: Data) throws -> [PlanetSceneGroup] {
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
            scenes.append(PlanetScene(id: id, acquiredAt: acquired, cloudCover: cloudCover, thumbnailURL: thumbnailURL))
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
            .map { date, group in PlanetSceneGroup(date: date, scenes: group) }
            .sorted { $0.date < $1.date }
    }
}
