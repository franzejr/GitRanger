import Foundation

final class GitHubService {
    static let shared = GitHubService()

    private let shell = ShellService.shared
    private init() {}

    private var ghBinary: String {
        let custom = UserDefaults.standard.string(forKey: "ghPath") ?? ""
        return custom.isEmpty ? "gh" : custom
    }

    // MARK: - Accounts

    func listAccounts() async -> [String] {
        // gh auth status may write to stderr on success
        guard let result = try? await runGh(
            arguments: ["auth", "status"],
            environment: baseShellEnv(), timeout: 10
        ) else { return [] }
        let combined = result.stdout + result.stderr
        return parseAccounts(from: combined)
    }

    private func parseAccounts(from text: String) -> [String] {
        // Matches "Logged in to github.com account <username>"
        text.components(separatedBy: "\n")
            .compactMap { line -> String? in
                guard line.contains("Logged in to") && line.contains("account") else { return nil }
                let parts = line.components(separatedBy: "account ")
                return parts.last?.components(separatedBy: " ").first?.trimmingCharacters(in: .whitespaces)
            }
    }

    private func shellEnv(account: String? = nil) async -> [String: String] {
        var env = baseShellEnv()
        if let account {
            // Get token for specific account
            if let result = try? await runGh(
                arguments: ["auth", "token", "--user", account],
                environment: env, timeout: 5
            ), result.exitCode == 0 {
                let token = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    env["GH_TOKEN"] = token
                }
            }
        }
        return env
    }

    // MARK: - Availability

    func isAvailable() async -> Bool {
        let binary = ghBinary
        if binary != "gh" {
            return FileManager.default.isExecutableFile(atPath: binary)
        }
        do {
            let output = try await shell.execute(
                "which", arguments: ["gh"],
                environment: baseShellEnv()
            )
            guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            let result = try await runGh(
                arguments: ["auth", "status"],
                environment: baseShellEnv(),
                timeout: 10
            )
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    func isGitHubRepo(url: String) -> Bool {
        url.contains("github.com")
    }

    /// Extract "owner/repo" from a GitHub URL (HTTPS or SSH, including custom host aliases)
    func extractRepoSlug(url: String) -> String? {
        // HTTPS: https://github.com/owner/repo.git
        // SSH:   git@github.com:owner/repo.git
        // Alias: git@github.com-myalias:owner/repo.git
        let cleaned = url
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // HTTPS format: contains "github.com/"
        if cleaned.contains("github.com/") {
            let parts = cleaned.components(separatedBy: "github.com/")
            if let path = parts.last, path.contains("/") {
                return path
            }
        }

        // SSH format: contains "github.com:" or "github.com-<alias>:"
        // Match pattern: github.com followed by optional -alias, then :
        if let range = cleaned.range(of: #"github\.com[^:/]*:"#, options: .regularExpression) {
            let afterColon = cleaned[range.upperBound...]
            let path = String(afterColon)
            if path.contains("/") {
                return path
            }
        }

        return nil
    }

    // MARK: - List PRs

    static let prPageSize = 30

    func listPullRequests(
        repoUrl: String, limit: Int = prPageSize, account: String? = nil
    ) async throws -> [PullRequest] {
        try await fetchPRList(
            repoUrl: repoUrl, state: "open", limit: limit, account: account
        )
    }

    func listPendingReviews(
        repoUrl: String, limit: Int = prPageSize, account: String? = nil
    ) async throws -> [PullRequest] {
        try await fetchPRList(
            repoUrl: repoUrl, state: "open",
            search: "review-requested:@me",
            limit: limit, account: account
        )
    }

    func listClosedPRs(
        repoUrl: String, limit: Int = prPageSize, account: String? = nil
    ) async throws -> [PullRequest] {
        try await fetchPRList(
            repoUrl: repoUrl, state: "closed", limit: limit, account: account
        )
    }

    func listMergedPRs(
        repoUrl: String, limit: Int = prPageSize, account: String? = nil
    ) async throws -> [PullRequest] {
        try await fetchPRList(
            repoUrl: repoUrl, state: "merged", limit: limit, account: account
        )
    }

    private func fetchPRList(
        repoUrl: String,
        state: String,
        search: String? = nil,
        limit: Int = prPageSize,
        account: String? = nil
    ) async throws -> [PullRequest] {
        guard let slug = extractRepoSlug(url: repoUrl) else {
            throw GitHubError.repoNotFound(repoUrl)
        }

        let fields = "number,title,author,state,headRefName,headRefOid,baseRefName," +
                     "createdAt,updatedAt,additions,deletions,changedFiles,url,isDraft," +
                     "reviewDecision,latestReviews,reviewRequests"

        var args = ["pr", "list", "-R", slug, "--state", state, "--json", fields, "--limit", "\(limit)"]
        if let search {
            args += ["--search", search]
        }

        let env = await shellEnv(account: account)
        let output = try await runGhOrThrow(arguments: args, environment: env, timeout: 30)

        guard let data = output.data(using: .utf8) else {
            throw GitHubError.invalidResponse("Empty output from gh pr list")
        }

        let dtos = try JSONDecoder.ghDecoder.decode([PRListDTO].self, from: data)
        return dtos.map { $0.toPullRequest() }
    }

    // MARK: - Current User

    func currentUser(account: String? = nil) async -> String? {
        let env = await shellEnv(account: account)
        guard let result = try? await runGh(
            arguments: ["api", "user", "--jq", ".login"],
            environment: env, timeout: 10
        ), result.exitCode == 0 else { return nil }

        let login = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return login.isEmpty ? nil : login
    }

    // MARK: - PR Diff

    func getPRDiff(repoUrl: String, prNumber: Int, account: String? = nil) async throws -> String {
        guard let slug = extractRepoSlug(url: repoUrl) else {
            throw GitHubError.repoNotFound(repoUrl)
        }

        let env = await shellEnv(account: account)
        return try await runGhOrThrow(
            arguments: ["pr", "diff", "\(prNumber)", "-R", slug],
            environment: env,
            timeout: 30
        )
    }

    // MARK: - PR Detail

    func getPRDetail(repoUrl: String, prNumber: Int, account: String? = nil) async throws -> PRDetail {
        guard let slug = extractRepoSlug(url: repoUrl) else {
            throw GitHubError.repoNotFound(repoUrl)
        }

        let env = await shellEnv(account: account)
        let output = try await runGhOrThrow(
            arguments: ["pr", "view", "\(prNumber)", "-R", slug, "--json", "title,body"],
            environment: env,
            timeout: 15
        )

        guard let data = output.data(using: .utf8) else {
            throw GitHubError.invalidResponse("Empty output from gh pr view")
        }

        let dto = try JSONDecoder().decode(PRDetailDTO.self, from: data)
        return PRDetail(title: dto.title, body: dto.body ?? "")
    }

    // MARK: - Private

    private func runGh(
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval = 30
    ) async throws -> ShellService.ShellResult {
        let binary = ghBinary
        if binary.contains("/") {
            return try await shell.runDirect(
                binary, arguments: arguments,
                environment: environment, timeout: timeout
            )
        }
        return try await shell.run(
            binary, arguments: arguments,
            environment: environment, timeout: timeout
        )
    }

    private func runGhOrThrow(
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval = 30
    ) async throws -> String {
        let result = try await runGh(
            arguments: arguments,
            environment: environment, timeout: timeout
        )
        if result.exitCode != 0 {
            throw ShellError.nonZeroExit(
                code: result.exitCode, stderr: result.stderr
            )
        }
        return result.stdout
    }

    private func baseShellEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Ensure Homebrew paths are available for GUI apps
        let path = env["PATH"] ?? ""
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let missing = extraPaths.filter { !path.contains($0) }
        if !missing.isEmpty {
            env["PATH"] = (missing + [path]).joined(separator: ":")
        }
        return env
    }
}

