import Foundation
import SwiftData

@Observable
final class PRReviewViewModel {
    var review: String?
    var isLoading = false
    var error: String?
    var diff: String?
    var selectedPR: PullRequest?
    var isCached = false

    private let githubService = GitHubService.shared
    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func loadPR(_ pr: PullRequest, repo: Repo) async {
        selectedPR = pr
        isLoading = true
        error = nil
        review = nil
        diff = nil
        isCached = false

        do {
            // Check for cached review
            if let cached = findCachedReview(
                repoUrl: repo.url,
                prNumber: pr.number,
                headSha: pr.headRefOid
            ) {
                review = cached.reviewText
                isCached = true
            }

            diff = try await githubService.getPRDiff(
                repoUrl: repo.url,
                prNumber: pr.number,
                account: repo.ghAccount
            )
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func generateReview(repo: Repo) async {
        guard let pr = selectedPR, let diff else { return }
        isLoading = true
        error = nil
        review = nil
        isCached = false

        do {
            let prDetail = try await githubService.getPRDetail(
                repoUrl: repo.url,
                prNumber: pr.number,
                account: repo.ghAccount
            )

            // Priority: per-repo prompt > global Settings prompt > default
            let customPrompt = repo.reviewPrompt
                ?? UserDefaults.standard.string(forKey: "prReviewPrompt")

            let prompt = PromptBuilder.buildPRReviewPrompt(.init(
                prTitle: pr.title,
                prBody: prDetail.body,
                prAuthor: pr.authorLogin,
                baseBranch: pr.baseRefName,
                headBranch: pr.headRefName,
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

    func dismiss() {
        review = nil
        error = nil
        isLoading = false
        diff = nil
        selectedPR = nil
        isCached = false
    }

    // MARK: - Private

    private func findCachedReview(repoUrl: String, prNumber: Int, headSha: String) -> PRReview? {
        guard let modelContext else { return nil }
        do {
            let allReviews = try modelContext.fetch(FetchDescriptor<PRReview>())
            return allReviews.first {
                $0.repoUrl == repoUrl &&
                $0.prNumber == prNumber &&
                $0.headSha == headSha
            }
        } catch {
            return nil
        }
    }

    private func saveReview(
        repoUrl: String,
        prNumber: Int,
        headSha: String,
        reviewText: String,
        providerName: String
    ) {
        guard let modelContext else { return }
        let review = PRReview(
            repoUrl: repoUrl,
            prNumber: prNumber,
            headSha: headSha,
            reviewText: reviewText,
            providerName: providerName
        )
        modelContext.insert(review)
        try? modelContext.save()
    }
}
