import XCTest
@testable import GitRanger

// MARK: - GitService Tests

final class GitServiceTests: XCTestCase {

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
        XCTAssertFalse(service.requiresAPIKey)
    }

    func testCreateAnthropic() {
        var settings = AISettings()
        settings.anthropicAPIKey = "test-key"
        let service = AIServiceFactory.create(provider: .anthropicAPI, settings: settings)
        XCTAssertEqual(service.displayName, "Anthropic API")
        XCTAssertTrue(service.requiresAPIKey)
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
    }

    func testCreateOllama() {
        let settings = AISettings()
        let service = AIServiceFactory.create(provider: .ollama, settings: settings)
        XCTAssertEqual(service.displayName, "Ollama (Local)")
        XCTAssertFalse(service.requiresAPIKey)
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