// MARK: - JSON DTOs

private struct PRListDTO: Codable {
    let number: Int
    let title: String
    let author: AuthorDTO
    let state: String
    let headRefName: String
    let headRefOid: String
    let baseRefName: String
    let createdAt: String
    let updatedAt: String
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    let url: String
    let isDraft: Bool
    let reviewDecision: String?
    let latestReviews: [ReviewDTO]?
    let reviewRequests: [ReviewRequestDTO]?

    struct AuthorDTO: Codable {
        let login: String
    }

    struct ReviewDTO: Codable {
        let author: AuthorDTO
        let state: String
    }

    struct ReviewRequestDTO: Codable {
        let login: String?
        let name: String?
    }

    func toPullRequest() -> PullRequest {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let reviews = (latestReviews ?? []).map {
            PRReviewStatus(login: $0.author.login, state: $0.state)
        }
        let requests = (reviewRequests ?? []).compactMap {
            $0.login
        }

        return PullRequest(
            number: number,
            title: title,
            authorLogin: author.login,
            state: state,
            headRefName: headRefName,
            headRefOid: headRefOid,
            baseRefName: baseRefName,
            createdAt: formatter.date(from: createdAt) ?? Date(),
            updatedAt: formatter.date(from: updatedAt) ?? Date(),
            additions: additions,
            deletions: deletions,
            changedFiles: changedFiles,
            url: url,
            isDraft: isDraft,
            reviewDecision: reviewDecision ?? "",
            reviewRequests: requests,
            latestReviews: reviews
        )
    }
}

private struct PRDetailDTO: Codable {
    let title: String
    let body: String?
}

private extension JSONDecoder {
    static let ghDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
}

// MARK: - Errors

enum GitHubError: LocalizedError {
    case ghNotInstalled
    case ghNotAuthenticated
    case notAGitHubRepo
    case repoNotFound(String)
    case invalidResponse(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .ghNotInstalled:
            "GitHub CLI (gh) is not installed. Install with: brew install gh"
        case .ghNotAuthenticated:
            "GitHub CLI is not authenticated. Run: gh auth login"
        case .notAGitHubRepo:
            "PR/MR review is only available for GitHub and GitLab repositories."
        case .repoNotFound(let url):
            "Could not find this repository on GitHub. It may be private, renamed, or deleted.\n\nURL: \(url)"
        case .invalidResponse(let detail):
            "Invalid GitHub response: \(detail)"
        case .commandFailed(let detail):
            "GitHub CLI error: \(detail)"
        }
    }
}
