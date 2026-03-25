//
//  ToolPlanetDownload.swift
//  RasterTools
//
//  Created by Marek on 2026-03-24.
//

import Foundation
import CryptoKit

/// Downloads completed Planet orders to the configured download directory.
/// One instance handles a batch of selected orders sequentially.
final class ToolPlanetDownload: ToolRunner {

    private var downloadTask: Task<Void, Never>? {
        didSet { isRunning = downloadTask != nil }
    }

    override func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    @MainActor
    func start(orders: [PlanetOrderRecord]) {
        error = nil
        let apiKey = AppSettings.shared.planetApiKey
        let downloadDir = AppStorage.planetDownloadDirectory().path

        downloadTask = Task { @MainActor in
            defer { downloadTask = nil }

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

                    // Find the manifest, fetch it to get the authoritative file list, discard it after parsing
                    guard let manifestResult = results.first(where: { $0.name.hasSuffix("manifest.json") }) else {
                        continue
                    }
                    let manifestFiles = try await PlanetAPI.getManifest(url: manifestResult.location, apiKey: apiKey)

                    // Build a lookup of result name suffix → download URL
                    let locationByPath = Dictionary(uniqueKeysWithValues: results.map { ($0.name, $0.location) })

                    for manifestFile in manifestFiles {
                        try Task.checkCancellation()

                        let resultEntry = locationByPath.first { $0.key.hasSuffix(manifestFile.path) }
                        guard let location = resultEntry?.value else { continue }

                        let filename = URL(fileURLWithPath: manifestFile.path).lastPathComponent
                        let destPath = (downloadDir as NSString).appendingPathComponent(filename)

                        let fileExists = FileManager.default.fileExists(atPath: destPath)

                        if !fileExists {
                            guard let downloadURL = URL(string: location) else { continue }

                            await update(ToolProgress(
                                statusText: "Downloading \(filename)",
                                progress: Double(completed) / Double(total),
                                logText: "⬇ \(filename)"
                            ))

                            var req = URLRequest(url: downloadURL)
                            req.setValue(
                                "Basic \(Data("\(apiKey):".utf8).base64EncodedString())",
                                forHTTPHeaderField: "Authorization"
                            )
                            let (tempURL, response) = try await URLSession.shared.download(for: req)
                            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                                throw PlanetAPIError.httpError(http.statusCode, "Download failed for \(filename)")
                            }

                            await update(ToolProgress(
                                statusText: "Verifying \(filename)",
                                progress: Double(completed) / Double(total),
                                logText: "🔍 \(filename)"
                            ))

                            let tempData = try Data(contentsOf: tempURL)
                            let computed = SHA256.hash(data: tempData).compactMap { String(format: "%02x", $0) }.joined()
                            guard computed == manifestFile.sha256 else {
                                throw PlanetAPIError.decodingError("SHA-256 mismatch for \(filename): expected \(manifestFile.sha256), got \(computed)")
                            }

                            try FileManager.default.moveItem(atPath: tempURL.path, toPath: destPath)
                        } else {
                            await update(ToolProgress(
                                statusText: "Verifying \(filename)",
                                progress: Double(completed) / Double(total),
                                logText: "🔍 \(filename)"
                            ))

                            let existingData = try Data(contentsOf: URL(fileURLWithPath: destPath))
                            let computed = SHA256.hash(data: existingData).compactMap { String(format: "%02x", $0) }.joined()
                            guard computed == manifestFile.sha256 else {
                                throw PlanetAPIError.decodingError("SHA-256 mismatch for existing \(filename): expected \(manifestFile.sha256), got \(computed)")
                            }
                        }

                        await update(ToolProgress(
                            statusText: "Verified \(filename)",
                            progress: Double(completed) / Double(total),
                            logText: "✓ \(filename)"
                        ))
                    }

                    completed += 1
                    await update(ToolProgress(
                        statusText: "Downloaded \(order.name)",
                        progress: Double(completed) / Double(total),
                        progressText: "\(completed) / \(total)",
                        logText: "✓ \(order.name)"
                    ))
                }

                await update(ToolProgress(
                    statusText: "Complete",
                    progress: 1.0,
                    progressText: "\(completed) / \(total)"
                ))

            } catch is CancellationError {
                await update(ToolProgress(statusText: "Cancelled", progress: progress.progress, logText: "Cancelled"))
            } catch {
                self.error = error
                await update(ToolProgress(statusText: "Error", progress: progress.progress, logText: error.localizedDescription))
            }
        }
    }
}
