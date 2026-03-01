import Foundation

enum PromptBuilder {

    static func buildCommitPrompt(commitMessage: String, diff: String) -> String {
        """
        Analyze this git commit diff. Respond ONLY with valid JSON matching this schema:
        {
          "one_liner": "one sentence summary of what changed",
          "explanation": "2-3 sentences explaining context and impact",
          "impact": "patch|minor|major|breaking",
          "categories": ["bugfix", "feature", "refactor", "docs", "test", "chore"],
          "related_files": ["optionally affected files"],
          "risk_notes": "potential risks or null"
        }

        Commit message: \(commitMessage)

        Diff:
        \(diff)
        """
    }

    static func buildCommitMessagePrompt(diff: String) -> String {
        let truncatedDiff = String(diff.prefix(30000))
        return """
        You are writing a git commit message for the following staged changes. \
        Respond ONLY with valid JSON matching this schema:
        {
          "summary": "short imperative summary, max 50 chars (e.g. 'Add user authentication')",
          "description": "1-3 sentences explaining what changed and why. Be concise."
        }

        Do NOT include markdown fences. Respond with raw JSON only.

        --- Staged Diff ---
        \(truncatedDiff)
        """
    }

    struct CommitMessage: Codable {
        let summary: String
        let description: String
    }

    static func parseCommitMessage(raw: String) throws -> CommitMessage {
        let clean = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = clean.data(using: .utf8) else {
            throw AIError.invalidResponse("Could not parse commit message")
        }
        return try JSONDecoder().decode(CommitMessage.self, from: data)
    }

    static func buildNarrativePrompt(
        repoName: String, commits: [NarrativeCommit], includeDiagram: Bool = false
    ) -> String {
        let perCommitBudget = 10000 / max(commits.count, 1)

        let commitSections = commits.enumerated().map { index, commit in
            let truncatedDiff = String(commit.diff.prefix(perCommitBudget))
            return """
            --- Commit \(index + 1) ---
            \(String(commit.sha.prefix(7))) | \(commit.authorName) | \(commit.committedAt)
            \(commit.message)
            \(commit.filesChanged) files, +\(commit.insertions) -\(commit.deletions)
            \(truncatedDiff)
            """
        }.joined(separator: "\n")

        return """
        Summarize these \(commits.count) commits from "\(repoName)". Write:

        1. A short overview paragraph (2-3 sentences max)
        2. A bullet-point list of the key changes (one bullet per logical change, not per commit)

        Keep it concise. No JSON, no markdown headers. Plain text only.
        \(includeDiagram ? mermaidInstructions : "")
        \(commitSections)
        """
    }

    private static let mermaidInstructions = """

    After the prose narrative, include a Mermaid flowchart diagram that visualizes \
    the flow of changes across these commits. Wrap the diagram in delimiters exactly like this:

    ---MERMAID_START---
    graph TD
        A[Step one] --> B[Step two]
    ---MERMAID_END---

    The flowchart should show the progression of changes, with nodes for key actions \
    and edges showing the flow. Keep it readable (max ~15 nodes). Use short labels.
    """

    // MARK: - PR Review

    static var defaultPRReviewPrompt: String {
        """
        You are an expert code reviewer. Review this pull request and provide:

        1. **Summary**: What does this PR do? (2-3 sentences)
        2. **Key Changes**: What are the most important code changes?
        3. **Potential Issues**: Any bugs, edge cases, or concerns?
        4. **Suggestions**: Concrete improvements the author could make.
        5. **Overall Assessment**: Is this PR ready to merge? (Ready / Needs Work / Needs Discussion)

        Be specific and reference actual code from the diff. Be constructive.
        """
    }

    struct PRReviewInput {
        let prTitle: String
        let prBody: String
        let prAuthor: String
        let baseBranch: String
        let headBranch: String
        let diff: String
        var customPrompt: String?
    }

