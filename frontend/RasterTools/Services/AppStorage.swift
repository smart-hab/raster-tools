//
//  AppStorage.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import Foundation

struct AppStorage {
    /// ~/Library/Application Support/RasterTools/ — the root of everything the app writes.
    /// Not created here; the callers below create the specific subdirectory they need.
    static func appSupportRoot() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RasterTools")
    }

    /// The built-in location for tool outputs, used until the user picks another one.
    /// ~/Library/Application Support/RasterTools/outputs/
    static func defaultOutputsDirectory() -> URL {
        appSupportRoot().appendingPathComponent("outputs")
    }

    /// The single source of truth for where tool outputs go: whatever Settings holds, falling
    /// back to the built-in location if that was never set or was cleared by hand.
    /// Every `outputDirectory(...)` below is rooted here, so nothing reads the old path directly.
    static func outputsRoot() -> URL {
        let configured = AppSettings.shared.outputsPath
        return configured.isEmpty
            ? defaultOutputsDirectory()
            : URL(fileURLWithPath: configured)
    }

    /// Returns (and creates if needed) the output directory for a project.
    /// All tool-generated files are stored here, not in the source directory.
    static func outputDirectory(for project: Project) -> URL {
        // {outputs root}/{Project-UUID}/
        let dir = outputsRoot()
            .appendingPathComponent(project.id.uuidString)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    /// Returns (and creates if needed) the Planet download directory.
    /// ~/Library/Application Support/RasterTools/planet/
    static func planetDownloadDirectory() -> URL {
        let dir = appSupportRoot().appendingPathComponent("planet")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Returns (and creates if needed) the directory for app-maintained caches.
    /// ~/Library/Application Support/RasterTools/cache/
    ///
    /// Application Support rather than ~/Library/Caches: what lives here (e.g. Sentinel-2 search
    /// results) is slow to regain, so macOS shouldn't purge it.
    static func cacheDirectory() -> URL {
        let dir = appSupportRoot().appendingPathComponent("cache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func outputDirectory(for project: Project, configuration: ToolConfiguration) -> URL {
        // {outputs root}/{Project-UUID}/{ToolConfiguration-UUID}/
        let dir = outputsRoot()
            .appendingPathComponent(project.id.uuidString)
            .appendingPathComponent(configuration.id.uuidString)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    /// The default location for the app-managed Python virtualenv.
    /// ~/Library/Application Support/RasterTools/venv
    ///
    /// Deliberately *not* created — `python -m venv` must own creation of this directory.
    static func defaultVenvDirectory() -> URL {
        appSupportRoot().appendingPathComponent("venv")
    }

    /// True when `path` is either absent or an empty directory — the only two states in which
    /// `python -m venv` may take it over.
    static func isEmptyOrMissingDirectory(atPath path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { return true }
        guard isDirectory.boolValue else { return false }
        let contents = try? fm.contentsOfDirectory(atPath: path)
        return contents?.isEmpty ?? false
    }

    /// Returns (and creates if needed) the directory for logs not tied to a project.
    /// ~/Library/Application Support/RasterTools/logs/
    static func logsDirectory() -> URL {
        let dir = appSupportRoot().appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
