//
//  KMeansRunner.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import SwiftData

/// Runs K-means clustering workflow on raster data
class KMeansRunner: ToolRunner {

    func run(configuration: ToolConfiguration, context: ModelContext) async throws {
        guard let config = configuration.kmeansConfig else {
            throw ToolError.missingConfiguration
        }
        guard let workspace = configuration.workspace else {
            throw ToolError.missingConfiguration
        }

        await MainActor.run {
            isRunning = true
            progress = ToolProgress(
                currentStep: "Starting K-Means",
                currentFile: nil,
                completedFiles: 0,
                totalFiles: config.filesFit.count + config.filesClassify.count,
                logs: []
            )
        }

        do {
            let outputDir = AppStorage.outputDirectory(for: workspace).path

            // Step 1: Fit K-means model
            try await fitKMeans(outputDir: outputDir, config: config, configuration: configuration, workspace: workspace, context: context)

            // Step 2: Classify rasters
            try await classifyRasters(outputDir: outputDir, config: config, configuration: configuration, workspace: workspace, context: context)

            // Step 3: Generate mean raster
            try await generateMeanRaster(outputDir: outputDir, config: config, configuration: configuration, workspace: workspace, context: context)

            // Step 4: Generate difference rasters
            try await generateDifferenceRasters(outputDir: outputDir, config: config, configuration: configuration, workspace: workspace, context: context)

            await updateStep("✅ K-Means processing complete!")

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

    private func fitKMeans(
        outputDir: String,
        config: KMeansConfiguration,
        configuration: ToolConfiguration,
        workspace: Workspace,
        context: ModelContext
    ) async throws {
        let centersPath = "\(outputDir)/\(config.centersFile)"

        // Skip if centers file already exists on disk
        if FileManager.default.fileExists(atPath: centersPath) {
            await log("✓ Using existing centers file: \(config.centersFile)")
            return
        }

        await updateStep("Fitting K-Means model")

        let inputPaths = config.filesFit.map { $0.originalPath }
        var args = ["-o", centersPath]
        args += ["-t", String(config.nTimes)]
        args += ["-c", String(config.centroids)]
        args += ["-r", String(config.seed)]
        args += ["-i"] + inputPaths

        try await runProcess(executable: "kmeans_fit", arguments: args)
        await log("✓ Fitted K-means model: \(config.centersFile)")
        await completeFile()
    }

    private func classifyRasters(
        outputDir: String,
        config: KMeansConfiguration,
        configuration: ToolConfiguration,
        workspace: Workspace,
        context: ModelContext
    ) async throws {
        await updateStep("Classifying rasters")

        let centersPath = "\(outputDir)/\(config.centersFile)"

        for sourceResource in config.filesClassify {
            let inputPath = sourceResource.originalPath
            let baseName = URL(fileURLWithPath: inputPath).deletingPathExtension().lastPathComponent
            let outputFile = "\(baseName)_classed.tif"
            let outputPath = "\(outputDir)/\(outputFile)"
            let pngPath = outputPath.replacingOccurrences(of: ".tif", with: ".png")

            await updateStep("Classifying", file: baseName)

            let alreadyExists = workspace.resources.contains { $0.originalPath == outputPath }
            if !alreadyExists {
                try await runProcess(
                    executable: "kmeans_classify",
                    arguments: ["-i", inputPath, "-k", centersPath, "-o", outputPath]
                )
                if !FileManager.default.fileExists(atPath: pngPath) {
                    try await runProcess(
                        executable: "plot",
                        arguments: ["-i", outputPath, "-o", pngPath]
                    )
                }
                makeOutputResource(
                    path: outputPath,
                    kind: .kmeansClassed,
                    date: sourceResource.date,
                    parents: [sourceResource],
                    pngPath: FileManager.default.fileExists(atPath: pngPath) ? pngPath : nil,
                    producedBy: configuration,
                    workspace: workspace,
                    context: context
                )
            }

            await log("✓ \(outputFile)")
            await completeFile()
        }
    }

    private func generateMeanRaster(
        outputDir: String,
        config: KMeansConfiguration,
        configuration: ToolConfiguration,
        workspace: Workspace,
        context: ModelContext
    ) async throws {
        let baseName = config.centersFile.replacingOccurrences(of: ".txt", with: "")
        let outputPath = "\(outputDir)/\(baseName)_mean.tif"
        let pngPath = outputPath.replacingOccurrences(of: ".tif", with: ".png")

        let alreadyExists = workspace.resources.contains { $0.originalPath == outputPath }
        if alreadyExists {
            await log("✓ Using existing mean raster")
            return
        }

        await updateStep("Generating mean raster")

        let inputPaths = config.filesFit.map { $0.originalPath }
        let args = ["-o", outputPath, "-i"] + inputPaths

        try await runProcess(executable: "means", arguments: args)
        if !FileManager.default.fileExists(atPath: pngPath) {
            try await runProcess(
                executable: "plot",
                arguments: ["-i", outputPath, "-o", pngPath]
            )
        }
        makeOutputResource(
            path: outputPath,
            kind: .kmeansMean,
            date: nil,
            parents: config.filesFit,
            pngPath: FileManager.default.fileExists(atPath: pngPath) ? pngPath : nil,
            producedBy: configuration,
            workspace: workspace,
            context: context
        )

        await log("✓ \(baseName)_mean.tif")
    }

    private func generateDifferenceRasters(
        outputDir: String,
        config: KMeansConfiguration,
        configuration: ToolConfiguration,
        workspace: Workspace,
        context: ModelContext
    ) async throws {
        await updateStep("Generating difference rasters")

        let baseName = config.centersFile.replacingOccurrences(of: ".txt", with: "")
        let meanPath = "\(outputDir)/\(baseName)_mean.tif"

        for sourceResource in config.filesClassify {
            let inputPath = sourceResource.originalPath
            let filename = URL(fileURLWithPath: inputPath).lastPathComponent
            let date = String(filename.prefix(8))

            let outputPath = "\(outputDir)/\(baseName)_mean_diff_\(date).tif"
            let pngPath = outputPath.replacingOccurrences(of: ".tif", with: ".png")

            await updateStep("Calculating difference", file: date)

            let alreadyExists = workspace.resources.contains { $0.originalPath == outputPath }
            if !alreadyExists {
                try await runProcess(
                    executable: "subtract",
                    arguments: ["-i", meanPath, inputPath, "-o", outputPath]
                )
                if !FileManager.default.fileExists(atPath: pngPath) {
                    try await runProcess(
                        executable: "plot",
                        arguments: ["-i", outputPath, "-o", pngPath]
                    )
                }
                let meanResource = workspace.resources.first { $0.originalPath == meanPath }
                var parents: [WorkspaceResource] = [sourceResource]
                if let mr = meanResource { parents.append(mr) }
                makeOutputResource(
                    path: outputPath,
                    kind: .kmeansDiff,
                    date: sourceResource.date,
                    parents: parents,
                    pngPath: FileManager.default.fileExists(atPath: pngPath) ? pngPath : nil,
                    producedBy: configuration,
                    workspace: workspace,
                    context: context
                )
            }

            await log("✓ \(baseName)_mean_diff_\(date).tif")
        }
    }
}
