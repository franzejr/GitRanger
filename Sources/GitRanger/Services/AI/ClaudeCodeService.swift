import Foundation

final class ClaudeCodeService: AIServiceProtocol {
    let displayName = "Claude Code (Local)"
    let requiresAPIKey = false

    private let shell = ShellService.shared

    private var claudeBinary: String {
        let custom = UserDefaults.standard.string(forKey: "claudePath") ?? ""
        return custom.isEmpty ? "claude" : custom
    }

    func isAvailable() async -> Bool {
        let binary = claudeBinary
        if binary != "claude" {
            return FileManager.default.isExecutableFile(atPath: binary)
        }
        do {
            let output = try await shell.execute("which", arguments: ["claude"])
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    func summarize(
        commitMessage: String,
        diff: String,
        repoPath: URL?
    ) async throws -> CommitSummary {
        let truncatedDiff = String(diff.prefix(12000))
        let prompt = PromptBuilder.buildCommitPrompt(
            commitMessage: commitMessage,
            diff: truncatedDiff
        )

        let output = try await runClaude(
            prompt: prompt,
            repoPath: repoPath,
            timeout: 90,
            useTools: true
        )

        return try PromptBuilder.parseCommitSummary(raw: output)
    }

    func generate(prompt: String, repoPath: URL?) async throws -> String {
        try await runClaude(
            prompt: prompt,
            repoPath: nil,
            timeout: 300,
            useTools: false
        )
    }

    // MARK: - Private

    private func runClaude(
        prompt: String,
        repoPath: URL?,
        timeout: TimeInterval,
        useTools: Bool
    ) async throws -> String {
        let arguments = buildArguments(
            useTools: useTools, repoPath: repoPath
        )

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")

        guard let stdinData = prompt.data(using: .utf8) else {
            throw AIError.invalidResponse("Could not encode prompt")
        }

        let result = try await executeClaudeBinary(
            arguments: arguments, env: env,
            stdinData: stdinData, timeout: timeout
        )

        guard result.exitCode == 0 else {
            throw claudeError(result)
        }

        return try parseClaudeOutput(result.stdout)
    }

    private func buildArguments(
        useTools: Bool, repoPath: URL?
    ) -> [String] {
        var args = [
            "-p", "-",
            "--output-format", "json",
            "--model", "haiku",
            "--no-session-persistence"
        ]
        if useTools {
            args += ["--allowedTools", "Read,Grep,Glob"]
        }
        if let repoPath {
            args += ["--add-dir", repoPath.path]
        }
        return args
    }

    private func executeClaudeBinary(
        arguments: [String], env: [String: String],
        stdinData: Data, timeout: TimeInterval
    ) async throws -> ShellService.ShellResult {
        let binary = claudeBinary
        if binary.contains("/") {
            return try await shell.runDirect(
                binary, arguments: arguments,
                environment: env, stdinData: stdinData,
                timeout: timeout
            )
        }
        return try await shell.run(
            binary, arguments: arguments,
            environment: env, stdinData: stdinData,
            timeout: timeout
        )
    }

    private func claudeError(
        _ result: ShellService.ShellResult
    ) -> AIError {
        if result.exitCode == 15 {
            return .providerError(
                "Request timed out. Try selecting fewer commits."
            )
        }
        let stderr = result.stderr.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return .providerError(
            stderr.isEmpty
                ? "Claude Code exited with code \(result.exitCode)"
                : stderr
        )
    }

    private func parseClaudeOutput(
        _ stdout: String
    ) throws -> String {
        let trimmed = stdout.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else {
            throw AIError.invalidResponse(
                "Empty output from Claude Code"
            )
        }
        let envelope = try JSONDecoder().decode(
            ClaudeCodeResponse.self, from: data
        )
        guard !envelope.isError else {
            throw AIError.providerError(envelope.result)
        }
        return envelope.result
    }
}
