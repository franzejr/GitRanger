import Foundation
import SwiftData

struct CommitFilters {
    var author: String = ""
    var since: Date?
    var until: Date?
    var limit: Int = 50
    var offset: Int = 0
}

@Observable
final class CommitListViewModel {
    var commits: [Commit] = []
    var total: Int = 0
    var isLoading = false
    var filters = CommitFilters()
    var checkedCommitIds: Set<UUID> = []
    var currentRepoId: UUID?
    var branches: [String] = []
    var selectedBranch: String = ""
    var isLoadingBranches = false
    var isLoadingMore = false

    private var modelContext: ModelContext?
    private let gitService = GitService.shared

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func loadCommits(repoId: UUID) {
        guard let modelContext else { return }
        isLoading = true
        currentRepoId = repoId
        checkedCommitIds = []

        let predicate = buildPredicate(repoId: repoId)

        // Count total
        let countDescriptor = FetchDescriptor<Commit>(predicate: predicate)
        total = (try? modelContext.fetchCount(countDescriptor)) ?? 0

        // Fetch page
        var descriptor = FetchDescriptor<Commit>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.committedAt, order: .reverse)]
        )
        descriptor.fetchLimit = filters.limit
        descriptor.fetchOffset = filters.offset

        commits = (try? modelContext.fetch(descriptor)) ?? []
        isLoading = false
    }

    func loadMore() {
        guard let repoId = currentRepoId, let modelContext else { return }
        filters.offset += filters.limit

        let predicate = buildPredicate(repoId: repoId)

        var descriptor = FetchDescriptor<Commit>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.committedAt, order: .reverse)]
        )
        descriptor.fetchLimit = filters.limit
        descriptor.fetchOffset = filters.offset

        let moreCommits = (try? modelContext.fetch(descriptor)) ?? []
        commits.append(contentsOf: moreCommits)
    }

    func setFilters(_ newFilters: CommitFilters) {
        filters = newFilters
        filters.offset = 0
        if let repoId = currentRepoId {
            loadCommits(repoId: repoId)
        }
    }

    func toggleCheck(_ commitId: UUID) {
        if checkedCommitIds.contains(commitId) {
            checkedCommitIds.remove(commitId)
        } else {
            checkedCommitIds.insert(commitId)
        }
    }

    func clearChecked() {
        checkedCommitIds = []
    }

    var hasMore: Bool {
        commits.count < total
    }

    var checkedCount: Int {
        checkedCommitIds.count
    }

    var canGenerateNarrative: Bool {
        checkedCount >= 2 && checkedCount <= 20
    }

    func loadMoreFromGit(repo: Repo) async {
        guard let modelContext, !isLoadingMore else { return }
        isLoadingMore = true

        let repoPath = URL(fileURLWithPath: repo.localPath)
        let skipCount = total

        do {
            let branch = selectedBranch.isEmpty ? nil : selectedBranch
            let commitInfos = try await gitService.getLog(
                repoPath: repoPath,
                branch: branch,
                maxCount: 50,
                skip: skipCount
            )

            guard !commitInfos.isEmpty else {
                isLoadingMore = false
                return
            }

            // Only insert commits we don't already have
            let repoId = repo.id
            let existingDescriptor = FetchDescriptor<Commit>(
                predicate: #Predicate { $0.repo?.id == repoId }
            )
            let existingShas = Set(
                (try? modelContext.fetch(existingDescriptor))?.map(\.sha) ?? []
            )

            var inserted = 0
            for info in commitInfos where !existingShas.contains(info.sha) {
                let commit = Commit(
                    sha: info.sha,
                    message: info.message,
                    authorName: info.authorName,
                    authorEmail: info.authorEmail,
                    committedAt: info.date,
                    filesChanged: info.filesChanged,
                    insertions: info.insertions,
                    deletions: info.deletions,
                    repo: repo
                )
                modelContext.insert(commit)
                inserted += 1
            }

            if inserted > 0 {
                try modelContext.save()
                loadCommits(repoId: repo.id)
            }
        } catch {
            // Silently fail — we're at the end of history
        }

        isLoadingMore = false
    }

    func loadBranches(repo: Repo) async {
        isLoadingBranches = true
        let repoPath = URL(fileURLWithPath: repo.localPath)
        branches = (try? await gitService.listBranches(repoPath: repoPath)) ?? []
        if selectedBranch.isEmpty || !branches.contains(selectedBranch) {
            selectedBranch = repo.defaultBranch
        }
        isLoadingBranches = false
    }

    func switchBranch(_ branch: String, repo: Repo) async {
        guard let modelContext else { return }
        selectedBranch = branch
        isLoading = true
        checkedCommitIds = []

        let repoPath = URL(fileURLWithPath: repo.localPath)

        do {
            let commitInfos = try await gitService.getLog(
                repoPath: repoPath,
                branch: branch,
                maxCount: 500
            )

            // Delete existing commits for this repo
            let repoId = repo.id
            let existing = try modelContext.fetch(
                FetchDescriptor<Commit>(predicate: #Predicate { $0.repo?.id == repoId })
            )
            for commit in existing {
                modelContext.delete(commit)
            }

            // Insert commits from the new branch
            for info in commitInfos {
                let commit = Commit(
                    sha: info.sha,
                    message: info.message,
                    authorName: info.authorName,
                    authorEmail: info.authorEmail,
                    committedAt: info.date,
                    filesChanged: info.filesChanged,
                    insertions: info.insertions,
                    deletions: info.deletions,
                    repo: repo
                )
                modelContext.insert(commit)
            }

            try modelContext.save()
            loadCommits(repoId: repo.id)
        } catch {
            isLoading = false
        }
    }

    // MARK: - Predicate Building

    /// Builds a single predicate that correctly combines all active filters.
    /// SwiftData predicates can't be dynamically composed, so we use
    /// explicit branches for each filter combination.
    private func buildPredicate(repoId: UUID) -> Predicate<Commit> {
        let hasAuthor = !filters.author.isEmpty
        let hasSince = filters.since != nil
        let hasUntil = filters.until != nil

        switch (hasAuthor, hasSince, hasUntil) {
        case (false, false, false):
            return #Predicate<Commit> { commit in
                commit.repo?.id == repoId
            }

        case (true, false, false):
            let author = filters.author
            return #Predicate<Commit> { commit in
                commit.repo?.id == repoId &&
                (commit.authorName.localizedStandardContains(author) ||
                 commit.authorEmail.localizedStandardContains(author))
            }

        case (false, true, false):
            let since = filters.since!
            return #Predicate<Commit> { commit in
                commit.repo?.id == repoId &&
                commit.committedAt >= since
            }

        case (false, false, true):
            let until = filters.until!
            return #Predicate<Commit> { commit in
                commit.repo?.id == repoId &&
                commit.committedAt <= until
            }

        case (true, true, false):
            let author = filters.author
            let since = filters.since!
            return #Predicate<Commit> { commit in
                commit.repo?.id == repoId &&
                (commit.authorName.localizedStandardContains(author) ||
                 commit.authorEmail.localizedStandardContains(author)) &&
                commit.committedAt >= since
            }

        case (true, false, true):
            let author = filters.author
            let until = filters.until!
            return #Predicate<Commit> { commit in
                commit.repo?.id == repoId &&
                (commit.authorName.localizedStandardContains(author) ||
                 commit.authorEmail.localizedStandardContains(author)) &&
                commit.committedAt <= until
            }

        case (false, true, true):
            let since = filters.since!
            let until = filters.until!
            return #Predicate<Commit> { commit in
                commit.repo?.id == repoId &&
                commit.committedAt >= since &&
                commit.committedAt <= until
            }

        case (true, true, true):
            let author = filters.author
            let since = filters.since!
            let until = filters.until!
            return #Predicate<Commit> { commit in
                commit.repo?.id == repoId &&
                (commit.authorName.localizedStandardContains(author) ||
                 commit.authorEmail.localizedStandardContains(author)) &&
                commit.committedAt >= since &&
                commit.committedAt <= until
            }
        }
    }
}
