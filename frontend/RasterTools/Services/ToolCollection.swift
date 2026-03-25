//
//  ToolCollection.swift
//  RasterTools
//
//  Created by Marek on 2026-03-24.
//

import Foundation
import SwiftData

/// Runs a Planet order for a single day. One instance per selected day.
final class ToolCollection: ToolRunner {
    let date: Date
    private let configuration: CollectionConfiguration
    private let workspaceName: String
    private var collectionTask: Task<Void, Never>? {
        didSet { isRunning = collectionTask != nil }
    }

    init(date: Date, configuration: CollectionConfiguration, workspaceName: String) {
        self.date = date
        self.configuration = configuration
        self.workspaceName = workspaceName
    }

    override func cancel() {
        collectionTask?.cancel()
        collectionTask = nil
        configuration.orderMemory.removeValue(forKey: configuration.orderMemoryKey(for: date))
    }

    @MainActor
    func startCollection(configName: String, sceneGroup: PlanetSceneGroup) {
        error = nil
        collectionTask = Task { @MainActor in
            defer { collectionTask = nil }

            let key = configuration.orderMemoryKey(for: date)
            configuration.orderMemory[key] = OrderMemoryStatus.queued.rawValue

            let itemIds = sceneGroup.scenes.map(\.id)
            let apiKey = AppSettings.shared.planetApiKey

            let orderName = resolveNamingPattern(
                configuration.namingPattern,
                configName: configName,
                workspaceName: workspaceName,
                itemType: configuration.itemType,
                productBundle: configuration.productBundle,
                harmonized: configuration.harmonized,
                composite: configuration.composite,
                date: date
            )

            do {
                await log("Queued for order")

                // 5-minute countdown
                for i in 0..<300 {
                    let remaining = 300 - i
                    let mins = remaining / 60
                    let secs = remaining % 60
                    await update(ToolProgress(
                        statusText: "Queued for order",
                        progress: Double(i) / 300.0,
                        progressText: String(format: "%d:%02d", mins, secs)
                    ))
                    try await Task.sleep(for: .seconds(1))
                }

                await update(ToolProgress(statusText: "Submitting order", progress: 1.0))
                await log("Submitting order...")

                guard let shapePath = configuration.shapeFile?.originalPath else {
                    throw PlanetAPIError.missingShapeFile
                }
                let geometry = try loadShapeFileGeometry(from: shapePath)

                let request = PlanetOrderRequest(
                    name: orderName,
                    geometry: geometry,
                    itemIds: itemIds,
                    itemType: configuration.itemType,
                    productBundle: configuration.productBundle,
                    harmonize: configuration.harmonized,
                    composite: configuration.composite
                )

                let orderId = try await PlanetAPI.createOrder(request, apiKey: apiKey)
                configuration.orderMemory[key] = OrderMemoryStatus.ordered.rawValue

                await update(ToolProgress(statusText: "Order placed", progress: 1.0))
                await log("  Order ID: \(orderId)")

            } catch is CancellationError {
                configuration.orderMemory.removeValue(forKey: key)
                await update(ToolProgress(statusText: "Cancelled", progress: progress.progress))
                await log("Cancelled")
            } catch {
                configuration.orderMemory.removeValue(forKey: key)
                self.error = error
                await update(ToolProgress(statusText: "Error", progress: progress.progress))
                await log("Error: \(error.localizedDescription)")
            }
        }
    }
}
