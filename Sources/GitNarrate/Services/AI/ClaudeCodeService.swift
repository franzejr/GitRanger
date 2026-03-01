import Foundation

final class ClaudeCodeService: AIServiceProtocol {
    let displayName = "Claude Code (Local)"
    let requiresAPIKey = false

    private let shell = ShellService.shared

    func isAvailable() async -> Bool {
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
        var arguments = [
            "-p", "-",
            "--output-format", "json",
            "--model", "haiku",
            "--no-session-persistence"
        ]

        if useTools {
            arguments += ["--allowedTools", "Read,Grep,Glob"]
        }

        if let repoPath {
            arguments += ["--add-dir", repoPath.path]
        }

        // Strip CLAUDECODE env var to avoid recursion if run from within Claude Code
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")

        guard let stdinData = prompt.data(using: .utf8) else {
            throw AIError.invalidResponse("Could not encode prompt")
        }

        let result = try await shell.run(
            "claude",
            arguments: arguments,
            environment: env,
            stdinData: stdinData,
            timeout: timeout
        )

        guard result.exitCode == 0 else {
            if result.exitCode == 15 {
                throw AIError.providerError(
                    "Request timed out. Try selecting fewer commits."
                )
            }
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AIError.providerError(
                stderr.isEmpty
                    ? "Claude Code exited with code \(result.exitCode)"
                    : stderr
            )
        }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !stdout.isEmpty, let data = stdout.data(using: .utf8) else {
            throw AIError.invalidResponse("Empty output from Claude Code")
        }

        let envelope = try JSONDecoder().decode(ClaudeCodeResponse.self, from: data)

        guard !envelope.isError else {
            throw AIError.providerError(envelope.result)
        }

        return envelope.result
    }
}
