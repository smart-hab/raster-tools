//
//  ToolVenvSetup.swift
//  RasterTools
//
//  Created by Marek on 2026-08-12.
//

import Foundation

/// Creates the app-managed Python virtualenv and installs the `smart_hab` processing package
/// into it, streaming the full transcript to the job log.
///
/// This runner deliberately does *not* use `ToolRunner.runProcess`: that resolves executables
/// inside an already-working venv, and it reads its pipes only after the process exits, which
/// deadlocks once pip's build output exceeds the pipe buffer. See `run(_:_:env:)` below.
final class ToolVenvSetup: ToolRunner {

    /// The processing package. Its `pyproject.toml` is the source of truth for the dependency
    /// closure — installing this URL resolves rasterio, geopandas, scikit-learn and the rest.
    static let packageURL = "git+ssh://git@github.com/smart-hab/processing-scripts.git"

    /// `smart_hab` requires Python >= 3.12.
    static let minimumPython = (major: 3, minor: 12)

    /// Absolute interpreter candidates, best first. Versions are determined by *executing* these,
    /// never inferred from the filename — `/usr/bin/python3` is the Command Line Tools shim and is
    /// commonly far older than the Homebrew interpreters.
    static let interpreterCandidates = [
        "/opt/homebrew/bin/python3.14",
        "/opt/homebrew/bin/python3.13",
        "/opt/homebrew/bin/python3.12",
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3.14",
        "/usr/local/bin/python3.13",
        "/usr/local/bin/python3.12",
        "/usr/local/bin/python3",
        "/usr/bin/python3",
    ]

    private var setupTask: Task<Void, Never>? {
        didSet { isRunning = setupTask != nil }
    }

    /// The child process currently running, so `cancel()` can kill a long pip install.
    /// The base class's `currentProcess` only tracks `runProcess`, which this runner bypasses.
    private var activeProcess: Process?

    override func cancel() {
        setupTask?.cancel()
        setupTask = nil
        activeProcess?.terminate()
        activeProcess = nil
    }

    /// The setup run currently in flight, if any. Observable end to end — reading this from a
    /// view body tracks both the job list and each runner's `isRunning`.
    @MainActor
    static var active: ToolVenvSetup? {
        JobRegistry.shared.jobs
            .compactMap { $0.runner as? ToolVenvSetup }
            .first { $0.isRunning }
    }

    /// Registers a setup run as a job and starts it, so its progress and log show up in the
    /// sidebar job list like any other tool run. Used by both the launch prompt and Settings.
    ///
    /// A setup already in flight is returned as-is: `AppView.task` runs once per window, so
    /// opening a second window must not start a second `venv --clear` on the same directory.
    @MainActor
    @discardableResult
    static func launch() -> ToolVenvSetup {
        if let existing = active { return existing }

        let runner = ToolVenvSetup()
        JobRegistry.shared.register(
            runner: runner,
            configName: "Python Environment Setup",
            projectName: ""
        )
        // The configured path is the destination; falling back to the default covers a path
        // the user cleared by hand.
        let configured = AppSettings.shared.virtualEnvPath
        let destination = configured.isEmpty
            ? AppStorage.defaultVenvDirectory()
            : URL(fileURLWithPath: configured)
        runner.start(destination: destination)
        return runner
    }

