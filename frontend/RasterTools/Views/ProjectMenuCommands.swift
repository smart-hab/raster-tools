//
//  ProjectMenuCommands.swift
//  RasterTools
//

import SwiftUI

struct ProjectMenuCommands: Commands {
    @FocusedValue(\.projects) private var projects
    @FocusedValue(\.sidebarSelection) private var selection
    @FocusedValue(\.addProject) private var addProject

    var body: some Commands {
        CommandMenu("Project") {
            Button("Add New Project") {
                addProject?()
            }
            .disabled(addProject == nil)

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
