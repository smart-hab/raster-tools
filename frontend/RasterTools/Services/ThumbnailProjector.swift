//
//  ThumbnailProjector.swift
//  RasterTools
//
//  Maps lon/lat coordinates onto a Planet scene thumbnail so geographic
//  boundaries (AOI, scene footprint) can be superimposed on the preview image.
//
//  Planet thumbnails are north-up PNGs in which the sensor footprint appears as
//  a rotated rectangle surrounded by transparent padding. We recover the image's
//  geographic extent empirically instead of guessing the padding:
//
//    • The tight bounding box of non-transparent content in the PNG corresponds
//      exactly to the footprint's lon/lat bounding box — the rotated rectangle's
//      extreme corners touch the edges of its axis-aligned bbox.
//    • Over a single scene a linear lon/lat → pixel map is sub-pixel accurate
//      (Web Mercator nonlinearity is negligible at this scale), and the sensor
//      rotation is already encoded in the footprint vertex coordinates — so no
//      rotation angle or aspect correction is needed.
//

import Foundation
import CoreGraphics
import AppKit

/// Projects lon/lat points into a thumbnail's on-screen content rectangle.
struct ThumbnailProjector {
    /// Geographic bounding box of the scene footprint.
    let minLon: Double
    let maxLon: Double
    let minLat: Double
    let maxLat: Double

    /// Tight pixel bounding box of the non-transparent image content, normalized
    /// to [0, 1] against the full image size. Storing normalized values lets us
    /// scale into any displayed content rect without knowing the pixel size again.
    let contentBox: CGRect   // normalized (0…1), origin top-left

    /// Builds a projector from a footprint ring and the decoded image.
    /// Returns nil when the footprint bbox is degenerate or no content is found;
    /// logs the reason so a missing boundary is never silent.
    nonisolated init?(footprintRing: [(lon: Double, lat: Double)], image: CGImage) {
        guard let box = Self.contentBoundingBox(of: image) else {
            print("[ThumbnailProjector] no non-transparent content detected in thumbnail")
            return nil
        }
        self.init(footprintRing: footprintRing, contentBox: box)
    }

    /// Builds a projector from a footprint ring and an already-detected content
    /// box (normalized). Returns nil when the footprint bbox is degenerate.
    nonisolated init?(footprintRing: [(lon: Double, lat: Double)], contentBox: CGRect) {
        guard footprintRing.count >= 3 else {
            print("[ThumbnailProjector] no footprint geometry (ring has \(footprintRing.count) points)")
            return nil
        }
        let lons = footprintRing.map(\.lon)
        let lats = footprintRing.map(\.lat)
        guard
            let minLon = lons.min(), let maxLon = lons.max(),
            let minLat = lats.min(), let maxLat = lats.max(),
            maxLon > minLon, maxLat > minLat
        else {
            print("[ThumbnailProjector] degenerate footprint bbox")
            return nil
        }
        self.minLon = minLon
        self.maxLon = maxLon
        self.minLat = minLat
        self.maxLat = maxLat
        self.contentBox = contentBox
    }

    /// Maps a lon/lat point into `contentRect` (the letterboxed rectangle the
    /// image occupies on screen), routing through the detected content box.
    func point(lon: Double, lat: Double, in contentRect: CGRect) -> CGPoint {
        let u = (lon - minLon) / (maxLon - minLon)
        let v = (maxLat - lat) / (maxLat - minLat)   // lat increases upward, y downward
        // Position within the detected content box (normalized), then into the
        // displayed content rect.
        let nx = contentBox.minX + u * contentBox.width
        let ny = contentBox.minY + v * contentBox.height
        return CGPoint(
            x: contentRect.minX + nx * contentRect.width,
            y: contentRect.minY + ny * contentRect.height
        )
    }

    /// Maps a lon/lat ring into a pixel path in `contentRect`.
    func path(for ring: [(lon: Double, lat: Double)], in contentRect: CGRect) -> [CGPoint] {
        ring.map { point(lon: $0.lon, lat: $0.lat, in: contentRect) }
    }

    // MARK: - Content detection

    /// Tight bounding box of non-transparent pixels, normalized to [0, 1] against
    /// the image size (origin top-left). Nil if the image is empty or fully clear.
    nonisolated static func contentBoundingBox(of cg: CGImage) -> CGRect? {
        // Alpha above this (0…255) counts as image content. Planet pads with
        // fully transparent pixels, so a low threshold cleanly isolates the footprint.
        let alphaThreshold: UInt8 = 8

        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return nil }

        // Draw into a known RGBA8 buffer so we can read alpha directly.
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                let alpha = pixels[rowStart + x * 4 + 3]
                if alpha > alphaThreshold {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        // Reading back a premultipliedLast context after `ctx.draw` gives a
        // top-left-origin buffer (row 0 = top), matching how the image displays.
        let w = Double(width), h = Double(height)
        let normMinX = Double(minX) / w
        let normMaxX = Double(maxX + 1) / w
        let normMinY = Double(minY) / h
        let normMaxY = Double(maxY + 1) / h
        return CGRect(
            x: normMinX,
            y: normMinY,
            width: normMaxX - normMinX,
            height: normMaxY - normMinY
        )
    }
}
