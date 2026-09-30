import Foundation

final class GitService {
    static let shared = GitService()

    private let shell = ShellService.shared

    private var reposDirectory: URL {
        // Preserve the legacy location because persisted Repo paths point here.
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gitnarrate")
        return appSupport.appendingPathComponent("GitNarrate/repos")
    }

    private init() {
        try? FileManager.default.createDirectory(
            at: reposDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Clone

    func clone(
        url: String,
        repoId: UUID,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> URL {
        let localPath = reposDirectory.appendingPathComponent(repoId.uuidString)

        if FileManager.default.fileExists(atPath: localPath.path) {
            throw GitError.repoExists(localPath.path)
        }

        let result = try await shell.run(
            "git",
            arguments: ["clone", "--depth", "100", "--progress", url, localPath.path],
            timeout: 300
        ) { text in
            // Git progress uses \r for in-place updates (e.g. "Receiving objects:  45%")
            let lines = text.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            if let last = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                onProgress?(last.trimmingCharacters(in: .whitespaces))
            }
        }

        if result.exitCode != 0 {
            throw ShellError.nonZeroExit(code: result.exitCode, stderr: result.stderr)
        }

        return localPath
    }

    // MARK: - Default Branch

    func getDefaultBranch(repoPath: URL) async throws -> String {
        // Try remote show origin
        if let output = try? await shell.execute(
            "git", arguments: ["remote", "show", "origin"],
            cwd: repoPath, timeout: 15
        ) {
            let lines = output.components(separatedBy: "\n")
            for line in lines where line.contains("HEAD branch:") {
                let branch = line.components(separatedBy: "HEAD branch:").last?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if !branch.isEmpty { return branch }
            }
        }

        // Fallback: check local branches
        let branches = try await shell.execute(
            "git", arguments: ["branch", "--list"],
            cwd: repoPath
        )
        let branchList = branches.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "* ", with: "") }
            .filter { !$0.isEmpty }

        if branchList.contains("main") { return "main" }
        if branchList.contains("master") { return "master" }
        return branchList.first ?? "main"
    }

    // MARK: - Branches

