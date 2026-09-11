//
//  JobRegistry.swift
//  RasterTools
//
//  Created by Marek on 2026-03-21.
//

import Foundation

struct Job: Identifiable {
    let id = UUID()
    let configName: String
    let projectName: String
    let startedAt: Date
    let runner: ToolRunner
}

@Observable
class JobRegistry {
    static let shared = JobRegistry()
    var jobs: [Job] = []

    private init() {}

    @discardableResult
    func register(runner: ToolRunner, configName: String, projectName: String) -> Job {
        let job = Job(configName: configName, projectName: projectName, startedAt: Date(), runner: runner)
        jobs.append(job)
        return job
    }

    func remove(_ job: Job) {
        jobs.removeAll { $0.id == job.id }
    }
}
