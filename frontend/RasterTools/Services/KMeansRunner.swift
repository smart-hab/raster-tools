//
//  KMeansRunner.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation

/// Runs K-means clustering workflow on raster data
class KMeansRunner: ToolRunner {
    
    func run(configuration: ToolConfiguration) async throws {
        guard let config = configuration.kmeansConfig else {
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
            let workspace = configuration.workspace?.sourceDirectory ?? ""
            
            // Step 1: Fit K-means model
            try await fitKMeans(workspace: workspace, config: config)
            
            // Step 2: Classify rasters
            try await classifyRasters(workspace: workspace, config: config)
            
            // Step 3: Generate mean raster
            try await generateMeanRaster(workspace: workspace, config: config)
            
            // Step 4: Generate difference rasters
            try await generateDifferenceRasters(workspace: workspace, config: config)
            
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
    
    private func fitKMeans(workspace: String, config: KMeansConfiguration) async throws {
        let centersPath = "\(workspace)/\(config.centersFile)"
        
        // Skip if centers file already exists
        if FileManager.default.fileExists(atPath: centersPath) {
            await log("✓ Using existing centers file: \(config.centersFile)")
            return
        }

        await updateStep("Fitting K-Means model")
        
        var args = ["-o", centersPath]
        args += ["-t", String(config.nTimes)]
        args += ["-c", String(config.centroids)]
        args += ["-r", String(config.seed)]
        args += ["-i"] + config.filesFit
        
        try await runProcess(executable: "kmeans_fit", arguments: args)
        await log("✓ Fitted K-means model: \(config.centersFile)")
        await completeFile()
    }
    
    private func classifyRasters(workspace: String, config: KMeansConfiguration) async throws {
        await updateStep("Classifying rasters")
        
        let centersPath = "\(workspace)/\(config.centersFile)"
        
        for inputFile in config.filesClassify {
            let inputPath = inputFile
            let baseName = URL(fileURLWithPath: inputFile).lastPathComponent
            let outputFile = baseName.replacingOccurrences(of: ".tif", with: "_classed.tif")
            let outputPath = "\(workspace)/\(outputFile)"
            let pngPath = outputPath.replacingOccurrences(of: ".tif", with: ".png")

            await updateStep("Classifying", file: baseName)
            
            // Classify if output doesn't exist
            if !FileManager.default.fileExists(atPath: outputPath) {
                try await runProcess(
                    executable: "kmeans_classify",
                    arguments: ["-i", inputPath, "-k", centersPath, "-o", outputPath]
                )
            }
            
            // Generate PNG if it doesn't exist
            if !FileManager.default.fileExists(atPath: pngPath) {
                try await runProcess(
                    executable: "plot",
                    arguments: ["-i", outputPath, "-o", pngPath]
                )
            }
            
            await log("✓ \(outputFile)")
            await completeFile()
        }
    }

    private func generateMeanRaster(workspace: String, config: KMeansConfiguration) async throws {
        let baseName = config.centersFile.replacingOccurrences(of: ".txt", with: "")
        let outputPath = "\(workspace)/\(baseName)_mean.tif"
        let pngPath = outputPath.replacingOccurrences(of: ".tif", with: ".png")
        
        // Skip if already exists
        if FileManager.default.fileExists(atPath: outputPath) {
            await log("✓ Using existing mean raster")
            return
        }

        await updateStep("Generating mean raster")
        
        var args = ["-o", outputPath, "-i"] + config.filesFit
        
        try await runProcess(executable: "means", arguments: args)
        
        // Generate PNG
        if !FileManager.default.fileExists(atPath: pngPath) {
            try await runProcess(
                executable: "plot",
                arguments: ["-i", outputPath, "-o", pngPath]
            )
        }
        
        await log("✓ \(baseName)_mean.tif")
    }

    private func generateDifferenceRasters(workspace: String, config: KMeansConfiguration) async throws {
        await updateStep("Generating difference rasters")
        
        let baseName = config.centersFile.replacingOccurrences(of: ".txt", with: "")
        let meanPath = "\(workspace)/\(baseName)_mean.tif"
        
        for inputFile in config.filesClassify {
            // Extract date from filename (assumes YYYYMMDD format at start)
            let filename = URL(fileURLWithPath: inputFile).lastPathComponent
            let date = String(filename.prefix(8))

            let outputPath = "\(workspace)/\(baseName)_mean_diff_\(date).tif"
            let pngPath = outputPath.replacingOccurrences(of: ".tif", with: ".png")

            await updateStep("Calculating difference", file: date)

            // Generate difference if it doesn't exist
            if !FileManager.default.fileExists(atPath: outputPath) {
                try await runProcess(
                    executable: "subtract",
                    arguments: ["-i", meanPath, inputFile, "-o", outputPath]
                )
            }
            
            // Generate PNG
            if !FileManager.default.fileExists(atPath: pngPath) {
                try await runProcess(
                    executable: "plot",
                    arguments: ["-i", outputPath, "-o", pngPath]
                )
            }
            
            await log("✓ \(baseName)_mean_diff_\(date).tif")
        }
    }
}
