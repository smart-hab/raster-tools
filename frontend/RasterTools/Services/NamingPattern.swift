//
//  NamingPattern.swift
//  RasterTools
//
//  Created by Marek on 2026-09-02.
//

import Foundation

/// Expands a configuration's naming pattern for one scene date.
///
/// Supported tokens: `{Project}`, `{ConfigName}`, `{Year}`, `{Month}`, `{Day}`, `{Parameters}`.
/// `parameters` is provider-specific — each collector builds its own summary of the search
/// parameters that produced the scene.
func resolveNamingPattern(
    _ pattern: String,
    configName: String,
    projectName: String,
    parameters: String,
    date: Date
) -> String {
    let calendar = Date.utcCalendar
    let year = String(format: "%04d", calendar.component(.year, from: date))
    let month = String(format: "%02d", calendar.component(.month, from: date))
    let day = String(format: "%02d", calendar.component(.day, from: date))

    return pattern
        .replacingOccurrences(of: "{Project}", with: projectName)
        .replacingOccurrences(of: "{ConfigName}", with: configName)
        .replacingOccurrences(of: "{Year}", with: year)
        .replacingOccurrences(of: "{Month}", with: month)
        .replacingOccurrences(of: "{Day}", with: day)
        .replacingOccurrences(of: "{Parameters}", with: parameters)
}
