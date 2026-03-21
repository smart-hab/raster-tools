//
//  AppStorage.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import Foundation

struct AppStorage {
    /// Returns (and creates if needed) the output directory for a workspace.
    /// All tool-generated files are stored here, not in the source directory.
    static func outputDirectory(for workspace: Workspace) -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support
            .appendingPathComponent("RasterTools")
            .appendingPathComponent("outputs")
            .appendingPathComponent(workspace.id.uuidString)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }
}
