//
//  Sentinel2API.swift
//  RasterTools
//
//  Created by Marek on 2026-09-02.
//

import Foundation

// MARK: - Enums

enum Sentinel2ProductType: String, CaseIterable, Codable {
    /// L1C keeps all 13 bands; L2A's atmospheric correction drops B10.
    case l1c = "MSIL1C"

    var displayName: String {
        switch self {
        case .l1c: return "Level-1C (top of atmosphere)"
        }
    }
}

enum DownloadMemoryStatus: String, Codable, CaseIterable {
    case downloading  // job in flight
    case downloaded   // product extracted and stacked
    case failed
}

// MARK: - Scene Types

struct Sentinel2Product: Identifiable, Hashable {
    let id: String            // CDSE OData product UUID
    let name: String          // e.g. S2A_MSIL1C_20220720T152641_..._.SAFE
    let sensingDate: Date
    let cloudCover: Double    // percent, 0–100
    let contentLength: Int
    let footprintRing: GeoRing

    static func == (a: Sentinel2Product, b: Sentinel2Product) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The archive name CDSE serves, and the folder it extracts into.
    var archiveStem: String {
        name.hasSuffix(".SAFE") ? String(name.dropLast(5)) : name
    }
}

/// Deliberately mirrors `PlanetSceneGroup` so the calendar day cells read the same for both
/// collectors.
struct Sentinel2SceneGroup: Identifiable {
    var id: Date { date }
    let date: Date
    let products: [Sentinel2Product]

    var averageCloudCover: Double {
        guard !products.isEmpty else { return 0 }
        return products.map(\.cloudCover).reduce(0, +) / Double(products.count)
    }

    /// The product a one-click download should take: lowest cloud cover wins.
    var best: Sentinel2Product? {
        products.min { $0.cloudCover < $1.cloudCover }
    }
}

// MARK: - Errors

enum Sentinel2APIError: LocalizedError {
    case missingCredentials
    case authenticationFailed(String)
    case httpError(Int, String)
    case decodingError(String)
    case missingShapeFile
    case invalidResponse
    case incompleteDownload(expected: Int, received: Int)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "No Copernicus credentials configured. Set them in Settings."
        case .authenticationFailed(let msg):
            return "Copernicus sign-in failed: \(msg)"
        case .httpError(let code, let msg):
            return "Copernicus API error \(code): \(msg)"
        case .decodingError(let msg):
            return "Failed to decode Copernicus response: \(msg)"
        case .missingShapeFile:
            return "No shape file selected."
        case .invalidResponse:
            return "Received an unexpected non-HTTP response from the Copernicus API."
        case .incompleteDownload(let expected, let received):
            return "Download truncated: expected \(expected) bytes but received \(received)."
        }
    }
}

// MARK: - Token Cache

