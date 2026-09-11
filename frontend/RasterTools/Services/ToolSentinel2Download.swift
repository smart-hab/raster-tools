//
//  ToolSentinel2Download.swift
//  RasterTools
//
//  Created by Marek on 2026-09-02.
//

import Foundation
import SwiftData

/// Downloads Sentinel-2 products from CDSE, extracts each `.SAFE` archive into the project's
/// source directory, and stacks its 13 L1C bands into a single GeoTIFF.
///
/// The Planet equivalent is `ToolPlanetUnzip`; this runner follows the same shape so
/// `ToolRunnerSheet` and `JobRegistry` need no provider-specific handling. It differs in three
/// ways, all forced by CDSE: the download is a manual redirect loop (see `download(product:to:)`),
/// there is no checksum manifest to verify against, and the extracted product needs a band-stack
/// pass before anything downstream can read it.
final class ToolSentinel2Download: ToolRunner {

    private var downloadTask: Task<Void, Never>? {
        didSet { isRunning = downloadTask != nil }
    }

    override func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    @MainActor
    func start(
        products: [Sentinel2Product],
        configuration: ToolSentinel2Configuration,
        project: Project,
        context: ModelContext
    ) {
        error = nil
        logFile = AppStorage.logsDirectory()
            .appendingPathComponent("sentinel2-\(generateTimestamp()).log")

        let destRoot = URL(fileURLWithPath: project.sourceDirectory)

        downloadTask = Task { @MainActor in
            defer { downloadTask = nil }

            guard !products.isEmpty else {
                await update(ToolProgress(statusText: "No products selected", progress: 1.0))
                return
            }

            let total = products.count
            var completed = 0

            do {
                if let logFile { await log("Log: \(logFile.path)") }

                for product in products {
                    try Task.checkCancellation()

                    let destDir = destRoot.appending(path: product.archiveStem)
                    let stackedTif = destDir.appending(path: "\(product.archiveStem)_13band.tif")

                    // Idempotency: the stacked raster is the artefact everything downstream uses,
                    // so its presence — not the .SAFE dir's — is what makes a product "done".
                    if FileManager.default.fileExists(atPath: stackedTif.path) {
                        await log("⏭ \(product.archiveStem)/ already downloaded, skipping")
                        completed += 1
                        await update(ToolProgress(
                            statusText: "Skipped: \(product.name)",
                            progress: Double(completed) / Double(total),
                            progressText: "\(completed) / \(total)"
                        ))
                        continue
                    }

                    configuration.setDownloadEntry(
                        entry(for: product, status: .downloading, localPath: nil),
                        for: product.sensingDate
                    )

                    do {
                        try await fetch(
                            product: product,
                            into: destDir,
                            stackedTif: stackedTif,
                            completed: completed,
                            total: total
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // One bad product should not abandon the rest of the batch.
                        await log("✗ \(product.name): \(error.localizedDescription)")
                        configuration.setDownloadEntry(
                            entry(for: product, status: .failed, localPath: nil),
                            for: product.sensingDate
                        )
                        completed += 1
                        continue
                    }

                    configuration.setDownloadEntry(
                        entry(for: product, status: .downloaded, localPath: stackedTif.path),
                        for: product.sensingDate
                    )
                    configuration.touch()

                    await log("🔄 Scanning \(product.archiveStem)/")
                    project.refresh(context: context)

                    completed += 1
                    await update(ToolProgress(
                        statusText: "Done: \(product.name)",
                        progress: Double(completed) / Double(total),
                        progressText: "\(completed) / \(total)"
                    ))
                    await log("✓ \(product.name) → \(product.archiveStem)/")
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

    // MARK: - Per-product pipeline

    private func fetch(
        product: Sentinel2Product,
        into destDir: URL,
        stackedTif: URL,
        completed: Int,
        total: Int
    ) async throws {
        let fraction = Double(completed) / Double(total)
        let counter = "\(completed) / \(total)"

        await update(ToolProgress(
            statusText: "Downloading \(product.archiveStem)",
            progress: fraction,
            progressText: counter
        ))
        await log("⬇ \(product.name) (\(ByteCountFormatter.string(fromByteCount: Int64(product.contentLength), countStyle: .file)))")

        let archive = try await download(product: product)
        defer { try? FileManager.default.removeItem(at: archive) }

        try Task.checkCancellation()

        await update(ToolProgress(
            statusText: "Extracting \(product.archiveStem)",
            progress: fraction,
            progressText: counter
        ))
        await log("📦 Extracting → \(product.archiveStem)/")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try await runDitto(source: archive.path, destination: destDir.path)

        try Task.checkCancellation()

        // The archive extracts to `<stem>.SAFE`; s2_stack accepts that directory and finds the
        // granule itself.
        let safeDir = destDir.appending(path: "\(product.archiveStem).SAFE")
        guard FileManager.default.fileExists(atPath: safeDir.path) else {
            throw ToolError.fileNotFound(safeDir.path)
        }

        await update(ToolProgress(
            statusText: "Stacking bands for \(product.archiveStem)",
            progress: fraction,
            progressText: counter
        ))
        await log("🧱 s2_stack → \(stackedTif.lastPathComponent)")
        let output = try await runProcess(
            executable: "s2_stack",
            arguments: ["-i", safeDir.path, "-o", stackedTif.path, "-v"]
        )
        if !output.isEmpty { await log(output) }
    }

    /// Streams the product archive to a temporary file.
    ///
    /// CDSE's download endpoint redirects to a different host, and `URLSession` deliberately
    /// strips the `Authorization` header on cross-host redirects — so redirects are followed by
    /// hand here, re-attaching the bearer token on every hop.
    private func download(product: Sentinel2Product) async throws -> URL {
        var url = Sentinel2API.downloadURL(productId: product.id)
        let token = try await Sentinel2API.accessToken()

        let session = URLSession(configuration: .default, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        // Bounded so a redirect cycle cannot spin forever.
        for _ in 0..<10 {
            try Task.checkCancellation()

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (tempURL, response) = try await session.download(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw Sentinel2APIError.invalidResponse
            }

            if (301...308).contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location"),
               let next = URL(string: location, relativeTo: url)?.absoluteURL {
                try? FileManager.default.removeItem(at: tempURL)
                url = next
                continue
            }

            guard (200..<300).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: tempURL)
                throw Sentinel2APIError.httpError(http.statusCode, "Download failed for \(product.name)")
            }

            // No SHA256 manifest exists on this path, so length is the only integrity check
            // available. A zero/absent Content-Length is not treated as a failure.
            let expected = http.expectedContentLength
            let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path)
            let received = attrs?[.size] as? Int ?? 0
            if expected > 0, Int64(received) != expected {
                try? FileManager.default.removeItem(at: tempURL)
                throw Sentinel2APIError.incompleteDownload(expected: Int(expected), received: received)
            }

            return tempURL
        }

        throw Sentinel2APIError.httpError(310, "Too many redirects downloading \(product.name)")
    }

    private func entry(
        for product: Sentinel2Product,
        status: DownloadMemoryStatus,
        localPath: String?
    ) -> DownloadMemoryEntry {
        DownloadMemoryEntry(
            status: status,
            productId: product.id,
            productName: product.name,
            sensingDate: product.sensingDate,
            cloudCover: product.cloudCover,
            fileSize: product.contentLength,
            localPath: localPath
        )
    }
}

/// Suppresses `URLSession`'s automatic redirect handling so the caller can re-attach the
/// `Authorization` header on each hop.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
