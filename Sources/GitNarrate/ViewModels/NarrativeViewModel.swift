import Foundation
import SwiftData

@Observable
final class NarrativeViewModel {
    var narrative: String?
    var mermaidDiagram: String?
    var isLoading = false
    var isLoadingDiagram = false
    var error: String?
    var diagramError: String?
    var timespan: (from: Date, to: Date)?
    var commitCount: Int = 0

    private let gitService = GitService.shared
    private var modelContext: ModelContext?
    private var lastCommitIds: Set<UUID> = []
    private var lastNarrativeCommits: [NarrativeCommit] = []
    private var lastRepoPath: URL?
    private var repoName: String = ""

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func generateNarrative(commitIds: Set<UUID>) async {
        guard let modelContext else { return }
        guard commitIds.count >= 2, commitIds.count <= 20 else {
            error = "Select between 2 and 20 commits"
            return
        }

        isLoading = true
        error = nil
        narrative = nil
        lastCommitIds = commitIds
        commitCount = commitIds.count

        do {
            let selected = fetchSelectedCommits(
                commitIds, context: modelContext
            )

            guard let firstCommit = selected.first,
                  let lastCommit = selected.last,
                  selected.count >= 2 else {
                throw AIError.invalidResponse(
                    "Could not find selected commits"
                )
            }

            repoName = firstCommit.repo?.name ?? "Unknown"
            timespan = (
                from: firstCommit.committedAt,
                to: lastCommit.committedAt
            )

            let narrativeCommits = try await buildNarrativeCommits(
                from: selected
            )
            lastNarrativeCommits = narrativeCommits

            let prompt = PromptBuilder.buildNarrativePrompt(
                repoName: repoName,
                commits: narrativeCommits
            )

            let repoPath = firstCommit.repo.map {
                URL(fileURLWithPath: $0.localPath)
            }
            lastRepoPath = repoPath
            let provider = AIServiceFactory.activeProvider()
            let raw = try await provider.generate(
                prompt: prompt, repoPath: repoPath
            )
            narrative = raw
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func retry() async {
        guard !lastCommitIds.isEmpty else { return }
        await generateNarrative(commitIds: lastCommitIds)
    }

    func generateDiagram() async {
        guard !lastNarrativeCommits.isEmpty else { return }
        isLoadingDiagram = true
        diagramError = nil

        do {
            let prompt = PromptBuilder.buildNarrativePrompt(
                repoName: repoName,
                commits: lastNarrativeCommits,
                includeDiagram: true
            )
            let provider = AIServiceFactory.activeProvider()
            let raw = try await provider.generate(
                prompt: prompt, repoPath: lastRepoPath
            )
            parseNarrativeResponse(raw)
        } catch {
            diagramError = error.localizedDescription
        }

        isLoadingDiagram = false
    }

    func dismiss() {
        narrative = nil
        mermaidDiagram = nil
        error = nil
        diagramError = nil
        isLoading = false
        isLoadingDiagram = false
        timespan = nil
        commitCount = 0
        lastCommitIds = []
        lastNarrativeCommits = []
        lastRepoPath = nil
    }

    // MARK: - Types

    private struct CommitSnapshot: Sendable {
        let sha: String
        let message: String
        let authorName: String
        let committedAt: String
        let repoPath: String
        let filesChanged: Int
        let insertions: Int
        let deletions: Int
    }

    // MARK: - Private Helpers

    private func parseNarrativeResponse(_ raw: String) {
        let startDelimiter = "---MERMAID_START---"
        let endDelimiter = "---MERMAID_END---"

        if let startRange = raw.range(of: startDelimiter),
           let endRange = raw.range(of: endDelimiter) {
            narrative = String(raw[raw.startIndex..<startRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            mermaidDiagram = String(
                raw[startRange.upperBound..<endRange.lowerBound]
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            narrative = raw
        }
    }

    private func fetchSelectedCommits(
        _ commitIds: Set<UUID>, context: ModelContext
    ) -> [Commit] {
        let descriptor = FetchDescriptor<Commit>(
            sortBy: [SortDescriptor(\.committedAt, order: .forward)]
        )
        let allCommits = (try? context.fetch(descriptor)) ?? []
        return allCommits.filter { commitIds.contains($0.id) }
            .sorted { $0.committedAt < $1.committedAt }
    }

    private func buildNarrativeCommits(
        from selected: [Commit]
    ) async throws -> [NarrativeCommit] {
        let formatter = ISO8601DateFormatter()

        let snapshots = selected.compactMap { commit -> CommitSnapshot? in
            guard let repoPath = commit.repo?.localPath else { return nil }
            return CommitSnapshot(
                sha: commit.sha, message: commit.message,
                authorName: commit.authorName,
                committedAt: formatter.string(from: commit.committedAt),
                repoPath: repoPath,
                filesChanged: commit.filesChanged,
                insertions: commit.insertions,
                deletions: commit.deletions
            )
        }

        return try await withThrowingTaskGroup(
            of: NarrativeCommit.self
        ) { group in
            for snap in snapshots {
                group.addTask {
                    let diff = try await self.gitService.getDiff(
                        repoPath: URL(fileURLWithPath: snap.repoPath),
                        sha: snap.sha
                    )
                    return NarrativeCommit(
                        sha: snap.sha, message: snap.message,
                        authorName: snap.authorName,
                        committedAt: snap.committedAt,
                        diff: diff.patch,
                        filesChanged: snap.filesChanged,
                        insertions: snap.insertions,
                        deletions: snap.deletions
                    )
                }
            }

            var results: [NarrativeCommit] = []
            for try await commit in group {
                results.append(commit)
            }
            return results.sorted { $0.committedAt < $1.committedAt }
        }
    }
}
