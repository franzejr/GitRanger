import Foundation

@Observable
final class PRListViewModel {
    var pullRequests: [PullRequest] = []
    var isLoading = false
    var error: String?
    var ghAvailable: Bool?
    var isGitHubRepo = false
    var ghAccounts: [String] = []

    private let githubService = GitHubService.shared

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

        do {
            pullRequests = try await githubService.listPullRequests(
                repoUrl: repo.url,
                account: repo.ghAccount
            )
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
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
}
