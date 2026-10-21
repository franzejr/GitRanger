import SwiftData
import XCTest
@testable import GitRanger

// MARK: - GitService Tests

final class GitServiceTests: XCTestCase {

    func testGitProviderDateParserAcceptsWholeSeconds() {
        let date = GitProviderDateParser.parse("2026-10-20T12:34:56Z")

        XCTAssertEqual(date?.timeIntervalSince1970, 1_792_499_696)
    }

    func testGitProviderDateParserAcceptsFractionalSeconds() {
        let date = GitProviderDateParser.parse("2026-10-20T12:34:56.789Z")

        XCTAssertEqual(
            date?.timeIntervalSince1970 ?? 0,
            1_792_499_696.789,
            accuracy: 0.001
        )
    }

    @MainActor
    func testShellStreamsLargeStdinWithoutBlockingMainActor() async throws {
        let input = String(repeating: "GitRanger background review\n", count: 20_000)
        let result = try await ShellService.shared.run(
            "/bin/cat",
            stdinData: Data(input.utf8),
            timeout: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, input)
        XCTAssertTrue(result.stderr.isEmpty)
    }

    func testCancellingShellTaskTerminatesChildProcess() async throws {
        let startedAt = Date()
        let task = Task {
            try await ShellService.shared.runDirect(
                "/bin/sleep",
                arguments: ["5"],
                timeout: 10
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled shell task must throw CancellationError")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
        }
    }

    func testCloneUsesSmallBloblessHistory() {
        let destination = URL(fileURLWithPath: "/tmp/git-ranger-test")
        let arguments = GitService.cloneArguments(
            url: "https://example.com/repo.git",
            destination: destination
        )

        XCTAssertEqual(arguments.first, "clone")
        XCTAssertTrue(arguments.contains("--depth"))
        XCTAssertTrue(arguments.contains("\(GitService.initialCloneDepth)"))
        XCTAssertTrue(arguments.contains("--filter=blob:none"))
        XCTAssertTrue(arguments.contains("--no-tags"))
    }

    func testDefaultBranchUsesLocalHead() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-ranger-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try await ShellService.shared.execute(
            "git", arguments: ["init", "-b", "feature", directory.path]
        )

        let branch = try await GitService.shared.getDefaultBranch(repoPath: directory)
        XCTAssertEqual(branch, "feature")
    }

    func testShallowCloneCanLoadOlderHistoryOnDemand() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-ranger-\(UUID().uuidString)")
        let source = workspace.appendingPathComponent("source")
        let origin = workspace.appendingPathComponent("origin.git")
        let clone = workspace.appendingPathComponent("clone")
        try FileManager.default.createDirectory(
            at: workspace, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        let shell = ShellService.shared
        _ = try await shell.execute(
            "git", arguments: ["init", "-b", "main", source.path]
        )
        _ = try await shell.execute(
            "git", arguments: ["config", "user.name", "GitRanger Tests"], cwd: source
        )
        _ = try await shell.execute(
            "git", arguments: ["config", "user.email", "tests@gitranger.local"], cwd: source
        )
        _ = try await shell.execute(
            "git", arguments: ["config", "commit.gpgsign", "false"], cwd: source
        )
        _ = try await shell.execute(
            "git", arguments: ["config", "core.hooksPath", "/dev/null"], cwd: source
        )
        for index in 1...35 {
            _ = try await shell.execute(
                "git",
                arguments: ["commit", "--allow-empty", "-m", "Commit \(index)"],
                cwd: source
            )
        }
        _ = try await shell.execute(
            "git", arguments: ["clone", "--bare", source.path, origin.path]
        )
        _ = try await shell.execute(
            "git",
            arguments: GitService.cloneArguments(
                url: origin.absoluteString, destination: clone
            )
        )

        let initialCount = try await shell.execute(
            "git", arguments: ["rev-list", "--count", "HEAD"], cwd: clone
        )
        XCTAssertEqual(initialCount.trimmingCharacters(in: .whitespacesAndNewlines), "30")

        try await GitService.shared.deepenHistory(repoPath: clone, by: 10)
        let deepenedCount = try await shell.execute(
            "git", arguments: ["rev-list", "--count", "HEAD"], cwd: clone
        )
        XCTAssertEqual(deepenedCount.trimmingCharacters(in: .whitespacesAndNewlines), "35")
    }

    func testExtractRepoNameHTTPS() {
        let git = GitService.shared
        XCTAssertEqual(git.extractRepoName(url: "https://github.com/user/my-repo.git"), "my-repo")
    }

    func testExtractRepoNameHTTPSNoGit() {
        let git = GitService.shared
        XCTAssertEqual(git.extractRepoName(url: "https://github.com/user/my-repo"), "my-repo")
    }

    func testExtractRepoNameSSH() {
        let git = GitService.shared
        XCTAssertEqual(git.extractRepoName(url: "git@github.com:user/my-repo.git"), "my-repo")
    }

    func testExtractRepoNameTrailingSlash() {
        let git = GitService.shared
        XCTAssertEqual(git.extractRepoName(url: "https://github.com/user/repo/"), "repo")
    }
}

// MARK: - Commit List Tests

final class CommitListViewModelTests: XCTestCase {

