import Foundation

final class GitService {
    static let shared = GitService()

    private let shell = ShellService.shared

    private var reposDirectory: URL {
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
            for line in lines {
                if line.contains("HEAD branch:") {
                    let branch = line.components(separatedBy: "HEAD branch:").last?
                        .trimmingCharacters(in: .whitespaces) ?? ""
                    if !branch.isEmpty { return branch }
                }
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

    // MARK: - Delete

    func deleteRepo(repoPath: URL) throws {
        if FileManager.default.fileExists(atPath: repoPath.path) {
            try FileManager.default.removeItem(at: repoPath)
        }
    }

    // MARK: - Helpers

    func extractRepoName(url: String) -> String {
        let cleaned = url
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = cleaned.components(separatedBy: "/")
        return parts.last ?? "unknown"
    }

    // MARK: - Private

    private func parseLogOutput(_ output: String, separator: String) -> [CommitInfo] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        var commits: [CommitInfo] = []
        let lines = output.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            guard line.contains(separator) else {
                i += 1
                continue
            }

            let parts = line.components(separatedBy: separator)
            guard parts.count >= 5 else {
                i += 1
                continue
            }

            let sha = parts[0]
            let message = parts[1]
            let authorName = parts[2]
            let authorEmail = parts[3]
            let dateStr = parts[4]
            let body = parts.count > 5 ? parts[5] : ""

            // Collect stat lines after the format line
            var statBlock = body
            i += 1
            while i < lines.count && !lines[i].contains(separator) {
                statBlock += "\n" + lines[i]
                i += 1
            }

            let (filesChanged, insertions, deletions) = parseStatBlock(statBlock)
            let date = dateFormatter.date(from: dateStr) ?? Date()

            commits.append(CommitInfo(
                sha: sha,
                message: message,
                authorName: authorName,
                authorEmail: authorEmail,
                date: date,
                filesChanged: filesChanged,
                insertions: insertions,
                deletions: deletions
            ))
        }

        return commits
    }

    private func parseStatBlock(_ block: String) -> (Int, Int, Int) {
        // Match: "3 files changed, 50 insertions(+), 10 deletions(-)"
        let pattern = #"(\d+) files? changed(?:, (\d+) insertions?\(\+\))?(?:, (\d+) deletions?\(-\))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: block,
                  range: NSRange(block.startIndex..., in: block)
              ) else {
            return (0, 0, 0)
        }

        func intAt(_ index: Int) -> Int {
            guard index < match.numberOfRanges,
                  let range = Range(match.range(at: index), in: block) else { return 0 }
            return Int(block[range]) ?? 0
        }

        return (intAt(1), intAt(2), intAt(3))
    }
}

enum GitError: LocalizedError {
    case repoExists(String)
    case notARepo(String)
    case cloneFailed(String)

    var errorDescription: String? {
        switch self {
        case .repoExists(let path): "Repository already exists at \(path)"
        case .notARepo(let path): "\(path) is not a git repository"
        case .cloneFailed(let reason): "Clone failed: \(reason)"
        }
    }
}
