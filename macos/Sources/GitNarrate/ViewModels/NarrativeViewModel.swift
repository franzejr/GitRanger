import Foundation
import SwiftData

@Observable
final class NarrativeViewModel {
    var narrative: String?
    var isLoading = false
    var error: String?
    var timespan: (from: Date, to: Date)?
    var commitCount: Int = 0

    private let gitService = GitService.shared
    private var modelContext: ModelContext?
    private var lastCommitIds: Set<UUID> = []
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
            // Fetch commits
            let descriptor = FetchDescriptor<Commit>(
                sortBy: [SortDescriptor(\.committedAt, order: .forward)]
            )
            let allCommits = (try? modelContext.fetch(descriptor)) ?? []
            let selected = allCommits.filter { commitIds.contains($0.id) }
                .sorted { $0.committedAt < $1.committedAt }

            guard let firstCommit = selected.first,
                  let lastCommit = selected.last,
                  selected.count >= 2 else {
                throw AIError.invalidResponse("Could not find selected commits")
            }

            repoName = firstCommit.repo?.name ?? "Unknown"
            timespan = (from: firstCommit.committedAt, to: lastCommit.committedAt)

            // Get diffs
            var narrativeCommits: [NarrativeCommit] = []
            for commit in selected {
                guard let repoPath = commit.repo?.localPath else { continue }
                let diff = try await gitService.getDiff(
                    repoPath: URL(fileURLWithPath: repoPath),
                    sha: commit.sha
                )
                let formatter = ISO8601DateFormatter()
                narrativeCommits.append(NarrativeCommit(
                    sha: commit.sha,
                    message: commit.message,
                    authorName: commit.authorName,
                    committedAt: formatter.string(from: commit.committedAt),
                    diff: diff.patch,
                    filesChanged: commit.filesChanged,
                    insertions: commit.insertions,
                    deletions: commit.deletions
                ))
            }

            let prompt = PromptBuilder.buildNarrativePrompt(
                repoName: repoName,
                commits: narrativeCommits
            )

            let repoPath = firstCommit.repo.map { URL(fileURLWithPath: $0.localPath) }
            let provider = AIServiceFactory.activeProvider()
            narrative = try await provider.generate(prompt: prompt, repoPath: repoPath)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func retry() async {
        guard !lastCommitIds.isEmpty else { return }
        await generateNarrative(commitIds: lastCommitIds)
    }

    func dismiss() {
        narrative = nil
        error = nil
        isLoading = false
        timespan = nil
        commitCount = 0
        lastCommitIds = []
    }
}
