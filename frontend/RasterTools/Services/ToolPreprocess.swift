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
        await MainActor.run {
            isRunning = true
            progress = ToolProgress(statusText: "Starting preprocessing", progress: 0, progressText: "0 / \(total)")
        }
        await log("[0/\(total)] Starting processing...")
        var completed = 0

        do {
            let shapeFilePath = shapeFileResource.originalPath
            let outputDir = AppStorage.outputDirectory(for: project, configuration: configuration).path

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
            await MainActor.run {
                self.error = error
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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let baseName = rasterResource.date.map { formatter.string(from: $0) }
            ?? URL(fileURLWithPath: inputPath).deletingPathExtension().lastPathComponent
        let dateLabel = rasterResource.date?.displayString ?? baseName

        let udmPath: String
        if let udmResource = rasterResource.udm {
            udmPath = udmResource.originalPath
        } else {
            udmPath = URL(fileURLWithPath: inputPath).deletingPathExtension().path + "_udm2.tif"
        }

        await update(ToolProgress(statusText: "Processing \(dateLabel)", progress: Double(completed) / Double(total), progressText: "\(completed) / \(total)"))
        await log("[\(completed + 1)/\(total)] \(baseName)")

        // Step 1: Clip to shape boundary
        let clippedPath = "\(outputDir)/\(baseName)_clipped.tif"
        let clippedPng = clippedPath.replacingOccurrences(of: ".tif", with: ".png")
        let clippedFilename = URL(fileURLWithPath: clippedPath).lastPathComponent

        let clippedExists = project.resources.contains { $0.originalPath == clippedPath }
        var clippedResource: ProjectResource?

        if !clippedExists {
            await update(ToolProgress(statusText: "Clipping \(dateLabel)", progress: Double(completed) / Double(total), progressText: "\(completed) / \(total)"))
            await log("  Clipping...")
            try await runProcess(
                executable: "clip",
                arguments: ["-i", inputPath, "-o", clippedPath, "-s", shapeFile]
            )
            if !FileManager.default.fileExists(atPath: clippedPng) {
                try await runProcess(
                    executable: "plot",
                    arguments: ["--rgb", "6", "4", "2", "-i", clippedPath, "-o", clippedPng]
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
        } else {
            clippedResource = project.resources.first { $0.originalPath == clippedPath }
        }
        await log("  \(clippedFilename)")

        // Step 2: Apply UDM2 mask (cloud/shadow removal)
        let maskedPath = "\(outputDir)/\(baseName)_clipped_masked.tif"
        let maskedPng = maskedPath.replacingOccurrences(of: ".tif", with: ".png")
        let maskedFilename = URL(fileURLWithPath: maskedPath).lastPathComponent

        let maskedExists = project.resources.contains { $0.originalPath == maskedPath }
        var maskedResource: ProjectResource?

        if !maskedExists {
            await update(ToolProgress(statusText: "Masking \(dateLabel)", progress: Double(completed) / Double(total), progressText: "\(completed) / \(total)"))
            await log("  Masking...")
            try await runProcess(
                executable: "mask",
                arguments: ["-i", clippedPath, "-u", udmPath, "-o", maskedPath]
            )
            if !FileManager.default.fileExists(atPath: maskedPng) {
                try await runProcess(
                    executable: "plot",
                    arguments: ["--rgb", "6", "4", "2", "-i", maskedPath, "-o", maskedPng]
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
        } else {
            maskedResource = project.resources.first { $0.originalPath == maskedPath }
        }
        await log("  \(maskedFilename)")

        // Step 3: Calculate indices
        for process in processes {
            switch process {
            case .ndci:
                try await calculateIndex(
                    name: "NDCI",
                    kind: .ndci,
                    inputPath: maskedPath,
                    outputPath: "\(outputDir)/\(baseName)_clipped_masked_ndci.tif",
                    band1: "7",
                    band2: "6",
                    date: rasterResource.date,
                    maskedResource: maskedResource,
                    configuration: configuration,
                    project: project,
                    context: context
                )

            case .ndvi:
                try await calculateIndex(
                    name: "NDVI",
                    kind: .ndvi,
                    inputPath: maskedPath,
                    outputPath: "\(outputDir)/\(baseName)_clipped_masked_ndvi.tif",
                    band1: "8",
                    band2: "6",
                    date: rasterResource.date,
                    maskedResource: maskedResource,
                    configuration: configuration,
                    project: project,
                    context: context
                )

            default:
                await log("  ⚠️ Unimplemented preprocess kind: \(process)")
            }
        }

        completed += 1
    }

    private func calculateIndex(
        name: String,
        kind: ResourceKind,
        inputPath: String,
        outputPath: String,
        band1: String,
        band2: String,
        date: Date?,
        maskedResource: ProjectResource?,
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
                arguments: ["-i", inputPath, "-o", outputPath, "-b", band1, band2]
            )
            if !FileManager.default.fileExists(atPath: pngPath) {
                try await runProcess(
                    executable: "plot",
                    arguments: ["-i", outputPath, "-o", pngPath]
                )
            }
            var parents: [ProjectResource] = []
            if let mr = maskedResource { parents.append(mr) }
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
