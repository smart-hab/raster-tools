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
    case collection = "Collection"

    var iconName: String {
        switch self {
        case .kmeans: return "circle.hexagongrid.fill"
        case .preprocess: return "wand.and.rays"
        case .collection: return "square.and.arrow.down.on.square"
        }
    }
}

// MARK: - Tool Configuration Protocol

protocol ToolConfiguration: AnyObject {
    var id: UUID { get }
    var name: String { get set }
    var kind: ToolKind { get }
    var workspace: Workspace { get }
    var createdAt: Date { get }
    var modifiedAt: Date { get }
    func touch()
}
