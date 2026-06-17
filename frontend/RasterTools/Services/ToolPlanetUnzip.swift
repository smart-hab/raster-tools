//
//  ToolPlanetUnzip.swift
//  RasterTools
//
//  Created by Marek on 2026-06-16.
//

import Foundation
import SwiftData

/// Downloads a Planet order's single zip archive and extracts it into the project's source directory.
/// Each order extracts into a subfolder named after the zip (minus the .zip suffix).
final class ToolPlanetUnzip: ToolRunner {

    private var unzipTask: Task<Void, Never>? {
        didSet { isRunning = unzipTask != nil }
    }

    override func cancel() {
        unzipTask?.cancel()
        unzipTask = nil
    }

    @MainActor
    func start(orders: [PlanetOrderRecord], project: Project, context: ModelContext) {
        error = nil
        let apiKey = AppSettings.shared.planetApiKey
        let destRoot = URL(fileURLWithPath: project.sourceDirectory)

        unzipTask = Task { @MainActor in
            defer { unzipTask = nil }

            let successOrders = orders.filter { $0.status == PlanetOrderStatus.success.rawValue }
            guard !successOrders.isEmpty else {
                await update(ToolProgress(statusText: "No completed orders selected", progress: 1.0))
                return
            }

            let total = successOrders.count
            var completed = 0

            do {
                for order in successOrders {
                    try Task.checkCancellation()

                    await update(ToolProgress(
                        statusText: "Fetching results for \(order.name)",
                        progress: Double(completed) / Double(total),
                        progressText: "\(completed) / \(total)"
                    ))

                    let results = try await PlanetAPI.getOrderResults(id: order.id, apiKey: apiKey)

                    guard let zipResult = results.first(where: { $0.name.hasSuffix(".zip") }) else {
                        await log("⚠ No archive found for \(order.name), skipping")
                        completed += 1
                        continue
                    }

                    let zipName = URL(fileURLWithPath: zipResult.name).lastPathComponent
                    let folderName = zipName.hasSuffix(".zip") ? String(zipName.dropLast(4)) : zipName
                    let destDir = destRoot.appending(path: folderName)

                    if FileManager.default.fileExists(atPath: destDir.path) {
                        await log("⏭ \(folderName)/ already exists, skipping")
                        completed += 1
                        await update(ToolProgress(
                            statusText: "Skipped: \(order.name)",
                            progress: Double(completed) / Double(total),
                            progressText: "\(completed) / \(total)"
                        ))
                        continue
                    }

                    try Task.checkCancellation()

                    await update(ToolProgress(
                        statusText: "Downloading \(zipName)",
                        progress: Double(completed) / Double(total),
                        progressText: "\(completed) / \(total)"
                    ))
                    await log("⬇ \(zipName)")

                    guard let downloadURL = URL(string: zipResult.location) else { continue }
                    var req = URLRequest(url: downloadURL)
                    req.setValue(
                        "Basic \(Data("\(apiKey):".utf8).base64EncodedString())",
                        forHTTPHeaderField: "Authorization"
                    )
                    let (tempURL, response) = try await URLSession.shared.download(for: req)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw PlanetAPIError.httpError(http.statusCode, "Download failed for \(zipName)")
                    }

                    try Task.checkCancellation()

                    await update(ToolProgress(
                        statusText: "Extracting \(zipName)",
                        progress: Double(completed) / Double(total),
                        progressText: "\(completed) / \(total)"
                    ))
                    await log("📦 Extracting → \(folderName)/")

                    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                    try await runDitto(source: tempURL.path, destination: destDir.path)
                    try? FileManager.default.removeItem(at: tempURL)

                    await log("🔄 Scanning \(folderName)/")
                    project.refresh(context: context)

                    completed += 1
                    await update(ToolProgress(
                        statusText: "Done: \(order.name)",
                        progress: Double(completed) / Double(total),
                        progressText: "\(completed) / \(total)"
                    ))
                    await log("✓ \(order.name) → \(folderName)/")
                }

                await update(ToolProgress(
                    statusText: "Complete",
                    progress: 1.0,
                    progressText: "\(completed) / \(total)"
                ))

            } catch is CancellationError {
                await update(ToolProgress(statusText: "Cancelled", progress: progress.progress))
            } catch {
                self.error = error
                await update(ToolProgress(statusText: "Error", progress: progress.progress))
                await log(error.localizedDescription)
            }
        }
    }

    private func runDitto(source: String, destination: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", source, destination]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                if proc.terminationStatus != 0 {
                    let msg = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(throwing: ToolError.processError(
                        code: proc.terminationStatus,
                        message: msg.isEmpty ? "ditto failed" : msg
                    ))
                } else {
                    continuation.resume()
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
