import Foundation

final class GitLabService {
    static let shared = GitLabService()

    private let shell = ShellService.shared
    private init() {}

    static let mrPageSize = 30

    private var glabBinary: String {
        let custom = UserDefaults.standard.string(forKey: "glabPath") ?? ""
        return custom.isEmpty ? "glab" : custom
    }

    // MARK: - Detection

    func isGitLabRepo(url: String) -> Bool {
        if url.contains("gitlab.com") || url.contains("gitlab.") {
            return true
        }
        let host = gitlabHost
        if !host.isEmpty, let hostURL = URL(string: host), let hostname = hostURL.host {
            return url.contains(hostname)
        }
        return false
    }

    /// Extract "owner/repo" (or "group/subgroup/repo") from a GitLab URL
    func extractRepoSlug(url: String) -> String? {
        let cleaned = url
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Custom host: https://gitlab.housecalldev.com/owner/repo
        let host = gitlabHost
        if !host.isEmpty, let hostURL = URL(string: host), let hostname = hostURL.host {
            // HTTPS with custom host
            if let range = cleaned.range(of: hostname + "/") {
                let path = String(cleaned[range.upperBound...])
                if path.contains("/") {
                    return path
                }
            }
            // SSH with custom host: git@gitlab.housecalldev.com:owner/repo
            if let range = cleaned.range(of: hostname + ":") {
                let path = String(cleaned[range.upperBound...])
                if path.contains("/") {
                    return path
                }
            }
        }

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
        let binary = glabBinary
        if binary != "glab" {
            return FileManager.default.isExecutableFile(atPath: binary)
        }
        do {
            // Only check if the binary exists, not auth status.
            // glab auth status exits 1 even when configured but
            // token is expired. Actual commands will fail with
            // proper auth errors if needed.
            let output = try await shell.execute(
                "which", arguments: ["glab"],
                environment: baseShellEnv()
            )
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Accounts

    func listHosts() async -> [String] {
        // glab auth status writes to stderr
        guard let result = try? await runGlab(
            arguments: ["auth", "status"],
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

        guard let result = try? await runGlab(
            arguments: args,
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
        // glab auth status output has bare hostnames as section headers:
        //   gitlab.com
        //     ✓ Logged in to gitlab.com as username
        // Or when auth fails:
        //   gitlab.com
        //     x gitlab.com: API call failed...
        var hosts: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Bare hostname line (no leading symbols like ✓, x, !)
            if !trimmed.hasPrefix("x ") &&
                !trimmed.hasPrefix("✓") &&
                !trimmed.hasPrefix("!") &&
                !trimmed.hasPrefix("X ") &&
                !trimmed.contains(" ") &&
                trimmed.contains(".") {
                hosts.append(trimmed)
            }
        }
        return hosts
    }

    // MARK: - List MRs

    func listMergeRequests(
        repoUrl: String, limit: Int = mrPageSize, host: String? = nil
    ) async throws -> [PullRequest] {
        try await fetchMRList(
            repoUrl: repoUrl, filter: .open, limit: limit, host: host
        )
    }

    func listPendingReviews(
        repoUrl: String, limit: Int = mrPageSize, host: String? = nil
    ) async throws -> [PullRequest] {
        try await fetchMRList(
            repoUrl: repoUrl, filter: .open,
            reviewer: "@me",
            limit: limit, host: host
        )
    }

    func listClosedMRs(
        repoUrl: String, limit: Int = mrPageSize, host: String? = nil
    ) async throws -> [PullRequest] {
        try await fetchMRList(
            repoUrl: repoUrl, filter: .closed, limit: limit, host: host
        )
    }

    func listMergedMRs(
        repoUrl: String, limit: Int = mrPageSize, host: String? = nil
    ) async throws -> [PullRequest] {
        try await fetchMRList(
            repoUrl: repoUrl, filter: .merged, limit: limit, host: host
        )
    }

    private enum MRFilter {
        case open, closed, merged
    }

    private func fetchMRList(
        repoUrl: String,
        filter: MRFilter,
        reviewer: String? = nil,
        limit: Int = mrPageSize,
        host: String? = nil
    ) async throws -> [PullRequest] {
        guard let slug = extractRepoSlug(url: repoUrl) else {
            throw GitLabError.repoNotFound(repoUrl)
        }

        // glab uses flags instead of --state:
        // (default) = open, --closed = closed, --merged = merged
        var args = [
            "mr", "list",
            "-R", slug,
            "--output", "json",
            "--per-page", "\(limit)"
        ]
        switch filter {
        case .open: break // default behavior
        case .closed: args += ["--closed"]
        case .merged: args += ["--merged"]
        }
        if let reviewer {
            args += ["--reviewer", reviewer]
        }

        let env = await shellEnv(host: host)
        let result = try await runGlab(
            arguments: args,
            environment: env, timeout: 60
        )

        guard result.exitCode == 0 else {
            throw GitLabError.commandFailed(describeFailure(result, arguments: args, envHint: env))
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
        let args = ["mr", "diff", "\(mrNumber)", "-R", slug, "--color=never"]
        let result = try await runGlab(
            arguments: args,
            environment: env,
            timeout: 90
        )

        guard result.exitCode == 0 else {
            throw GitLabError.commandFailed(describeFailure(result, arguments: args, envHint: env))
        }

        return result.stdout
    }

    // MARK: - MR Detail

    func getMRDetail(repoUrl: String, mrNumber: Int, host: String? = nil) async throws -> PRDetail {
        guard let slug = extractRepoSlug(url: repoUrl) else {
            throw GitLabError.repoNotFound(repoUrl)
        }

        let env = await shellEnv(host: host)
        let args = ["mr", "view", "\(mrNumber)", "-R", slug, "--output", "json"]
        let result = try await runGlab(
            arguments: args,
            environment: env,
            timeout: 60
        )

        guard result.exitCode == 0 else {
            throw GitLabError.commandFailed(describeFailure(result, arguments: args, envHint: env))
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = output.data(using: .utf8) else {
            throw GitLabError.invalidResponse("Empty output from glab mr view")
        }

        let dto = try JSONDecoder.glabDecoder.decode(MRDetailDTO.self, from: data)
        return PRDetail(title: dto.title, body: dto.description ?? "")
    }

    // MARK: - MR Actions

    func approveMR(repoUrl: String, mrNumber: Int, host: String? = nil) async throws {
        guard let slug = extractRepoSlug(url: repoUrl) else {
            throw GitLabError.repoNotFound(repoUrl)
        }

        let env = await shellEnv(host: host)
        let args = ["mr", "approve", "\(mrNumber)", "-R", slug]
        let result = try await runGlab(
            arguments: args, environment: env, timeout: 30
        )

        guard result.exitCode == 0 else {
            throw GitLabError.commandFailed(describeFailure(result, arguments: args, envHint: env))
        }
    }

    func commentOnMR(repoUrl: String, mrNumber: Int, message: String, host: String? = nil) async throws {
        guard let slug = extractRepoSlug(url: repoUrl) else {
            throw GitLabError.repoNotFound(repoUrl)
        }

        let env = await shellEnv(host: host)
        let args = ["mr", "note", "\(mrNumber)", "-R", slug, "-m", message]
        let result = try await runGlab(
            arguments: args, environment: env, timeout: 30
        )

        guard result.exitCode == 0 else {
            throw GitLabError.commandFailed(describeFailure(result, arguments: args, envHint: env))
        }
    }

    // MARK: - Private

    /// Build a descriptive error from a failed glab result, including the command for debugging.
    /// Exit code 15 (SIGTERM) indicates the process was killed by our timeout.
    private func describeFailure(
        _ result: ShellService.ShellResult,
        arguments: [String],
        envHint: [String: String] = [:]
    ) -> String {
        let binary = glabBinary
        let command = ([binary] + arguments)
            .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")

        var envPrefix = ""
        if let host = envHint["GITLAB_HOST"], !host.isEmpty {
            envPrefix = "GITLAB_HOST=\(host) "
        }

        let reason: String
        if result.exitCode == 15 {
            reason = "Request timed out. Your GitLab server may be slow to respond."
        } else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            reason = !stderr.isEmpty ? stderr : (!stdout.isEmpty ? stdout : "exit code \(result.exitCode)")
        }

        return "\(reason)\n\nTry in terminal:\n\(envPrefix)\(command)"
    }

    private func runGlab(
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval = 30
    ) async throws -> ShellService.ShellResult {
        let binary = glabBinary
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

    private func shellEnv(host: String? = nil) async -> [String: String] {
        var env = baseShellEnv()
        // Resolve which host to fetch the token for:
        // prefer the explicit host param, fall back to the global setting
        let tokenHost = host ?? {
            let global = gitlabHost
            if global.isEmpty { return nil }
            if let url = URL(string: global), let h = url.host { return h }
            return global
        }()
        if let tokenHost, !tokenHost.isEmpty {
            if let token = readGlabToken(for: tokenHost), !token.isEmpty {
                env["GITLAB_TOKEN"] = token
            }
        }
        return env
    }

    /// Read the auth token for a host directly from glab's config file.
    /// glab stores tokens in ~/.config/glab-cli/config.yml under hosts.<hostname>.token
    /// Format:
    ///   hosts:
    ///       gitlab.example.com:
    ///           token: <value>
    private func readGlabToken(for host: String) -> String? {
        let configDir = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            ?? (NSHomeDirectory() + "/.config")
        let configPath = configDir + "/glab-cli/config.yml"

        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }

        let lines = contents.components(separatedBy: "\n")
        // Find the line with our host, then scan for its token
        guard let hostIdx = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "\(host):"
        }) else { return nil }

        let hostIndent = lines[hostIdx].prefix(while: { $0 == " " }).count

        for i in (hostIdx + 1)..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let indent = line.prefix(while: { $0 == " " }).count
            // Less or equal indent means we left this host's block
            if indent <= hostIndent { break }

            if trimmed.hasPrefix("token:") {
                let token = trimmed.dropFirst("token:".count)
                    .trimmingCharacters(in: .whitespaces)
                return token.isEmpty ? nil : token
            }
        }
        return nil
    }

    private var gitlabHost: String {
        let custom = UserDefaults.standard.string(forKey: "gitlabHost") ?? ""
        return custom.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func baseShellEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? ""
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let missing = extraPaths.filter { !path.contains($0) }
        if !missing.isEmpty {
            env["PATH"] = (missing + [path]).joined(separator: ":")
        }
        if !gitlabHost.isEmpty {
            // Strip trailing slash and protocol for GITLAB_HOST (glab expects just the hostname)
            var host = gitlabHost
            if let url = URL(string: host), let urlHost = url.host {
                host = urlHost
            }
            env["GITLAB_HOST"] = host
        }
        return env
    }
}

// MARK: - JSON DTOs

private struct MRListDTO: Codable {
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
        // Reviewers who haven't approved yet are "pending"
        let pendingReviewers = reviewerLogins.filter { !approvedUsers.contains($0) }

        let reviews = approvedUsers.map {
            PRReviewStatus(login: $0, state: "APPROVED")
        }

        let decision: String
        if !approvedUsers.isEmpty && pendingReviewers.isEmpty {
            decision = "APPROVED"
        } else {
            decision = ""
        }

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
