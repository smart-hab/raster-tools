//
//  AppStorage.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import Foundation

struct AppStorage {
    /// Returns (and creates if needed) the output directory for a project.
    /// All tool-generated files are stored here, not in the source directory.
    static func outputDirectory(for project: Project) -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // ~/Library/Application Support/RasterTools/outputs/{Project-UUID}/
        let dir = support
            .appendingPathComponent("RasterTools")
            .appendingPathComponent("outputs")
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
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support
            .appendingPathComponent("RasterTools")
            .appendingPathComponent("planet")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func outputDirectory(for project: Project, configuration: ToolConfiguration) -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // ~/Library/Application Support/RasterTools/outputs/{Project-UUID}/{ToolConfiguration-UUID}/
        let dir = support
            .appendingPathComponent("RasterTools")
            .appendingPathComponent("outputs")
            .appendingPathComponent(project.id.uuidString)
            .appendingPathComponent(configuration.id.uuidString)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }
}
