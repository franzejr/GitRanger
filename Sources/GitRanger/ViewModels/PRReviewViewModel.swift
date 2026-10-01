import Foundation
import SwiftData

@MainActor
@Observable
final class PRReviewViewModel {
    // Legacy single review
    var review: String?
    var secondReview: String?
    var isLoading = false
    var isLoadingSecondReview = false
    var error: String?
    var diff: String?
    var prDetail: PRDetail?
    var selectedPR: PullRequest?
    var isCached = false

    // Sub-agent reviews (built-in)
    var agentReviews: [ReviewAgent: String] = [:]
    var agentErrors: [ReviewAgent: String] = [:]
    var agentLoading: Set<ReviewAgent> = []
    var agentQueued: Set<ReviewAgent> = []
    var agentCached: Set<ReviewAgent> = []
    var agentVerdicts: [ReviewAgent: Bool] = [:]

    // Custom agent reviews (keyed by custom agent ID)
    var customAgentReviews: [String: String] = [:]
    var customAgentErrors: [String: String] = [:]
    var customAgentLoading: Set<String> = []
    var customAgentQueued: Set<String> = []
    var customAgentCached: Set<String> = []
    var customAgentVerdicts: [String: Bool] = [:]

    // Deep verify (second pass per agent)
    var agentDeepReviews: [ReviewAgent: String] = [:]
    var agentDeepErrors: [ReviewAgent: String] = [:]
    var agentDeepLoading: Set<ReviewAgent> = []
    var agentDeepVerdicts: [ReviewAgent: Bool] = [:]

    var launchedAgentCount: Int = 0

    var isAnyAgentLoading: Bool {
        !agentLoading.isEmpty || !agentQueued.isEmpty
            || !customAgentLoading.isEmpty || !customAgentQueued.isEmpty
    }

    var activity: PRReviewActivity? {
        if isAnyAgentLoading || isLoadingSecondReview
            || !agentDeepLoading.isEmpty {
            return .reviewing
        }
        if isLoading {
            return diff == nil ? .loading : .reviewing
        }
        return nil
    }
    var completedAgentCount: Int {
        agentReviews.count + customAgentReviews.count
    }
    var totalAgentCount: Int {
        launchedAgentCount > 0
            ? launchedAgentCount : ReviewAgent.allCases.count
    }
    var hasSubAgentResults: Bool {
        !agentReviews.isEmpty || isAnyAgentLoading
            || !customAgentReviews.isEmpty
    }

    // PR actions (approve/comment)
    var isSubmittingAction = false
    var actionError: String?
    var actionSuccess: String?

    let githubService = GitHubService.shared
    let gitlabService = GitLabService.shared
    var modelContext: ModelContext?

    enum AgentTaskResult: Sendable {
        case builtIn(ReviewAgent, Result<String, Error>)
        case custom(String, Result<String, Error>)
    }

    enum ReviewJob: Sendable {
        case builtIn(ReviewAgent)
        case custom(CustomReviewAgent)
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func prepareToLoad(_ pr: PullRequest) {
        selectedPR = pr
        isLoading = true
        error = nil
        review = nil
        secondReview = nil
        diff = nil
        prDetail = nil
        isCached = false
        agentReviews = [:]
        agentErrors = [:]
        agentLoading = []
        agentQueued = []
        agentCached = []
    }

