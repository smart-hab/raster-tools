//
//  WorkspaceScanner.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import Foundation

struct WorkspaceScanner {

    /// Scans a source directory and returns WorkspaceResource records.
    /// Does not write to disk or create symlinks.
    static func scan(directory: String) -> [WorkspaceResource] {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: directory)

        guard let enumerator = fm.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var resources: [WorkspaceResource] = []

        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                continue
            }

            let filename = fileURL.lastPathComponent
            let ext = fileURL.pathExtension.lowercased()

            guard isMatchingFile(filename: filename, ext: ext) else { continue }

            let kind = inferKind(filename: filename, ext: ext)
            let date = extractDate(from: fileURL)

            let resource = WorkspaceResource(
                originalPath: fileURL.path(percentEncoded: false),
                filename: filename,
                date: date,
                fileExtension: ext,
                kind: kind
            )
            resources.append(resource)
        }

        return resources
    }

    // MARK: - Private helpers

    private static func isMatchingFile(filename: String, ext: String) -> Bool {
        let knownNames: Set<String> = ["composite.tif", "composite_udm2.tif", "composite_metadata.json"]
        if knownNames.contains(filename) { return true }
        if ext == "geojson" || ext == "shp" { return true }
        return false
    }

    private static func inferKind(filename: String, ext: String) -> ResourceKind {
        switch filename {
        case "composite.tif":         return .sourceRaster
        case "composite_udm2.tif":    return .udm
        case "composite_metadata.json": return .metadata
        default:
            if ext == "geojson" || ext == "shp" { return .shapeFile }
            return .unknown
        }
    }

    /// Extracts a date from a directory component matching `<base>-YYYYMMDD-*` pattern.
    private static func extractDate(from fileURL: URL) -> Date? {
        let components = fileURL.pathComponents
        let pattern = /\b(\d{8})\b/

        for component in components {
            if let match = component.firstMatch(of: pattern) {
                let dateString = String(match.1)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                return formatter.date(from: dateString)
            }
        }
        return nil
    }
}
