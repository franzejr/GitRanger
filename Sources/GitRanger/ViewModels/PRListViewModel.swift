import Foundation

enum PRFilterMode: String, CaseIterable, Sendable {
    case open = "Open"
    case closed = "Closed"
    case merged = "Merged"
    case pendingMyReview = "My Reviews"
}

@MainActor
@Observable
final class PRListViewModel {
    private struct FetchContext: Sendable {
        let repoURL: String
        let githubAccount: String?
        let gitlabHost: String?
        let isGitLab: Bool
        let filterMode: PRFilterMode

        var cacheKey: PRListCacheKey {
            PRListCacheKey(
                repoURL: repoURL,
                provider: isGitLab ? "gitlab" : "github",
                filter: filterMode.rawValue,
                account: githubAccount,
                host: gitlabHost
            )
        }
    }

    var pullRequests: [PullRequest] = []
    var isLoading = false
    var isLoadingMore = false
    var isShowingCachedResults = false
    var error: String?
    var refreshError: String?
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
    private let listCache = PRListCache.shared
    private let pageSize = GitHubService.prPageSize
    private var activeCacheKey: PRListCacheKey?
    private var activeLoadID: UUID?

    func loadPullRequests(repo: Repo) async {
        let context = fetchContext(for: repo)
        isGitHubRepo = !context.isGitLab
            && githubService.isGitHubRepo(url: context.repoURL)
        isGitLabRepo = context.isGitLab

        guard isPRSupported else {
            error = "PR/MR review is only available for GitHub and GitLab repositories."
            isLoading = false
            return
        }

        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        error = nil
        refreshError = nil
        await showCachedResultsIfNeeded(for: context, loadID: loadID)
        guard isCurrentLoad(loadID) else { return }

        if isGitHubRepo {
            await loadGitHubPRs(context: context, loadID: loadID)
        } else {
            await loadGitLabMRs(context: context, loadID: loadID)
        }

        if isCurrentLoad(loadID) {
            isLoading = false
        }
    }

