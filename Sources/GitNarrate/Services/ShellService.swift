import Foundation

final class ShellService {
    static let shared = ShellService()

    private init() {}

    struct ShellResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private struct ProcessConfig {
        let executable: String
        let arguments: [String]
        let cwd: URL?
        let environment: [String: String]?
        let stdinData: Data?
    }

    func run(
        _ executable: String,
        arguments: [String] = [],
        cwd: URL? = nil,
        environment: [String: String]? = nil,
        stdinData: Data? = nil,
        timeout: TimeInterval = 60
    ) async throws -> ShellResult {
        let config = ProcessConfig(
            executable: executable, arguments: arguments,
            cwd: cwd, environment: environment, stdinData: stdinData
        )
        return try await runProcess(
            config: config, timeout: timeout
        )
    }

    /// Run with live stderr streaming via callback
    func run(
        _ executable: String,
        arguments: [String] = [],
        cwd: URL? = nil,
        environment: [String: String]? = nil,
        stdinData: Data? = nil,
        timeout: TimeInterval = 60,
        stderrHandler: @escaping @Sendable (String) -> Void
    ) async throws -> ShellResult {
        let config = ProcessConfig(
            executable: executable, arguments: arguments,
            cwd: cwd, environment: environment, stdinData: stdinData
        )
        return try await runProcess(
            config: config, timeout: timeout,
            stderrHandler: stderrHandler
        )
    }

    /// Run a binary directly by its full path (bypasses /usr/bin/env)
    func runDirect(
        _ executablePath: String,
        arguments: [String] = [],
        cwd: URL? = nil,
        environment: [String: String]? = nil,
        stdinData: Data? = nil,
        timeout: TimeInterval = 60
    ) async throws -> ShellResult {
        let config = ProcessConfig(
            executable: executablePath, arguments: arguments,
            cwd: cwd, environment: environment, stdinData: stdinData
        )
        return try await runProcess(
            config: config, timeout: timeout, directExec: true
        )
    }

    /// Convenience: run and throw on non-zero exit
    func execute(
        _ executable: String,
        arguments: [String] = [],
        cwd: URL? = nil,
        environment: [String: String]? = nil,
        stdinData: Data? = nil,
        timeout: TimeInterval = 60
    ) async throws -> String {
        let result = try await run(
            executable, arguments: arguments,
            cwd: cwd, environment: environment,
            stdinData: stdinData, timeout: timeout
        )
        if result.exitCode != 0 {
            throw ShellError.nonZeroExit(
                code: result.exitCode, stderr: result.stderr
            )
        }
        return result.stdout
    }

    // MARK: - Private

    private func runProcess(
        config: ProcessConfig,
        timeout: TimeInterval,
        directExec: Bool = false,
        stderrHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            configureProcess(
                process, config: config,
                stdoutPipe: stdoutPipe, stderrPipe: stderrPipe,
                directExec: directExec
            )

            let accumulator = stderrHandler.map { handler -> LockedData in
                let acc = LockedData()
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    acc.append(data)
                    if let text = String(data: data, encoding: .utf8) {
                        handler(text)
                    }
                }
                return acc
            }

            let timeoutItem = scheduleTimeout(for: process, after: timeout)

            process.terminationHandler = { _ in
                timeoutItem.cancel()
                if stderrHandler != nil {
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                }
                let result = Self.collectOutput(
                    stdoutPipe: stdoutPipe,
                    stderrPipe: stderrPipe,
                    stderrAccumulator: accumulator,
                    exitCode: process.terminationStatus
                )
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                timeoutItem.cancel()
                if stderrHandler != nil {
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                }
                continuation.resume(throwing: error)
            }
        }
    }

    private func configureProcess(
        _ process: Process,
        config: ProcessConfig,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        directExec: Bool = false
    ) {
        if directExec {
            process.executableURL = URL(fileURLWithPath: config.executable)
            process.arguments = config.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [config.executable] + config.arguments
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let cwd = config.cwd {
            process.currentDirectoryURL = cwd
        }
        if let env = config.environment {
            process.environment = env
        }
        if let stdinData = config.stdinData {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            stdinPipe.fileHandleForWriting.write(stdinData)
            stdinPipe.fileHandleForWriting.closeFile()
        }
    }

    private func scheduleTimeout(
        for process: Process, after timeout: TimeInterval
    ) -> DispatchWorkItem {
        let timeoutItem = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + timeout, execute: timeoutItem
        )
        return timeoutItem
    }

    private static func collectOutput(
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        stderrAccumulator: LockedData?,
        exitCode: Int32
    ) -> ShellResult {
        let stdoutData = stdoutPipe.fileHandleForReading
            .readDataToEndOfFile()
        let stderrData = stderrAccumulator?.data
            ?? stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return ShellResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: exitCode
        )
    }
}

/// Thread-safe Data accumulator for use across concurrent closures.
private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return _data
    }

    func append(_ newData: Data) {
        lock.lock()
        _data.append(newData)
        lock.unlock()
    }
}

enum ShellError: LocalizedError {
    case nonZeroExit(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let code, let stderr):
            "Command failed (exit \(code)): \(stderr)"
        }
    }
}
