import Foundation

enum RoutinePublishResult: Sendable {
    case published
    case alreadyPublished
}

actor RoutineReviewPublisher {
    static let shared = RoutineReviewPublisher()

    func publish(
        comment: String,
        marker: String,
        repository: RoutineRepositoryContext,
        pullRequest: PullRequest
    ) async throws -> RoutinePublishResult {
        if GitLabService.shared.isGitLabRepo(url: repository.url) {
            let exists = try await GitLabService.shared.hasMRComment(
                repoUrl: repository.url,
                mrNumber: pullRequest.number,
                containing: marker,
                host: repository.gitlabHost
            )
            guard !exists else { return .alreadyPublished }
            try await GitLabService.shared.commentOnMR(
                repoUrl: repository.url,
                mrNumber: pullRequest.number,
                message: comment,
                host: repository.gitlabHost
            )
        } else {
            let exists = try await GitHubService.shared.hasPRComment(
                repoUrl: repository.url,
                prNumber: pullRequest.number,
                containing: marker,
                account: repository.githubAccount
            )
            guard !exists else { return .alreadyPublished }
            try await GitHubService.shared.postPRComment(
                repoUrl: repository.url,
                prNumber: pullRequest.number,
                message: comment,
                account: repository.githubAccount
            )
        }
        return .published
    }
}
