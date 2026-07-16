//
//  RasterToolsTests.swift
//  RasterToolsTests
//
//  Created by Marek on 2026-03-20.
//

import Testing
import CoreGraphics
import AppKit
@testable import RasterTools

struct RasterToolsTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    // MARK: - ThumbnailProjector

    /// A footprint whose lon/lat bbox fills the whole detected content box maps
    /// its corners to the corners of the on-screen content rect.
    @Test func projectorMapsCornersToContentRect() throws {
        // Footprint bbox: lon 10…12, lat 40…42 (rotated ring, corners on edges).
        let footprint: [(lon: Double, lat: Double)] = [
            (11, 42), (12, 41), (11, 40), (10, 41)
        ]
        let fullBox = CGRect(x: 0, y: 0, width: 1, height: 1)
        let projector = try #require(ThumbnailProjector(footprintRing: footprint, contentBox: fullBox))

        let rect = CGRect(x: 100, y: 200, width: 400, height: 400)

        let topLeft = projector.point(lon: 10, lat: 42, in: rect)      // minLon, maxLat
        #expect(abs(topLeft.x - rect.minX) < 0.001)
        #expect(abs(topLeft.y - rect.minY) < 0.001)

        let bottomRight = projector.point(lon: 12, lat: 40, in: rect)  // maxLon, minLat
        #expect(abs(bottomRight.x - rect.maxX) < 0.001)
        #expect(abs(bottomRight.y - rect.maxY) < 0.001)

        let center = projector.point(lon: 11, lat: 41, in: rect)
        #expect(abs(center.x - rect.midX) < 0.001)
        #expect(abs(center.y - rect.midY) < 0.001)
    }

    /// When content occupies an inset sub-box (padding), the mapping honors it.
    @Test func projectorRespectsContentBoxInset() throws {
        let footprint: [(lon: Double, lat: Double)] = [
            (0, 10), (10, 10), (10, 0), (0, 0)
        ]
        // Content sits in the middle 50% of the image (25% padding each side).
        let inset = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let projector = try #require(ThumbnailProjector(footprintRing: footprint, contentBox: inset))

        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        // minLon/maxLat → top-left of the inset content box.
        let topLeft = projector.point(lon: 0, lat: 10, in: rect)
        #expect(abs(topLeft.x - 25) < 0.001)
        #expect(abs(topLeft.y - 25) < 0.001)
    }

    /// Content-box detection finds the tight bbox of non-transparent pixels.
    @Test func contentBoundingBoxDetectsOpaqueRegion() throws {
        let size = 100
        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: size * bytesPerRow)  // fully clear
        // Paint an opaque square from (20,30) to (60,70) in top-left coords.
        for y in 30..<70 {
            for x in 20..<60 {
                let i = y * bytesPerRow + x * 4
                pixels[i] = 255; pixels[i + 1] = 255; pixels[i + 2] = 255; pixels[i + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let cg = ctx.makeImage()!

        let box = try #require(ThumbnailProjector.contentBoundingBox(of: cg))
        #expect(abs(box.minX - 0.20) < 0.02)
        #expect(abs(box.minY - 0.30) < 0.02)
        #expect(abs(box.maxX - 0.60) < 0.02)
        #expect(abs(box.maxY - 0.70) < 0.02)
    }

}
