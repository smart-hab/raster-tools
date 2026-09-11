//
//  ProjectScanner.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import Foundation
import SwiftData

struct ProjectScanner {

    /// Scans a source directory and returns ProjectResource records.
    /// Source rasters are paired with their UDM sibling when present.
    /// Does not write to disk or create symlinks.
    static func scan(directory: String) -> [ProjectResource] {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: directory)

        guard let enumerator = fm.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var resources: [ProjectResource] = []

        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                continue
            }

            let filename = fileURL.lastPathComponent
            let ext = fileURL.pathExtension.lowercased()

            // Shape files: match by extension
            if ext == "geojson" || ext == "shp" {
                let date = extractDate(from: fileURL)
                let resource = ProjectResource(
                    originalPath: fileURL.path(percentEncoded: false),
                    filename: filename,
                    date: date,
                    fileExtension: ext,
                    kind: .shapeFile,
                    fileSize: fileSize(at: fileURL)
                )
                resources.append(resource)
                continue
            }

            // Sentinel-2: the stacked 13-band GeoTIFF produced by `s2_stack` after a CDSE
            // download. The individual .jp2 bands inside the .SAFE tree are deliberately not
            // registered — there are 13 per product and none is usable on its own. There is no
            // UDM2 companion either; Sentinel-2 ships cloud masks in a different form.
            if filename.hasSuffix("_13band.tif") {
                let resource = ProjectResource(
                    originalPath: fileURL.path(percentEncoded: false),
                    filename: filename,
                    date: extractDate(from: fileURL),
                    fileExtension: ext,
                    kind: .sourceRaster,
                    fileSize: fileSize(at: fileURL)
                )
                resources.append(resource)
                continue
            }

            // Metadata — Planet's composite sidecar, or a Sentinel-2 product manifest
            if filename == "composite_metadata.json" || filename == "MTD_MSIL1C.xml" {
                let date = extractDate(from: fileURL)
                let resource = ProjectResource(
                    originalPath: fileURL.path(percentEncoded: false),
                    filename: filename,
                    date: date,
                    fileExtension: ext,
                    kind: .metadata,
                    fileSize: fileSize(at: fileURL)
                )
                resources.append(resource)
                continue
            }

            // Source raster — only composite.tif drives the scan
            guard filename == "composite.tif" else { continue }

            let dir = fileURL.deletingLastPathComponent()
            let date = extractDate(from: fileURL)

            let source = ProjectResource(
                originalPath: fileURL.path(percentEncoded: false),
                filename: filename,
                date: date,
                fileExtension: ext,
                kind: .sourceRaster,
                fileSize: fileSize(at: fileURL)
            )

            // Check for UDM sibling in the same directory
            let udmURL = dir.appendingPathComponent("composite_udm2.tif")
            if fm.fileExists(atPath: udmURL.path(percentEncoded: false)) {
                let udm = ProjectResource(
                    originalPath: udmURL.path(percentEncoded: false),
                    filename: "composite_udm2.tif",
                    date: date,
                    fileExtension: "tif",
                    kind: .udm,
                    fileSize: fileSize(at: udmURL)
                )
                source.udm = udm
                resources.append(udm)
            }

            resources.append(source)
        }

        return resources
    }

    // MARK: - Private helpers

    private static func fileSize(at url: URL) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return attrs?[.size] as? Int ?? 0
    }

    private static let yyyymmddFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Extracts a date from the first 8-digit run in any path component — Planet's
    /// `<base>-YYYYMMDD-*` folders and Sentinel-2's `S2A_MSIL1C_YYYYMMDDTHHMMSS_…` products
    /// both match.
    private static func extractDate(from fileURL: URL) -> Date? {
        let components = fileURL.pathComponents
        let pattern = /\b(\d{8})\b/

        for component in components {
            if let match = component.firstMatch(of: pattern) {
                // Parsed as UTC to match every other date in the app — a local-time parse can
                // shift a scene into the neighbouring calendar day.
                return yyyymmddFormatter.date(from: String(match.1))
            }
        }
        return nil
    }
}
