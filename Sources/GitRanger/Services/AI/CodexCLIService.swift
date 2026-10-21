import Foundation

final class CodexCLIService: AIServiceProtocol {
    let displayName = "Codex CLI (Local)"
    let requiresAPIKey = false
    var modelName: String {
        if let modelOverride, !modelOverride.isEmpty { return modelOverride }
        let selected = UserDefaults.standard.string(forKey: "codexModel") ?? ""
        guard selected.isEmpty else { return selected }
        return LocalAIModelCatalog.configuredModel(for: .codexCLI)
            ?? "CLI default"
    }
    var reasoningEffort: String {
        reasoningEffortOverride
            ?? LocalAIModelCatalog.configuredReasoningEffort()
            ?? "provider default"
    }

    private let shell = ShellService.shared
    private let modelOverride: String?
    private let reasoningEffortOverride: String?

    init(
        modelOverride: String? = nil,
        reasoningEffortOverride: String? = nil
    ) {
        self.modelOverride = modelOverride
        self.reasoningEffortOverride = reasoningEffortOverride
    }

    private enum ExecutableResolution {
        case available(String)
        case unavailable(AIAvailabilityStatus)
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
        switch await CLIExecutableResolver.codex.resolve(using: shell) {
        case .found(let path):
            return .available(path)
        case .configuredMissing(let path):
            return .unavailable(missingConfiguredExecutableStatus(path))
        case .notFound:
            return .unavailable(unavailableExecutableStatus())
        }
    }

    private func executablePath() async throws -> String {
        switch await resolveExecutable() {
        case .available(let binary):
            return binary
        case .unavailable(let status):
            throw AIError.providerError(status.detail)
        }
    }

    private func authenticationStatus(
        binary: String
    ) async -> AIAvailabilityStatus {
        do {
            let result = try await executeCodex(
                binary,
                arguments: ["login", "status"],
                stdinData: nil,
                cwd: nil,
                timeout: 10
            )
            guard result.exitCode == 0 else {
                return AIAvailabilityStatus(
                    isAvailable: false,
                    detail: Self.errorMessage(from: result)
                )
            }
            return AIAvailabilityStatus(
                isAvailable: true,
                detail: "Authenticated with Codex CLI at \(binary)."
            )
        } catch {
            return AIAvailabilityStatus(
                isAvailable: false,
                detail: "Could not run Codex CLI at \(binary): \(error.localizedDescription)"
            )
        }
    }

    func summarize(
        commitMessage: String,
        diff: String,
        repoPath: URL?
    ) async throws -> CommitSummary {
        let prompt = PromptBuilder.buildCommitPrompt(
            commitMessage: commitMessage,
            diff: String(diff.prefix(12_000))
        )
        let output = try await runCodex(
            binary: try await executablePath(),
            prompt: prompt,
            repoPath: configuredRepoPath(repoPath),
            timeout: 120
        )
        return try PromptBuilder.parseCommitSummary(raw: output)
    }

    func generate(prompt: String, repoPath: URL?) async throws -> String {
        try await generate(prompt: prompt, repoPath: repoPath, timeout: 300)
    }

    func generate(
        prompt: String,
        repoPath: URL?,
        timeout: TimeInterval
    ) async throws -> String {
        try await runCodex(
            binary: try await executablePath(),
            prompt: prompt,
            repoPath: configuredRepoPath(repoPath),
            timeout: timeout
        )
    }

    // MARK: - Private

    private func missingConfiguredExecutableStatus(
        _ path: String
    ) -> AIAvailabilityStatus {
        AIAvailabilityStatus(
            isAvailable: false,
            detail: "The configured Codex executable is missing or not executable: \(path)"
        )
    }

    private func unavailableExecutableStatus() -> AIAvailabilityStatus {
        AIAvailabilityStatus(
            isAvailable: false,
            detail: "Codex CLI was not found in ~/.local/bin, Homebrew, "
                + "/usr/local/bin, or your shell PATH. Install it, or set the "
                + "executable path in Settings → Accounts → Codex CLI."
        )
    }

    private func runCodex(
        binary: String,
        prompt: String,
        repoPath: URL?,
        timeout: TimeInterval
    ) async throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitranger-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        guard let stdinData = prompt.data(using: .utf8) else {
            throw AIError.invalidResponse("Could not encode prompt")
        }

        let result = try await executeCodex(
            binary,
            arguments: arguments(outputURL: outputURL, repoPath: repoPath),
            stdinData: stdinData,
            cwd: repoPath ?? FileManager.default.temporaryDirectory,
            timeout: timeout
        )

        guard result.exitCode == 0 else {
            if result.exitCode == 15 {
                throw AIError.providerError(
                    "Codex CLI exceeded the \(Int(timeout / 60))-minute "
                        + "timeout. Retry this agent or reduce the PR scope."
                )
            }
            throw AIError.providerError(Self.errorMessage(from: result))
        }

        let output = (try? String(contentsOf: outputURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty else {
            throw AIError.invalidResponse("Empty output from Codex CLI")
        }
        return output
    }

    private func arguments(outputURL: URL, repoPath: URL?) -> [String] {
        var result = [
            "exec",
            "--ephemeral",
            "--color", "never",
            "--sandbox", "read-only",
            "--output-last-message", outputURL.path
        ]

        let model = modelOverride
            ?? UserDefaults.standard.string(forKey: "codexModel")
            ?? ""
        if !model.isEmpty {
            result += ["--model", model]
        }
        if let reasoningEffortOverride {
            result += [
                "--config",
                "model_reasoning_effort=\"\(reasoningEffortOverride)\""
            ]
        }

        if let repoPath {
            result += ["--cd", repoPath.path]
        } else {
            result.append("--skip-git-repo-check")
        }
        result.append("-")
        return result
    }

    private func configuredRepoPath(_ repoPath: URL?) -> URL? {
        let useRepoContext = UserDefaults.standard.object(
            forKey: "codexRepoContext"
        ) as? Bool ?? true
        return useRepoContext ? repoPath : nil
    }

    private func executeCodex(
        _ binary: String,
        arguments: [String],
        stdinData: Data?,
        cwd: URL?,
        timeout: TimeInterval
    ) async throws -> ShellService.ShellResult {
        let environment = CLIExecutableResolver.environment(
            ProcessInfo.processInfo.environment
        )
        if binary.contains("/") {
            return try await shell.runDirect(
                binary,
                arguments: arguments,
                cwd: cwd,
                environment: environment,
                stdinData: stdinData,
                timeout: timeout
            )
        }
        return try await shell.run(
            binary,
            arguments: arguments,
            cwd: cwd,
            environment: environment,
            stdinData: stdinData,
            timeout: timeout
        )
    }

    static func errorMessage(from result: ShellService.ShellResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = stderr.isEmpty ? stdout : stderr
        let lowered = detail.lowercased()

        if lowered.contains("not logged in")
            || lowered.contains("authentication required")
            || lowered.contains("unauthorized")
            || lowered.contains("login required") {
            return "Codex CLI is not authenticated. Open Terminal, run `codex login`, then retry."
        }

        return detail.isEmpty
            ? "Codex CLI exited with code \(result.exitCode)"
            : detail
    }
}