    @MainActor
    func start(destination: URL) {
        error = nil
        logFile = AppStorage.logsDirectory()
            .appendingPathComponent("venv-setup-\(generateTimestamp()).log")

        setupTask = Task { @MainActor in
            defer { setupTask = nil }

            do {
                // Recorded first so the user can find this transcript again after relaunch —
                // jobs themselves live only in memory.
                if let logFile { await log("Log: \(logFile.path)") }
                await log("Destination: \(destination.path)")

                // 1. Interpreter
                await update(ToolProgress(statusText: "Looking for Python", progress: 0.1))
                let python = try await findInterpreter()

                try Task.checkCancellation()

                // 2. Create the venv. --clear because this runner also repairs a half-built venv.
                await update(ToolProgress(statusText: "Creating virtual environment", progress: 0.3))
                await log("$ \(python.path) -m venv --clear \(destination.path)")
                try await runChecked(python, ["-m", "venv", "--clear", destination.path])

                let venvPython = destination.appendingPathComponent("bin/python")

                try Task.checkCancellation()

                // 3. Modern pip, so the git+ssh install and wheel resolution behave.
                await update(ToolProgress(statusText: "Upgrading pip", progress: 0.4))
                await log("$ python -m pip install --upgrade pip")
                try await runChecked(venvPython, ["-m", "pip", "install", "--upgrade", "pip"])

                try Task.checkCancellation()

                // 4. The one direct requirement; its dependencies follow from pyproject.toml.
                await update(ToolProgress(
                    statusText: "Installing processing tools",
                    progress: 0.5,
                    progressText: "this takes a few minutes"
                ))
                await log("$ python -m pip install \(Self.packageURL)")
                try await runChecked(
                    venvPython,
                    ["-m", "pip", "install", Self.packageURL],
                    env: Self.gitEnvironment
                )

                // 5. Only adopt the venv once it demonstrably works.
                let sentinel = destination
                    .appendingPathComponent("bin")
                    .appendingPathComponent(AppSettings.sentinelScript)
                guard FileManager.default.isExecutableFile(atPath: sentinel.path) else {
                    throw ToolError.fileNotFound(sentinel.path)
                }

                AppSettings.shared.virtualEnvPath = destination.path
                await update(ToolProgress(statusText: "Complete", progress: 1.0))
                await log("✓ Python environment ready at \(destination.path)")

            } catch is CancellationError {
                await update(ToolProgress(statusText: "Cancelled", progress: progress.progress))
                await log("Cancelled — the Python environment was not configured.")
            } catch {
                self.error = error
                await update(ToolProgress(statusText: "Error", progress: progress.progress))
                await log("✗ \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Interpreter discovery

    private func findInterpreter() async throws -> URL {
        let fm = FileManager.default
        for path in Self.interpreterCandidates {
            guard fm.isExecutableFile(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path)
            guard let version = try? await pythonVersion(of: url) else { continue }

            let ok = (version.major, version.minor) >= (Self.minimumPython.major, Self.minimumPython.minor)
            await log("\(ok ? "✓" : "·") \(path) → Python \(version.major).\(version.minor)")
            if ok { return url }
        }
        throw VenvSetupError.noSuitablePython
    }

    /// Reads a candidate interpreter's version.
    ///
    /// Deliberately *not* routed through `run(_:_:env:)`: the output is a handful of bytes, so
    /// there is no pipe-buffer risk, and draining after exit keeps the result on one thread
    /// instead of accumulating it across background readability callbacks.
    private func pythonVersion(of interpreter: URL) async throws -> (major: Int, minor: Int) {
        let process = Process()
        process.executableURL = interpreter
        process.arguments = ["-c", "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard process.terminationStatus == 0, parts.count == 2,
              let major = Int(parts[0]), let minor = Int(parts[1]) else {
            throw VenvSetupError.versionCheckFailed(interpreter.path)
        }
        return (major, minor)
    }

    // MARK: - Subprocess

    /// A GUI-launched app has no controlling terminal, so an ssh passphrase, host-key or credential
    /// prompt from pip's `git clone` would block forever with no output. BatchMode turns those into
    /// a prompt failure that surfaces in the log within seconds.
    private static let gitEnvironment = [
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_SSH_COMMAND": "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new",
    ]

    private func runChecked(_ executable: URL, _ args: [String], env: [String: String] = [:]) async throws {
        let status = try await run(executable, args, env: env)
        guard status == 0 else {
            // `cancel()` kills the child, which surfaces here as a non-zero exit. Report that as
            // cancellation rather than a tool failure.
            if Task.isCancelled { throw CancellationError() }
            throw ToolError.processError(
                code: status,
                message: "\(executable.lastPathComponent) failed — see the log above for details"
            )
        }
    }

    /// Runs `executable` and streams stdout+stderr line by line as they arrive.
    ///
    /// Streaming is required, not cosmetic: pip emits megabytes while building rasterio and
    /// geopandas, which would fill the pipe buffer and wedge the child if we only drained the
    /// pipes after exit.
    @discardableResult
    private func run(
        _ executable: URL,
        _ args: [String],
        env: [String: String] = [:]
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        if !env.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Partial reads split mid-line, so hold a remainder between callbacks.
        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in buffer.append(data) {
                Task { await self.log(line) }
            }
        }

        activeProcess = process
        defer { activeProcess = nil }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }

        // Drain whatever landed between the last callback and exit, then detach the handler.
        // Never mix this with readDataToEndOfFile while a handler is installed.
        let remaining = pipe.fileHandleForReading.availableData
        pipe.fileHandleForReading.readabilityHandler = nil
        for line in buffer.flush(remaining) {
            await log(line)
        }

        return process.terminationStatus
    }
}

/// Accumulates streamed bytes and hands back only complete lines.
private final class LineBuffer: @unchecked Sendable {
    private var partial = ""
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        partial += String(decoding: data, as: UTF8.self)
        var lines = partial.components(separatedBy: "\n")
        partial = lines.removeLast()
        return lines
    }

    func flush(_ data: Data) -> [String] {
        var lines = append(data)
        lock.lock()
        defer { lock.unlock() }
        if !partial.isEmpty {
            lines.append(partial)
            partial = ""
        }
        return lines
    }
}

enum VenvSetupError: LocalizedError {
    case noSuitablePython
    case versionCheckFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSuitablePython:
            return "No Python \(ToolVenvSetup.minimumPython.major).\(ToolVenvSetup.minimumPython.minor) or newer was found. Install one (for example: brew install python@3.13) and try again."
        case .versionCheckFailed(let path):
            return "Could not determine the Python version of \(path)"
        }
    }
}