    func testInitialBranchSelectionDoesNotReloadHistory() {
        XCTAssertFalse(
            CommitListViewModel.shouldSwitchBranch(from: "", to: "main")
        )
    }

    func testUserBranchSelectionReloadsHistory() {
        XCTAssertTrue(
            CommitListViewModel.shouldSwitchBranch(from: "main", to: "feature")
        )
    }
}

// MARK: - AI Models Tests

final class AIModelsTests: XCTestCase {

    func testClaudeAvailabilityExplainsInvalidConfiguredExecutable() async {
        let defaults = UserDefaults.standard
        let previousPath = defaults.string(forKey: "claudePath")
        let missingPath = "/tmp/gitranger-missing-\(UUID().uuidString)/claude"
        defaults.set(missingPath, forKey: "claudePath")
        defer {
            if let previousPath {
                defaults.set(previousPath, forKey: "claudePath")
            } else {
                defaults.removeObject(forKey: "claudePath")
            }
        }

        let status = await ClaudeCodeService().availabilityStatus()

        XCTAssertFalse(status.isAvailable)
        XCTAssertTrue(status.detail.contains("missing or not executable"))
        XCTAssertTrue(status.detail.contains(missingPath))
    }

    func testClaudeAuthenticationErrorExplainsHowToLogin() {
        let result = ShellService.ShellResult(
            stdout: """
            {"type":"result","subtype":"error","is_error":true,"result":"Failed to authenticate: OAuth session expired and could not be refreshed"}
            """,
            stderr: "",
            exitCode: 1
        )

        let message = ClaudeCodeService.errorMessage(from: result)
        XCTAssertTrue(message.contains("not authenticated"))
        XCTAssertTrue(message.contains("claude login"))
    }

    func testClaudeStructuredErrorIsPreserved() {
        let result = ShellService.ShellResult(
            stdout: """
            {"type":"result","subtype":"error","is_error":true,"result":"Provider overloaded"}
            """,
            stderr: "",
            exitCode: 1
        )

        XCTAssertEqual(
            ClaudeCodeService.errorMessage(from: result),
            "Provider overloaded"
        )
    }

    func testClaudeCandidatePathsCoverStandardInstalls() {
        XCTAssertEqual(
            CLIExecutableLocator.claude.candidatePaths(homeDirectory: "/Users/example"),
            [
                "/Users/example/.local/bin/claude",
                "/Users/example/.claude/local/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude"
            ]
        )
    }

    func testClaudeAutoDetectPrefersNativeInstallOverHomebrew() {
        let home = "/Users/example"
        let native = "\(home)/.local/bin/claude"
        let homebrew = "/opt/homebrew/bin/claude"
        let lookup = CLIExecutableLocator.claude.resolve(
            configuredPath: "",
            homeDirectory: home,
            isExecutable: { $0 == native || $0 == homebrew }
        )
        XCTAssertEqual(lookup, .found(native))
    }

    func testClaudeAutoDetectUsesHomebrewWhenNativeInstallIsMissing() {
        let homebrew = "/opt/homebrew/bin/claude"
        let lookup = CLIExecutableLocator.claude.resolve(
            configuredPath: "   ",
            homeDirectory: "/Users/example",
            isExecutable: { $0 == homebrew }
        )
        XCTAssertEqual(lookup, .found(homebrew))
    }

    func testClaudeConfiguredPathIsNotReplacedByAutoDetect() {
        let configured = "/custom/claude"
        let lookup = CLIExecutableLocator.claude.resolve(
            configuredPath: configured,
            homeDirectory: "/Users/example",
            isExecutable: { $0 == configured || $0.hasSuffix("/.local/bin/claude") }
        )
        XCTAssertEqual(lookup, .found(configured))
    }

    func testClaudeConfiguredMissingPathDoesNotFallBack() {
        let configured = "/missing/claude"
        let lookup = CLIExecutableLocator.claude.resolve(
            configuredPath: configured,
            homeDirectory: "/Users/example",
            isExecutable: { $0.hasSuffix("/.local/bin/claude") }
        )
        XCTAssertEqual(lookup, .configuredMissing(configured))
    }

    func testClaudeAutoDetectUsesShellPathWhenInstallLocationsMiss() {
        let shellPath = "/Users/example/.nvm/versions/node/v20.19.6/bin/claude"
        let lookup = CLIExecutableLocator.claude.resolve(
            configuredPath: "",
            homeDirectory: "/Users/example",
            isExecutable: { $0 == shellPath },
            fallbackPath: shellPath
        )
        XCTAssertEqual(lookup, .found(shellPath))
    }

    func testClaudeAutoDetectReportsNotFoundWithoutAFallback() {
        let lookup = CLIExecutableLocator.claude.resolve(
            configuredPath: "",
            homeDirectory: "/Users/example",
            isExecutable: { _ in false },
            fallbackPath: "claude"
        )
        XCTAssertEqual(lookup, .notFound)
    }

    func testClaudeLoginShellOutputIgnoresStartupNoise() {
        let output = """
        oh-my-zsh loaded /Users/example/.oh-my-zsh
        /Users/example/.local/bin/claude
        """
        XCTAssertEqual(
            CLIExecutableLocator.claude.executablePath(fromLoginShellOutput: output),
            "/Users/example/.local/bin/claude"
        )
    }

