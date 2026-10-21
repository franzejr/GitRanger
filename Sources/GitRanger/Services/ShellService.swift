import Foundation

final class ShellService: @unchecked Sendable {
    static let shared = ShellService()

    private let processQueue = DispatchQueue(
        label: "com.gitranger.shell-process",
        qos: .utility,
        attributes: .concurrent
    )

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

    private struct ProcessLaunchOptions {
        let timeout: TimeInterval
        let directExec: Bool
        let stderrHandler: (@Sendable (String) -> Void)?
        let controller: ProcessCancellationController
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
        let controller = ProcessCancellationController()
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Process setup and launch can perform synchronous filesystem
                // and IPC work. Keep it away from the caller's actor.
                processQueue.async { [self] in
                    launchProcess(
                        config: config,
                        options: ProcessLaunchOptions(
                            timeout: timeout,
                            directExec: directExec,
                            stderrHandler: stderrHandler,
                            controller: controller
                        ),
                        continuation: continuation
                    )
                }
            }
        } onCancel: {
            controller.cancel()
        }
        try Task.checkCancellation()
        return result
    }

    private func launchProcess(
        config: ProcessConfig,
        options: ProcessLaunchOptions,
        continuation: CheckedContinuation<ShellResult, Error>
    ) {
        let process = Process()
        let processIO = ProcessIO(hasInput: config.stdinData != nil)
        configureProcess(
            process,
            config: config,
            processIO: processIO,
            directExec: options.directExec
        )
        processIO.beginReading(stderrHandler: options.stderrHandler)

        let timeoutItem = scheduleTimeout(
            for: process,
            after: options.timeout
        )
        process.terminationHandler = { _ in
            timeoutItem.cancel()
            processIO.finishReading()
            continuation.resume(returning: ShellResult(
                stdout: processIO.stdout,
                stderr: processIO.stderr,
                exitCode: process.terminationStatus
            ))
        }

        do {
            try options.controller.launch(process)
            streamInput(config.stdinData, to: processIO)
        } catch {
            timeoutItem.cancel()
            processIO.close()
            continuation.resume(throwing: error)
        }
    }

    private func streamInput(_ data: Data?, to processIO: ProcessIO) {
        guard let data, let inputHandle = processIO.inputHandle else { return }

        // A pipe must be fed only after the child starts reading. Writing a
        // large prompt before process.run() can fill the pipe and freeze the
        // caller indefinitely.
        processQueue.async {
            try? inputHandle.write(contentsOf: data)
            try? inputHandle.close()
        }
    }

    private func configureProcess(
        _ process: Process,
        config: ProcessConfig,
        processIO: ProcessIO,
        directExec: Bool = false
    ) {
        if directExec {
            process.executableURL = URL(fileURLWithPath: config.executable)
            process.arguments = config.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [config.executable] + config.arguments
        }
        process.qualityOfService = .utility
        process.standardOutput = processIO.stdoutPipe
        process.standardError = processIO.stderrPipe
        process.standardInput = processIO.stdinPipe

        if let cwd = config.cwd {
            process.currentDirectoryURL = cwd
        }
        if let env = config.environment {
            process.environment = env
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

}

/// Connects structured-concurrency cancellation to Foundation's Process.
/// Without this bridge a cancelled review leaves its CLI running and can later
/// consume a coordinator slot or provider quota.
private final class ProcessCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    func launch(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { throw CancellationError() }
        self.process = process
        try process.run()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let runningProcess = process?.isRunning == true ? process : nil
        lock.unlock()
        runningProcess?.terminate()
    }
}

/// Owns a child process's pipes and drains them without blocking its caller.
private final class ProcessIO: @unchecked Sendable {
    let stdinPipe: Pipe?
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    private let stdoutAccumulator = LockedData()
    private let stderrAccumulator = LockedData()

    init(hasInput: Bool) {
        stdinPipe = hasInput ? Pipe() : nil
    }

    var inputHandle: FileHandle? {
        stdinPipe?.fileHandleForWriting
    }

    var stdout: String {
        String(data: stdoutAccumulator.data, encoding: .utf8) ?? ""
    }

    var stderr: String {
        String(data: stderrAccumulator.data, encoding: .utf8) ?? ""
    }

    func beginReading(
        stderrHandler: (@Sendable (String) -> Void)?
    ) {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [stdoutAccumulator] handle in
            stdoutAccumulator.append(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [stderrAccumulator] handle in
            let data = handle.availableData
            stderrAccumulator.append(data)
            if let stderrHandler,
               !data.isEmpty,
               let text = String(data: data, encoding: .utf8) {
                stderrHandler(text)
            }
        }
    }

    func finishReading() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutAccumulator.append(
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        )
        stderrAccumulator.append(
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        )
    }

    func close() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? inputHandle?.close()
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
