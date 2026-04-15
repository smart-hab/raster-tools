//
//  SettingsView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var venvPath: String = AppSettings.shared.virtualEnvPath
    @State private var planetApiKey: String = AppSettings.shared.planetApiKey

    var body: some View {
        Form {
            Section("Python") {
                HStack {
                    Text("Virtual Environment Path")
                    Spacer()
                    Text(venvPath.isEmpty ? "No path selected" : venvPath)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    Button("Choose…") {
                        selectVenvDirectory()
                    }
                }
                Text("The folder containing the bin/ directory of your Python virtualenv.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Planet.com") {
                SecureField("API Key", text: $planetApiKey)
                    .overlay(alignment: .trailing) {
                        if planetApiKey.isEmpty {
                            Text("No API key set")
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                        }
                    }
                Text("Your Planet Labs API key, used by the Collection tool.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480)
        .onChange(of: venvPath) { _, newValue in
            AppSettings.shared.virtualEnvPath = newValue
        }
        .onChange(of: planetApiKey) { _, newValue in
            AppSettings.shared.planetApiKey = newValue
        }
    }

    private func selectVenvDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Virtual Environment Directory"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        venvPath = url.path
    }
}

#Preview {
    SettingsView()
}
