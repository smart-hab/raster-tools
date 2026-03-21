//
//  ToolRunner.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation

/// Progress information for tool execution
struct ToolProgress {
    var currentStep: String
    var currentFile: String?
    var completedFiles: Int
    var totalFiles: Int
    var logs: [String]
    
    var progress: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(completedFiles) / Double(totalFiles)
    }
}

/// Observable class for running geospatial tools
@Observable
class ToolRunner {
    var isRunning = false
    var progress = ToolProgress(currentStep: "", currentFile: nil, completedFiles: 0, totalFiles: 0, logs: [])
    var error: Error?
    
    private var currentProcess: Process?
    
    func cancel() {
        currentProcess?.terminate()
        isRunning = false
    }
    
    /// Run a subprocess and capture output
    @discardableResult
    func runProcess(executable: String, arguments: [String]) async throws -> String {
        let process = Process()
        currentProcess = process
        
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        var outputData = Data()
        var errorData = Data()
        
        // Read output
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputData.append(handle.availableData)
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorData.append(handle.availableData)
        }
        
        try process.run()
        process.waitUntilExit()
        
        // Stop reading
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            throw ToolError.processError(
                code: process.terminationStatus,
                message: errorOutput.isEmpty ? "Process failed" : errorOutput
            )
        }
        
        return output
    }
    
    /// Log a message
    func log(_ message: String) {
        Task { @MainActor in
            progress.logs.append(message)
            print("🔧 \(message)")
        }
    }
    
    /// Update current step
    func updateStep(_ step: String, file: String? = nil) {
        Task { @MainActor in
            progress.currentStep = step
            progress.currentFile = file
            log(file != nil ? "\(step): \(file!)" : step)
        }
    }
    
    /// Mark file as completed
    func completeFile() {
        Task { @MainActor in
            progress.completedFiles += 1
        }
    }
}

enum ToolError: LocalizedError {
    case processError(code: Int32, message: String)
    case missingConfiguration
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .processError(let code, let message):
            return "Process failed with exit code \(code): \(message)"
        case .missingConfiguration:
            return "Configuration is missing or invalid"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}
