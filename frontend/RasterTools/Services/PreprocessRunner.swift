//
//  PreprocessRunner.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation

/// Runs preprocessing workflow on satellite imagery
class PreprocessRunner: ToolRunner {
    
    func run(configuration: ToolConfiguration) async throws {
        guard let config = configuration.preprocessConfig else {
            throw ToolError.missingConfiguration
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
            let workspace = configuration.workspacePath
            let shapeFilePath = "\(workspace)/\(config.shapeFile)"
            
            // Validate shape file exists
            guard FileManager.default.fileExists(atPath: shapeFilePath) else {
                throw ToolError.fileNotFound(shapeFilePath)
            }
            
            // Process each raster file
            for rasterFile in config.files {
                try await preprocessRaster(
                    rasterFile: rasterFile,
                    workspace: workspace,
                    shapeFile: shapeFilePath,
                    processes: config.processTypes
                )
                completeFile()
            }
            
            updateStep("✅ Preprocessing complete!")
            
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
        rasterFile: String,
        workspace: String,
        shapeFile: String,
        processes: [PreprocessType]
    ) async throws {
        let baseName = rasterFile.replacingOccurrences(of: ".tif", with: "")
        let inputPath = "\(workspace)/\(rasterFile)"
        let udmPath = "\(workspace)/\(baseName)_udm2.tif"
        
        log("Processing: \(rasterFile)")
        
        // Step 1: Clip to shape boundary
        let clippedPath = "\(workspace)/\(baseName)_clipped.tif"
        let clippedPng = clippedPath.replacingOccurrences(of: ".tif", with: ".png")
        
        if !FileManager.default.fileExists(atPath: clippedPath) {
            updateStep("Clipping", file: rasterFile)
            try await runProcess(
                executable: "clip",
                arguments: ["-i", inputPath, "-o", clippedPath, "-s", shapeFile]
            )
        }
        
        // Generate RGB composite PNG
        if !FileManager.default.fileExists(atPath: clippedPng) {
            try await runProcess(
                executable: "plot",
                arguments: ["--rgb", "6", "4", "2", "-i", clippedPath, "-o", clippedPng]
            )
        }
        
        log("  ✓ Clipped")
        
        // Step 2: Apply UDM2 mask (cloud/shadow removal)
        let maskedPath = "\(workspace)/\(baseName)_clipped_masked.tif"
        let maskedPng = maskedPath.replacingOccurrences(of: ".tif", with: ".png")
        
        if !FileManager.default.fileExists(atPath: maskedPath) {
            updateStep("Masking", file: rasterFile)
            try await runProcess(
                executable: "mask",
                arguments: ["-i", clippedPath, "-u", udmPath, "-o", maskedPath]
            )
        }
        
        if !FileManager.default.fileExists(atPath: maskedPng) {
            try await runProcess(
                executable: "plot",
                arguments: ["--rgb", "6", "4", "2", "-i", maskedPath, "-o", maskedPng]
            )
        }
        
        log("  ✓ Masked")
        
        // Step 3: Calculate indices based on selected processes
        for process in processes {
            switch process {
            case .ndci:
                try await calculateIndex(
                    name: "NDCI",
                    inputPath: maskedPath,
                    outputPath: "\(workspace)/\(baseName)_clipped_masked_ndci.tif",
                    band1: "7",
                    band2: "6",
                    rasterFile: rasterFile
                )
                
            case .ndvi:
                try await calculateIndex(
                    name: "NDVI",
                    inputPath: maskedPath,
                    outputPath: "\(workspace)/\(baseName)_clipped_masked_ndvi.tif",
                    band1: "8",
                    band2: "6",
                    rasterFile: rasterFile
                )
            }
        }
    }
    
    private func calculateIndex(
        name: String,
        inputPath: String,
        outputPath: String,
        band1: String,
        band2: String,
        rasterFile: String
    ) async throws {
        let pngPath = outputPath.replacingOccurrences(of: ".tif", with: ".png")
        
        if !FileManager.default.fileExists(atPath: outputPath) {
            updateStep("Calculating \(name)", file: rasterFile)
            try await runProcess(
                executable: "norm_diff",
                arguments: ["-i", inputPath, "-o", outputPath, "-b", band1, band2]
            )
        }
        
        if !FileManager.default.fileExists(atPath: pngPath) {
            try await runProcess(
                executable: "plot",
                arguments: ["-i", outputPath, "-o", pngPath]
            )
        }
        
        log("  ✓ \(name)")
    }
}
