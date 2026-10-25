import Foundation

/// Falls back to paginated file patches when GitHub refuses a large raw diff.
enum GitHubPRDiffLoader {
    struct Metadata: Decodable {
        struct Ref: Decodable { let sha: String }
        let changedFiles: Int
        let head: Ref
        let base: Ref

        enum CodingKeys: String, CodingKey {
            case changedFiles = "changed_files"
            case head, base
        }
    }

    struct FilePatch: Decodable {
        let filename: String
        let previousFilename: String?
        let status: String
        let additions: Int
        let deletions: Int
        let patch: String?

        enum CodingKeys: String, CodingKey {
            case filename, status, additions, deletions, patch
            case previousFilename = "previous_filename"
        }

        var complete: Bool {
            guard let patch else { return additions == 0 && deletions == 0 }
            let lines = patch.components(separatedBy: "\n")
            return lines.filter { $0.hasPrefix("+") }.count == additions
                && lines.filter { $0.hasPrefix("-") }.count == deletions
        }

        var diff: String {
            let old = "a/\(previousFilename ?? filename)"
            let new = "b/\(filename)"
            let source = status == "added" ? "/dev/null" : old
            let destination = status == "removed" ? "/dev/null" : new
            return "diff --git \(old) \(new)\n--- \(source)\n+++ \(destination)\n"
                + (patch ?? "[No textual patch: binary file or metadata-only change]")
        }
    }

    static func isTooLarge(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("too_large")
            || lower.contains("diff exceeded")
            || lower.contains("diff is too large")
    }

    static func load(
        slug: String,
        number: Int,
        execute: ([String]) async throws -> String
    ) async throws -> String {
        do {
            return try await execute(["pr", "diff", "\(number)", "-R", slug])
        } catch {
            try Task.checkCancellation()
            guard isTooLarge(error.localizedDescription) else { throw error }
        }
        let endpoint = "repos/\(slug)/pulls/\(number)"
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(
            Metadata.self, from: Data(try await execute(["api", endpoint]).utf8)
        )
        guard metadata.changedFiles <= 3_000 else {
            throw DiffError.incomplete("This PR exceeds GitHub's 3,000-file API limit.")
        }
        var files: [FilePatch] = []
        for page in 1...max(1, (metadata.changedFiles + 99) / 100) {
            try Task.checkCancellation()
            let output = try await execute(["api", "\(endpoint)/files?per_page=100&page=\(page)"])
            files += try decoder.decode([FilePatch].self, from: Data(output.utf8))
        }
        guard files.count == metadata.changedFiles,
              Set(files.map(\.filename)).count == files.count,
              files.allSatisfy(\.complete) else {
            throw DiffError.incomplete("GitHub omitted or truncated one or more file patches.")
        }
        let latest = try decoder.decode(
            Metadata.self, from: Data(try await execute(["api", endpoint]).utf8)
        )
        guard latest.head.sha == metadata.head.sha, latest.base.sha == metadata.base.sha else {
            throw DiffError.changed
        }
        return files.map(\.diff).joined(separator: "\n\n")
    }

    enum DiffError: LocalizedError {
        case incomplete(String)
        case changed

        var errorDescription: String? {
            switch self {
            case .incomplete(let reason):
                "Incomplete PR diff: \(reason) Review locally or split the PR. "
                    + "Automatic retries are paused for this commit; manual Retry remains available."
            case .changed:
                "The PR changed while downloading its diff. Retry to load the current version."
            }
        }
    }
}
