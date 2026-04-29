//
//  AppView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData
import AppKit

enum SidebarSelection: Hashable {
    case project(Project)
    case kmeansConfiguration(ToolKmeansConfiguration)
    case preprocessConfiguration(ToolPreprocessConfiguration)
    case collectionConfiguration(ToolCollectionConfiguration)
    case planet
}

// MARK: - App View (Main App view)

struct AppView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.modifiedAt, order: .reverse)
    private var projects: [Project]

    @State private var selection: SidebarSelection?
    @State private var showingNewProjectSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                projects: projects,
                selection: $selection,
                onAddProject: { showingNewProjectSheet = true }
            )
        } detail: {
            DetailView(selection: selection) { deleteSelection() }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingNewProjectSheet) {
            ProjectCreateSheet { project in
                modelContext.insert(project)
                selection = .project(project)
                showingNewProjectSheet = false
            } onCancel: {
                showingNewProjectSheet = false
            }
        }
    }

    private func deleteSelection() {
        guard let selection else { return }
        self.selection = nil
        switch selection {
        case .project(let ws):
            NSWorkspace.shared.open(AppStorage.outputDirectory(for: ws))
            modelContext.delete(ws)
        case .kmeansConfiguration(let config):
            NSWorkspace.shared.open(AppStorage.outputDirectory(for: config.project, configuration: config))
            modelContext.delete(config)
        case .preprocessConfiguration(let config):
            NSWorkspace.shared.open(AppStorage.outputDirectory(for: config.project, configuration: config))
            modelContext.delete(config)
        case .collectionConfiguration(let config):
            NSWorkspace.shared.open(AppStorage.outputDirectory(for: config.project, configuration: config))
            modelContext.delete(config)
        case .planet:
            break
        }
    }
}

// MARK: - Detail View

struct DetailView: View {
    let selection: SidebarSelection?
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        Group {
            switch selection {
            case .project(let ws):
                ProjectDetailView(project: ws)
            case .kmeansConfiguration(let config):
                ToolKmeansView(configuration: config)
            case .preprocessConfiguration(let config):
                ToolPreprocessView(configuration: config)
            case .collectionConfiguration(let config):
                ToolCollectionView(configuration: config)
            case .planet:
                PlanetView()
            case nil:
                WelcomeView()
            }
        }
        .toolbar {
            if let selection = selection, selection != .planet {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var deleteTitle: String {
        switch selection {
        case .project(let ws): return "Delete \"\(ws.name)\"?"
        case .kmeansConfiguration(let c): return "Delete \"\(c.name)\"?"
        case .preprocessConfiguration(let c): return "Delete \"\(c.name)\"?"
        case .collectionConfiguration(let c): return "Delete \"\(c.name)\"?"
        case .planet, nil: return "Delete?"
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    var body: some View {
        ContentUnavailableView(
            "Welcome to RasterTools",
            systemImage: "map.fill",
            description: Text("Select a project or configuration from the sidebar, or create a new project to get started.")
        )
    }
}

#Preview {
    AppView()
        .modelContainer(for: Project.self, inMemory: true)
}
