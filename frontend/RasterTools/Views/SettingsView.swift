//
//  SettingsView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    /// Bound directly rather than mirrored into `@State`: a local copy is a second source of
    /// truth, and re-reading it on window focus would clobber a path the user just picked.
    @Bindable private var settings = AppSettings.shared

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
        .frame(minWidth: 480)
        // Immediate feedback when the path itself changes (Choose…, or a job that relocates it).
        .onChange(of: settings.virtualEnvPath) { refresh() }
        // Returning to the app after the environment was renamed or deleted behind our back.
        // macOS reuses the Settings window, so onAppear alone would not fire on reopen.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refresh()
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
}
