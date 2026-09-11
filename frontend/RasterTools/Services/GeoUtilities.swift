//
//  GeoUtilities.swift
//  RasterTools
//
//  Created by Marek on 2026-09-02.
//

import Foundation

/// Provider-agnostic geometry helpers shared by the Planet and Sentinel-2 collectors.
/// Everything here works on lon/lat rings in EPSG:4326 and knows nothing about either API.

/// The exterior ring of a polygon, in lon/lat degrees.
typealias GeoRing = [(lon: Double, lat: Double)]

enum GeoError: LocalizedError {
    case invalidShapeFile

    var errorDescription: String? {
        switch self {
        case .invalidShapeFile:
            return "Could not read a valid polygon geometry from the shape file."
        }
    }
}

// MARK: - GeoJSON

/// Reads a GeoJSON file and returns its first polygon geometry, accepting a FeatureCollection,
/// a bare Feature, or a naked geometry object.
func loadShapeFileGeometry(from path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw GeoError.invalidShapeFile
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
    throw GeoError.invalidShapeFile
}

/// Exterior ring of a GeoJSON Polygon or the first ring of a MultiPolygon.
func extractRing(from geometry: [String: Any]?) -> GeoRing {
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

/// Axis-aligned bounding box of a ring, as (minLon, minLat, maxLon, maxLat).
///
/// Sentinel-2's CDSE search puts the AOI in the *URL*, where a full-precision hydrology polygon
/// is long enough to get the connection reset — the envelope is coarse but plenty for picking
/// the right tile.
func boundingBox(of ring: GeoRing) -> (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double)? {
    guard let minLon = ring.map(\.lon).min(), let maxLon = ring.map(\.lon).max(),
          let minLat = ring.map(\.lat).min(), let maxLat = ring.map(\.lat).max() else {
        return nil
    }
    return (minLon, minLat, maxLon, maxLat)
}

// MARK: - Coverage

/// Fraction of the AOI covered by the union of `footprints`, in [0, 100].
/// Heavy (grid sampling) — call off the main actor. Returns nil when there is no AOI ring or
/// no footprints to measure.
nonisolated func aoiCoveragePercent(aoiRing: GeoRing, footprints: [GeoRing]) -> Double? {
    guard !aoiRing.isEmpty else { return nil }
    let rings = footprints.filter { !$0.isEmpty }
    guard !rings.isEmpty else { return nil }
    return gridCoveragePercent(aoi: aoiRing, scenes: rings)
}

/// Estimates what fraction of the AOI polygon is covered by the union of scene footprint polygons.
/// Uses grid sampling in lat/lon space (sufficient for percentage ratios on small areas).
/// Returns a value in [0, 100].
nonisolated func gridCoveragePercent(
    aoi: GeoRing,
    scenes: [GeoRing],
    gridSize: Int = 150
) -> Double {
    guard !aoi.isEmpty, !scenes.isEmpty, let box = boundingBox(of: aoi) else { return 0 }
    let dLon = (box.maxLon - box.minLon) / Double(gridSize)
    let dLat = (box.maxLat - box.minLat) / Double(gridSize)
    guard dLon > 0, dLat > 0 else { return 0 }

    var aoiCells = 0
    var coveredCells = 0
    for i in 0..<gridSize {
        for j in 0..<gridSize {
            let lon = box.minLon + (Double(i) + 0.5) * dLon
            let lat = box.minLat + (Double(j) + 0.5) * dLat
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
nonisolated func pointInRing(_ point: (lon: Double, lat: Double), _ ring: GeoRing) -> Bool {
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
