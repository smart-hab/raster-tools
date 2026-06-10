//
//  OrderQueue.swift
//  RasterTools
//
//  Created by Marek on 2026-05-27.
//

import Foundation
import Observation

/// Singleton that owns the countdown + order-placement tasks for ToolCollection.
/// Replaces ToolCollection (a ToolRunner subclass) so that queued orders are managed
/// independently of any view lifetime.
@Observable
@MainActor
final class OrderQueue {
    static let shared = OrderQueue()
    private var tasks: [String: Task<Void, Never>] = [:]
    var countdowns: [String: Int] = [:]

    private init() {}

    func countdown(for key: String) -> Int? { countdowns[key] }

    func queue(configuration: ToolCollectionConfiguration, sceneGroup: PlanetSceneGroup) {
        let key = configuration.orderMemoryKey(for: sceneGroup.date)
        guard tasks[key] == nil else { return }

        let date = sceneGroup.date
        let itemIds = sceneGroup.scenes.map(\.id)
        let configName = configuration.name
        let projectName = configuration.project.name

        configuration.setOrderEntry(OrderMemoryEntry(status: .queued), for: date)

        let task = Task { @MainActor in
            defer { self.tasks.removeValue(forKey: key) }

            let orderName = resolveNamingPattern(
                configuration.namingPattern,
                configName: configName,
                projectName: projectName,
                itemType: configuration.itemType,
                productBundle: configuration.productBundle,
                harmonized: configuration.harmonized,
                composite: configuration.composite,
                date: date
            )

            do {
                var remaining = 300
                self.countdowns[key] = remaining
                while remaining > 0 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .seconds(1))
                    // Allow fastForward() to lower the countdown externally
                    remaining = min(remaining - 1, self.countdowns[key] ?? remaining - 1)
                    self.countdowns[key] = remaining
                }
                self.countdowns.removeValue(forKey: key)

                guard let shapePath = configuration.shapeFile?.originalPath else {
                    throw PlanetAPIError.missingShapeFile
                }
                let geometry = try loadShapeFileGeometry(from: shapePath)
                let apiKey = AppSettings.shared.planetApiKey

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
                configuration.setOrderEntry(OrderMemoryEntry(status: .ordered, orderId: orderId), for: date)

            } catch is CancellationError {
                configuration.removeOrderEntry(for: date)
                self.countdowns.removeValue(forKey: key)
            } catch {
                configuration.removeOrderEntry(for: date)
                self.countdowns.removeValue(forKey: key)
                print("[OrderQueue] Order failed for \(key): \(error)")
            }
        }

        tasks[key] = task
    }

    func fastForward(configuration: ToolCollectionConfiguration, date: Date) {
        let key = configuration.orderMemoryKey(for: date)
        if let current = countdowns[key], current > 5 {
            countdowns[key] = 5
        }
    }

    func cancel(configuration: ToolCollectionConfiguration, date: Date) {
        let key = configuration.orderMemoryKey(for: date)
        tasks[key]?.cancel()
        tasks.removeValue(forKey: key)
        configuration.removeOrderEntry(for: date)
    }

    /// Cancels all in-flight tasks for the given configuration and clears its order entries.
    func resetMemory(for configuration: ToolCollectionConfiguration) {
        let configKeys = Set(configuration.orderEntries.keys)
        for key in configKeys {
            tasks[key]?.cancel()
            tasks.removeValue(forKey: key)
        }
        configuration.orderEntries = [:]
    }

    /// Cancels in-flight tasks and removes entries for the given record IDs.
    /// Each record ID is either a Planet order ID or a composite memory key (for queued items).
    func resetMemory(for configuration: ToolCollectionConfiguration, recordIds: Set<String>) {
        let keysToRemove = configuration.orderEntries.filter { key, entry in
            recordIds.contains(entry.orderId ?? key)
        }.map(\.key)
        for key in keysToRemove {
            tasks[key]?.cancel()
            tasks.removeValue(forKey: key)
            configuration.orderEntries.removeValue(forKey: key)
        }
        configuration.touch()
    }
}