    func loadPR(_ pr: PullRequest, repo: Repo) async {
        if selectedPR?.number == pr.number
            && selectedPR?.headRefOid == pr.headRefOid {
            isLoading = true
            error = nil
        } else {
            prepareToLoad(pr)
        }

        do {
            if let cached = findCachedReview(
                repoUrl: repo.url,
                prNumber: pr.number,
                headSha: pr.headRefOid
            ) {
                review = cached.reviewText
                secondReview = cached.secondReviewText
                isCached = true
            }

            loadCachedSubAgentReviews(
                repoUrl: repo.url,
                prNumber: pr.number,
                headSha: pr.headRefOid
            )

            try await loadRemoteContent(for: pr, repo: repo)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func loadRemoteContent(
        for pr: PullRequest, repo: Repo
    ) async throws {
        if gitlabService.isGitLabRepo(url: repo.url) {
            async let loadedDiff = gitlabService.getMRDiff(
                repoUrl: repo.url,
                mrNumber: pr.number,
                host: repo.glHost
            )
            async let loadedDetail = gitlabService.getMRDetail(
                repoUrl: repo.url,
                mrNumber: pr.number,
                host: repo.glHost
            )
            diff = try await loadedDiff
            prDetail = try await loadedDetail
        } else {
            async let loadedDiff = githubService.getPRDiff(
                repoUrl: repo.url,
                prNumber: pr.number,
                account: repo.ghAccount
            )
            async let loadedDetail = githubService.getPRDetail(
                repoUrl: repo.url,
                prNumber: pr.number,
                account: repo.ghAccount
            )
            diff = try await loadedDiff
            prDetail = try await loadedDetail
        }
    }

    // MARK: - Legacy Single Review

    func generateReview(repo: Repo) async {
        guard let pr = selectedPR, let diff else { return }
        isLoading = true
        error = nil
        review = nil
        secondReview = nil
        isCached = false

        do {
            let input = try await buildPRInput(
                pr: pr, repo: repo, diff: diff
            )
            let customPrompt = repo.reviewPrompt
                ?? UserDefaults.standard.string(forKey: "prReviewPrompt")

            let prompt = PromptBuilder.buildPRReviewPrompt(.init(
                prTitle: input.prTitle,
                prBody: input.prBody,
                prAuthor: input.prAuthor,
                baseBranch: input.baseBranch,
                headBranch: input.headBranch,
                diff: diff,
                customPrompt: customPrompt
            ))

            let provider = AIServiceFactory.activeProvider()
            let result = try await provider.generate(
                prompt: prompt,
                repoPath: URL(fileURLWithPath: repo.localPath)
            )

            review = result
            saveReview(
                repoUrl: repo.url,
                prNumber: pr.number,
                headSha: pr.headRefOid,
                reviewText: result,
                providerName: provider.displayName
            )
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func generateSecondReview(repo: Repo) async {
        guard let pr = selectedPR,
              let diff,
              let firstReview = review else { return }
        isLoadingSecondReview = true
        secondReview = nil

        do {
            let prompt = PromptBuilder.buildSecondReviewPrompt(.init(
                firstReview: firstReview,
                prTitle: pr.title,
                prAuthor: pr.authorLogin,
                baseBranch: pr.baseRefName,
                headBranch: pr.headRefName,
                diff: diff
            ))

            let provider = AIServiceFactory.activeProvider()
            let result = try await provider.generate(
                prompt: prompt,
                repoPath: URL(fileURLWithPath: repo.localPath)
            )

            secondReview = result
            updateCachedSecondReview(
                repoUrl: repo.url,
                prNumber: pr.number,
                headSha: pr.headRefOid,
                secondReviewText: result
            )
        } catch {
            self.error = error.localizedDescription
        }

        isLoadingSecondReview = false
    }

    func dismiss() {
        review = nil
        secondReview = nil
        error = nil
        isLoading = false
        isLoadingSecondReview = false
        diff = nil
        prDetail = nil
        selectedPR = nil
        isCached = false
        actionError = nil
        actionSuccess = nil
        isSubmittingAction = false
        agentReviews = [:]
        agentErrors = [:]
        agentLoading = []
        agentQueued = []
        agentCached = []
        agentVerdicts = [:]
        customAgentReviews = [:]
        customAgentErrors = [:]
        customAgentLoading = []
        customAgentQueued = []
        customAgentCached = []
        customAgentVerdicts = [:]
        agentDeepReviews = [:]
        agentDeepErrors = [:]
        agentDeepLoading = []
        agentDeepVerdicts = [:]
        launchedAgentCount = 0
    }

    // MARK: - Verdict Parsing

    nonisolated static func parseVerdict(_ text: String) -> Bool? {
        guard let firstLine = text
            .components(separatedBy: "\n")
            .first?
            .trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        let upper = firstLine.uppercased()
        if upper.hasPrefix("VERDICT: PASS") { return true }
        if upper.hasPrefix("VERDICT: FAIL") { return false }
        return nil
    }

    nonisolated static func stripVerdictLine(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines
            .first?
            .trimmingCharacters(in: .whitespaces),
              first.uppercased().hasPrefix("VERDICT:") else {
            return text
        }
        return lines.dropFirst()
            .drop(while: {
                $0.trimmingCharacters(in: .whitespaces).isEmpty
            })
            .joined(separator: "\n")
    }
}
