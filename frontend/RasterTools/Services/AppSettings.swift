//
//  AppSettings.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation

/// Stores global app settings backed by UserDefaults.
@Observable
class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    // Stored, not computed over UserDefaults: the @Observable macro only instruments stored
    // properties, so computed accessors would publish nothing and no view could react to a write.
    // Seeded once at init; didSet writes back.
    var virtualEnvPath: String {
        didSet { defaults.set(virtualEnvPath, forKey: "virtualEnvPath") }
    }

    var planetApiKey: String {
        didSet { defaults.set(planetApiKey, forKey: "planetApiKey") }
    }

    /// Where tool outputs are written. Read through `AppStorage.outputsRoot()`, never directly.
    var outputsPath: String {
        didSet { defaults.set(outputsPath, forKey: "outputsPath") }
    }

    private init() {
        virtualEnvPath = defaults.string(forKey: "virtualEnvPath")
            ?? AppStorage.defaultVenvDirectory().path
        planetApiKey = defaults.string(forKey: "planetApiKey") ?? ""
        outputsPath = defaults.string(forKey: "outputsPath")
            ?? AppStorage.defaultOutputsDirectory().path
    }

    /// True when `virtualEnvPath` points at a venv that can actually run the tools:
    /// an executable `bin/python`, plus one of the `smart_hab` console scripts to prove
    /// the processing package is installed and not just an empty virtualenv.
    var isVirtualEnvValid: Bool {
        Self.isValidVirtualEnv(atPath: virtualEnvPath)
    }

    /// True when `virtualEnvPath` is free for `python -m venv` to claim — the directory is
    /// either empty or does not exist yet. Setup runs `venv --clear`, so anything else would
    /// be deleted.
    var isVirtualEnvEmptyOrMissing: Bool {
        AppStorage.isEmptyOrMissingDirectory(atPath: virtualEnvPath)
    }

    static func isValidVirtualEnv(atPath path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let bin = URL(fileURLWithPath: path).appendingPathComponent("bin")
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: bin.appendingPathComponent("python").path)
            && fm.isExecutableFile(atPath: bin.appendingPathComponent(Self.sentinelScript).path)
    }

    /// One of `smart_hab`'s console scripts, used as the marker that the package is installed.
    static let sentinelScript = "kmeans_fit"
}
