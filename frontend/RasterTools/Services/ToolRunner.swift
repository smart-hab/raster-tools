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
    
    /// Resolve an executable name to a full path using the configured virtualenv.
    /// Run a subprocess and capture output
    @discardableResult
    func runProcess(executable: String, arguments: [String]) async throws -> String {
        let process = Process()
        currentProcess = process

        let venv = AppSettings.shared.virtualEnvPath
        guard !venv.isEmpty else {
            throw ToolError.missingVirtualEnv
        }
        let venvBin = (venv as NSString).appendingPathComponent("bin")
        let python = (venvBin as NSString).appendingPathComponent("python")
        let script = (venvBin as NSString).appendingPathComponent(executable)
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script] + arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            throw ToolError.processError(
                code: process.terminationStatus,
                message: errorOutput.isEmpty ? "Process failed" : errorOutput
            )
        }
        
        return output
    }
    
    /// Log a message
    func log(_ message: String) async {
        await MainActor.run {
            progress.logs.append(message)
            print("🔧 \(message)")
        }
    }

    /// Update current step
    func updateStep(_ step: String, file: String? = nil) async {
        await MainActor.run {
            progress.currentStep = step
            progress.currentFile = file
        }
        await log(file != nil ? "\(step): \(file!)" : step)
    }

    /// Mark file as completed
    func completeFile() async {
        await MainActor.run {
            progress.completedFiles += 1
        }
    }
}


enum ToolError: LocalizedError {
    case processError(code: Int32, message: String)
    case missingConfiguration
    case missingVirtualEnv
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .processError(let code, let message):
            return "Process failed with exit code \(code): \(message)"
        case .missingConfiguration:
            return "Configuration is missing or invalid"
        case .missingVirtualEnv:
            return "No virtual environment configured. Set it in Settings."
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}
