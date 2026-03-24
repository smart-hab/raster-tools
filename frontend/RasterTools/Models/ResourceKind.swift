//
//  ResourceKind.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import SwiftUI

enum ResourceKind: String, Codable {
    case sourceRaster  // composite.tif
    case udm           // composite_udm2.tif
    case metadata      // composite_metadata.json
    case shapeFile     // .geojson / .shp
    case clipped       // *_clipped.tif (generated)
    case masked        // *_clipped_masked.tif (generated)
    case ndvi          // generated NDVI
    case ndci          // generated NDCI
    case kmeansCenters // centers.txt (k-means fitted model)
    case kmeansClassed // *_classed.tif (k-means classification)
    case kmeansMean    // mean.tif (k-means mean raster)
    case kmeansDiff    // mean_diff_*.tif (k-means difference raster)
    case unknown

    var displayName: String {
        switch self {
        case .sourceRaster:  return "Source"
        case .udm:           return "UDM2"
        case .metadata:      return "Metadata"
        case .shapeFile:     return "Shape"
        case .clipped:       return "Clipped"
        case .masked:        return "Masked"
        case .ndvi:          return "NDVI"
        case .ndci:          return "NDCI"
        case .kmeansCenters: return "Centers"
        case .kmeansClassed: return "Classed"
        case .kmeansMean:    return "Mean"
        case .kmeansDiff:    return "Diff"
        case .unknown:       return "Unknown"
        }
    }

    var iconName: String {
        switch self {
        case .sourceRaster:  return "photo"
        case .udm:           return "cloud.fill"
        case .metadata:      return "doc.text.fill"
        case .shapeFile:     return "globe.europe.africa.fill"
        case .clipped:       return "crop"
        case .masked:        return "rectangle.pattern.checkered"
        case .ndvi:          return "leaf.fill"
        case .ndci:          return "drop.fill"
        case .kmeansCenters: return "target"
        case .kmeansClassed: return "circle.hexagongrid.fill"
        case .kmeansMean:    return "square.3.layers.3d"
        case .kmeansDiff:    return "plus.forwardslash.minus"
        case .unknown:       return "questionmark.square.fill"
        }
    }

    var color: Color {
        switch self {
        case .sourceRaster:  return .secondary
        case .udm:           return .yellow
        case .metadata:      return .secondary
        case .shapeFile:     return .brown
        case .clipped:       return .orange
        case .masked:        return .red
        case .ndvi:          return .green
        case .ndci:          return .teal
        case .kmeansCenters: return .secondary
        case .kmeansClassed: return .indigo
        case .kmeansMean:    return .secondary
        case .kmeansDiff:    return .purple
        case .unknown:       return .secondary
        }
    }
}
