//
//  UpdateCommands.swift
//  RasterTools
//
//  Created by Marek on 2026-09-25.
//

import SwiftUI

/// "Check for Updates…" in the app menu, right after "About RasterTools".
struct UpdateCommands: Commands {
    private let updater = AppUpdater.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }
    }
}
