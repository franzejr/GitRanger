import Foundation

final class ShellService {
    static let shared = ShellService()

    private init() {}

    struct ShellResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    func run(
        _ executable: String,
        arguments: [String] = [],
        cwd: URL? = nil,
        environment: [String: String]? = nil,
        stdinData: Data? = nil,
        timeout: TimeInterval = 60
    ) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            if let cwd {
                process.currentDirectoryURL = cwd
            }

            if let environment {
                process.environment = environment
            }

            if let stdinData {
                let stdinPipe = Pipe()
                process.standardInput = stdinPipe
                stdinPipe.fileHandleForWriting.write(stdinData)
                stdinPipe.fileHandleForWriting.closeFile()
            }

            // Timeout watchdog
            let timeoutItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutItem
            )

            process.terminationHandler = { _ in
                timeoutItem.cancel()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                continuation.resume(returning: ShellResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: process.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                timeoutItem.cancel()
                continuation.resume(throwing: error)
            }
        }
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
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            if let cwd {
                process.currentDirectoryURL = cwd
            }

            if let environment {
                process.environment = environment
            }

            if let stdinData {
                let stdinPipe = Pipe()
                process.standardInput = stdinPipe
                stdinPipe.fileHandleForWriting.write(stdinData)
                stdinPipe.fileHandleForWriting.closeFile()
            }

            // Thread-safe accumulator for stderr data
            let accumulator = LockedData()
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                accumulator.append(data)
                if let text = String(data: data, encoding: .utf8) {
                    stderrHandler(text)
                }
            }

            let timeoutItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutItem
            )

            process.terminationHandler = { _ in
                timeoutItem.cancel()
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: accumulator.data, encoding: .utf8) ?? ""
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

                continuation.resume(returning: ShellResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: process.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                timeoutItem.cancel()
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
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
            executable,
            arguments: arguments,
            cwd: cwd,
            environment: environment,
            stdinData: stdinData,
            timeout: timeout
        )
        if result.exitCode != 0 {
            throw ShellError.nonZeroExit(
                code: result.exitCode,
                stderr: result.stderr
            )
        }
        return result.stdout
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
