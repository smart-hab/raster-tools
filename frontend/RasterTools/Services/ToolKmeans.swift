//
//  ToolKmeans.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import SwiftData

/// Runs K-means clustering workflow on raster data
class ToolKmeans: ToolRunner {

    func run(configuration: ToolKmeansConfiguration, context: ModelContext) async throws {
        let project = configuration.project
        let outputDir = AppStorage.outputDirectory(for: project, configuration: configuration)
        logFile = outputDir.appendingPathComponent("\(configuration.name)-\(generateTimestamp()).log")
        let total = 1 + configuration.filesClassify.count
        await MainActor.run {
            isRunning = true
            progress = ToolProgress(statusText: "Starting K-Means", progress: 0, progressText: "0 / \(total)")
        }
        await log("[0/\(total)] Starting K-Means...")
        var completed = 0

        do {
            let outputDir = AppStorage.outputDirectory(for: project, configuration: configuration).path

            // Step 1: Fit K-means model
            try await fitKmeans(outputDir: outputDir, configuration: configuration, project: project, context: context, total: total, completed: &completed)

            // Step 2: Classify rasters
            try await classifyRasters(outputDir: outputDir, configuration: configuration, project: project, context: context, total: total, completed: &completed)

            // Step 3: Generate mean raster
            try await generateMeanRaster(outputDir: outputDir, configuration: configuration, project: project, context: context)

            // Step 4: Generate difference rasters
            try await generateDifferenceRasters(outputDir: outputDir, configuration: configuration, project: project, context: context)

            await update(ToolProgress(statusText: "K-Means complete!", progress: 1, progressText: "\(total) / \(total)"))
            await log("[\(total)/\(total)] K-Means complete!")

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

    private func fitKmeans(
        outputDir: String,
        configuration: ToolKmeansConfiguration,
        project: Project,
        context: ModelContext,
        total: Int,
        completed: inout Int
    ) async throws {
        let centersPath = "\(outputDir)/centers.txt"
        let centersFilename = URL(fileURLWithPath: centersPath).lastPathComponent

        await update(ToolProgress(statusText: "Fitting K-Means model", progress: Double(completed) / Double(total), progressText: "\(completed) / \(total)"))
        await log("[\(completed + 1)/\(total)] Fitting K-Means model")

        if project.resources.contains(where: { $0.originalPath == centersPath }) {
            await log("  \(centersFilename)")
            completed += 1
            return
        }

        await log("  Fitting...")
        let inputPaths = configuration.filesFit.map { $0.originalPath }
        var args = ["-o", centersPath]
        args += ["-t", String(configuration.nTimes)]
        args += ["-c", String(configuration.centroids)]
        args += ["-r", String(configuration.seed)]
        args += ["-i"] + inputPaths

        try await runProcess(executable: "kmeans_fit", arguments: args)
        makeResource(
            path: centersPath,
            kind: .kmeansCenters,
            date: nil,
            parents: configuration.filesFit,
            producedBy: configuration.id,
            project: project,
            context: context
        )
        await log("  \(centersFilename)")
        completed += 1
    }

    private func classifyRasters(
        outputDir: String,
        configuration: ToolKmeansConfiguration,
        project: Project,
        context: ModelContext,
        total: Int,
        completed: inout Int
    ) async throws {
        let centersPath = "\(outputDir)/centers.txt"

        for sourceResource in configuration.filesClassify {
            let inputPath = sourceResource.originalPath
            let baseName = URL(fileURLWithPath: inputPath).deletingPathExtension().lastPathComponent
            let dateLabel = sourceResource.date?.displayString ?? baseName
            let outputFile = "\(baseName)_classed.tif"
            let outputPath = "\(outputDir)/\(outputFile)"
            let pngPath = outputPath.replacingOccurrences(of: ".tif", with: ".png")

            await update(ToolProgress(statusText: "Classifying: \(dateLabel)", progress: Double(completed) / Double(total), progressText: "\(completed) / \(total)"))
            await log("[\(completed + 1)/\(total)] \(baseName)")

            let alreadyExists = project.resources.contains { $0.originalPath == outputPath }
            if !alreadyExists {
                await log("  Classifying...")
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
                makeResource(
                    path: outputPath,
                    kind: .kmeansClassed,
                    date: sourceResource.date,
                    parents: [sourceResource],
                    pngPath: FileManager.default.fileExists(atPath: pngPath) ? pngPath : nil,
                    producedBy: configuration.id,
                    project: project,
                    context: context
                )
            }

            await log("  \(outputFile)")
            completed += 1
        }
    }

    private func generateMeanRaster(
        outputDir: String,
        configuration: ToolKmeansConfiguration,
        project: Project,
        context: ModelContext
    ) async throws {
        let outputPath = "\(outputDir)/mean.tif"
        let pngPath = outputPath.replacingOccurrences(of: ".tif", with: ".png")
        let outputFilename = URL(fileURLWithPath: outputPath).lastPathComponent

        await update(ToolProgress(statusText: "Generating mean raster", progress: progress.progress, progressText: progress.progressText))
        await log("Generating mean raster")

        let alreadyExists = project.resources.contains { $0.originalPath == outputPath }
        if !alreadyExists {
            await log("  Calculating mean...")
            let inputPaths = configuration.filesFit.map { $0.originalPath }
            let args = ["-o", outputPath, "-i"] + inputPaths

            try await runProcess(executable: "means", arguments: args)
            if !FileManager.default.fileExists(atPath: pngPath) {
                try await runProcess(
                    executable: "plot",
                    arguments: ["-i", outputPath, "-o", pngPath]
                )
            }
            makeResource(
                path: outputPath,
                kind: .kmeansMean,
                date: nil,
                parents: configuration.filesFit,
                pngPath: FileManager.default.fileExists(atPath: pngPath) ? pngPath : nil,
                producedBy: configuration.id,
                project: project,
                context: context
            )
        }

        await log("  \(outputFilename)")
    }

    private func generateDifferenceRasters(
        outputDir: String,
        configuration: ToolKmeansConfiguration,
        project: Project,
        context: ModelContext
    ) async throws {
        let meanPath = "\(outputDir)/mean.tif"

        await update(ToolProgress(statusText: "Calculating differences", progress: progress.progress, progressText: progress.progressText))
        await log("Calculating differences")

        for sourceResource in configuration.filesClassify {
            let inputPath = sourceResource.originalPath
            let filename = URL(fileURLWithPath: inputPath).lastPathComponent
            let date = String(filename.prefix(8))
            let dateLabel = sourceResource.date?.displayString ?? date

            let outputPath = "\(outputDir)/mean_diff_\(date).tif"
            let pngPath = outputPath.replacingOccurrences(of: ".tif", with: ".png")
            let outputFilename = URL(fileURLWithPath: outputPath).lastPathComponent

            let alreadyExists = project.resources.contains { $0.originalPath == outputPath }
            if !alreadyExists {
                await log("  \(dateLabel)...")
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
                let meanResource = project.resources.first { $0.originalPath == meanPath }
                var parents: [ProjectResource] = [sourceResource]
                if let mr = meanResource { parents.append(mr) }
                makeResource(
                    path: outputPath,
                    kind: .kmeansDiff,
                    date: sourceResource.date,
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
}
