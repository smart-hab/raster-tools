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

    // Secrets live in the Keychain, not UserDefaults; the stored property is still required for
    // the reason above, so it acts as an observable mirror of the Keychain item.
    var planetApiKey: String {
        didSet { KeychainStore.set(planetApiKey, for: "planetApiKey") }
    }

    /// Copernicus Data Space Ecosystem account — not a secret, so it stays in UserDefaults.
    var cdseUsername: String {
        didSet { defaults.set(cdseUsername, forKey: "cdseUsername") }
    }

    var cdsePassword: String {
        didSet { KeychainStore.set(cdsePassword, for: "cdsePassword") }
    }

    /// Where tool outputs are written. Read through `AppStorage.outputsRoot()`, never directly.
    var outputsPath: String {
        didSet { defaults.set(outputsPath, forKey: "outputsPath") }
    }

    private init() {
        virtualEnvPath = defaults.string(forKey: "virtualEnvPath")
            ?? AppStorage.defaultVenvDirectory().path
        outputsPath = defaults.string(forKey: "outputsPath")
            ?? AppStorage.defaultOutputsDirectory().path

        // One-time migration: the API key used to live in UserDefaults. Adopt any leftover value
        // into the Keychain and clear the plist copy so the secret is not stored twice.
        if let keychainKey = KeychainStore.string(for: "planetApiKey") {
            planetApiKey = keychainKey
        } else if let legacyKey = defaults.string(forKey: "planetApiKey"), !legacyKey.isEmpty {
            planetApiKey = legacyKey
            KeychainStore.set(legacyKey, for: "planetApiKey")
        } else {
            planetApiKey = ""
        }
        defaults.removeObject(forKey: "planetApiKey")

        cdseUsername = defaults.string(forKey: "cdseUsername") ?? ""
        cdsePassword = KeychainStore.string(for: "cdsePassword") ?? ""
    }

    /// True when a Sentinel-2 search can authenticate against CDSE.
    var hasCDSECredentials: Bool {
        !cdseUsername.isEmpty && !cdsePassword.isEmpty
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
