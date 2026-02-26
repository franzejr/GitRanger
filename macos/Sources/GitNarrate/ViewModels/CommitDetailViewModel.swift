import Foundation
import SwiftData

@Observable
final class CommitDetailViewModel {
    var commit: Commit?
    var diff: String?
    var isLoading = false
    var isAnalyzing = false
    var analyzeError: String?

    private let gitService = GitService.shared
    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func loadDetail(commit: Commit) async {
        isLoading = true
        self.commit = commit
        diff = nil
        analyzeError = nil

        guard let repoPath = commit.repo?.localPath else {
            isLoading = false
            return
        }

        do {
            let commitDiff = try await gitService.getDiff(
                repoPath: URL(fileURLWithPath: repoPath),
                sha: commit.sha
            )
            diff = commitDiff.patch
        } catch {
            diff = "Failed to load diff: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func analyzeCommit() async {
        guard let commit, let diff else { return }

        isAnalyzing = true
        analyzeError = nil

        do {
            let provider = AIServiceFactory.activeProvider()
            let repoPath = commit.repo.map { URL(fileURLWithPath: $0.localPath) }

            let summary = try await provider.summarize(
                commitMessage: commit.message,
                diff: diff,
                repoPath: repoPath
            )

            commit.applySummary(summary)
            try? modelContext?.save()
        } catch {
            analyzeError = error.localizedDescription
        }

        isAnalyzing = false
    }

    func clear() {
        commit = nil
        diff = nil
        analyzeError = nil
    }
}
