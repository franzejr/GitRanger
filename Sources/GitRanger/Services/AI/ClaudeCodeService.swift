import Foundation

final class ClaudeCodeService: AIServiceProtocol {
    let displayName = "Claude Code (Local)"
    let requiresAPIKey = false

    private let shell = ShellService.shared

    private enum ExecutableResolution {
        case available(String)
        case unavailable(AIAvailabilityStatus)
    }

    private var claudeBinary: String {
        let custom = UserDefaults.standard.string(forKey: "claudePath") ?? ""
        return custom.isEmpty ? "claude" : custom
    }

    func isAvailable() async -> Bool {
        await availabilityStatus().isAvailable
    }

    func availabilityStatus() async -> AIAvailabilityStatus {
        switch await resolveExecutable() {
        case .available(let binary):
            return await authenticationStatus(binary: binary)
        case .unavailable(let status):
            return status
        }
    }

    private func resolveExecutable() async -> ExecutableResolution {
        let binary = claudeBinary
        if binary != "claude" {
            guard FileManager.default.isExecutableFile(atPath: binary) else {
                return .unavailable(AIAvailabilityStatus(
                    isAvailable: false,
                    detail: "The configured Claude executable is missing or not executable: \(binary)"
                ))
            }
            return .available(binary)
        }

        do {
            let output = try await shell.execute(
                "which", arguments: ["claude"], timeout: 5
            )
            let resolved = output.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return resolved.isEmpty
                ? .unavailable(unavailableExecutableStatus())
                : .available(resolved)
        } catch {
            return .unavailable(unavailableExecutableStatus())
        }
    }

    private func authenticationStatus(
        binary: String
    ) async -> AIAvailabilityStatus {
        do {
            let result = try await executeClaudeBinary(
                arguments: ["auth", "status"],
                env: ProcessInfo.processInfo.environment,
                stdinData: Data(),
                timeout: 10
            )
            guard result.exitCode == 0 else {
                return AIAvailabilityStatus(
                    isAvailable: false,
                    detail: Self.errorMessage(from: result)
                )
            }
            guard let data = result.stdout.data(using: .utf8),
                  let status = try? JSONDecoder().decode(
                    ClaudeAuthStatus.self, from: data
                  ) else {
                return AIAvailabilityStatus(
                    isAvailable: false,
                    detail: "Claude Code returned an unexpected response to `claude auth status`."
                )
            }
            guard status.loggedIn else {
                return AIAvailabilityStatus(
                    isAvailable: false,
                    detail: "Claude Code is not authenticated. Open Terminal, run `claude login`, then retry."
                )
            }
            return AIAvailabilityStatus(
                isAvailable: true,
                detail: "Authenticated with Claude Code at \(binary)."
            )
        } catch {
            return AIAvailabilityStatus(
                isAvailable: false,
                detail: "Could not run Claude Code at \(binary): \(error.localizedDescription)"
            )
        }
    }

    func summarize(
        commitMessage: String,
        diff: String,
        repoPath: URL?
    ) async throws -> CommitSummary {
        let useRepoContext = UserDefaults.standard.object(
            forKey: "claudeRepoContext"
        ) as? Bool ?? true
        let truncatedDiff = String(diff.prefix(12000))
        let prompt = PromptBuilder.buildCommitPrompt(
            commitMessage: commitMessage,
            diff: truncatedDiff
        )

        let output = try await runClaude(
            prompt: prompt,
            repoPath: useRepoContext ? repoPath : nil,
            timeout: 90,
            useTools: useRepoContext
        )

        return try PromptBuilder.parseCommitSummary(raw: output)
    }

    func generate(prompt: String, repoPath: URL?) async throws -> String {
        let useRepoContext = UserDefaults.standard.object(
            forKey: "claudeRepoContext"
        ) as? Bool ?? true
        return try await runClaude(
            prompt: prompt,
            repoPath: useRepoContext ? repoPath : nil,
            timeout: 300,
            useTools: useRepoContext
        )
    }

    // MARK: - Private

    private func unavailableExecutableStatus() -> AIAvailabilityStatus {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "(not set)"
        return AIAvailabilityStatus(
            isAvailable: false,
            detail: "Claude Code was not found in the app PATH (\(path)). "
                + "Set its full executable path in Settings → Accounts → Claude Code."
        )
    }

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
        let model = Self.resolvedModel(
            selected: UserDefaults.standard.string(forKey: "claudeModel") ?? "haiku",
            custom: UserDefaults.standard.string(forKey: "claudeCustomModel") ?? ""
        )
        var args = [
            "-p", "-",
            "--output-format", "json",
            "--model", model,
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

    static func resolvedModel(selected: String, custom: String) -> String {
        selected == "custom" && !custom.isEmpty ? custom : selected
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
        return .providerError(Self.errorMessage(from: result))
    }

    /// Claude writes structured provider failures to stdout, even when the
    /// process exits with a non-zero status. Surface that detail instead of
    /// replacing it with a generic exit-code message.
    static func errorMessage(
        from result: ShellService.ShellResult
    ) -> String {
        let stdout = result.stdout.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let stderr = result.stderr.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let structuredDetail: String? = stdout.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode(ClaudeCodeResponse.self, from: $0) }
            .map(\.result)
        let detail = structuredDetail ?? (stderr.isEmpty ? stdout : stderr)
        let lowered = detail.lowercased()

        if lowered.contains("authenticate")
            || lowered.contains("oauth session expired")
            || lowered.contains("not logged in") {
            return "Claude Code is not authenticated. Open Terminal, run `claude login`, then retry."
        }

        return detail.isEmpty
            ? "Claude Code exited with code \(result.exitCode)"
            : detail
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

private struct ClaudeAuthStatus: Decodable {
    let loggedIn: Bool
}