    func testClaudeLoginShellOutputRejectsNonClaudePaths() {
        XCTAssertNil(
            CLIExecutableLocator.claude.executablePath(
                fromLoginShellOutput: "/Users/example/.oh-my-zsh/tools/check"
            )
        )
    }

    func testClaudeAugmentedPathAddsInstallLocations() {
        let path = CLIExecutableLocator.augmentedPath(
            "/usr/bin:/bin",
            homeDirectory: "/Users/example"
        )
        XCTAssertEqual(
            path,
            "/Users/example/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        )
    }

    func testClaudeAugmentedPathDoesNotDuplicateEntries() {
        let path = CLIExecutableLocator.augmentedPath(
            "/opt/homebrew/bin:/usr/bin",
            homeDirectory: "/Users/example"
        )
        let homebrewEntries = path.split(separator: ":").filter { $0 == "/opt/homebrew/bin" }
        XCTAssertEqual(homebrewEntries.count, 1)
        XCTAssertTrue(path.contains("/Users/example/.local/bin"))
    }

    func testClaudeAutoDetectFindsInstalledBinaryWhenPresent() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lookup = CLIExecutableLocator.claude.resolve(
            configuredPath: "",
            homeDirectory: home,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        )
        let installed = CLIExecutableLocator.claude.candidatePaths(homeDirectory: home)
            .filter { FileManager.default.isExecutableFile(atPath: $0) }
        if let expected = installed.first {
            XCTAssertEqual(lookup, .found(expected))
        } else {
            XCTAssertEqual(lookup, .notFound)
        }
    }

    func testCodexCandidatePathsCoverStandardInstalls() {
        XCTAssertEqual(
            CLIExecutableLocator.codex.candidatePaths(homeDirectory: "/Users/example"),
            [
                "/Users/example/.local/bin/codex",
                "/Users/example/.codex/packages/standalone/current/bin/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex"
            ]
        )
    }

    func testCodexAutoDetectPrefersLocalBinOverStandalonePackage() {
        let home = "/Users/example"
        let localBin = "\(home)/.local/bin/codex"
        let standalone = "\(home)/.codex/packages/standalone/current/bin/codex"
        let lookup = CLIExecutableLocator.codex.resolve(
            configuredPath: "",
            homeDirectory: home,
            isExecutable: { $0 == localBin || $0 == standalone }
        )
        XCTAssertEqual(lookup, .found(localBin))
    }

    func testCodexAutoDetectUsesShellPathWhenInstallLocationsMiss() {
        let shellPath = "/Users/example/.local/share/mise/shims/codex"
        let lookup = CLIExecutableLocator.codex.resolve(
            configuredPath: "",
            homeDirectory: "/Users/example",
            isExecutable: { $0 == shellPath },
            fallbackPath: shellPath
        )
        XCTAssertEqual(lookup, .found(shellPath))
    }

    func testCodexLoginShellOutputIgnoresClaudePath() {
        let output = """
        /Users/example/.local/bin/claude
        /Users/example/.local/bin/codex
        """
        XCTAssertEqual(
            CLIExecutableLocator.codex.executablePath(fromLoginShellOutput: output),
            "/Users/example/.local/bin/codex"
        )
        XCTAssertNil(
            CLIExecutableLocator.codex.executablePath(
                fromLoginShellOutput: "/Users/example/.local/bin/claude"
            )
        )
    }

    func testCodexConfiguredMissingPathDoesNotFallBack() {
        let configured = "/missing/codex"
        let lookup = CLIExecutableLocator.codex.resolve(
            configuredPath: configured,
            homeDirectory: "/Users/example",
            isExecutable: { $0.hasSuffix("/.local/bin/codex") }
        )
        XCTAssertEqual(lookup, .configuredMissing(configured))
    }

