//
//  ProjectMenuCommands.swift
//  RasterTools
//

import SwiftUI

struct ProjectMenuCommands: Commands {
    @FocusedValue(\.projects) private var projects
    @FocusedValue(\.sidebarSelection) private var selection
    @FocusedValue(\.addProject) private var addProject
    @FocusedValue(\.importShapeFiles) private var importShapeFiles

    var body: some Commands {
        CommandMenu("Project") {
            Button("Create New Project…") {
                addProject?()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(addProject == nil)

            Button("Import Shape Files…") {
                importShapeFiles?()
            }
            .disabled(importShapeFiles == nil)

            if let projects, !projects.isEmpty {
                Divider()
                ForEach(projects.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) { project in
                    let isActive = selection?.wrappedValue == .project(project)
                    Button {
                        selection?.wrappedValue = .project(project)
                    } label: {
                        if isActive {
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
                        }
                    }
                }
            }
        }
    }
}
