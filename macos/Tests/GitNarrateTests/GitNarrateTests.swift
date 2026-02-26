import Testing
import Foundation
@testable import GitNarrate

// MARK: - GitService Tests

@Suite("GitService")
struct GitServiceTests {

    @Test("extractRepoName from HTTPS URL")
    func extractRepoNameHTTPS() {
        let git = GitService.shared
        #expect(git.extractRepoName(url: "https://github.com/user/my-repo.git") == "my-repo")
    }

    @Test("extractRepoName from HTTPS URL without .git")
    func extractRepoNameHTTPSNoGit() {
        let git = GitService.shared
        #expect(git.extractRepoName(url: "https://github.com/user/my-repo") == "my-repo")
    }

    @Test("extractRepoName from SSH URL")
    func extractRepoNameSSH() {
        let git = GitService.shared
        #expect(git.extractRepoName(url: "git@github.com:user/my-repo.git") == "my-repo")
    }

    @Test("extractRepoName with trailing slash")
    func extractRepoNameTrailingSlash() {
        let git = GitService.shared
        #expect(git.extractRepoName(url: "https://github.com/user/repo/") == "repo")
    }
}

// MARK: - AI Models Tests

@Suite("AIModels")
struct AIModelsTests {

    @Test("AIProvider displayName")
    func providerDisplayNames() {
        #expect(AIProvider.claudeCode.displayName == "Claude Code (Local)")
        #expect(AIProvider.anthropicAPI.displayName == "Anthropic API")
        #expect(AIProvider.openAI.displayName == "OpenAI API")
        #expect(AIProvider.ollama.displayName == "Ollama (Local)")
    }

    @Test("AIProvider requiresAPIKey")
    func providerRequiresAPIKey() {
        #expect(AIProvider.claudeCode.requiresAPIKey == false)
        #expect(AIProvider.anthropicAPI.requiresAPIKey == true)
        #expect(AIProvider.openAI.requiresAPIKey == true)
        #expect(AIProvider.ollama.requiresAPIKey == false)
    }

    @Test("ImpactLevel has all cases")
    func impactLevelCases() {
        let cases = ImpactLevel.allCases
        #expect(cases.count == 4)
        #expect(cases.contains(.patch))
        #expect(cases.contains(.minor))
        #expect(cases.contains(.major))
        #expect(cases.contains(.breaking))
    }

    @Test("CommitSummary decodes from JSON")
    func commitSummaryDecoding() throws {
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

        #expect(summary.oneLiner == "Fix login bug")
        #expect(summary.explanation == "The login flow was broken.")
        #expect(summary.impact == "patch")
        #expect(summary.categories == ["bugfix"])
        #expect(summary.relatedFiles == ["src/auth.ts"])
        #expect(summary.riskNotes == nil)
    }

    @Test("ClaudeCodeResponse decodes envelope")
    func claudeCodeResponseDecoding() throws {
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

        #expect(response.type == "result")
        #expect(response.subtype == "success")
        #expect(response.isError == false)
        #expect(response.costUsd == 0.003)
        #expect(response.result.contains("Fix bug"))
    }
}

// MARK: - PromptBuilder Tests

@Suite("PromptBuilder")
struct PromptBuilderTests {

    @Test("buildCommitPrompt includes commit message and diff")
    func buildCommitPrompt() {
        let prompt = PromptBuilder.buildCommitPrompt(
            commitMessage: "Fix auth bug",
            diff: "+added line\n-removed line"
        )
        #expect(prompt.contains("Fix auth bug"))
        #expect(prompt.contains("+added line"))
        #expect(prompt.contains("-removed line"))
        #expect(prompt.contains("one_liner"))
    }

    @Test("buildNarrativePrompt includes all commits")
    func buildNarrativePrompt() {
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
        #expect(prompt.contains("test-repo"))
        #expect(prompt.contains("First commit"))
        #expect(prompt.contains("Second commit"))
        #expect(prompt.contains("Commit 1 of 2"))
        #expect(prompt.contains("Commit 2 of 2"))
    }

    @Test("parseCommitSummary parses valid JSON")
    func parseValidJSON() throws {
        let json = """
        {
            "one_liner": "Add feature",
            "explanation": "New capability added.",
            "impact": "minor",
            "categories": ["feature"]
        }
        """
        let summary = try PromptBuilder.parseCommitSummary(raw: json)
        #expect(summary.oneLiner == "Add feature")
        #expect(summary.impact == "minor")
    }

    @Test("parseCommitSummary strips markdown fences")
    func parseWithMarkdownFences() throws {
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
        #expect(summary.oneLiner == "Fix bug")
    }

    @Test("parseCommitSummary throws on invalid JSON")
    func parseInvalidJSON() {
        #expect(throws: (any Error).self) {
            try PromptBuilder.parseCommitSummary(raw: "not json at all")
        }
    }
}

// MARK: - AIServiceFactory Tests

@Suite("AIServiceFactory")
struct AIServiceFactoryTests {

    @Test("create returns ClaudeCodeService")
    func createClaudeCode() {
        let settings = AISettings()
        let service = AIServiceFactory.create(provider: .claudeCode, settings: settings)
        #expect(service.displayName == "Claude Code (Local)")
        #expect(service.requiresAPIKey == false)
    }

    @Test("create returns AnthropicAPIService")
    func createAnthropic() {
        var settings = AISettings()
        settings.anthropicAPIKey = "test-key"
        let service = AIServiceFactory.create(provider: .anthropicAPI, settings: settings)
        #expect(service.displayName == "Anthropic API")
        #expect(service.requiresAPIKey == true)
    }

    @Test("create returns OpenAIService")
    func createOpenAI() {
        var settings = AISettings()
        settings.openAIAPIKey = "test-key"
        let service = AIServiceFactory.create(provider: .openAI, settings: settings)
        #expect(service.displayName == "OpenAI API")
        #expect(service.requiresAPIKey == true)
    }

    @Test("create returns OllamaService")
    func createOllama() {
        let settings = AISettings()
        let service = AIServiceFactory.create(provider: .ollama, settings: settings)
        #expect(service.displayName == "Ollama (Local)")
        #expect(service.requiresAPIKey == false)
    }
}