    func testCodexAutoDetectFindsInstalledBinaryWhenPresent() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lookup = CLIExecutableLocator.codex.resolve(
            configuredPath: "",
            homeDirectory: home,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        )
        let installed = CLIExecutableLocator.codex.candidatePaths(homeDirectory: home)
            .filter { FileManager.default.isExecutableFile(atPath: $0) }
        if let expected = installed.first {
            XCTAssertEqual(lookup, .found(expected))
        } else {
            XCTAssertEqual(lookup, .notFound)
        }
    }

    func testClaudeCustomModelIsUsedWhenSelected() {
        XCTAssertEqual(
            ClaudeCodeService.resolvedModel(
                selected: "custom",
                custom: "claude-special-model"
            ),
            "claude-special-model"
        )
        XCTAssertEqual(
            ClaudeCodeService.resolvedModel(selected: "sonnet", custom: "ignored"),
            "sonnet"
        )
    }

    func testCodexAuthenticationErrorExplainsHowToLogin() {
        let result = ShellService.ShellResult(
            stdout: "",
            stderr: "Not logged in. Please run codex login.",
            exitCode: 1
        )

        let message = CodexCLIService.errorMessage(from: result)
        XCTAssertTrue(message.contains("not authenticated"))
        XCTAssertTrue(message.contains("codex login"))
    }

    func testCodexErrorIsPreserved() {
        let result = ShellService.ShellResult(
            stdout: "",
            stderr: "Model is not available",
            exitCode: 1
        )

        XCTAssertEqual(
            CodexCLIService.errorMessage(from: result),
            "Model is not available"
        )
    }

    func testProviderDisplayNames() {
        XCTAssertEqual(AIProvider.claudeCode.displayName, "Claude Code (Local)")
        XCTAssertEqual(AIProvider.codexCLI.displayName, "Codex CLI (Local)")
        XCTAssertEqual(AIProvider.anthropicAPI.displayName, "Anthropic API")
        XCTAssertEqual(AIProvider.openAI.displayName, "OpenAI API")
        XCTAssertEqual(AIProvider.ollama.displayName, "Ollama (Local)")
    }

    func testProviderRequiresAPIKey() {
        XCTAssertFalse(AIProvider.claudeCode.requiresAPIKey)
        XCTAssertFalse(AIProvider.codexCLI.requiresAPIKey)
        XCTAssertTrue(AIProvider.anthropicAPI.requiresAPIKey)
        XCTAssertTrue(AIProvider.openAI.requiresAPIKey)
        XCTAssertFalse(AIProvider.ollama.requiresAPIKey)
    }

    func testImpactLevelCases() {
        let cases = ImpactLevel.allCases
        XCTAssertEqual(cases.count, 4)
        XCTAssertTrue(cases.contains(.patch))
        XCTAssertTrue(cases.contains(.minor))
        XCTAssertTrue(cases.contains(.major))
        XCTAssertTrue(cases.contains(.breaking))
    }

    func testCommitSummaryDecoding() throws {
        let json = """
        {
            "one_liner": "Fix login bug",
            "explanation": "The login flow was broken.",
            "impact": "patch",
            "categories": ["bugfix"],
            "related_files": ["src/auth.ts"],
            "risk_notes": null
        }
        """
        let data = json.data(using: .utf8)!
        let summary = try JSONDecoder().decode(CommitSummary.self, from: data)

        XCTAssertEqual(summary.oneLiner, "Fix login bug")
        XCTAssertEqual(summary.explanation, "The login flow was broken.")
        XCTAssertEqual(summary.impact, "patch")
        XCTAssertEqual(summary.categories, ["bugfix"])
        XCTAssertEqual(summary.relatedFiles, ["src/auth.ts"])
        XCTAssertNil(summary.riskNotes)
    }

    func testClaudeCodeResponseDecoding() throws {
        let json = """
        {
            "type": "result",
            "subtype": "success",
            "cost_usd": 0.003,
            "is_error": false,
            "duration_ms": 2340,
            "num_turns": 1,
            "result": "{\\"one_liner\\": \\"Fix bug\\"}",
            "session_id": "abc-123"
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaudeCodeResponse.self, from: data)

        XCTAssertEqual(response.type, "result")
        XCTAssertEqual(response.subtype, "success")
        XCTAssertFalse(response.isError)
        XCTAssertEqual(response.costUsd, 0.003)
        XCTAssertTrue(response.result.contains("Fix bug"))
    }
}

// MARK: - PromptBuilder Tests

final class PromptBuilderTests: XCTestCase {
    func testSubAgentPromptIncludesReviewTimeBudget() {
        let prompt = PromptBuilder.buildSubAgentPrompt(
            agent: .security,
            input: PromptBuilder.PRReviewInput(
                prTitle: "Harden sessions",
                prBody: "Validate session ownership",
                prAuthor: "author",
                baseBranch: "main",
                headBranch: "secure-sessions",
                diff: "+guard session.userID == currentUser.id"
            )
        )

        XCTAssertTrue(prompt.contains("Complete this review within 3 minutes"))
        XCTAssertTrue(prompt.contains("Do not scan the full repository"))
    }

    func testBuildCommitPrompt() {
        let prompt = PromptBuilder.buildCommitPrompt(
            commitMessage: "Fix auth bug",
            diff: "+added line\n-removed line"
        )
        XCTAssertTrue(prompt.contains("Fix auth bug"))
        XCTAssertTrue(prompt.contains("+added line"))
        XCTAssertTrue(prompt.contains("-removed line"))
        XCTAssertTrue(prompt.contains("one_liner"))
    }

    func testBuildNarrativePrompt() {
        let commits = [
            NarrativeCommit(
                sha: "abc1234", message: "First commit",
                authorName: "Alice", committedAt: "2024-01-01",
                diff: "+new file", filesChanged: 1, insertions: 10, deletions: 0
            ),
            NarrativeCommit(
                sha: "def5678", message: "Second commit",
                authorName: "Bob", committedAt: "2024-01-02",
                diff: "+another change", filesChanged: 2, insertions: 5, deletions: 3
            )
        ]
        let prompt = PromptBuilder.buildNarrativePrompt(
            repoName: "test-repo",
            commits: commits
        )
        XCTAssertTrue(prompt.contains("test-repo"))
        XCTAssertTrue(prompt.contains("First commit"))
        XCTAssertTrue(prompt.contains("Second commit"))
        XCTAssertTrue(prompt.contains("Commit 1"))
        XCTAssertTrue(prompt.contains("Commit 2"))
    }

    func testParseValidJSON() throws {
        let json = """
        {
            "one_liner": "Add feature",
            "explanation": "New capability added.",
            "impact": "minor",
            "categories": ["feature"]
        }
        """
        let summary = try PromptBuilder.parseCommitSummary(raw: json)
        XCTAssertEqual(summary.oneLiner, "Add feature")
        XCTAssertEqual(summary.impact, "minor")
    }

    func testParseWithMarkdownFences() throws {
        let json = """
        ```json
        {
            "one_liner": "Fix bug",
            "explanation": "Bug was fixed.",
            "impact": "patch",
            "categories": ["bugfix"]
        }
        ```
        """
        let summary = try PromptBuilder.parseCommitSummary(raw: json)
        XCTAssertEqual(summary.oneLiner, "Fix bug")
    }

    func testParseInvalidJSON() {
        XCTAssertThrowsError(try PromptBuilder.parseCommitSummary(raw: "not json at all"))
    }
}

// MARK: - AIServiceFactory Tests

final class AIServiceFactoryTests: XCTestCase {

    func testCreateClaudeCode() {
        let settings = AISettings()
        let service = AIServiceFactory.create(provider: .claudeCode, settings: settings)
        XCTAssertEqual(service.displayName, "Claude Code (Local)")
        XCTAssertFalse(service.modelName.isEmpty)
        XCTAssertFalse(service.requiresAPIKey)
    }

    func testCreateAnthropic() {
        var settings = AISettings()
        settings.anthropicAPIKey = "test-key"
        let service = AIServiceFactory.create(provider: .anthropicAPI, settings: settings)
        XCTAssertEqual(service.displayName, "Anthropic API")
        XCTAssertTrue(service.requiresAPIKey)
        XCTAssertEqual(service.modelName, settings.anthropicModel)
    }

    func testCreateCodexCLI() {
        let settings = AISettings()
        let service = AIServiceFactory.create(provider: .codexCLI, settings: settings)
        XCTAssertEqual(service.displayName, "Codex CLI (Local)")
        XCTAssertFalse(service.requiresAPIKey)
    }

    func testCreateOpenAI() {
        var settings = AISettings()
        settings.openAIAPIKey = "test-key"
        let service = AIServiceFactory.create(provider: .openAI, settings: settings)
        XCTAssertEqual(service.displayName, "OpenAI API")
        XCTAssertTrue(service.requiresAPIKey)
        XCTAssertEqual(service.modelName, settings.openAIModel)
    }

    func testCreateOllama() {
        let settings = AISettings()
        let service = AIServiceFactory.create(provider: .ollama, settings: settings)
        XCTAssertEqual(service.displayName, "Ollama (Local)")
        XCTAssertFalse(service.requiresAPIKey)
        XCTAssertEqual(service.modelName, settings.ollamaModel)
    }

    func testModelCatalogOffersCurrentAndCustomizableChoices() {
        let anthropic = AIModelCatalog.builtInOptions(for: .anthropicAPI)
        let openAI = AIModelCatalog.builtInOptions(for: .openAI)

        XCTAssertTrue(anthropic.contains { $0.id == "claude-sonnet-4-6" })
        XCTAssertTrue(openAI.contains { $0.id == "gpt-4.1" })
        XCTAssertEqual(Set(openAI.map(\.id)).count, openAI.count)
    }

    func testCodexCatalogUsesVisibleModelsInPriorityOrder() throws {
        let data = Data("""
        {
          "models": [
            {"slug":"hidden","display_name":"Hidden","visibility":"hide","priority":0},
            {"slug":"gpt-fast","display_name":"GPT Fast","visibility":"list","priority":2},
            {"slug":"gpt-best","display_name":"GPT Best","visibility":"list","priority":1}
          ]
        }
        """.utf8)

        let models = try LocalAIModelCatalog.decodeCodexOptions(from: data)

        XCTAssertEqual(models.map(\.id), ["gpt-best", "gpt-fast"])
        XCTAssertEqual(models.map(\.name), ["GPT Best", "GPT Fast"])
    }

    func testClaudeCatalogUsesExactModelIdentifiers() throws {
        let data = Data("""
        {
          "catalog": {
            "config": {
              "models": [
                {"id":"claude-opus-current","name":"Opus Current"},
                {"id":"claude-sonnet-current","name":"Sonnet Current"}
              ]
            }
          }
        }
        """.utf8)

        let models = try LocalAIModelCatalog.decodeClaudeOptions(from: data)

        XCTAssertEqual(
            models.map(\.id),
            ["claude-opus-current", "claude-sonnet-current"]
        )
    }

    func testCodexConfiguredModelParserIgnoresReasoningSetting() {
        let config = """
        model = "gpt-current"
        model_reasoning_effort = "high"
        """

        XCTAssertEqual(
            LocalAIModelCatalog.codexConfiguredModel(from: config),
            "gpt-current"
        )
    }
}

// MARK: - Pull Request Content Cache Tests

final class PRContentLoaderTests: XCTestCase {
    func testContentPersistsByHeadSHA() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitranger-pr-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let request = PRContentRequest(
            repoURL: "https://example.com/team/repo",
            prNumber: 42,
            headSHA: "abc123",
            githubAccount: nil,
            gitlabHost: nil
        )
        let content = PRContent(
            diff: "+cached line",
            detail: PRDetail(title: "Cached PR", body: "Cached body"),
            fetchedAt: Date()
        )
        let writer = PRContentLoader(cacheDirectory: directory)
        await writer.store(content, for: request)

        let reader = PRContentLoader(cacheDirectory: directory)
        let cached = await reader.cachedContent(for: request)
        let changedHead = PRContentRequest(
            repoURL: request.repoURL,
            prNumber: request.prNumber,
            headSHA: "new-head",
            githubAccount: nil,
            gitlabHost: nil
        )

        XCTAssertEqual(cached?.diff, content.diff)
        XCTAssertEqual(cached?.detail.title, content.detail.title)
        XCTAssertEqual(cached?.detail.body, content.detail.body)
        let staleContent = await reader.cachedContent(for: changedHead)
        XCTAssertNil(staleContent)
    }
}

// MARK: - AI Work Coordinator Tests

final class AIWorkCoordinatorTests: XCTestCase {
    private actor ConcurrencyProbe {
        private var active = 0
        private(set) var peak = 0

        func enter() {
            active += 1
            peak = max(peak, active)
        }

        func leave() {
            active -= 1
        }
    }

    func testCoordinatorCapsConcurrentAIWork() async {
        let coordinator = AIWorkCoordinator(maxConcurrentJobs: 2)
        let probe = ConcurrencyProbe()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try? await coordinator.acquire()
                    await probe.enter()
                    try? await Task.sleep(for: .milliseconds(20))
                    await probe.leave()
                    await coordinator.release()
                }
            }
        }

        let peak = await probe.peak
        XCTAssertEqual(peak, 2)
    }

    func testCancelledAIWaiterNeverStartsLater() async throws {
        let coordinator = AIWorkCoordinator(maxConcurrentJobs: 1)
        try await coordinator.acquire()

        let waiting = Task {
            try await coordinator.acquire()
        }
        try await Task.sleep(for: .milliseconds(20))
        waiting.cancel()
        await coordinator.release()

        do {
            try await waiting.value
            await coordinator.release()
            XCTFail("A cancelled waiter must not acquire a later slot")
        } catch is CancellationError {
            // Expected.
        }

        try await coordinator.acquire()
        await coordinator.release()
    }

    func testRoutineCoordinatorCapsConcurrentPullRequests() async {
        let coordinator = RoutineExecutionCoordinator(maxConcurrentRuns: 2)
        let probe = ConcurrencyProbe()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    await coordinator.acquire()
                    await probe.enter()
                    try? await Task.sleep(for: .milliseconds(20))
                    await probe.leave()
                    await coordinator.release()
                }
            }
        }

        let peak = await probe.peak
        XCTAssertEqual(peak, 2)
    }
}

// MARK: - PR Review Session Tests

@MainActor
final class PRReviewSessionStoreTests: XCTestCase {
    func testSwitchingPRKeepsFirstReviewRunning() {
        let store = PRReviewSessionStore()
        let firstPR = makePullRequest(number: 10, sha: "first")
        let secondPR = makePullRequest(number: 11, sha: "second")

        XCTAssertTrue(store.select(firstPR, repoURL: "https://example.com/repo"))
        let firstViewModel = store.selectedViewModel
        firstViewModel?.isLoading = false
        firstViewModel?.diff = "diff"
        firstViewModel?.agentLoading.insert(.performance)

        XCTAssertTrue(store.select(secondPR, repoURL: "https://example.com/repo"))

        XCTAssertEqual(store.selectedViewModel?.selectedPR?.number, 11)
        XCTAssertEqual(
            store.activity(
                for: firstPR,
                repoURL: "https://example.com/repo"
            ),
            .reviewing
        )

        XCTAssertFalse(store.select(firstPR, repoURL: "https://example.com/repo"))
        XCTAssertTrue(store.selectedViewModel === firstViewModel)
    }

    func testNewHeadSHAStartsANewReviewSession() {
        let store = PRReviewSessionStore()
        let oldHead = makePullRequest(number: 10, sha: "old")
        let newHead = makePullRequest(number: 10, sha: "new")

        XCTAssertTrue(store.select(oldHead, repoURL: "https://example.com/repo"))
        let oldViewModel = store.selectedViewModel

        XCTAssertTrue(store.select(newHead, repoURL: "https://example.com/repo"))
        XCTAssertFalse(store.selectedViewModel === oldViewModel)
        XCTAssertEqual(store.sessions.count, 2)
    }

    func testCompletedSessionsAreEvictedWithoutStoppingActiveReviews() {
        let store = PRReviewSessionStore(maxRetainedSessions: 2)
        let activePR = makePullRequest(number: 10, sha: "active")
        let completedPR = makePullRequest(number: 11, sha: "completed")
        let newestPR = makePullRequest(number: 12, sha: "newest")

        store.select(activePR, repoURL: "https://example.com/repo")
        let activeViewModel = store.selectedViewModel
        activeViewModel?.diff = "diff"
        activeViewModel?.agentLoading.insert(.security)

        store.select(completedPR, repoURL: "https://example.com/repo")
        store.selectedViewModel?.isLoading = false
        store.select(newestPR, repoURL: "https://example.com/repo")

        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertTrue(store.sessions.values.contains { $0 === activeViewModel })
        XCTAssertFalse(store.sessions.keys.contains(PRReviewSessionKey(
            repoURL: "https://example.com/repo",
            pullRequest: completedPR
        )))
        XCTAssertEqual(
            store.activity(for: activePR, repoURL: "https://example.com/repo"),
            .reviewing
        )
    }

    private func makePullRequest(number: Int, sha: String) -> PullRequest {
        PullRequest(
            number: number,
            title: "PR \(number)",
            authorLogin: "reviewer",
            state: "OPEN",
            headRefName: "feature-\(number)",
            headRefOid: sha,
            baseRefName: "main",
            createdAt: Date(),
            updatedAt: Date(),
            additions: 1,
            deletions: 0,
            changedFiles: 1,
            url: "https://example.com/repo/pull/\(number)",
            isDraft: false,
            reviewDecision: "",
            reviewRequests: [],
            latestReviews: []
        )
    }
}

// MARK: - Review Routine Tests

final class ReviewRoutineTests: XCTestCase {
    func testBatchResponseIsSplitIntoAgentResults() {
        let response = """
        <<<GITRANGER_AGENT:summary>>>
        VERDICT: PASS
        Clear summary.
        <<<GITRANGER_END_AGENT>>>
        <<<GITRANGER_AGENT:security>>>
        VERDICT: FAIL
        Missing authorization check.
        <<<GITRANGER_END_AGENT>>>
        """

        let sections = RoutineReviewPipeline.parseBatchSections(
            response,
            agentIDs: ["summary", "security", "performance"]
        )

        XCTAssertEqual(
            sections["summary"],
            "VERDICT: PASS\nClear summary."
        )
        XCTAssertEqual(
            sections["security"],
            "VERDICT: FAIL\nMissing authorization check."
        )
        XCTAssertNil(sections["performance"])
    }

    func testQuickReviewCommentReportsReasoningEffort() {
        let request = RoutinePipelineRequest(
            routineID: UUID(),
            repository: RoutineRepositoryContext(
                id: UUID(),
                name: "Example",
                url: "https://github.com/example/repo",
                localPath: "/tmp/example",
                githubAccount: nil,
                gitlabHost: nil,
                agentPrompts: [:],
                customAgents: []
            ),
            pullRequest: makePullRequest(sha: "abc123"),
            agentIDs: [ReviewAgent.summary.rawValue],
            provider: .codexCLI,
            modelName: "test-model"
        )
        let agent = RoutineAgentSnapshot(
            id: ReviewAgent.summary.rawValue,
            name: ReviewAgent.summary.displayName,
            status: .completed,
            phase: "Review complete",
            providerName: "Codex CLI (Local)",
            modelName: "test-model",
            reasoningEffort: "low",
            reviewText: "VERDICT: PASS\nLooks good."
        )

        let comment = RoutineReviewPipeline.buildComment(
            request: request,
            agents: [agent]
        )

        XCTAssertTrue(comment.contains("AI Code Review Summary"))
        XCTAssertTrue(comment.contains("**Mode:** Quick review"))
        XCTAssertTrue(comment.contains("test-model · effort: low"))
    }

    func testScheduleAdvancesFromRunDate() {
        let routine = ReviewRoutine(
            name: "Review open PRs",
            repoIDs: [UUID()],
            intervalMinutes: 15
        )
        let runDate = Date(timeIntervalSince1970: 1_000)

        routine.markScheduled(from: runDate)

        XCTAssertEqual(routine.lastRunAt, runDate)
        XCTAssertEqual(
            routine.nextRunAt,
            runDate.addingTimeInterval(15 * 60)
        )
    }

    @MainActor
    func testEditingRoutineUpdatesExistingRecord() throws {
        let schema = Schema([ReviewRoutine.self, RoutineRun.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let routine = ReviewRoutine(
            name: "Original",
            repoIDs: [UUID()],
            intervalMinutes: 15
        )
        container.mainContext.insert(routine)
        try container.mainContext.save()

        let engine = RoutineEngine()
        engine.modelContext = container.mainContext
        engine.loadPersistedState()
        engine.save(RoutineDraft(
            id: routine.id,
            name: "Updated",
            repoIDs: routine.repoIDs,
            intervalMinutes: 5,
            maxPullRequestsPerRun: 2,
            scope: .open,
            skipDrafts: true,
            agentIDs: [ReviewAgent.summary.rawValue],
            provider: .codexCLI,
            modelName: "test-model",
            publishingMode: .automaticComment,
            isEnabled: true
        ))

        XCTAssertEqual(engine.routines.count, 1)
        XCTAssertEqual(engine.routines.first?.id, routine.id)
        XCTAssertEqual(engine.routines.first?.name, "Updated")
        XCTAssertEqual(engine.routines.first?.intervalMinutes, 5)
        XCTAssertEqual(engine.routines.first?.maxPullRequestsPerRun, 2)
    }

    func testPublicationMarkerIsStablePerRoutineAndHead() {
        let routineID = UUID()
        let first = RoutinePublicationMarker.value(
            routineID: routineID,
            headSHA: "abc123"
        )
        let repeated = RoutinePublicationMarker.value(
            routineID: routineID,
            headSHA: "abc123"
        )
        let changedHead = RoutinePublicationMarker.value(
            routineID: routineID,
            headSHA: "def456"
        )

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, changedHead)
        XCTAssertTrue(first.hasPrefix("<!-- gitranger:routine="))
    }

    func testCompletedHeadIsDeduplicatedAndFailedHeadCanRetry() {
        let routine = makeRoutine()
        let repo = makeRepo()
        let pullRequest = makePullRequest(sha: "head-one")
        let run = RoutineRun(
            routine: routine,
            repo: repo,
            pullRequest: pullRequest,
            trigger: .schedule
        )
        run.status = .completed

        XCTAssertFalse(RoutineRunPolicy.shouldEnqueue(
            run.identity,
            existingRuns: [run]
        ))

        run.status = .failed
        XCTAssertTrue(RoutineRunPolicy.shouldEnqueue(
            run.identity,
            existingRuns: [run]
        ))

        let changedIdentity = RoutineRunIdentity(
            routineID: routine.id,
            repoURL: repo.url,
            prNumber: pullRequest.number,
            headSHA: "head-two"
        )
        run.status = .posted
        XCTAssertTrue(RoutineRunPolicy.shouldEnqueue(
            changedIdentity,
            existingRuns: [run]
        ))
    }

    func testRunPersistsAgentActivitySnapshots() {
        let pullRequest = makePullRequest(sha: "abc")
        let run = RoutineRun(
            routine: makeRoutine(),
            repo: makeRepo(),
            pullRequest: pullRequest,
            trigger: .manual
        )
        let snapshot = RoutineAgentSnapshot(
            id: ReviewAgent.security.rawValue,
            name: ReviewAgent.security.displayName,
            status: .reviewing,
            phase: "Reviewing pull request",
            providerName: "Test provider",
            modelName: "test-model",
            startedAt: Date()
        )

        run.agentSnapshots = [snapshot]

        XCTAssertEqual(run.agentSnapshots, [snapshot])
        XCTAssertEqual(run.prAuthorLogin, "author")
        XCTAssertEqual(run.prCreatedAt, pullRequest.createdAt)
    }

    func testProviderModelOverridesAreReported() {
        XCTAssertEqual(
            ClaudeCodeService(modelOverride: "opus").modelName,
            "opus"
        )
        XCTAssertEqual(
            CodexCLIService(modelOverride: "gpt-test").modelName,
            "gpt-test"
        )
    }

    func testRoutineFailureSummarySurfacesProviderError() {
        let failed = RoutineAgentSnapshot(
            id: ReviewAgent.summary.rawValue,
            name: ReviewAgent.summary.displayName,
            status: .failed,
            phase: "Review failed",
            providerName: "Local provider",
            modelName: "test-model",
            error: "Authentication is required."
        )
        let output = RoutinePipelineOutput(agents: [failed], comment: "")

        XCTAssertEqual(
            output.failureSummary,
            "1 review agent(s) failed: Authentication is required."
        )
    }

    func testCancellingRunClearsActiveAgentStates() {
        let completed = RoutineAgentSnapshot(
            id: "completed",
            name: "Completed",
            status: .completed,
            phase: "Review complete"
        )
        let reviewing = RoutineAgentSnapshot(
            id: "reviewing",
            name: "Reviewing",
            status: .reviewing,
            phase: "Reviewing pull request"
        )
        let queued = RoutineAgentSnapshot(
            id: "queued",
            name: "Queued",
            status: .queued,
            phase: "Waiting"
        )

        let result = [completed, reviewing, queued].cancellingActiveAgents()

        XCTAssertEqual(result[0].status, .completed)
        XCTAssertEqual(result[1].status, .cancelled)
        XCTAssertEqual(result[2].status, .cancelled)
        XCTAssertNotNil(result[1].completedAt)
        XCTAssertNotNil(result[2].completedAt)
    }

    func testIncompleteAgentPreventsPublication() {
        let queued = RoutineAgentSnapshot(
            id: "queued",
            name: "Queued",
            status: .queued,
            phase: "Waiting"
        )
        let output = RoutinePipelineOutput(agents: [queued], comment: "")

        XCTAssertTrue(output.hasFailures)
        XCTAssertEqual(
            output.failureSummary,
            "1 review agent(s) did not complete. Nothing was posted."
        )
    }

    private func makeRoutine() -> ReviewRoutine {
        ReviewRoutine(name: "Routine", repoIDs: [UUID()])
    }

    private func makeRepo() -> Repo {
        Repo(
            name: "Example",
            url: "https://github.com/example/repo",
            localPath: "/tmp/example"
        )
    }

    private func makePullRequest(sha: String) -> PullRequest {
        PullRequest(
            number: 42,
            title: "Improve review automation",
            authorLogin: "author",
            state: "OPEN",
            headRefName: "feature",
            headRefOid: sha,
            baseRefName: "main",
            createdAt: Date(),
            updatedAt: Date(),
            additions: 10,
            deletions: 2,
            changedFiles: 2,
            url: "https://github.com/example/repo/pull/42",
            isDraft: false,
            reviewDecision: "",
            reviewRequests: [],
            latestReviews: []
        )
    }
}
