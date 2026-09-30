import XCTest
@testable import GitRanger

// MARK: - GitService Tests

final class GitServiceTests: XCTestCase {

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

// MARK: - AI Models Tests

final class AIModelsTests: XCTestCase {

    func testProviderDisplayNames() {
        XCTAssertEqual(AIProvider.claudeCode.displayName, "Claude Code (Local)")
        XCTAssertEqual(AIProvider.anthropicAPI.displayName, "Anthropic API")
        XCTAssertEqual(AIProvider.openAI.displayName, "OpenAI API")
        XCTAssertEqual(AIProvider.ollama.displayName, "Ollama (Local)")
    }

    func testProviderRequiresAPIKey() {
        XCTAssertFalse(AIProvider.claudeCode.requiresAPIKey)
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
