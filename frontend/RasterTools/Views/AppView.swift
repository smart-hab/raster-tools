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
    case workspace(Workspace)
    case configuration(ToolConfiguration)
    case planet
}

// MARK: - App View (Main App view)

struct AppView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workspace.modifiedAt, order: .reverse)
    private var workspaces: [Workspace]

    @State private var selection: SidebarSelection?
    @State private var showingNewWorkspaceSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                workspaces: workspaces,
                selection: $selection,
                onAddWorkspace: { showingNewWorkspaceSheet = true }
            )
        } detail: {
            DetailView(selection: selection) { deleteSelection() }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingNewWorkspaceSheet) {
            WorkspaceCreateSheet { workspace in
                modelContext.insert(workspace)
                selection = .workspace(workspace)
                showingNewWorkspaceSheet = false
            } onCancel: {
                showingNewWorkspaceSheet = false
            }
        }
    }

    private func deleteSelection() {
        guard let selection else { return }
        self.selection = nil
        switch selection {
        case .workspace(let ws):
            NSWorkspace.shared.open(AppStorage.outputDirectory(for: ws))
            modelContext.delete(ws)
        case .configuration(let config):
            if let workspace = config.workspace {
                NSWorkspace.shared.open(AppStorage.outputDirectory(for: workspace, configuration: config))
            }
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
            case .workspace(let ws):
                WorkspaceDetailView(workspace: ws)
            case .configuration(let config):
                switch config.toolType {
                case .kmeans:
                    ToolKmeansView(configuration: config)
                case .preprocess:
                    ToolPreprocessView(configuration: config)
                case .collection:
                    ToolCollectionView(configuration: config)
                }
            case .planet:
                PlanetView()
            case nil:
                WelcomeView()
            }
        }
        .toolbar {
            if selection != nil, selection != .planet {
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
        case .workspace(let ws): return "Delete \"\(ws.name)\"?"
        case .configuration(let c): return "Delete \"\(c.name)\"?"
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
            description: Text("Select a workspace or configuration from the sidebar, or create a new workspace to get started.")
        )
    }
}

#Preview {
    AppView()
        .modelContainer(for: Workspace.self, inMemory: true)
}
