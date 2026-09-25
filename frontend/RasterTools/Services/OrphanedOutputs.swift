//
//  OrphanedOutputs.swift
//  RasterTools
//

import Foundation

/// What the current app state still points at inside the outputs root. Captured on the main
/// actor (it reads SwiftData), then handed to `OrphanedOutputs.scan` off it.
struct OutputReferences: Equatable, Sendable {
    var outputsRoot: URL
    var projectIDs: Set<UUID>
    var configurationIDs: Set<UUID>
    /// Every file a `ProjectResource` records. Deleting a configuration keeps the resources it
    /// produced, so a configuration folder with no configuration can still hold live files.
    var referencedPaths: Set<String>

    @MainActor
    init(projects: [Project], outputsRoot: URL = AppStorage.outputsRoot()) {
        self.outputsRoot = outputsRoot
        projectIDs = Set(projects.map(\.id))
        configurationIDs = Set(projects.flatMap { $0.allConfigurations.map(\.config.id) })
        referencedPaths = Set(projects.flatMap { project in
            project.resources.flatMap { [$0.originalPath, $0.pngPath].compactMap { $0 } }
        }.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    }

    init(outputsRoot: URL, projectIDs: Set<UUID>, configurationIDs: Set<UUID>, referencedPaths: Set<String>) {
        self.outputsRoot = outputsRoot
        self.projectIDs = projectIDs
        self.configurationIDs = configurationIDs
        self.referencedPaths = referencedPaths
    }
}

struct OrphanReport: Equatable, Sendable {
    var items: [URL] = []
    var totalBytes: Int64 = 0
}

/// Finds and removes UUID-named folders in the outputs root that nothing links to any more:
/// `{root}/{Project-UUID}/` whose project is gone, and `{root}/{Project-UUID}/{Config-UUID}/`
/// under a live project whose configuration is gone. A folder that still contains a file some
/// resource records is never an orphan. Anything not named by a UUID (logs, stray files) is left
/// alone.
enum OrphanedOutputs {
    static func scan(_ refs: OutputReferences) -> OrphanReport {
        let fm = FileManager.default
        let root = refs.outputsRoot.standardizedFileURL
        var items: [URL] = []

        for projectDir in uuidDirectories(in: root) {
            guard let projectID = UUID(uuidString: projectDir.lastPathComponent) else { continue }
            if refs.projectIDs.contains(projectID) {
                for configDir in uuidDirectories(in: projectDir) {
                    guard let configID = UUID(uuidString: configDir.lastPathComponent),
                          !refs.configurationIDs.contains(configID),
                          !isReferenced(configDir, by: refs.referencedPaths)
                    else { continue }
                    items.append(configDir)
                }
            } else if !isReferenced(projectDir, by: refs.referencedPaths) {
                items.append(projectDir)
            }
        }

        let totalBytes = items.reduce(Int64(0)) { $0 + allocatedSize(of: $1, fileManager: fm) }
        return OrphanReport(items: items, totalBytes: totalBytes)
    }

    /// Re-scans and deletes only what is *still* orphaned among `candidates`, so anything that
    /// became linked between the report and the confirmation survives. Returns what was removed.
    @discardableResult
    static func remove(_ candidates: [URL], refs: OutputReferences) -> [URL] {
        let stillOrphaned = Set(scan(refs).items)
        let fm = FileManager.default
        return candidates.filter { url in
            guard stillOrphaned.contains(url) else { return false }
            do {
                try fm.removeItem(at: url)
                return true
            } catch {
                print("Error removing orphaned output \(url.path): \(error)")
                return false
            }
        }
    }

    private static func uuidDirectories(in dir: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )) ?? []
        return contents.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            // Never follow a symlink out of the outputs root.
            return values?.isDirectory == true
                && values?.isSymbolicLink != true
                && UUID(uuidString: url.lastPathComponent) != nil
        }
        .map(\.standardizedFileURL)
        .sorted { $0.path < $1.path }
    }

    private static func isReferenced(_ dir: URL, by paths: Set<String>) -> Bool {
        let prefix = dir.path.hasSuffix("/") ? dir.path : dir.path + "/"
        return paths.contains { $0.hasPrefix(prefix) }
    }

    private static func allocatedSize(of dir: URL, fileManager fm: FileManager) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }
}
