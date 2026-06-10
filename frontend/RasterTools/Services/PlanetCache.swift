//
//  PlanetCache.swift
//  RasterTools
//

import Foundation
import Observation

@MainActor
@Observable final class PlanetCache {
    static let shared = PlanetCache()
    private(set) var cache: [String: PlanetOrderRecord] = [:]

    private init() {}

    private func prettyJSON(_ record: PlanetOrderRecord) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record),
              let str = String(data: data, encoding: .utf8) else { return "(encoding failed)" }
        return str
    }

    func getOrder(_ id: String) async -> PlanetOrderRecord? {
        if let cached = cache[id] {
            let status = PlanetOrderStatus(rawValue: cached.status)
            if status == .success || status == .failed || status == .cancelled {
                print("[PlanetCache] HIT (terminal) \(cached.id) — \(cached.name) [\(cached.status)]\n\(prettyJSON(cached))")
                return cached
            }
        }
        guard let record = try? await PlanetAPI.getOrderRecord(id: id, apiKey: AppSettings.shared.planetApiKey) else {
            print("[PlanetCache] MISS (fetch failed) \(id)")
            return nil
        }
        print("[PlanetCache] MISS (fetched) \(record.id) — \(record.name) [\(record.status)]\n\(prettyJSON(record))")
        cache[id] = record
        return record
    }
}
