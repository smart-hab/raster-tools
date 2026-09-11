//
//  ToolConfiguration.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation

// MARK: - Tool Kind Enumeration

enum ToolKind: String, Codable, CaseIterable {
    case kmeans = "K-Means Clustering"
    case preprocess = "Preprocess"
    case collectionPlanet = "Collection (Planet)"
    case collectionSentinel2 = "Collection (Sentinel-2)"

    var iconName: String {
        switch self {
        case .kmeans: return "circle.hexagongrid.fill"
        case .preprocess: return "wand.and.rays"
        case .collectionPlanet: return "square.and.arrow.down.on.square"
        case .collectionSentinel2: return "globe.europe.africa.fill"
        }
    }

    /// The two collectors share a workflow (AOI + month + cloud cover → scenes on disk) and
    /// differ only in provider, so several call sites treat them alike.
    var isCollector: Bool {
        self == .collectionPlanet || self == .collectionSentinel2
    }
}

// MARK: - Tool Configuration Protocol

protocol ToolConfiguration: AnyObject {
    var id: UUID { get }
    var name: String { get set }
    var kind: ToolKind { get }
    var project: Project { get }
    var createdAt: Date { get }
    var modifiedAt: Date { get }
    func touch()
}
