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

    static func buildNarrativePrompt(repoName: String, commits: [NarrativeCommit]) -> String {
        let perCommitBudget = 30000 / max(commits.count, 1)

        let commitSections = commits.enumerated().map { index, commit in
            let truncatedDiff = String(commit.diff.prefix(perCommitBudget))
            return """
            --- Commit \(index + 1) of \(commits.count) ---
            SHA: \(String(commit.sha.prefix(7)))
            Author: \(commit.authorName)
            Date: \(commit.committedAt)
            Message: \(commit.message)
            Stats: \(commit.filesChanged) files changed, +\(commit.insertions) -\(commit.deletions)

            Diff (truncated):
            \(truncatedDiff)
            """
        }.joined(separator: "\n\n")

        return """
        You are a technical storyteller. Below are \(commits.count) git commits \
        from the "\(repoName)" repository, listed in chronological order (oldest first).

        Write a narrative that tells the story of these changes as a cohesive account. Your narrative should:

        1. Be written in clear, engaging prose (not bullet points or JSON)
        2. Follow chronological order, showing how the codebase evolved
        3. Explain the "why" behind changes, not just the "what"
        4. Connect related changes across commits
        5. Highlight the overall arc — what was the developer trying to accomplish?
        6. Be 2-5 paragraphs long, depending on the number and complexity of commits

        Do NOT output JSON. Write plain prose. Do NOT use markdown headers. Use paragraph breaks only.

        \(commitSections)
        """
    }

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
