//
//
//  KMeansConfigView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct KMeansConfigView: View {
    @Bindable var configuration: ToolConfiguration
    @State private var runner = KMeansRunner()

    var body: some View {
        Form {
            Section("Configuration") {
                LabeledContent("Name") {
                    Text(configuration.name)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Workspace") {
                    Text(configuration.workspacePath)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                }
            }

            Section("K-Means Parameters") {
                if configuration.kmeansConfig != nil {
                    LabeledContent("Centers File") {
                        TextField("centers.txt", text: Binding(
                            get: { configuration.kmeansConfig?.centersFile ?? "centers.txt" },
                            set: { newValue in
                                configuration.kmeansConfig?.centersFile = newValue
                                configuration.touch()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Centroids") {
                        Stepper(value: Binding(
                            get: { configuration.kmeansConfig?.centroids ?? 6 },
                            set: { newValue in
                                configuration.kmeansConfig?.centroids = newValue
                                configuration.touch()
                            }
                        ), in: 2...20) {
                            Text("\(configuration.kmeansConfig?.centroids ?? 6)")
                                .monospacedDigit()
                        }
                    }

                    LabeledContent("Iterations") {
                        Stepper(value: Binding(
                            get: { configuration.kmeansConfig?.nTimes ?? 10 },
                            set: { newValue in
                                configuration.kmeansConfig?.nTimes = newValue
                                configuration.touch()
                            }
                        ), in: 1...100) {
                            Text("\(configuration.kmeansConfig?.nTimes ?? 10)")
                                .monospacedDigit()
                        }
                    }

                    LabeledContent("Random Seed") {
                        TextField("42", value: Binding(
                            get: { configuration.kmeansConfig?.seed ?? 42 },
                            set: { newValue in
                                configuration.kmeansConfig?.seed = newValue
                                configuration.touch()
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }

            Section("Fit Rasters") {
                if let kmeansConfig = configuration.kmeansConfig {
                    if kmeansConfig.filesFit.isEmpty {
                        Text("No raster files selected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(kmeansConfig.filesFit, id: \.self) { path in
                            HStack {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                Spacer()
                                Button {
                                    configuration.kmeansConfig?.filesFit.removeAll { $0 == path }
                                    configuration.touch()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button("Add Files...") {
                        pickRasterFiles { urls in
                            for url in urls {
                                BookmarkManager.shared.saveBookmark(for: url)
                                if !(configuration.kmeansConfig?.filesFit.contains(url.path) ?? false) {
                                    configuration.kmeansConfig?.filesFit.append(url.path)
                                }
                            }
                            configuration.touch()
                        }
                    }
                }
            }

            Section("Classify Rasters") {
                if let kmeansConfig = configuration.kmeansConfig {
                    if kmeansConfig.filesClassify.isEmpty {
                        Text("No raster files selected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(kmeansConfig.filesClassify, id: \.self) { path in
                            HStack {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                Spacer()
                                Button {
                                    configuration.kmeansConfig?.filesClassify.removeAll { $0 == path }
                                    configuration.touch()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button("Add Files...") {
                        pickRasterFiles { urls in
                            for url in urls {
                                BookmarkManager.shared.saveBookmark(for: url)
                                if !(configuration.kmeansConfig?.filesClassify.contains(url.path) ?? false) {
                                    configuration.kmeansConfig?.filesClassify.append(url.path)
                                }
                            }
                            configuration.touch()
                        }
                    }
                }
            }

            if runner.isRunning || !runner.progress.logs.isEmpty {
                Section("Progress") {
                    ToolProgressView(runner: runner)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(configuration.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if runner.isRunning {
                    Button("Cancel", role: .destructive) {
                        runner.cancel()
                    }
                } else {
                    Button("Run K-Means") {
                        Task {
                            do {
                                try await runner.run(configuration: configuration)
                            } catch {
                                print("Error running K-Means: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(configuration.kmeansConfig?.filesFit.isEmpty != false)
                }
            }
        }
    }

    private func pickRasterFiles(completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: configuration.workspacePath)
        panel.allowedContentTypes = [
            UTType(filenameExtension: "tif")!,
            UTType(filenameExtension: "tiff")!
        ]
        if panel.runModal() == .OK {
            completion(panel.urls)
        }
    }
}
