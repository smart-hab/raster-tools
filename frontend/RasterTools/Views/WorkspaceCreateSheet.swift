//
//  WorkspaceCreateSheet.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI

struct WorkspaceCreateSheet: View {
    let onSave: (Workspace) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var directoryURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Name", text: $name, prompt: Text("My Project"))

                    HStack {
                        Text("Source Dir")
                        Spacer()
                        if let url = directoryURL {
                            Button(action: selectDirectory) {
                                Label(url.lastPathComponent, systemImage: "folder")
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        } else {
                            Button("Choose Directory…") { selectDirectory() }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createWorkspace() }
                        .disabled(name.isEmpty || directoryURL == nil)
                }
            }
        }
        .frame(width: 460, height: 240)
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select source directory"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            directoryURL = url
            if name.isEmpty {
                name = url.lastPathComponent
            }
        }
    }

    private func createWorkspace() {
        guard let url = directoryURL else { return }
        let workspace = Workspace(name: name, sourceDirectory: url.path(percentEncoded: false))

        let scanned = WorkspaceScanner.scan(directory: workspace.sourceDirectory)
        for resource in scanned {
            resource.workspace = workspace
            workspace.resources.append(resource)
        }

        onSave(workspace)
    }
}
