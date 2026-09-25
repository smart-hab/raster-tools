//
//  OrphanedOutputsTests.swift
//  RasterToolsTests
//

import Testing
import Foundation
@testable import RasterTools

struct OrphanedOutputsTests {

    /// A throwaway outputs root; each test removes it when done.
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrphanedOutputsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.standardizedFileURL
    }

    @discardableResult
    private func makeDir(_ url: URL, file: String? = nil, bytes: Int = 0) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let file {
            try Data(count: bytes).write(to: url.appendingPathComponent(file))
        }
        return url
    }

    @Test func findsDeletedProjectsAndConfigurations() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let liveProject = UUID(), liveConfig = UUID()
        let goneProject = UUID(), goneConfig = UUID(), keptConfig = UUID()

        try makeDir(root.appendingPathComponent(liveProject.uuidString), file: "Run.log", bytes: 10)
        try makeDir(root.appendingPathComponent("\(liveProject)/\(liveConfig)"), file: "a.tif", bytes: 10)
        let orphanConfig = try makeDir(root.appendingPathComponent("\(liveProject)/\(goneConfig)"), file: "b.tif", bytes: 5000)
        // Configuration gone, but a resource in the project still points at a file inside.
        let kept = try makeDir(root.appendingPathComponent("\(liveProject)/\(keptConfig)"), file: "c.tif", bytes: 10)
        let orphanProject = try makeDir(root.appendingPathComponent(goneProject.uuidString), file: "d.tif", bytes: 5000)
        // Not UUID-named: never touched.
        try makeDir(root.appendingPathComponent("not-a-uuid"), file: "e.tif", bytes: 10)

        let refs = OutputReferences(
            outputsRoot: root,
            projectIDs: [liveProject],
            configurationIDs: [liveConfig],
            referencedPaths: [kept.appendingPathComponent("c.tif").path]
        )
        let report = OrphanedOutputs.scan(refs)

        #expect(Set(report.items.map(\.path)) == [orphanConfig.path, orphanProject.path])
        #expect(report.totalBytes >= 10_000)
    }

    @Test func removeDeletesOnlyWhatIsStillOrphaned() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let a = UUID(), b = UUID()
        let dirA = try makeDir(root.appendingPathComponent(a.uuidString), file: "x.tif", bytes: 1)
        let dirB = try makeDir(root.appendingPathComponent(b.uuidString), file: "y.tif", bytes: 1)

        let empty = OutputReferences(outputsRoot: root, projectIDs: [], configurationIDs: [], referencedPaths: [])
        let candidates = OrphanedOutputs.scan(empty).items
        #expect(candidates.count == 2)

        // Project B reappears between the report and the confirmation.
        let now = OutputReferences(outputsRoot: root, projectIDs: [b], configurationIDs: [], referencedPaths: [])
        let removed = OrphanedOutputs.remove(candidates, refs: now)

        #expect(removed.map(\.path) == [dirA.path])
        #expect(!FileManager.default.fileExists(atPath: dirA.path))
        #expect(FileManager.default.fileExists(atPath: dirB.path))
    }
}
