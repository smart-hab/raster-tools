//
//  ToolRunner.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation
import SwiftData

/// Progress information for tool execution
struct ToolProgress {
    var statusText: String
    var progress: Double          // 0.0–1.0
    var progressText: String?     // optional label shown next to progress bar; nil → "42%"
    var logs: [String] = []
}

/// Observable class for running geospatial tools
@Observable
class ToolRunner {
    var isRunning = false
    var progress = ToolProgress(statusText: "", progress: 0, progressText: nil)
    var error: Error?
    var logFile: URL? = nil

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
    
    /// Update progress state (compact status header only — preserves existing logs).
    func update(_ p: ToolProgress) async {
        await MainActor.run {
            var updated = p
            updated.logs = progress.logs
            progress = updated
        }
        await Task.yield()
    }

    /// Append an arbitrary line to the log without changing status or progress.
    func log(_ text: String) async {
        await MainActor.run {
            progress.logs.append(text)
            print("🔧 \(text)")
        }
        appendToLogFile(text)
    }

    func generateTimestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return f.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    private func appendToLogFile(_ text: String) {
        guard let url = logFile else { return }
        let line = text + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}


// MARK: - Output Resource Helper

extension ToolRunner {
    @discardableResult
    func makeResource(
        path: String,
        kind: ResourceKind,
        date: Date?,
        parents: [ProjectResource],
        pngPath: String? = nil,
        producedBy: UUID,
        project: Project,
        context: ModelContext
    ) -> ProjectResource {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = attrs?[.size] as? Int ?? 0
        let r = ProjectResource(
            originalPath: path,
            filename: URL(fileURLWithPath: path).lastPathComponent,
            date: date,
            fileExtension: URL(fileURLWithPath: path).pathExtension.lowercased(),
            kind: kind,
            fileSize: size,
            pngPath: pngPath,
            parents: parents,
            producedByConfigId: producedBy,
            project: project
        )
        context.insert(r)
        project.resources.append(r)
        return r
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
