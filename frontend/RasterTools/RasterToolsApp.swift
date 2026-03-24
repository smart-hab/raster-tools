//
//  RasterToolsApp.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData

@main
struct RasterToolsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Workspace.self,
            WorkspaceResource.self,
            ToolConfiguration.self,
            KmeansConfiguration.self,
            PreprocessConfiguration.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Store location: ~/Library/Containers/org.swimalert.RasterTools/Data/Library/Application Support/default.store
            fatalError("Could not create ModelContainer: \(error)")
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
