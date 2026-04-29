//
//  ProjectCreateSheet.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI

struct ProjectCreateSheet: View {
    let onSave: (Project) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var directoryURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Name", text: $name, prompt: Text("My Project"))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)

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
                    Button("Create") { createProject() }
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

    private func createProject() {
        guard let url = directoryURL else { return }
        let project = Project(name: name, sourceDirectory: url.path(percentEncoded: false))

        let scanned = ProjectScanner.scan(directory: project.sourceDirectory)
        for resource in scanned {
            resource.project = project
            project.resources.append(resource)
        }

        onSave(project)
    }
}