    func loadMore(repo: Repo) async {
        guard !isLoading, !isLoadingMore else { return }
        let context = fetchContext(for: repo)
        guard context.cacheKey == activeCacheKey else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = try await fetchPRs(
                context: context,
                limit: pullRequests.count + pageSize
            )
            guard context.cacheKey == activeCacheKey else { return }
            pullRequests = nextPage
            isShowingCachedResults = false
            await listCache.store(nextPage, for: context.cacheKey)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refresh(repo: Repo) async {
        await loadPullRequests(repo: repo)
    }

    func clear() {
        activeLoadID = nil
        activeCacheKey = nil
        pullRequests = []
        isLoading = false
        isLoadingMore = false
        isShowingCachedResults = false
        error = nil
        refreshError = nil
        ghAvailable = nil
        glAvailable = nil
        isGitHubRepo = false
        isGitLabRepo = false
        currentGhUser = nil
        currentGlUser = nil
    }

    // MARK: - GitHub

    private func loadGitHubPRs(
        context: FetchContext,
        loadID: UUID
    ) async {
        let available = await githubService.isAvailable()
        guard !Task.isCancelled, isCurrentLoad(loadID) else { return }
        ghAvailable = available
        guard available else {
            showRefreshError(GitHubError.ghNotInstalled.localizedDescription)
            return
        }

        do {
            async let accounts = resolvedGitHubAccounts()
            async let user = resolvedGitHubUser(account: context.githubAccount)
            async let requests = fetchPRs(context: context, limit: pageSize)
            let loaded = try await requests
            guard isCurrentLoad(loadID) else { return }
            pullRequests = loaded
            isShowingCachedResults = false
            isLoading = false
            await listCache.store(loaded, for: context.cacheKey)
            let metadata = await (accounts, user)
            guard isCurrentLoad(loadID) else { return }
            ghAccounts = metadata.0
            currentGhUser = metadata.1
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentLoad(loadID) else { return }
            showRefreshError(error.localizedDescription)
        }
    }

    // MARK: - GitLab

    private func loadGitLabMRs(
        context: FetchContext,
        loadID: UUID
    ) async {
        let available = await gitlabService.isAvailable()
        guard !Task.isCancelled, isCurrentLoad(loadID) else { return }
        glAvailable = available
        guard available else {
            showRefreshError(GitLabError.glabNotInstalled.localizedDescription)
            return
        }

        do {
            async let hosts = resolvedGitLabHosts()
            async let user = resolvedGitLabUser(host: context.gitlabHost)
            async let requests = fetchPRs(context: context, limit: pageSize)
            let loaded = try await requests
            guard isCurrentLoad(loadID) else { return }
            pullRequests = loaded
            isShowingCachedResults = false
            isLoading = false
            await listCache.store(loaded, for: context.cacheKey)
            let metadata = await (hosts, user)
            guard isCurrentLoad(loadID) else { return }
            glHosts = metadata.0
            currentGlUser = metadata.1
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentLoad(loadID) else { return }
            showRefreshError(error.localizedDescription)
        }
    }

    // MARK: - Cache and Fetch

    private func showCachedResultsIfNeeded(
        for context: FetchContext,
        loadID: UUID
    ) async {
        guard activeCacheKey != context.cacheKey else { return }
        activeCacheKey = context.cacheKey
        pullRequests = []
        isShowingCachedResults = false

        guard let snapshot = await listCache.snapshot(for: context.cacheKey),
              isCurrentLoad(loadID) else { return }
        pullRequests = snapshot.pullRequests
        isShowingCachedResults = true
    }

    private func fetchContext(for repo: Repo) -> FetchContext {
        let isGitLab = !githubService.isGitHubRepo(url: repo.url)
            && gitlabService.isGitLabRepo(url: repo.url)
        return FetchContext(
            repoURL: repo.url,
            githubAccount: repo.ghAccount,
            gitlabHost: repo.glHost,
            isGitLab: isGitLab,
            filterMode: filterMode
        )
    }

    private func isCurrentLoad(_ loadID: UUID) -> Bool {
        activeLoadID == loadID
    }

    private func showRefreshError(_ message: String) {
        if pullRequests.isEmpty {
            error = message
        } else {
            refreshError = message
            isShowingCachedResults = true
        }
    }

    private func resolvedGitHubAccounts() async -> [String] {
        if !ghAccounts.isEmpty { return ghAccounts }
        return await githubService.listAccounts()
    }

    private func resolvedGitHubUser(account: String?) async -> String? {
        if let currentGhUser { return currentGhUser }
        return await githubService.currentUser(account: account)
    }

    private func resolvedGitLabHosts() async -> [String] {
        if !glHosts.isEmpty { return glHosts }
        return await gitlabService.listHosts()
    }

    private func resolvedGitLabUser(host: String?) async -> String? {
        if let currentGlUser { return currentGlUser }
        return await gitlabService.currentUser(host: host)
    }

    private func fetchPRs(
        context: FetchContext,
        limit: Int
    ) async throws -> [PullRequest] {
        if context.isGitLab {
            return try await fetchGitLabMRs(context: context, limit: limit)
        }
        return try await fetchGitHubPRs(context: context, limit: limit)
    }

    private func fetchGitHubPRs(
        context: FetchContext,
        limit: Int
    ) async throws -> [PullRequest] {
        switch context.filterMode {
        case .open:
            return try await githubService.listPullRequests(
                repoUrl: context.repoURL,
                limit: limit,
                account: context.githubAccount
            )
        case .closed:
            return try await githubService.listClosedPRs(
                repoUrl: context.repoURL,
                limit: limit,
                account: context.githubAccount
            )
        case .merged:
            return try await githubService.listMergedPRs(
                repoUrl: context.repoURL,
                limit: limit,
                account: context.githubAccount
            )
        case .pendingMyReview:
            return try await githubService.listPendingReviews(
                repoUrl: context.repoURL,
                limit: limit,
                account: context.githubAccount
            )
        }
    }

    private func fetchGitLabMRs(
        context: FetchContext,
        limit: Int
    ) async throws -> [PullRequest] {
        switch context.filterMode {
        case .open:
            return try await gitlabService.listMergeRequests(
                repoUrl: context.repoURL,
                limit: limit,
                host: context.gitlabHost
            )
        case .closed:
            return try await gitlabService.listClosedMRs(
                repoUrl: context.repoURL,
                limit: limit,
                host: context.gitlabHost
            )
        case .merged:
            return try await gitlabService.listMergedMRs(
                repoUrl: context.repoURL,
                limit: limit,
                host: context.gitlabHost
            )
        case .pendingMyReview:
            return try await gitlabService.listPendingReviews(
                repoUrl: context.repoURL,
                limit: limit,
                host: context.gitlabHost
            )
        }
    }
}
