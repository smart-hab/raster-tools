//
//  Sentinel2SearchCache.swift
//  RasterTools
//

import Foundation

/// Remembers Sentinel-2 search results across launches, so flipping calendar months shows the
/// last known results immediately. It is only a first paint: the view still runs a fresh search
/// on every change and writes the result back, so newly published scenes turn up.
///
/// Persisted as JSON in `AppStorage.cacheDirectory()`. Entries are small (a month is tens of KB),
/// and the AOI ring is deliberately left out — it can be thousands of vertices, and the view
/// re-reads it from the local shape file.
@MainActor
final class Sentinel2SearchCache {
    static let shared = Sentinel2SearchCache()

    struct Key: Hashable, Codable {
        let shapePath: String
        /// Editing the shape file invalidates its entries, so persisted AOI coverage can't go stale.
        let shapeModified: Date
        let startDate: Date
        let endDate: Date
        let productType: String
        let maxCloudCover: Double
    }

    struct Entry: Codable {
        var groups: [Sentinel2SceneGroup]
        /// AOI coverage per UTC "yyyy-MM-dd", filled in as it is computed.
        var coverageByDay: [String: Double]
        var fetchedAt: Date
    }

    private struct StoredEntry: Codable {
        let key: Key
        let entry: Entry
    }

    private struct StoredFile: Codable {
        let version: Int
        let entries: [StoredEntry]
    }

    private static let fileVersion = 1
    private static let saveDelay: Duration = .seconds(1)

    private var entries: [Key: Entry] = [:]
    private var saveTask: Task<Void, Never>?

    private var fileURL: URL {
        AppStorage.cacheDirectory().appendingPathComponent("sentinel2-search.json")
    }

    private init() {
        load()
    }

    func entry(for key: Key) -> Entry? {
        entries[key]
    }

    /// Stores fresh results. Coverage is carried over for days whose products are unchanged, so a
    /// refresh that finds nothing new doesn't recompute (or blank) every cell.
    func store(_ groups: [Sentinel2SceneGroup], for key: Key) {
        let previous = entries[key]
        var coverage: [String: Double] = [:]
        if let previous {
            let previousIDs = Dictionary(
                previous.groups.map { (Date.utcFormatter.string(from: $0.date), Set($0.products.map(\.id))) },
                uniquingKeysWith: { a, _ in a }
            )
            for group in groups {
                let day = Date.utcFormatter.string(from: group.date)
                if previousIDs[day] == Set(group.products.map(\.id)), let pct = previous.coverageByDay[day] {
                    coverage[day] = pct
                }
            }
        }
        entries[key] = Entry(groups: groups, coverageByDay: coverage, fetchedAt: Date())
        scheduleSave()
    }

    func storeCoverage(_ percent: Double, day: String, for key: Key) {
        guard entries[key] != nil else { return }
        entries[key]?.coverageByDay[day] = percent
        scheduleSave()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        // Default date coding (seconds as a Double) on purpose: ISO 8601 drops fractional
        // seconds, and `Key.shapeModified` must round-trip exactly to match again.
        guard let file = try? JSONDecoder().decode(StoredFile.self, from: data),
              file.version == Self.fileVersion else {
            print("[Sentinel2SearchCache] discarding unreadable cache at \(fileURL.path)") // todo: logging utility
            return
        }
        entries = Dictionary(file.entries.map { ($0.key, $0.entry) }, uniquingKeysWith: { _, b in b })
        print("[Sentinel2SearchCache] loaded \(entries.count) searches") // todo: logging utility
    }

    /// Coalesces bursts of updates (coverage lands one day at a time) into a single write.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: Self.saveDelay)
            if Task.isCancelled { return }
            save()
        }
    }

    private func save() {
        let file = StoredFile(
            version: Self.fileVersion,
            entries: entries.map { StoredEntry(key: $0.key, entry: $0.value) }
        )
        guard let data = try? JSONEncoder().encode(file) else {
            print("[Sentinel2SearchCache] encoding failed") // todo: logging utility
            return
        }
        let url = fileURL
        Task.detached(priority: .utility) {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                print("[Sentinel2SearchCache] write failed: \(error)") // todo: logging utility
            }
        }
    }
}