/// Holds the OAuth2 bearer token between calls.
///
/// Unlike Planet's stateless Basic auth, CDSE issues short-lived tokens (~10 minutes) from a
/// Keycloak password grant, so every request has to be able to mint or refresh one.
private actor Sentinel2TokenCache {
    static let shared = Sentinel2TokenCache()

    private var token: String?
    private var expiresAt: Date = .distantPast

    /// A minted token is treated as expired slightly early so a request never starts with a
    /// token that dies mid-flight.
    private static let expiryMargin: TimeInterval = 30

    func token(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let token, Date() < expiresAt {
            return token
        }
        let (fresh, lifetime) = try await mint()
        token = fresh
        expiresAt = Date().addingTimeInterval(max(lifetime - Self.expiryMargin, 0))
        return fresh
    }

    private func mint() async throws -> (token: String, lifetime: TimeInterval) {
        let (username, password) = await MainActor.run {
            (AppSettings.shared.cdseUsername, AppSettings.shared.cdsePassword)
        }
        guard !username.isEmpty, !password.isEmpty else {
            throw Sentinel2APIError.missingCredentials
        }

        var request = URLRequest(url: Sentinel2API.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "client_id": "cdse-public",
            "grant_type": "password",
            "username": username,
            "password": password,
        ]
        request.httpBody = Data(
            form.map { "\($0.key)=\(formEncode($0.value))" }.joined(separator: "&").utf8
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Sentinel2APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            // CDSE returns {"error": "...", "error_description": "..."} for bad credentials;
            // surfacing the description is far more useful than the bare status code.
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (json?["error_description"] as? String)
                ?? String(data: data, encoding: .utf8)
                ?? "\(http.statusCode)"
            throw Sentinel2APIError.authenticationFailed(message)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw Sentinel2APIError.decodingError("No access_token in token response")
        }
        let lifetime = (json["expires_in"] as? Double) ?? 300
        return (token, lifetime)
    }

    /// `application/x-www-form-urlencoded` — passwords routinely contain `&`, `+` and `=`.
    private func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

// MARK: - API

struct Sentinel2API {

    static let catalogueURL = URL(string: "https://catalogue.dataspace.copernicus.eu/odata/v1/Products")!
    static let tokenURL = URL(
        string: "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token"
    )!

    static func accessToken(forceRefresh: Bool = false) async throws -> String {
        try await Sentinel2TokenCache.shared.token(forceRefresh: forceRefresh)
    }

    // MARK: - Search

    /// Searches the CDSE catalogue and returns products grouped by sensing day (UTC).
    static func search(
        aoiRing: GeoRing,
        startDate: Date,
        endDate: Date,
        productType: String,
        maxCloudCover: Double,
        maxResults: Int = 100
    ) async throws -> [Sentinel2SceneGroup] {
        guard let box = boundingBox(of: aoiRing) else {
            throw Sentinel2APIError.missingShapeFile
        }

        // The OData filter travels in the URL, and a full-precision AOI (a detailed hydrology
        // polygon can carry thousands of vertices) produces a WKT string long enough to blow past
        // URL length limits and get the connection reset. The envelope is coarser but plenty for
        // picking the right S2 tile.
        let wkt = """
            POLYGON((\(box.minLon) \(box.minLat),\(box.maxLon) \(box.minLat),\
            \(box.maxLon) \(box.maxLat),\(box.minLon) \(box.maxLat),\(box.minLon) \(box.minLat)))
            """

        var filter = """
            Collection/Name eq 'SENTINEL-2' and \
            contains(Name,'\(productType)') and \
            OData.CSC.Intersects(area=geography'SRID=4326;\(wkt)') and \
            ContentDate/Start gt \(odata(startDate)) and \
            ContentDate/Start lt \(odata(endDate))
            """
        filter += """
             and Attributes/OData.CSC.DoubleAttribute/any(a:a/Name eq 'cloudCover' \
            and a/OData.CSC.DoubleAttribute/Value le \(maxCloudCover))
            """

        var components = URLComponents(url: catalogueURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "$filter", value: filter),
            URLQueryItem(name: "$top", value: String(maxResults)),
            URLQueryItem(name: "$expand", value: "Attributes"),
        ]
        guard let url = components.url else { throw Sentinel2APIError.invalidResponse }

        let data = try await get(url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["value"] as? [[String: Any]] else {
            throw Sentinel2APIError.decodingError("No 'value' array in search response")
        }

        return group(values.compactMap(parseProduct))
    }

    /// CDSE quicklooks are served from the same authenticated host as the products.
    static func fetchQuicklook(url: URL) async throws -> Data {
        try await get(url)
    }

    /// OData addresses an entity as `Products(<id>)` — no slash before the key — so this is
    /// built as a string rather than with `appendingPathComponent`, which would insert one and
    /// get a 404. The catalogue host redirects to the download host, which `download` follows.
    static func downloadURL(productId: String) -> URL {
        URL(string: "\(catalogueURL.absoluteString)(\(productId))/$value")!
    }

    // MARK: - Private

    /// An authenticated GET that retries once on a 401 with a freshly minted token, since a
    /// cached token can expire between the check and the request reaching CDSE.
    private static func get(_ url: URL) async throws -> Data {
        var token = try await accessToken()
        var (data, http) = try await send(url, token: token)

        if http.statusCode == 401 {
            token = try await accessToken(forceRefresh: true)
            (data, http) = try await send(url, token: token)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw Sentinel2APIError.httpError(
                http.statusCode,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }

    private static func send(_ url: URL, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Sentinel2APIError.invalidResponse
        }
        return (data, http)
    }

    private static func parseProduct(_ value: [String: Any]) -> Sentinel2Product? {
        guard let id = value["Id"] as? String,
              let name = value["Name"] as? String,
              let startString = value["ContentDate"].flatMap({ ($0 as? [String: Any])?["Start"] as? String }),
              let sensingDate = parseODataDate(startString) else {
            return nil
        }

        let attributes = (value["Attributes"] as? [[String: Any]]) ?? []
        let cloudCover = attributes
            .first { $0["Name"] as? String == "cloudCover" }
            .flatMap { $0["Value"] as? Double }
            ?? 100

        let contentLength = (value["ContentLength"] as? Int)
            ?? (value["ContentLength"] as? NSNumber)?.intValue
            ?? 0

        return Sentinel2Product(
            id: id,
            name: name,
            sensingDate: sensingDate,
            cloudCover: cloudCover,
            contentLength: contentLength,
            footprintRing: extractRing(from: value["GeoFootprint"] as? [String: Any])
        )
    }

    private static func group(_ products: [Sentinel2Product]) -> [Sentinel2SceneGroup] {
        var grouped: [Date: [Sentinel2Product]] = [:]
        for product in products {
            let day = Date.utcCalendar.startOfDay(for: product.sensingDate)
            grouped[day, default: []].append(product)
        }
        return grouped
            .map { Sentinel2SceneGroup(date: $0.key, products: $0.value.sorted { $0.cloudCover < $1.cloudCover }) }
            .sorted { $0.date < $1.date }
    }

    /// OData wants an unquoted, unescaped `2022-07-01T00:00:00.000Z` literal in the filter.
    private static func odata(_ date: Date) -> String {
        odataFormatter.string(from: date)
    }

    private static let odataFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// CDSE is inconsistent about fractional seconds on ContentDate.
    private static func parseODataDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: string)
    }
}
