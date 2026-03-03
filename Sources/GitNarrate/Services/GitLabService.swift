import Foundation

final class GitLabService {
    static let shared = GitLabService()

    private let shell = ShellService.shared
    private init() {}

    static let mrPageSize = 30

    // MARK: - Detection

    func isGitLabRepo(url: String) -> Bool {
        url.contains("gitlab.com") || url.contains("gitlab.")
    }

    /// Extract "owner/repo" (or "group/subgroup/repo") from a GitLab URL
    func extractRepoSlug(url: String) -> String? {
        let cleaned = url
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // HTTPS: https://gitlab.com/owner/repo or https://gitlab.com/group/subgroup/repo
        if let range = cleaned.range(of: #"gitlab\.[^/]+/"#, options: .regularExpression) {
            let path = String(cleaned[range.upperBound...])
            if path.contains("/") {
                return path
            }
        }

        // SSH: git@gitlab.com:owner/repo or git@gitlab.com:group/subgroup/repo
        if let range = cleaned.range(of: #"gitlab\.[^:/]*:"#, options: .regularExpression) {
            let path = String(cleaned[range.upperBound...])
            if path.contains("/") {
                return path
            }
        }

        return nil
    }

    // MARK: - Availability

    func isAvailable() async -> Bool {
        do {
            let output = try await shell.execute(
                "which", arguments: ["glab"],
                environment: baseShellEnv()
            )
            guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            let result = try await shell.run(
                "glab", arguments: ["auth", "status"],
                environment: baseShellEnv(),
                timeout: 10
            )
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    // MARK: - Accounts

    func listHosts() async -> [String] {
        // glab auth status writes to stderr
        guard let result = try? await shell.run(
            "glab", arguments: ["auth", "status"],
            environment: baseShellEnv(), timeout: 10
        ) else { return [] }

        let combined = result.stdout + result.stderr
        return parseHosts(from: combined)
    }

    func currentUser(host: String? = nil) async -> String? {
        var args = ["auth", "status"]
        if let host {
            args += ["-h", host]
        }

        guard let result = try? await shell.run(
            "glab", arguments: args,
            environment: baseShellEnv(), timeout: 10
        ) else { return nil }

        let combined = result.stdout + result.stderr
        // Parse "Logged in to gitlab.com as <username>"
        for line in combined.components(separatedBy: "\n") {
            if line.contains("Logged in to") && line.contains(" as ") {
                let parts = line.components(separatedBy: " as ")
                if let username = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: " ").first {
                    return username
                }
            }
        }
        return nil
    }

    private func parseHosts(from text: String) -> [String] {
        // Matches lines like "gitlab.com" or "  - gitlab.com"
        // glab auth status output varies, but hosts appear on their own lines
        text.components(separatedBy: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Lines like "gitlab.com" or "gitlab.mycompany.com"
                if trimmed.contains("Logged in to") {
                    let parts = trimmed.components(separatedBy: "Logged in to ")
                    if let hostPart = parts.last {
                        return hostPart.components(separatedBy: " ").first
                    }
                }
                return nil
            }
    }

    // MARK: - List MRs

    func listMergeRequests(
        repoUrl: String, limit: Int = mrPageSize, host: String? = nil
    ) async throws -> [PullRequest] {
        try await fetchMRList(
            repoUrl: repoUrl, state: "opened", limit: limit, host: host
        )
    }

    func listPendingReviews(
        repoUrl: String, limit: Int = mrPageSize, host: String? = nil
    ) async throws -> [PullRequest] {
        try await fetchMRList(
            repoUrl: repoUrl, state: "opened",
            reviewer: "@me",
            limit: limit, host: host
        )
    }

    func listClosedMRs(
        repoUrl: String, limit: Int = mrPageSize, host: String? = nil
    ) async throws -> [PullRequest] {
        try await fetchMRList(
            repoUrl: repoUrl, state: "closed", limit: limit, host: host
        )
    }

    func listMergedMRs(
        repoUrl: String, limit: Int = mrPageSize, host: String? = nil
    ) async throws -> [PullRequest] {
        try await fetchMRList(
            repoUrl: repoUrl, state: "merged", limit: limit, host: host
        )
    }

    private func fetchMRList(
        repoUrl: String,
        state: String,
        reviewer: String? = nil,
        limit: Int = mrPageSize,
        host: String? = nil
    ) async throws -> [PullRequest] {
        guard let slug = extractRepoSlug(url: repoUrl) else {
            throw GitLabError.repoNotFound(repoUrl)
        }

        var args = [
            "mr", "list",
            "-R", slug,
            "--state", state,
            "--output", "json",
            "--per-page", "\(limit)"
        ]
        if let reviewer {
            args += ["--reviewer", reviewer]
        }

        let env = await shellEnv(host: host)
        let result = try await shell.run(
            "glab", arguments: args,
            environment: env, timeout: 30
        )

        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitLabError.commandFailed(
                stderr.isEmpty ? "glab exited with code \(result.exitCode)" : stderr
            )
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty, let data = output.data(using: .utf8) else {
            return []
        }

        let dtos = try JSONDecoder.glabDecoder.decode([MRListDTO].self, from: data)
        return dtos.map { $0.toPullRequest() }
    }

    // MARK: - MR Diff

    func getMRDiff(repoUrl: String, mrNumber: Int, host: String? = nil) async throws -> String {
        guard let slug = extractRepoSlug(url: repoUrl) else {
            throw GitLabError.repoNotFound(repoUrl)
        }

        let env = await shellEnv(host: host)
        let result = try await shell.run(
            "glab",
            arguments: ["mr", "diff", "\(mrNumber)", "-R", slug],
            environment: env,
            timeout: 30
        )

        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitLabError.commandFailed(
                stderr.isEmpty ? "glab mr diff failed" : stderr
            )
        }

        return result.stdout
    }

