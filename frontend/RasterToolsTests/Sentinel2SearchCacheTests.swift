//
//  Sentinel2SearchCacheTests.swift
//  RasterToolsTests
//

import Testing
import Foundation
@testable import RasterTools

struct Sentinel2SearchCacheTests {

    @Test func productRoundTripsThroughJSON() throws {
        let product = Sentinel2Product(
            id: "0f6c2b1e-1111-2222-3333-444455556666",
            name: "S2A_MSIL1C_20220720T152641_N0400_R025_T18TWL_20220720T190535.SAFE",
            sensingDate: Date(timeIntervalSinceReferenceDate: 679_937_201.024),
            cloudCover: 12.345,
            contentLength: 812_345_678,
            footprintRing: [(-74.1, 40.5), (-73.2, 40.5), (-73.2, 41.4), (-74.1, 40.5)]
        )
        let group = Sentinel2SceneGroup(date: product.sensingDate, products: [product])

        let decoded = try JSONDecoder().decode(
            Sentinel2SceneGroup.self,
            from: JSONEncoder().encode(group)
        )
        let back = try #require(decoded.products.first)

        #expect(decoded.date == group.date)
        #expect(back.id == product.id)
        #expect(back.name == product.name)
        // Exact, not approximate: the cache relies on dates matching after a reload.
        #expect(back.sensingDate == product.sensingDate)
        #expect(back.cloudCover == product.cloudCover)
        #expect(back.contentLength == product.contentLength)
        #expect(back.footprintRing.map(\.lon) == product.footprintRing.map(\.lon))
        #expect(back.footprintRing.map(\.lat) == product.footprintRing.map(\.lat))
    }
}