    static func buildPRReviewPrompt(_ input: PRReviewInput) -> String {
        let instructions = (input.customPrompt?.isEmpty ?? true)
            ? defaultPRReviewPrompt
            : input.customPrompt!

        let truncatedDiff = String(input.diff.prefix(30000))

        return """
        \(instructions)

        --- Pull Request ---
        Title: \(input.prTitle)
        Author: \(input.prAuthor)
        Branch: \(input.headBranch) -> \(input.baseBranch)

        Description:
        \(input.prBody.isEmpty ? "(no description)" : input.prBody)

        --- Diff ---
        \(truncatedDiff)
        """
    }

    // MARK: - Sub-Agent Review

    static func buildSubAgentPrompt(
        agent: ReviewAgent,
        input: PRReviewInput,
        customInstructions: String? = nil
    ) -> String {
        let baseInstructions = if let custom = customInstructions, !custom.isEmpty {
            custom
        } else {
            agentPrompt(for: agent)
        }
        let truncatedDiff = String(input.diff.prefix(30000))

        return """
        \(baseInstructions)

        IMPORTANT: Begin your response with exactly "VERDICT: PASS" if you find no significant \
        issues, or "VERDICT: FAIL" if you find issues that should be addressed. \
        Put this on the very first line, then continue with your review below.

        --- Pull Request ---
        Title: \(input.prTitle)
        Author: \(input.prAuthor)
        Branch: \(input.headBranch) -> \(input.baseBranch)

        Description:
        \(input.prBody.isEmpty ? "(no description)" : input.prBody)

        --- Diff ---
        \(truncatedDiff)
        """
    }

    static func buildCustomAgentPrompt(
        customAgent: CustomReviewAgent,
        input: PRReviewInput
    ) -> String {
        let truncatedDiff = String(input.diff.prefix(30000))

        return """
        \(customAgent.prompt)

        IMPORTANT: Begin your response with exactly "VERDICT: PASS" if you find no significant \
        issues, or "VERDICT: FAIL" if you find issues that should be addressed. \
        Put this on the very first line, then continue with your review below.

        --- Pull Request ---
        Title: \(input.prTitle)
        Author: \(input.prAuthor)
        Branch: \(input.headBranch) -> \(input.baseBranch)

        Description:
        \(input.prBody.isEmpty ? "(no description)" : input.prBody)

        --- Diff ---
        \(truncatedDiff)
        """
    }

    // MARK: - Second Review

    static var defaultSecondReviewPrompt: String {
        """
        You previously reviewed a pull request. Now review your own review. \
        Re-examine the diff carefully and validate each point you made.

        For each point in your original review:
        - Confirm if it holds up against the actual code
        - Flag any that were incorrect, overstated, or misleading
        - Note anything important you missed the first time

        Be honest and specific. Reference the diff when correcting yourself.
        """
    }

    struct SecondReviewInput {
        let firstReview: String
        let prTitle: String
        let prAuthor: String
        let baseBranch: String
        let headBranch: String
        let diff: String
    }

    static func buildSecondReviewPrompt(_ input: SecondReviewInput) -> String {
        let truncatedDiff = String(input.diff.prefix(30000))

        return """
        \(defaultSecondReviewPrompt)

        --- Pull Request ---
        Title: \(input.prTitle)
        Author: \(input.prAuthor)
        Branch: \(input.headBranch) -> \(input.baseBranch)

        --- Your Previous Review ---
        \(input.firstReview)

        --- Diff ---
        \(truncatedDiff)
        """
    }

    // MARK: - Parsing

    static func parseCommitSummary(raw: String) throws -> CommitSummary {
        let clean = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = clean.data(using: .utf8) else {
            throw AIError.invalidResponse("Could not convert response to data")
        }

        let summary = try JSONDecoder().decode(CommitSummary.self, from: data)

        guard !summary.oneLiner.isEmpty,
              !summary.explanation.isEmpty,
              !summary.impact.isEmpty,
              !summary.categories.isEmpty else {
            throw AIError.invalidResponse("AI response missing required fields")
        }

        return summary
    }
}

struct NarrativeCommit {
    let sha: String
    let message: String
    let authorName: String
    let committedAt: String
    let diff: String
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
}
