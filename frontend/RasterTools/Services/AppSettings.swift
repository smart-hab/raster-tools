//
//  AppSettings.swift
//  RasterTools
//
//  Created by Marek on 2026-03-20.
//

import Foundation

/// Stores global app settings backed by UserDefaults.
@Observable
class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private init() {}

    var virtualEnvPath: String {
        get { defaults.string(forKey: "virtualEnvPath") ?? "" }
        set { defaults.set(newValue, forKey: "virtualEnvPath") }
    }

    var planetApiKey: String {
        get { defaults.string(forKey: "planetApiKey") ?? "" }
        set { defaults.set(newValue, forKey: "planetApiKey") }
    }
}
