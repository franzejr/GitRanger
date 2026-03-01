import Foundation

// MARK: - AI Provider

enum AIProvider: String, CaseIterable, Codable {
    case claudeCode = "claude_code"
    case anthropicAPI = "anthropic_api"
    case openAI = "openai"
    case ollama = "ollama"

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code (Local)"
        case .anthropicAPI: "Anthropic API"
        case .openAI: "OpenAI API"
        case .ollama: "Ollama (Local)"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .claudeCode, .ollama: false
        case .anthropicAPI, .openAI: true
        }
    }

    var description: String {
        switch self {
        case .claudeCode:
            "Uses your local Claude Code installation. No API key needed — uses your existing Claude subscription."
        case .anthropicAPI:
            "Direct API calls to Anthropic's Claude. Requires an API key from console.anthropic.com."
        case .openAI:
            "Uses OpenAI's GPT models. Requires an API key from platform.openai.com."
        case .ollama:
            "Fully local AI via Ollama. No internet needed, but requires Ollama installed with a model."
        }
    }
}

// MARK: - Impact Level

enum ImpactLevel: String, Codable, CaseIterable {
    case patch
    case minor
    case major
    case breaking
}

// MARK: - Commit Summary

struct CommitSummary: Codable {
    let oneLiner: String
    let explanation: String
    let impact: String
    let categories: [String]
    let relatedFiles: [String]?
    let riskNotes: String?

    enum CodingKeys: String, CodingKey {
        case oneLiner = "one_liner"
        case explanation
        case impact
        case categories
        case relatedFiles = "related_files"
        case riskNotes = "risk_notes"
    }
}

// MARK: - Claude Code Response Envelope

struct ClaudeCodeResponse: Codable {
    let type: String
    let subtype: String
    let costUsd: Double?
    let isError: Bool
    let durationMs: Int?
    let numTurns: Int?
    let result: String
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case type, subtype, result
        case costUsd = "cost_usd"
        case isError = "is_error"
        case durationMs = "duration_ms"
        case numTurns = "num_turns"
        case sessionId = "session_id"
    }
}

// MARK: - Anthropic API Response

struct AnthropicResponse: Codable {
    let content: [AnthropicContent]

    struct AnthropicContent: Codable {
        let type: String
        let text: String?
    }
}

// MARK: - OpenAI Response

struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]

    struct OpenAIChoice: Codable {
        let message: OpenAIMessage
    }

    struct OpenAIMessage: Codable {
        let content: String?
    }
}

// MARK: - Ollama Response

struct OllamaResponse: Codable {
    let response: String
}

// MARK: - AI Errors

enum AIError: LocalizedError {
    case invalidResponse(String)
    case providerError(String)
    case providerUnavailable(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let detail): "Invalid AI response: \(detail)"
        case .providerError(let detail): "AI provider error: \(detail)"
        case .providerUnavailable(let name): "\(name) is not available"
        case .timeout: "AI request timed out"
        }
    }
}

// MARK: - AI Settings

struct AISettings {
    var aiProvider: AIProvider = .claudeCode
    var anthropicAPIKey: String = ""
    var anthropicModel: String = "claude-sonnet-4-5-20250514"
    var openAIAPIKey: String = ""
    var openAIModel: String = "gpt-4o"
    var ollamaModel: String = "llama3.2"
    var ollamaURL: String = "http://localhost:11434"
}

// MARK: - Git Supporting Types

struct CommitInfo {
    let sha: String
    let message: String
    let authorName: String
    let authorEmail: String
    let date: Date
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
}

struct CommitDiff {
    let sha: String
    let stat: String
    let patch: String
}

// MARK: - Pull Request Types

struct PRReviewStatus {
    let login: String
    let state: String // APPROVED, CHANGES_REQUESTED, COMMENTED, PENDING
}

struct PullRequest: Identifiable {
    let number: Int
    let title: String
    let authorLogin: String
    let state: String
    let headRefName: String
    let headRefOid: String
    let baseRefName: String
    let createdAt: Date
    let updatedAt: Date
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    let url: String
    let isDraft: Bool
    var reviewDecision: String
    var reviewRequests: [String]
    var latestReviews: [PRReviewStatus]

    var id: Int { number }

    var isApproved: Bool { reviewDecision == "APPROVED" }
    var hasChangesRequested: Bool { reviewDecision == "CHANGES_REQUESTED" }

    func isAwaitingReview(by login: String) -> Bool {
        reviewRequests.contains(login)
    }

    func wasReviewedBy(_ login: String) -> PRReviewStatus? {
        latestReviews.first { $0.login == login }
    }
}

struct PRDetail {
    let title: String
    let body: String
}