    func listBranches(repoPath: URL) async throws -> [String] {
        let output = try await shell.execute(
            "git", arguments: ["branch", "-a", "--no-color"],
            cwd: repoPath
        )
        return output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("* ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty && !$0.contains("HEAD ->") }
            .map { $0.replacingOccurrences(of: "remotes/origin/", with: "") }
            .reduce(into: [String]()) { result, branch in
                if !result.contains(branch) { result.append(branch) }
            }
    }

    // MARK: - Log

    struct LogQuery {
        var branch: String?
        var maxCount: Int?
        var since: String?
        var until: String?
        var author: String?
        var skip: Int?
    }

    func getLog(
        repoPath: URL,
        branch: String? = nil,
        maxCount: Int? = nil,
        since: String? = nil,
        until: String? = nil,
        author: String? = nil,
        skip: Int? = nil
    ) async throws -> [CommitInfo] {
        let separator = "---GN_SEPARATOR---"
        let format = ["%H", "%s", "%an", "%ae", "%aI", "%b"].joined(separator: separator)

        var arguments = ["log"]
        if let branch { arguments.append(branch) }
        arguments += ["--shortstat", "--format=\(format)"]
        if let maxCount { arguments += ["-n", "\(maxCount)"] }
        if let skip { arguments += ["--skip=\(skip)"] }
        if let since { arguments += ["--since=\(since)"] }
        if let until { arguments += ["--until=\(until)"] }
        if let author { arguments += ["--author=\(author)"] }

        let output = try await shell.execute(
            "git", arguments: arguments, cwd: repoPath
        )

        return parseLogOutput(output, separator: separator)
    }

    // MARK: - Diff

    func getDiff(repoPath: URL, sha: String) async throws -> CommitDiff {
        let stat = try await shell.execute(
            "git",
            arguments: ["show", sha, "--stat", "--no-color", "--format="],
            cwd: repoPath
        )

        let patch = try await shell.execute(
            "git",
            arguments: ["show", sha, "--patch", "--no-color", "--format="],
            cwd: repoPath
        )

        return CommitDiff(
            sha: sha,
            stat: stat.trimmingCharacters(in: .whitespacesAndNewlines),
            patch: patch.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - Pull

    func pull(repoPath: URL) async throws -> Int {
        let beforeHead = try await shell.execute(
            "git", arguments: ["rev-parse", "HEAD"], cwd: repoPath
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // Fetch all branches + try to unshallow if needed
        _ = try? await shell.execute(
            "git", arguments: ["fetch", "--all", "--unshallow"], cwd: repoPath, timeout: 120
        )
        _ = try? await shell.execute(
            "git", arguments: ["fetch", "--all"], cwd: repoPath, timeout: 120
        )

        _ = try await shell.execute(
            "git", arguments: ["pull"], cwd: repoPath, timeout: 120
        )

        let afterHead = try await shell.execute(
            "git", arguments: ["rev-parse", "HEAD"], cwd: repoPath
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if beforeHead == afterHead { return 0 }

        let countOutput = try await shell.execute(
            "git",
            arguments: ["rev-list", "--count", "\(beforeHead)..\(afterHead)"],
            cwd: repoPath
        )
        return Int(countOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    // MARK: - Working Tree

    func getStatus(repoPath: URL) async throws -> [ChangedFile] {
        let output = try await shell.execute(
            "git", arguments: ["status", "--porcelain=v1"],
            cwd: repoPath
        )
        return parseStatus(output)
    }

    func diffFile(repoPath: URL, path: String, staged: Bool) async throws -> String {
        var args = ["diff"]
        if staged { args.append("--cached") }
        args += ["--", path]

        return try await shell.execute(
            "git", arguments: args, cwd: repoPath
        )
    }

    func stageFile(repoPath: URL, path: String) async throws {
        _ = try await shell.execute(
            "git", arguments: ["add", "--", path], cwd: repoPath
        )
    }

    func unstageFile(repoPath: URL, path: String) async throws {
        _ = try await shell.execute(
            "git", arguments: ["reset", "HEAD", "--", path], cwd: repoPath
        )
    }

    func discardFile(repoPath: URL, path: String) async throws {
        _ = try await shell.execute(
            "git", arguments: ["checkout", "--", path], cwd: repoPath
        )
    }

    func commit(repoPath: URL, summary: String, description: String?) async throws {
        var args = ["commit", "-m", summary]
        if let description, !description.isEmpty {
            args += ["-m", description]
        }
        let result = try await shell.run(
            "git", arguments: args, cwd: repoPath, timeout: 30
        )
        if result.exitCode != 0 {
            throw GitError.commitFailed(result.stderr)
        }
    }

    func currentBranch(repoPath: URL) async -> String? {
        guard let output = try? await shell.execute(
            "git", arguments: ["branch", "--show-current"],
            cwd: repoPath, timeout: 5
        ) else { return nil }
        let branch = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }

    private func parseStatus(_ output: String) -> [ChangedFile] {
        output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> ChangedFile? in
                guard line.count >= 4 else { return nil }
                let index = line.index(line.startIndex, offsetBy: 0)
                let worktree = line.index(line.startIndex, offsetBy: 1)
                let pathStart = line.index(line.startIndex, offsetBy: 3)
                let path = String(line[pathStart...])
                let x = line[index]
                let y = line[worktree]

                if x != " " && x != "?" {
                    // Staged change
                    return ChangedFile(
                        path: path,
                        status: fileStatus(from: x),
                        isStaged: true
                    )
                } else if y != " " || x == "?" {
                    // Unstaged or untracked
                    return ChangedFile(
                        path: path,
                        status: x == "?" ? .untracked : fileStatus(from: y),
                        isStaged: false
                    )
                }
                return nil
            }
    }

    private func fileStatus(from code: Character) -> FileStatus {
        switch code {
        case "M": .modified
        case "A": .added
        case "D": .deleted
        case "R": .renamed
        case "?": .untracked
        default: .modified
        }
    }

    // MARK: - Delete

    func deleteRepo(repoPath: URL) throws {
        if FileManager.default.fileExists(atPath: repoPath.path) {
            try FileManager.default.removeItem(at: repoPath)
        }
    }

    // MARK: - Local Repo Helpers

    func isGitRepo(path: URL) -> Bool {
        let gitDir = path.appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitDir.path)
    }

    func getRemoteURL(repoPath: URL) async -> String? {
        guard let output = try? await shell.execute(
            "git", arguments: ["remote", "get-url", "origin"],
            cwd: repoPath, timeout: 5
        ) else { return nil }

        let url = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }

    // MARK: - Helpers

    func extractRepoName(url: String) -> String {
        let cleaned = url
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = cleaned.components(separatedBy: "/")
        return parts.last ?? "unknown"
    }

}

// MARK: - Working Tree Types

struct ChangedFile: Identifiable {
    let path: String
    let status: FileStatus
    var isStaged: Bool

    var id: String { "\(isStaged ? "s" : "u"):\(path)" }

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var directory: String? {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? nil : dir
    }
}

enum FileStatus: String {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case untracked = "?"

    var label: String {
        switch self {
        case .modified: "Modified"
        case .added: "Added"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .untracked: "Untracked"
        }
    }
}

// MARK: - Errors

enum GitError: LocalizedError {
    case repoExists(String)
    case notARepo(String)
    case cloneFailed(String)
    case commitFailed(String)

    var errorDescription: String? {
        switch self {
        case .repoExists(let path): "Repository already exists at \(path)"
        case .notARepo(let path): "\(path) is not a git repository"
        case .cloneFailed(let reason): "Clone failed: \(reason)"
        case .commitFailed(let reason): "Commit failed: \(reason)"
        }
    }
}
