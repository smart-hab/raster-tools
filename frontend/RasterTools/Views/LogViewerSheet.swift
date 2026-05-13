//
//  LogViewerSheet.swift
//  RasterTools
//
//  Created by Marek on 2026-05-13.
//

import SwiftUI

struct LogSelection: Identifiable {
    let id = UUID()
    let url: URL
}

struct LogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                Text(fileText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .padding()
            }
        }
        .navigationTitle(url.lastPathComponent)
        .frame(minWidth: 600, minHeight: 400)
    }

    private var fileText: String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "Could not read file."
    }
}

// MARK: - Log Helpers

extension LogViewerSheet {
    static func loadLogFiles(for project: Project) -> [URL] {
        let dir = AppStorage.outputDirectory(for: project)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: []
        )) ?? []
        return urls
            .filter { $0.pathExtension == "log" }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }
    }

    static func configName(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        // filename: "MyConfig-2026-05-13T10-30-00" — drop "-YYYY-MM-DDTHH-MM-SS" (20 chars)
        guard name.count > 20 else { return name }
        return String(name.dropLast(20))
    }

    static func groupedLogs(from logFiles: [URL]) -> [(String, [URL])] {
        var dict: [String: [URL]] = [:]
        for url in logFiles {
            let key = configName(from: url)
            dict[key, default: []].append(url)
        }
        return dict.sorted { a, b in
            let da = (a.value.first.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }) ?? .distantPast
            let db = (b.value.first.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }) ?? .distantPast
            return da > db
        }
    }
}
