import Foundation

final class CodexCLIService: AIServiceProtocol {
    let displayName = "Codex CLI (Local)"
    let requiresAPIKey = false

    private let shell = ShellService.shared

    private var codexBinary: String {
        let custom = UserDefaults.standard.string(forKey: "codexPath") ?? ""
        if !custom.isEmpty { return custom }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? "codex"
    }

    func isAvailable() async -> Bool {
        await availabilityStatus().isAvailable
    }

    func availabilityStatus() async -> AIAvailabilityStatus {
        let binary = codexBinary
        var resolvedBinary = binary

        if binary.contains("/") {
            guard FileManager.default.isExecutableFile(atPath: binary) else {
                return AIAvailabilityStatus(
                    isAvailable: false,
                    detail: "The configured Codex executable is missing or not executable: \(binary)"
                )
            }
        } else {
            do {
                resolvedBinary = try await shell.execute(
                    "which", arguments: [binary], timeout: 5
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !resolvedBinary.isEmpty else {
                    return unavailableExecutableStatus()
                }
            } catch {
                return unavailableExecutableStatus()
            }
        }

        do {
            let result = try await executeCodex(
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
                detail: "Authenticated with Codex CLI at \(resolvedBinary)."
            )
        } catch {
            return AIAvailabilityStatus(
                isAvailable: false,
                detail: "Could not run Codex CLI at \(resolvedBinary): \(error.localizedDescription)"
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
            prompt: prompt,
            repoPath: configuredRepoPath(repoPath),
            timeout: 120
        )
        return try PromptBuilder.parseCommitSummary(raw: output)
    }

    func generate(prompt: String, repoPath: URL?) async throws -> String {
        try await runCodex(
            prompt: prompt,
            repoPath: configuredRepoPath(repoPath),
            timeout: 300
        )
    }

    // MARK: - Private

    private func runCodex(
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
            arguments: arguments(outputURL: outputURL, repoPath: repoPath),
            stdinData: stdinData,
            cwd: repoPath ?? FileManager.default.temporaryDirectory,
            timeout: timeout
        )

        guard result.exitCode == 0 else {
            if result.exitCode == 15 {
                throw AIError.providerError(
                    "Request timed out. Try selecting fewer commits."
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

        let model = UserDefaults.standard.string(forKey: "codexModel") ?? ""
        if !model.isEmpty {
            result += ["--model", model]
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

    private func unavailableExecutableStatus() -> AIAvailabilityStatus {
        AIAvailabilityStatus(
            isAvailable: false,
            detail: "Codex CLI was not found in the app PATH. "
                + "Set its full executable path in Settings → Accounts → Codex CLI."
        )
    }

    private func executeCodex(
        arguments: [String],
        stdinData: Data?,
        cwd: URL?,
        timeout: TimeInterval
    ) async throws -> ShellService.ShellResult {
        if codexBinary.contains("/") {
            return try await shell.runDirect(
                codexBinary,
                arguments: arguments,
                cwd: cwd,
                environment: ProcessInfo.processInfo.environment,
                stdinData: stdinData,
                timeout: timeout
            )
        }
        return try await shell.run(
            codexBinary,
            arguments: arguments,
            cwd: cwd,
            environment: ProcessInfo.processInfo.environment,
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
