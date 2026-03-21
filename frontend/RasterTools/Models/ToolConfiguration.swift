//
//  ToolConfiguration.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import SwiftData

enum ToolType: String, Codable, CaseIterable {
    case kmeans = "K-Means Clustering"
    case preprocess = "Preprocess"
    
    var iconName: String {
        switch self {
        case .kmeans: return "circle.hexagongrid.fill"
        case .preprocess: return "wand.and.stars"
        }
    }
}

enum PreprocessType: String, Codable, CaseIterable {
    case ndci = "NDCI"
    case ndvi = "NDVI"
}

// MARK: - Main Configuration

@Model
final class ToolConfiguration {
    var id: UUID
    var name: String
    var toolType: ToolType
    var workspacePath: String
    var createdAt: Date
    var modifiedAt: Date
    
    // K-Means specific properties
    var kmeansConfig: KMeansConfiguration?
    
    // Preprocess specific properties
    var preprocessConfig: PreprocessConfiguration?
    
    init(name: String, toolType: ToolType, workspacePath: String) {
        self.id = UUID()
        self.name = name
        self.toolType = toolType
        self.workspacePath = workspacePath
        self.createdAt = Date()
        self.modifiedAt = Date()
        
        // Initialize the appropriate config
        switch toolType {
        case .kmeans:
            self.kmeansConfig = KMeansConfiguration()
        case .preprocess:
            self.preprocessConfig = PreprocessConfiguration()
        }
    }
    
    func touch() {
        modifiedAt = Date()
    }
}

// MARK: - K-Means Configuration

@Model
final class KMeansConfiguration {
    var centersFile: String
    var centroids: Int
    var nTimes: Int
    var seed: Int
    var filesFit: [String]
    var filesClassify: [String]
    
    init(centersFile: String = "centers.txt",
         centroids: Int = 6,
         nTimes: Int = 10,
         seed: Int = 42,
         filesFit: [String] = [],
         filesClassify: [String] = []) {
        self.centersFile = centersFile
        self.centroids = centroids
        self.nTimes = nTimes
        self.seed = seed
        self.filesFit = filesFit
        self.filesClassify = filesClassify
    }
}

// MARK: - Preprocess Configuration

@Model
final class PreprocessConfiguration {
    var shapeFile: String
    var processes: [String] // Store as strings for SwiftData compatibility
    var files: [String]
    
    init(shapeFile: String = "",
         processes: [PreprocessType] = [.ndci, .ndvi],
         files: [String] = []) {
        self.shapeFile = shapeFile
        self.processes = processes.map { $0.rawValue }
        self.files = files
    }
    
    var processTypes: [PreprocessType] {
        get { processes.compactMap { PreprocessType(rawValue: $0) } }
        set { processes = newValue.map { $0.rawValue } }
    }
}

