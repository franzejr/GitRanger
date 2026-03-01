import Foundation

enum PRFilterMode: String, CaseIterable {
    case all = "All PRs"
    case pendingMyReview = "Needs My Review"
    case merged = "Merged"
}

@Observable
final class PRListViewModel {
    var pullRequests: [PullRequest] = []
    var isLoading = false
    var isLoadingMore = false
    var error: String?
    var ghAvailable: Bool?
    var isGitHubRepo = false
    var ghAccounts: [String] = []
    var filterMode: PRFilterMode = .all
    var currentGhUser: String?

    var hasMore: Bool {
        pullRequests.count >= pageSize && pullRequests.count % pageSize == 0
    }

    private let githubService = GitHubService.shared
    private let pageSize = GitHubService.prPageSize

    func loadPullRequests(repo: Repo) async {
        isLoading = true
        error = nil

        isGitHubRepo = githubService.isGitHubRepo(url: repo.url)
        guard isGitHubRepo else {
            error = GitHubError.notAGitHubRepo.localizedDescription
            isLoading = false
            return
        }

        ghAvailable = await githubService.isAvailable()
        guard ghAvailable == true else {
            error = GitHubError.ghNotInstalled.localizedDescription
            isLoading = false
            return
        }

        ghAccounts = await githubService.listAccounts()

        if currentGhUser == nil {
            currentGhUser = await githubService.currentUser(
                account: repo.ghAccount
            )
        }

        do {
            pullRequests = try await fetchPRs(repo: repo, limit: pageSize)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadMore(repo: Repo) async {
        guard !isLoadingMore else { return }
        isLoadingMore = true

        do {
            let nextPage = try await fetchPRs(
                repo: repo,
                limit: pullRequests.count + pageSize
            )
            pullRequests = nextPage
        } catch {
            self.error = error.localizedDescription
        }

        isLoadingMore = false
    }

    func refresh(repo: Repo) async {
        await loadPullRequests(repo: repo)
    }

    func clear() {
        pullRequests = []
        error = nil
        ghAvailable = nil
        isGitHubRepo = false
    }

    private func fetchPRs(repo: Repo, limit: Int) async throws -> [PullRequest] {
        switch filterMode {
        case .all:
            return try await githubService.listPullRequests(
                repoUrl: repo.url, limit: limit, account: repo.ghAccount
            )
        case .pendingMyReview:
            return try await githubService.listPendingReviews(
                repoUrl: repo.url, limit: limit, account: repo.ghAccount
            )
        case .merged:
            return try await githubService.listMergedPRs(
                repoUrl: repo.url, limit: limit, account: repo.ghAccount
            )
        }
    }
}
