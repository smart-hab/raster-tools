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

    func run(configuration: ToolConfiguration, context: ModelContext) async throws {
        guard let config = configuration.preprocessConfig else {
            throw ToolError.missingConfiguration
        }
        guard let workspace = configuration.workspace else {
            throw ToolError.missingConfiguration
        }
        guard let shapeFileResource = config.shapeFile else {
            throw ToolError.fileNotFound("No shape file selected")
        }

        await MainActor.run {
            isRunning = true
            progress = ToolProgress(
                currentStep: "Starting preprocessing",
                currentFile: nil,
                completedFiles: 0,
                totalFiles: config.files.count,
                logs: []
            )
        }

        do {
            let shapeFilePath = shapeFileResource.originalPath
            let outputDir = AppStorage.outputDirectory(for: workspace, configuration: configuration).path

            guard FileManager.default.fileExists(atPath: shapeFilePath) else {
                throw ToolError.fileNotFound(shapeFilePath)
            }

            for rasterResource in config.files {
                try await preprocessRaster(
                    rasterResource: rasterResource,
                    outputDir: outputDir,
                    shapeFile: shapeFilePath,
                    processes: config.processTypes,
                    configuration: configuration,
                    workspace: workspace,
                    context: context
                )
                await completeFile()
            }

            await updateStep("Preprocessing complete!")

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
        rasterResource: WorkspaceResource,
        outputDir: String,
        shapeFile: String,
        processes: [ResourceKind],
        configuration: ToolConfiguration,
        workspace: Workspace,
        context: ModelContext
    ) async throws {
        let inputPath = rasterResource.originalPath
        // Use the resource date as a unique prefix (YYYYMMDD) so that multiple
        // composite.tif files from different dates produce distinct output filenames.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let baseName = rasterResource.date.map { formatter.string(from: $0) }
            ?? URL(fileURLWithPath: inputPath).deletingPathExtension().lastPathComponent

        // Derive UDM path from the resource's linked udm companion
        let udmPath: String
        if let udmResource = rasterResource.udm {
            udmPath = udmResource.originalPath
        } else {
            udmPath = URL(fileURLWithPath: inputPath).deletingPathExtension().path + "_udm2.tif"
        }

        await log("Processing: \(baseName)")

        // Step 1: Clip to shape boundary
        let clippedPath = "\(outputDir)/\(baseName)_clipped.tif"
        let clippedPng = clippedPath.replacingOccurrences(of: ".tif", with: ".png")

        let clippedExists = workspace.resources.contains { $0.originalPath == clippedPath }
        var clippedResource: WorkspaceResource?

        if !clippedExists {
            await updateStep("Clipping", file: baseName)
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
                producedBy: configuration,
                workspace: workspace,
                context: context
            )
        } else {
            clippedResource = workspace.resources.first { $0.originalPath == clippedPath }
        }

        await log("  ✓ Clipped")

        // Step 2: Apply UDM2 mask (cloud/shadow removal)
        let maskedPath = "\(outputDir)/\(baseName)_clipped_masked.tif"
        let maskedPng = maskedPath.replacingOccurrences(of: ".tif", with: ".png")

        let maskedExists = workspace.resources.contains { $0.originalPath == maskedPath }
        var maskedResource: WorkspaceResource?

        if !maskedExists {
            await updateStep("Masking", file: baseName)
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
            var maskParents: [WorkspaceResource] = []
            if let cr = clippedResource { maskParents.append(cr) }
            if let udm = rasterResource.udm { maskParents.append(udm) }
            maskedResource = makeResource(
                path: maskedPath,
                kind: .masked,
                date: rasterResource.date,
                parents: maskParents,
                pngPath: FileManager.default.fileExists(atPath: maskedPng) ? maskedPng : nil,
                producedBy: configuration,
                workspace: workspace,
                context: context
            )
        } else {
            maskedResource = workspace.resources.first { $0.originalPath == maskedPath }
        }

        await log("  ✓ Masked")

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
                    workspace: workspace,
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
                    workspace: workspace,
                    context: context
                )

            default:
                await log("⚠️ Unimplemented preprocess kind: \(process)")
            }
        }
    }

    private func calculateIndex(
        name: String,
        kind: ResourceKind,
        inputPath: String,
        outputPath: String,
        band1: String,
        band2: String,
        date: Date?,
        maskedResource: WorkspaceResource?,
        configuration: ToolConfiguration,
        workspace: Workspace,
        context: ModelContext
    ) async throws {
        let pngPath = outputPath.replacingOccurrences(of: ".tif", with: ".png")

        let alreadyExists = workspace.resources.contains { $0.originalPath == outputPath }
        if !alreadyExists {
            await updateStep("Calculating \(name)", file: URL(fileURLWithPath: inputPath).lastPathComponent)
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
            var parents: [WorkspaceResource] = []
            if let mr = maskedResource { parents.append(mr) }
            makeResource(
                path: outputPath,
                kind: kind,
                date: date,
                parents: parents,
                pngPath: FileManager.default.fileExists(atPath: pngPath) ? pngPath : nil,
                producedBy: configuration,
                workspace: workspace,
                context: context
            )
        }

        await log("  ✓ \(name)")
    }
}
