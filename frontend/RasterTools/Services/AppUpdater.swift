//
//  AppUpdater.swift
//  RasterTools
//
//  Created by Marek on 2026-09-25.
//

import Foundation
import Sparkle

/// Checks GitHub Releases for newer builds and installs them, via Sparkle.
///
/// The feed is `appcast.xml` on the latest release (`SUFeedURL` in Info.plist), written and
/// signed by `scripts/release.sh`. Sparkle compares `CFBundleVersion`, the commit count.
@Observable
class AppUpdater {
    static let shared = AppUpdater()

    /// Debug builds never start the updater: their build number is 1, so every release looks
    /// newer, and they share the bundle ID — and so Sparkle's preferences — with the installed app.
    #if DEBUG
    let isEnabled = false
    #else
    let isEnabled = true
    #endif

    /// Mirrors `SPUUpdater.canCheckForUpdates`, which is false while a check is in flight.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: isEnabled, updaterDelegate: nil, userDriverDelegate: nil)
        // Sparkle publishes this through KVO on the main thread.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    /// Stored by Sparkle in the app's defaults, so it is read through rather than mirrored.
    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    /// "2026.9.25 (138)" — the same pair the About window shows.
    var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// Shows Sparkle's own progress and result windows, including "You're up to date".
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
