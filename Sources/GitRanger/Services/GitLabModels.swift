import Foundation

struct MRListDTO: Codable {
    let iid: Int
    let title: String
    let author: UserDTO
    let state: String
    let sourceBranch: String
    let targetBranch: String
    let sha: String?
    let createdAt: String
    let updatedAt: String
    let webUrl: String
    let draft: Bool?
    let reviewers: [UserDTO]?
    let approvedBy: [ApprovalDTO]?

    struct UserDTO: Codable {
        let username: String
    }

    struct ApprovalDTO: Codable {
        let user: UserDTO
    }

    enum CodingKeys: String, CodingKey {
        case iid, title, author, state, sha, draft, reviewers
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case webUrl = "web_url"
        case approvedBy = "approved_by"
    }

    func toPullRequest() -> PullRequest {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let mappedState: String
        switch state {
        case "opened": mappedState = "OPEN"
        case "closed": mappedState = "CLOSED"
        case "merged": mappedState = "MERGED"
        default: mappedState = state.uppercased()
        }

        let isDraft = draft ?? (title.hasPrefix("Draft:") || title.hasPrefix("WIP:"))
        let approvedUsers = (approvedBy ?? []).map { $0.user.username }
        let reviewerLogins = (reviewers ?? []).map { $0.username }
        let pendingReviewers = reviewerLogins.filter { !approvedUsers.contains($0) }
        let reviews = approvedUsers.map {
            PRReviewStatus(login: $0, state: "APPROVED")
        }
        let decision = !approvedUsers.isEmpty && pendingReviewers.isEmpty
            ? "APPROVED" : ""

        return PullRequest(
            number: iid,
            title: title,
            authorLogin: author.username,
            state: mappedState,
            headRefName: sourceBranch,
            headRefOid: sha ?? "",
            baseRefName: targetBranch,
            createdAt: formatter.date(from: createdAt) ?? Date(),
            updatedAt: formatter.date(from: updatedAt) ?? Date(),
            additions: 0,
            deletions: 0,
            changedFiles: 0,
            url: webUrl,
            isDraft: isDraft,
            reviewDecision: decision,
            reviewRequests: pendingReviewers,
            latestReviews: reviews
        )
    }
}

struct MRDetailDTO: Codable {
    let title: String
    let description: String?
}

extension JSONDecoder {
    static let glabDecoder = JSONDecoder()
}

enum GitLabError: LocalizedError {
    case glabNotInstalled
    case glabNotAuthenticated
    case notAGitLabRepo
    case repoNotFound(String)
    case invalidResponse(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .glabNotInstalled:
            "GitLab CLI (glab) is not installed. Install with: brew install glab"
        case .glabNotAuthenticated:
            "GitLab CLI is not authenticated. Run: glab auth login"
        case .notAGitLabRepo:
            "This is not a GitLab repository."
        case .repoNotFound(let url):
            "Could not find this repository on GitLab. It may be private or deleted.\n\nURL: \(url)"
        case .invalidResponse(let detail):
            "Invalid GitLab response: \(detail)"
        case .commandFailed(let detail):
            "GitLab CLI error: \(detail)"
        }
    }
}
