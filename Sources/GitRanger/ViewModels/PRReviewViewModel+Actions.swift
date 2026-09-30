import Foundation

@MainActor
extension PRReviewViewModel {
    func approvePR(repo: Repo, comment: String = "") async {
        guard let pr = selectedPR else { return }
        isSubmittingAction = true
        actionError = nil
        actionSuccess = nil

        do {
            if gitlabService.isGitLabRepo(url: repo.url) {
                try await gitlabService.approveMR(
                    repoUrl: repo.url, mrNumber: pr.number, host: repo.glHost
                )
                if !comment.isEmpty {
                    try await gitlabService.commentOnMR(
                        repoUrl: repo.url, mrNumber: pr.number,
                        message: comment, host: repo.glHost
                    )
                }
            } else if comment.isEmpty {
                try await githubService.approvePR(
                    repoUrl: repo.url, prNumber: pr.number, account: repo.ghAccount
                )
            } else {
                // gh cannot approve with a body, so submit the comment separately.
                try await githubService.approvePR(
                    repoUrl: repo.url, prNumber: pr.number, account: repo.ghAccount
                )
                try await githubService.commentOnPR(
                    repoUrl: repo.url, prNumber: pr.number,
                    message: comment, account: repo.ghAccount
                )
            }
            actionSuccess = "Approved #\(pr.number)"
        } catch {
            actionError = error.localizedDescription
        }

        isSubmittingAction = false
    }

    func commentOnPR(repo: Repo, message: String) async {
        guard let pr = selectedPR else { return }
        isSubmittingAction = true
        actionError = nil
        actionSuccess = nil

        do {
            if gitlabService.isGitLabRepo(url: repo.url) {
                try await gitlabService.commentOnMR(
                    repoUrl: repo.url, mrNumber: pr.number,
                    message: message, host: repo.glHost
                )
            } else {
                try await githubService.commentOnPR(
                    repoUrl: repo.url, prNumber: pr.number,
                    message: message, account: repo.ghAccount
                )
            }
            actionSuccess = "Comment added to #\(pr.number)"
        } catch {
            actionError = error.localizedDescription
        }

        isSubmittingAction = false
    }

    /// Build a formatted summary from all completed agent reviews.
    func buildReviewSummary() -> String {
        var parts = ["## AI Code Review Summary", ""]

        for agent in ReviewAgent.allCases {
            guard let text = agentReviews[agent] else { continue }
            let verdict = agentVerdicts[agent]
            let icon = verdict == true ? "✅" : (verdict == false ? "⚠️" : "📝")
            parts.append("### \(icon) \(agent.displayName)")
            parts.append(Self.stripVerdictLine(text))
            parts.append("")

            if let deepText = agentDeepReviews[agent] {
                let deepIcon = agentDeepVerdicts[agent] == true ? "✅" : "⚠️"
                parts.append("#### \(deepIcon) Verification")
                parts.append(Self.stripVerdictLine(deepText))
                parts.append("")
            }
        }

        for agent in customAgentReviews {
            let verdict = customAgentVerdicts[agent.key]
            let icon = verdict == true ? "✅" : (verdict == false ? "⚠️" : "📝")
            parts.append("### \(icon) \(agent.key)")
            parts.append(Self.stripVerdictLine(agent.value))
            parts.append("")
        }

        return parts.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func postReviewAsComment(repo: Repo) async {
        await commentOnPR(repo: repo, message: buildReviewSummary())
    }
}
