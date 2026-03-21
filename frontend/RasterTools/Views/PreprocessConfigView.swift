//
//  PreprocessConfigView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct PreprocessConfigView: View {
    @Bindable var configuration: ToolConfiguration
    @State private var runner = PreprocessRunner()
    @State private var availableShapeFiles: [String] = []
    @State private var isLoadingFiles = false
    
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
            
            Section("Shape File") {
                if configuration.preprocessConfig != nil {
                    if isLoadingFiles {
                        ProgressView()
                    } else if availableShapeFiles.isEmpty {
                        Button("Retry") {
                            loadWorkspaceFiles()
                        }
                        Text("No shape files (.geojson, .shp) found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Shape File", selection: Binding(
                            get: { configuration.preprocessConfig?.shapeFile ?? "" },
                            set: { newValue in
                                configuration.preprocessConfig?.shapeFile = newValue
                                configuration.touch()
                            }
                        )) {
                            Text("Select a shape file...").tag("")
                            ForEach(availableShapeFiles, id: \.self) { file in
                                Text(file).tag(file)
                            }
                        }
                    }
                }
            }
            
            Section("Processes") {
                if configuration.preprocessConfig != nil {
                    Text("Select which indices to calculate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(PreprocessType.allCases, id: \.self) { processType in
                        Toggle(processType.rawValue, isOn: Binding(
                            get: { 
                                configuration.preprocessConfig?.processTypes.contains(processType) ?? false
                            },
                            set: { isSelected in
                                guard var types = configuration.preprocessConfig?.processTypes else { return }
                                if isSelected {
                                    if !types.contains(processType) {
                                        types.append(processType)
                                    }
                                } else {
                                    types.removeAll { $0 == processType }
                                }
                                configuration.preprocessConfig?.processTypes = types
                                configuration.touch()
                            }
                        ))
                        .toggleStyle(.checkmark)
                    }
                }
            }
            
            Section("Raster Files") {
                if let preprocessConfig = configuration.preprocessConfig {
                    if preprocessConfig.files.isEmpty {
                        Text("No raster files selected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(preprocessConfig.files, id: \.self) { path in
                            HStack {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                Spacer()
                                Button {
                                    configuration.preprocessConfig?.files.removeAll { $0 == path }
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
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = true
                        panel.resolvesAliases = false
                        panel.directoryURL = URL(fileURLWithPath: configuration.workspacePath)
                        panel.allowedContentTypes = [
                            UTType(filenameExtension: "tif")!,
                            UTType(filenameExtension: "tiff")!
                        ]
                        if panel.runModal() == .OK {
                            for url in panel.urls {
                                if !(configuration.preprocessConfig?.files.contains(url.path) ?? false) {
                                    configuration.preprocessConfig?.files.append(url.path)
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
                    Button("Run Preprocessing") {
                        Task {
                            do {
                                try await runner.run(configuration: configuration)
                            } catch {
                                print("Error running preprocessing: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        configuration.preprocessConfig?.files.isEmpty != false ||
                        configuration.preprocessConfig?.shapeFile.isEmpty != false
                    )
                }
            }
        }
        .onAppear {
            loadWorkspaceFiles()
        }
    }

    private func loadWorkspaceFiles() {
        isLoadingFiles = true
        Task {
            do {
                let fileManager = FileManager.default
                let workspaceURL = URL(fileURLWithPath: configuration.workspacePath)
                let files = try fileManager.contentsOfDirectory(
                    at: workspaceURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )

                await MainActor.run {
                    self.availableShapeFiles = files
                        .filter {
                            let ext = $0.pathExtension.lowercased()
                            return ext == "geojson" || ext == "shp"
                        }
                        .map { $0.lastPathComponent }
                        .sorted()

                    self.isLoadingFiles = false
                }
            } catch {
                print("Error loading files: \(error)")
                await MainActor.run {
                    self.isLoadingFiles = false
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ToolConfiguration.self, KMeansConfiguration.self, PreprocessConfiguration.self, configurations: config)

    let toolConfig = ToolConfiguration(
        name: "Test Preprocess",
        toolType: .preprocess,
        workspacePath: "/tmp/workspace"
    )
    container.mainContext.insert(toolConfig)

    return PreprocessConfigView(configuration: toolConfig)
        .modelContainer(container)
        .frame(width: 600, height: 800)
}
