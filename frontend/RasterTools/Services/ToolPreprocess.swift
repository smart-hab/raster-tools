//
//  ToolPreprocess.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import SwiftData

/// Runs preprocessing workflow on satellite imagery
class ToolPreprocess: ToolRunner {

    func run(configuration: ToolPreprocessConfiguration, context: ModelContext) async throws {
        let project = configuration.project
        guard let shapeFileResource = configuration.shapeFile else {
            throw ToolError.fileNotFound("No shape file selected")
        }

        let total = configuration.files.count
        let outputDir = AppStorage.outputDirectory(for: project, configuration: configuration)
        await MainActor.run {
            isRunning = true
            logFile = AppStorage.outputDirectory(for: project).appendingPathComponent("\(configuration.name)-\(generateTimestamp()).log")
            progress = ToolProgress(statusText: "Starting preprocessing", progress: 0, progressText: "0 / \(total)")
        }
        await log("[0/\(total)] Starting processing...")
        var completed = 0

        do {
            let shapeFilePath = shapeFileResource.originalPath
            let outputDir = outputDir.path

            guard FileManager.default.fileExists(atPath: shapeFilePath) else {
                throw ToolError.fileNotFound(shapeFilePath)
            }

            for rasterResource in configuration.files {
                try await preprocessRaster(
                    rasterResource: rasterResource,
                    outputDir: outputDir,
                    shapeFile: shapeFilePath,
                    processes: configuration.processTypes,
                    configuration: configuration,
                    project: project,
                    context: context,
                    total: total,
                    completed: &completed
                )
            }

            await update(ToolProgress(statusText: "Preprocessing complete!", progress: 1, progressText: "\(total) / \(total)"))
            await log("[\(total)/\(total)] Processing complete!")

        } catch {
            // The log is where the user looks first, and a failing step's stderr only reaches
            // them through here.
            await log("✗ \(error.localizedDescription)")
            await update(ToolProgress(statusText: "Error", progress: progress.progress, progressText: progress.progressText))
            await MainActor.run {
                self.error = error
                isRunning = false
            }
            throw error
        }

        await MainActor.run {
            isRunning = false
        }
    }

    private func preprocessRaster(
        rasterResource: ProjectResource,
        outputDir: String,
        shapeFile: String,
        processes: [ResourceKind],
        configuration: ToolPreprocessConfiguration,
        project: Project,
        context: ModelContext,
        total: Int,
        completed: inout Int
    ) async throws {
        let inputPath = rasterResource.originalPath
        defer { completed += 1 }

        guard let profile = rasterResource.kind.bandProfile else {
            await log("[\(completed + 1)/\(total)] ⚠️ Skipping \(rasterResource.filename): not a source raster")
            return
        }

        let stem = rasterResource.date.map { Date.compactUTCFormatter.string(from: $0) }
            ?? URL(fileURLWithPath: inputPath).deletingPathExtension().lastPathComponent
        let baseName = stem + profile.outputTag
        let dateLabel = rasterResource.date?.displayString ?? baseName
        let rgbArguments = ["--rgb"] + profile.rgb.map(String.init)

        await update(ToolProgress(statusText: "Processing \(dateLabel)", progress: Double(completed) / Double(total), progressText: "\(completed) / \(total)"))
        await log("[\(completed + 1)/\(total)] \(baseName) (\(rasterResource.kind.displayName))")

        // Step 1: Clip to shape boundary
        let clippedPath = "\(outputDir)/\(baseName)_clipped.tif"
        let clippedPng = clippedPath.replacingOccurrences(of: ".tif", with: ".png")
        let clippedFilename = URL(fileURLWithPath: clippedPath).lastPathComponent

        var clippedResource = project.resources.first { $0.originalPath == clippedPath }

        if clippedResource == nil {
            await update(ToolProgress(statusText: "Clipping \(dateLabel)", progress: Double(completed) / Double(total), progressText: "\(completed) / \(total)"))
            await log("  Clipping...")
            try await runProcess(
                executable: "clip",
                arguments: ["-i", inputPath, "-o", clippedPath, "-s", shapeFile]
            )
            if !FileManager.default.fileExists(atPath: clippedPng) {
                try await runProcess(
                    executable: "plot",
                    arguments: rgbArguments + ["-i", clippedPath, "-o", clippedPng]
                )
            }
            clippedResource = makeResource(
                path: clippedPath,
                kind: .clipped,
                date: rasterResource.date,
                parents: [rasterResource],
                pngPath: FileManager.default.fileExists(atPath: clippedPng) ? clippedPng : nil,
                producedBy: configuration.id,
                project: project,
                context: context
            )
        }
        await log("  \(clippedFilename)")

        // Step 2: Apply the cloud mask when the raster has one; otherwise indices are
        // calculated on the clipped raster.
        var indexInputPath = clippedPath
        var indexInputResource = clippedResource
        var indexStem = "\(baseName)_clipped"

        if let maskPath = cloudMaskPath(for: rasterResource) {
            let maskedPath = "\(outputDir)/\(baseName)_clipped_masked.tif"
            let maskedPng = maskedPath.replacingOccurrences(of: ".tif", with: ".png")
            let maskedFilename = URL(fileURLWithPath: maskedPath).lastPathComponent

            var maskedResource = project.resources.first { $0.originalPath == maskedPath }

            if maskedResource == nil {
                await update(ToolProgress(statusText: "Masking \(dateLabel)", progress: Double(completed) / Double(total), progressText: "\(completed) / \(total)"))
                await log("  Masking...")
                try await runProcess(
                    executable: "mask",
                    arguments: ["-i", clippedPath, "-u", maskPath, "-o", maskedPath, "-b"]
                        + profile.maskBands.map(String.init)
                )
                if !FileManager.default.fileExists(atPath: maskedPng) {
                    try await runProcess(
                        executable: "plot",
                        arguments: rgbArguments + ["-i", maskedPath, "-o", maskedPng]
                    )
                }
                var maskParents: [ProjectResource] = []
                if let cr = clippedResource { maskParents.append(cr) }
                if let udm = rasterResource.udm { maskParents.append(udm) }
                maskedResource = makeResource(
                    path: maskedPath,
                    kind: .masked,
                    date: rasterResource.date,
                    parents: maskParents,
                    pngPath: FileManager.default.fileExists(atPath: maskedPng) ? maskedPng : nil,
                    producedBy: configuration.id,
                    project: project,
                    context: context
                )
            }
            await log("  Cloud mask applied (\(URL(fileURLWithPath: maskPath).lastPathComponent))")
            await log("  \(maskedFilename)")

            indexInputPath = maskedPath
            indexInputResource = maskedResource
            indexStem = "\(baseName)_clipped_masked"
        } else {
            await log("  No cloud mask found — skipping masking")
        }

        // Step 3: Calculate indices
        for process in processes {
            switch process {
            case .ndci:
                try await calculateIndex(
                    name: "NDCI",
                    kind: .ndci,
                    inputPath: indexInputPath,
                    outputPath: "\(outputDir)/\(indexStem)_ndci.tif",
                    band1: profile.redEdge,
                    band2: profile.red,
                    date: rasterResource.date,
                    inputResource: indexInputResource,
                    configuration: configuration,
                    project: project,
                    context: context
                )

            case .ndvi:
                try await calculateIndex(
                    name: "NDVI",
                    kind: .ndvi,
                    inputPath: indexInputPath,
                    outputPath: "\(outputDir)/\(indexStem)_ndvi.tif",
                    band1: profile.nir,
                    band2: profile.red,
                    date: rasterResource.date,
                    inputResource: indexInputResource,
                    configuration: configuration,
                    project: project,
                    context: context
                )

            default:
                await log("  ⚠️ Unimplemented preprocess kind: \(process)")
            }
        }
    }

