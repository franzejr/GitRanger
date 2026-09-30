import Foundation

enum PRFilterMode: String, CaseIterable {
    case open = "Open"
    case closed = "Closed"
    case merged = "Merged"
    case pendingMyReview = "My Reviews"
}

@Observable
final class PRListViewModel {
    var pullRequests: [PullRequest] = []
    var isLoading = false
    var isLoadingMore = false
    var error: String?
    var ghAvailable: Bool?
    var glAvailable: Bool?
    var isGitHubRepo = false
    var isGitLabRepo = false
    var ghAccounts: [String] = []
    var glHosts: [String] = []
    var filterMode: PRFilterMode = .open
    var currentGhUser: String?
    var currentGlUser: String?

    var isPRSupported: Bool { isGitHubRepo || isGitLabRepo }

    var hasMore: Bool {
        pullRequests.count >= pageSize && pullRequests.count % pageSize == 0
    }

    private let githubService = GitHubService.shared
    private let gitlabService = GitLabService.shared
    private let pageSize = GitHubService.prPageSize

    func loadPullRequests(repo: Repo) async {
        isLoading = true
        error = nil

        isGitHubRepo = githubService.isGitHubRepo(url: repo.url)
        isGitLabRepo = !isGitHubRepo && gitlabService.isGitLabRepo(url: repo.url)

        if isGitHubRepo {
            await loadGitHubPRs(repo: repo)
        } else if isGitLabRepo {
            await loadGitLabMRs(repo: repo)
        } else {
            error = "PR/MR review is only available for GitHub and GitLab repositories."
            isLoading = false
        }
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
        glAvailable = nil
        isGitHubRepo = false
        isGitLabRepo = false
    }

    // MARK: - GitHub

    private func loadGitHubPRs(repo: Repo) async {
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

    // MARK: - GitLab

    private func loadGitLabMRs(repo: Repo) async {
        glAvailable = await gitlabService.isAvailable()
        guard glAvailable == true else {
            error = GitLabError.glabNotInstalled.localizedDescription
            isLoading = false
            return
        }

        glHosts = await gitlabService.listHosts()

        if currentGlUser == nil {
            currentGlUser = await gitlabService.currentUser(host: repo.glHost)
        }

        do {
            pullRequests = try await fetchPRs(repo: repo, limit: pageSize)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Fetch

    private func fetchPRs(repo: Repo, limit: Int) async throws -> [PullRequest] {
        if isGitLabRepo {
            return try await fetchGitLabMRs(repo: repo, limit: limit)
        }
        return try await fetchGitHubPRs(repo: repo, limit: limit)
    }

    private func fetchGitHubPRs(repo: Repo, limit: Int) async throws -> [PullRequest] {
        switch filterMode {
        case .open:
            return try await githubService.listPullRequests(
                repoUrl: repo.url, limit: limit, account: repo.ghAccount
            )
        case .closed:
            return try await githubService.listClosedPRs(
                repoUrl: repo.url, limit: limit, account: repo.ghAccount
            )
        case .merged:
            return try await githubService.listMergedPRs(
                repoUrl: repo.url, limit: limit, account: repo.ghAccount
            )
        case .pendingMyReview:
            return try await githubService.listPendingReviews(
                repoUrl: repo.url, limit: limit, account: repo.ghAccount
            )
        }
    }

    private func fetchGitLabMRs(repo: Repo, limit: Int) async throws -> [PullRequest] {
        switch filterMode {
        case .open:
            return try await gitlabService.listMergeRequests(
                repoUrl: repo.url, limit: limit, host: repo.glHost
            )
        case .closed:
            return try await gitlabService.listClosedMRs(
                repoUrl: repo.url, limit: limit, host: repo.glHost
            )
        case .merged:
            return try await gitlabService.listMergedMRs(
                repoUrl: repo.url, limit: limit, host: repo.glHost
            )
        case .pendingMyReview:
            return try await gitlabService.listPendingReviews(
                repoUrl: repo.url, limit: limit, host: repo.glHost
            )
        }
    }
}
