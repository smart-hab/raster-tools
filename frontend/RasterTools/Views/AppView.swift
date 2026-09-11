//
//  AppView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - Focused Values (for menu)

private struct FocusedProjectsKey: FocusedValueKey {
    typealias Value = [Project]
}

private struct FocusedSelectionKey: FocusedValueKey {
    typealias Value = Binding<SidebarSelection?>
}

private struct FocusedAddProjectKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct FocusedImportShapeFilesKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct FocusedAddConfigurationKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var projects: [Project]? {
        get { self[FocusedProjectsKey.self] }
        set { self[FocusedProjectsKey.self] = newValue }
    }
    var sidebarSelection: Binding<SidebarSelection?>? {
        get { self[FocusedSelectionKey.self] }
        set { self[FocusedSelectionKey.self] = newValue }
    }
    var addProject: (() -> Void)? {
        get { self[FocusedAddProjectKey.self] }
        set { self[FocusedAddProjectKey.self] = newValue }
    }
    var importShapeFiles: (() -> Void)? {
        get { self[FocusedImportShapeFilesKey.self] }
        set { self[FocusedImportShapeFilesKey.self] = newValue }
    }
    var addConfiguration: (() -> Void)? {
        get { self[FocusedAddConfigurationKey.self] }
        set { self[FocusedAddConfigurationKey.self] = newValue }
    }
}

// MARK: - SidebarSelection

enum SidebarSelection: Hashable {
    case project(Project)
    case kmeansConfiguration(ToolKmeansConfiguration)
    case preprocessConfiguration(ToolPreprocessConfiguration)
    case collectionConfiguration(ToolCollectionConfiguration)
    case sentinel2Configuration(ToolSentinel2Configuration)
    case planet
}

// MARK: - App View (Main App view)

struct AppView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.modifiedAt, order: .reverse)
    private var projects: [Project]

    @State private var selection: SidebarSelection?
    @State private var showingNewProjectSheet = false
    @State private var showingNewConfigSheet = false
    @State private var showingVenvSetupPrompt = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                projects: projects,
                selection: $selection,
                onAddProject: { showingNewProjectSheet = true }
            )
        } detail: {
            DetailView(selection: selection, onAddConfiguration: { showingNewConfigSheet = true }) {
                deleteSelection()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .focusedValue(\.projects, projects)
        .focusedValue(\.sidebarSelection, $selection)
        .focusedValue(\.addProject, { showingNewProjectSheet = true })
        .focusedValue(\.importShapeFiles, importShapeFilesCallback)
        .focusedValue(\.addConfiguration, addConfigurationCallback)
        .task {
            // Prompt on every launch until a working environment exists — declining is not
            // remembered, since without one no tool can run at all.
            //
            // Suppressed when the configured directory holds anything, because setup runs
            // `venv --clear` on it: offering one-click deletion of a folder the user pointed at
            // by mistake is not a prompt worth showing. Settings handles that case with an
            // explanation instead.
            if !AppSettings.shared.isVirtualEnvValid,
               AppSettings.shared.isVirtualEnvEmptyOrMissing {
                showingVenvSetupPrompt = true
            }
        }
        .alert("No Python Environment detected", isPresented: $showingVenvSetupPrompt) {
            Button("Continue") { ToolVenvSetup.launch() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Would you like to initialize a new environment now?\n\nThe path can be changed later in the Settings.\n\nThis process takes a few minutes. You can follow the progress in the Jobs list in the sidebar.")
        }
        .sheet(isPresented: $showingNewProjectSheet) {
            ProjectCreateSheet { project in
                modelContext.insert(project)
                selection = .project(project)
                showingNewProjectSheet = false
            } onCancel: {
                showingNewProjectSheet = false
            }
        }
        .sheet(isPresented: $showingNewConfigSheet) {
            if let project = selectedProject {
                ToolCreateSheet(defaultProject: project) { config in
                    if let c = config as? ToolKmeansConfiguration {
                        selection = .kmeansConfiguration(c)
                    } else if let c = config as? ToolPreprocessConfiguration {
                        selection = .preprocessConfiguration(c)
                    } else if let c = config as? ToolCollectionConfiguration {
                        selection = .collectionConfiguration(c)
                    } else if let c = config as? ToolSentinel2Configuration {
                        selection = .sentinel2Configuration(c)
                    }
                    showingNewConfigSheet = false
                }
            }
        }
    }

    private var selectedProject: Project? {
        switch selection {
        case .project(let p): return p
        case .kmeansConfiguration(let c): return c.project
        case .preprocessConfiguration(let c): return c.project
        case .collectionConfiguration(let c): return c.project
        case .sentinel2Configuration(let c): return c.project
        case .planet, nil: return nil
        }
    }

    private var addConfigurationCallback: (() -> Void)? {
        selectedProject != nil ? { showingNewConfigSheet = true } : nil
    }

    private var importShapeFilesCallback: (() -> Void)? {
        guard case .project(let project) = selection else { return nil }
        return { openShapeFileImporter(for: project) }
    }

    private func openShapeFileImporter(for project: Project) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Select shape files to import"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "shp"),
            UTType(filenameExtension: "geojson"),
        ].compactMap { $0 }
        panel.begin { response in
            guard response == .OK else { return }
            if project.importShapeFiles(from: panel.urls) {
                project.refresh(context: modelContext)
            }
        }
    }

    private func deleteSelection() {
        guard let selection else { return }
        self.selection = nil
        switch selection {
        case .project(let project):
            NSWorkspace.shared.open(AppStorage.outputDirectory(for: project))
            modelContext.delete(project)
        case .kmeansConfiguration(let config):
            NSWorkspace.shared.open(AppStorage.outputDirectory(for: config.project, configuration: config))
            modelContext.delete(config)
        case .preprocessConfiguration(let config):
            NSWorkspace.shared.open(AppStorage.outputDirectory(for: config.project, configuration: config))
            modelContext.delete(config)
        case .collectionConfiguration(let config):
            NSWorkspace.shared.open(AppStorage.outputDirectory(for: config.project, configuration: config))
            modelContext.delete(config)
        case .sentinel2Configuration(let config):
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
    let onAddConfiguration: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        Group {
            switch selection {
            case .project(let project):
                ProjectDetailView(project: project, onAddConfiguration: onAddConfiguration)
            case .kmeansConfiguration(let config):
                ToolKmeansView(configuration: config)
            case .preprocessConfiguration(let config):
                ToolPreprocessView(configuration: config)
            case .collectionConfiguration(let config):
                ToolCollectionPlanetView(configuration: config)
            case .sentinel2Configuration(let config):
                ToolSentinel2View(configuration: config)
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
        case .project(let project): return "Delete \"\(project.name)\"?"
        case .kmeansConfiguration(let c): return "Delete \"\(c.name)\"?"
        case .preprocessConfiguration(let c): return "Delete \"\(c.name)\"?"
        case .collectionConfiguration(let c): return "Delete \"\(c.name)\"?"
        case .sentinel2Configuration(let c): return "Delete \"\(c.name)\"?"
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
