//
//  SettingsView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import SwiftData
import AppKit

struct SettingsView: View {
    /// Bound directly rather than mirrored into `@State`: a local copy is a second source of
    /// truth, and re-reading it on window focus would clobber a path the user just picked.
    @Bindable private var settings = AppSettings.shared

    @Environment(JobRegistry.self) private var jobRegistry
    @Query private var projects: [Project]

    /// Nil until the first scan finishes. Sizing can walk gigabytes, so it never runs on the
    /// 3-second poll below — only when the references change or the window regains focus.
    @State private var orphanReport: OrphanReport?
    @State private var scanGeneration = 0
    @State private var isCleaningUp = false
    @State private var showingCleanUpConfirmation = false

    /// Validity, unlike the path, is filesystem state that nothing can publish, so it has to be
    /// polled. See `refresh()` and the triggers on the form below.
    @State private var isValid: Bool = AppSettings.shared.isVirtualEnvValid

    /// Same story: whether the configured directory is still empty enough for `venv` to claim.
    @State private var canSetUp: Bool = AppSettings.shared.isVirtualEnvEmptyOrMissing

    var body: some View {
        Form {
            Section("Python") {
                LabeledContent("Virtual Environment Path") {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isValid ? .green : .orange)
                    Text(settings.virtualEnvPath.isEmpty ? "No path selected" : settings.virtualEnvPath)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    Button("Choose…") {
                        selectVenvDirectory()
                    }
                }
                if !isValid {
                    LabeledContent("") {
                        Button("Setup Environment") {
                            ToolVenvSetup.launch()
                        }
                        // `python -m venv` must own the directory, so setup is only offered
                        // when it is empty or does not exist yet — and never while a run is
                        // already building one.
                        .disabled(!canSetUp || isSettingUp)
                    }
                }
                Text(helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tool Outputs") {
                LabeledContent("Output Directory") {
                    Text(settings.outputsPath.isEmpty
                         ? AppStorage.defaultOutputsDirectory().path
                         : settings.outputsPath)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    Button("Choose…") {
                        selectOutputsDirectory()
                    }
                }
                // Second row, like "Setup Environment" above: an action about the path rather
                // than part of the path row itself, which would otherwise overflow it.
                if !isUsingDefaultOutputs {
                    LabeledContent("") {
                        Button("Use Default") {
                            settings.outputsPath = AppStorage.defaultOutputsDirectory().path
                        }
                    }
                }
                Text("The folder where all tool outputs are stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Orphaned Outputs") {
                LabeledContent("Orphaned Folders") {
                    Text(orphanSummary)
                        .monospacedDigit()
                    Button("Clean Up…") {
                        showingCleanUpConfirmation = true
                    }
                    .disabled((orphanReport?.items.isEmpty ?? true) || isCleaningUp || hasRunningJobs)
                }
                Text(orphanHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Planet.com") {
                SecureField("API Key", text: $settings.planetApiKey)
                    .overlay(alignment: .trailing) {
                        if settings.planetApiKey.isEmpty {
                            Text("No API key set")
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                        }
                    }
                Text("Your Planet Labs API key, used by the Planet Collection tool.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Copernicus") {
                TextField("Username", text: $settings.cdseUsername)
                SecureField("Password", text: $settings.cdsePassword)
                    .overlay(alignment: .trailing) {
                        if settings.cdsePassword.isEmpty {
                            Text("No password set")
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                        }
                    }
                Text("""
                    Your Copernicus Data Space Ecosystem account, used by the Sentinel-2 \
                    Collection tool. Registration is free at dataspace.copernicus.eu.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        // Tall enough to show every section without scrolling.
        .frame(minWidth: 480, minHeight: 800)
        // Immediate feedback when the path itself changes (Choose…, or a job that relocates it).
        .onChange(of: settings.virtualEnvPath) { refresh() }
        // Returning to the app after the environment was renamed or deleted behind our back.
        // macOS reuses the Settings window, so onAppear alone would not fire on reopen.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refresh()
            scanGeneration += 1
        }
        // Re-scans whenever a project, configuration or resource comes or goes, or the outputs
        // root moves. `.task(id:)` cancels a scan that a newer one supersedes.
        .task(id: ScanKey(references: outputReferences, generation: scanGeneration)) {
            await scanOrphans()
        }
        .alert("Delete Orphaned Outputs?", isPresented: $showingCleanUpConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("I am sure", role: .destructive) {
                Task { await cleanUpOrphans() }
            }
        } message: {
            Text("""
                \(orphanSummary) will be permanently deleted from \
                \(AppStorage.outputsRoot().path). This cannot be undone.
                """)
        }
        // Catch-all, and the only trigger that covers a setup job finishing at the *same* path
        // while this window stays focused — re-assigning an identical string does not trip
        // onChange. Two file checks per tick, so the interval is cheap to shorten.
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// A setup job in flight. Unlike `isValid`/`canSetUp` this needs no polling — the runner is
    /// `@Observable`, so reading it from the body is enough to redraw when the run ends.
    @MainActor
    private var isSettingUp: Bool { ToolVenvSetup.active != nil }

    /// The caption under the path row. The `!canSetUp` branch explains the disabled button:
    /// the path is broken *and* the directory is occupied, so the user has to intervene.
    @MainActor
    private var helpText: String {
        if isSettingUp {
            return "Initializing environment…"
        }
        if isValid {
            return "The folder containing the bin/ directory of your Python virtualenv."
        }
        if canSetUp {
            return "This environment is missing bin/python or the processing tools."
        }
        return "The configured path is not a valid virtual environment, and the directory is not empty. Please select a different path."
    }

    /// Re-checks the configured path on disk. Never writes the path — that would be a second
    /// source of truth racing the user's own edits.
    private func refresh() {
        isValid = settings.isVirtualEnvValid
        canSetUp = settings.isVirtualEnvEmptyOrMissing
    }

    // MARK: - Orphaned outputs

    private struct ScanKey: Equatable {
        let references: OutputReferences
        let generation: Int
    }

    /// Reading `projects` (and their relationships) here is what ties the scan to SwiftData
    /// changes: the view redraws, the key changes, the task restarts.
    private var outputReferences: OutputReferences {
        OutputReferences(projects: projects, outputsRoot: AppStorage.outputsRoot())
    }

    /// Deleting outputs under a job that is writing them would pull files out from under it.
    private var hasRunningJobs: Bool {
        jobRegistry.jobs.contains { $0.runner.isRunning }
    }

    private var orphanSummary: String {
        guard let orphanReport else { return "Scanning…" }
        let count = orphanReport.items.count
        let size = ByteCountFormatter.string(fromByteCount: orphanReport.totalBytes, countStyle: .file)
        return "\(count) folder\(count == 1 ? "" : "s") (\(size))"
    }

    private var orphanHelpText: String {
        if isCleaningUp {
            return "Deleting orphaned outputs…"
        }
        if hasRunningJobs, !(orphanReport?.items.isEmpty ?? true) {
            return "Clean up is unavailable while jobs are running."
        }
        return """
            Output folders left behind by deleted projects and tool configurations. Folders \
            holding files still listed in a project are kept.
            """
    }

    private func scanOrphans() async {
        let refs = outputReferences
        let report = await Task.detached(priority: .utility) { OrphanedOutputs.scan(refs) }.value
        guard !Task.isCancelled else { return }
        orphanReport = report
    }

    private func cleanUpOrphans() async {
        guard let items = orphanReport?.items, !items.isEmpty, !hasRunningJobs else { return }
        isCleaningUp = true
        // Captured now, on the main actor, so the removal re-checks against current state.
        let refs = outputReferences
        await Task.detached(priority: .userInitiated) {
            OrphanedOutputs.remove(items, refs: refs)
        }.value
        isCleaningUp = false
        orphanReport = nil
        scanGeneration += 1
    }

    /// True when the configured outputs path is the built-in one — including the cleared case,
    /// which `AppStorage.outputsRoot()` also resolves to the default.
    private var isUsingDefaultOutputs: Bool {
        settings.outputsPath.isEmpty
            || settings.outputsPath == AppStorage.defaultOutputsDirectory().path
    }

    private func selectVenvDirectory() {
        guard let url = chooseDirectory(title: "Select Virtual Environment Directory") else { return }
        settings.virtualEnvPath = url.path
    }

    private func selectOutputsDirectory() {
        guard let url = chooseDirectory(
            title: "Select Output Directory",
            canCreateDirectories: true
        ) else { return }
        settings.outputsPath = url.path
    }

    private func chooseDirectory(title: String, canCreateDirectories: Bool = false) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = canCreateDirectories
        panel.allowsMultipleSelection = false
        panel.title = title
        panel.prompt = "Select"

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

#Preview {
    SettingsView()
        .environment(JobRegistry.shared)
        .modelContainer(for: Project.self, inMemory: true)
}
