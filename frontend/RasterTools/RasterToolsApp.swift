//
//  RasterToolsApp.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = JobRegistry.shared.jobs.filter { $0.runner.isRunning }
        guard !running.isEmpty else { return .terminateNow }

        let count = running.count
        let alert = NSAlert()
        alert.messageText = "Jobs Are Still Running"
        alert.informativeText = "\(count) job\(count == 1 ? " is" : "s are") currently running. Quitting will cancel \(count == 1 ? "it" : "them") immediately."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            running.forEach { $0.runner.cancel() }
            return .terminateNow
        }
        return .terminateCancel
    }
}

@main
struct RasterToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self,
            ProjectResource.self,
            ToolKmeansConfiguration.self,
            ToolPreprocessConfiguration.self,
            ToolCollectionConfiguration.self,
        ])

        let storeURL = URL.applicationSupportDirectory
            .appending(path: "default.store")
        let modelConfiguration = ModelConfiguration(schema: schema, url: storeURL, allowsSave: true)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Migration failed — back up the broken store and start fresh.
            // Project files on disk are untouched; re-scan to recover resources.
            print("⚠️ SwiftData failed to load store: \(error)")
            print("⚠️ Backing up store and starting fresh.")

            let fm = FileManager.default
            let tag = Int(Date().timeIntervalSince1970)
            let dir = storeURL.deletingLastPathComponent()

            for suffix in ["default.store", "default.store-shm", "default.store-wal"] {
                let src = dir.appending(path: suffix)
                let dst = dir.appending(path: "\(suffix).bak-\(tag)")
                try? fm.copyItem(at: src, to: dst)
                try? fm.removeItem(at: src)
            }

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after clearing store: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppView()
                .environment(JobRegistry.shared)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1000, height: 700)

        Settings {
            SettingsView()
        }
    }
}