    // MARK: - MR Detail

    func getMRDetail(repoUrl: String, mrNumber: Int, host: String? = nil) async throws -> PRDetail {
        guard let slug = extractRepoSlug(url: repoUrl) else {
            throw GitLabError.repoNotFound(repoUrl)
        }

        let env = await shellEnv(host: host)
        let result = try await shell.run(
            "glab",
            arguments: ["mr", "view", "\(mrNumber)", "-R", slug, "--output", "json"],
            environment: env,
            timeout: 15
        )

        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitLabError.commandFailed(
                stderr.isEmpty ? "glab mr view failed" : stderr
            )
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = output.data(using: .utf8) else {
            throw GitLabError.invalidResponse("Empty output from glab mr view")
        }

        let dto = try JSONDecoder.glabDecoder.decode(MRDetailDTO.self, from: data)
        return PRDetail(title: dto.title, body: dto.description ?? "")
    }

    // MARK: - Private

    private func shellEnv(host: String? = nil) async -> [String: String] {
        var env = baseShellEnv()
        if let host {
            // Get token for specific host
            if let result = try? await shell.run(
                "glab", arguments: ["auth", "token", "-h", host],
                environment: env, timeout: 5
            ), result.exitCode == 0 {
                let token = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    env["GITLAB_TOKEN"] = token
                }
            }
        }
        return env
    }

    private func baseShellEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
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

private struct MRListDTO: Codable {
    let iid: Int
    let title: String
    let author: AuthorDTO
    let state: String
    let sourceBranch: String
    let targetBranch: String
    let sha: String?
    let createdAt: String
    let updatedAt: String
    let webUrl: String
    let draft: Bool?

    struct AuthorDTO: Codable {
        let username: String
    }

    enum CodingKeys: String, CodingKey {
        case iid, title, author, state, sha, draft
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case webUrl = "web_url"
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

        let isDraft = draft ?? title.hasPrefix("Draft:") || title.hasPrefix("WIP:")

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
            reviewDecision: "",
            reviewRequests: [],
            latestReviews: []
        )
    }
}

private struct MRDetailDTO: Codable {
    let title: String
    let description: String?
}

private extension JSONDecoder {
    static let glabDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
}

// MARK: - Errors

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