    /// The cloud mask for a source raster, if one exists on disk.
    ///
    /// Planet rasters carry a UDM2 sibling. Sentinel-2 products keep `MSK_CLASSI_B00.jp2` in the
    /// `.SAFE` tree next to the stacked raster; products older than processing baseline 04.00
    /// ship GML masks instead, and have no usable mask here.
    private func cloudMaskPath(for resource: ProjectResource) -> String? {
        let fm = FileManager.default
        let rasterURL = URL(fileURLWithPath: resource.originalPath)

        switch resource.kind {
        case .planet:
            let path = resource.udm?.originalPath
                ?? rasterURL.deletingPathExtension().path + "_udm2.tif"
            return fm.fileExists(atPath: path) ? path : nil

        case .sentinel:
            let stem = rasterURL.lastPathComponent.replacingOccurrences(of: "_13band.tif", with: "")
            let granules = rasterURL.deletingLastPathComponent()
                .appending(path: "\(stem).SAFE")
                .appending(path: "GRANULE")
            let names = (try? fm.contentsOfDirectory(atPath: granules.path)) ?? []
            return names.sorted()
                .map { granules.appending(path: $0).appending(path: "QI_DATA/MSK_CLASSI_B00.jp2").path }
                .first { fm.fileExists(atPath: $0) }

        default:
            return nil
        }
    }

    private func calculateIndex(
        name: String,
        kind: ResourceKind,
        inputPath: String,
        outputPath: String,
        band1: Int,
        band2: Int,
        date: Date?,
        inputResource: ProjectResource?,
        configuration: ToolPreprocessConfiguration,
        project: Project,
        context: ModelContext
    ) async throws {
        let pngPath = outputPath.replacingOccurrences(of: ".tif", with: ".png")
        let outputFilename = URL(fileURLWithPath: outputPath).lastPathComponent

        let alreadyExists = project.resources.contains { $0.originalPath == outputPath }
        if !alreadyExists {
            await log("  \(name)...")
            try await runProcess(
                executable: "norm_diff",
                arguments: ["-i", inputPath, "-o", outputPath, "-b", String(band1), String(band2)]
            )
            if !FileManager.default.fileExists(atPath: pngPath) {
                try await runProcess(
                    executable: "plot",
                    arguments: ["-i", outputPath, "-o", pngPath]
                )
            }
            var parents: [ProjectResource] = []
            if let input = inputResource { parents.append(input) }
            makeResource(
                path: outputPath,
                kind: kind,
                date: date,
                parents: parents,
                pngPath: FileManager.default.fileExists(atPath: pngPath) ? pngPath : nil,
                producedBy: configuration.id,
                project: project,
                context: context
            )
        }

        await log("  \(outputFilename)")
    }
}
