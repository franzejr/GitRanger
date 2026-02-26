import Foundation
import SwiftData

@Observable
final class RepoListViewModel {
    var repos: [Repo] = []
    var selectedRepoId: UUID?
    var isImporting = false
    var importError: String?
    var isSyncing = false
    var syncError: String?
    var importStatus: String?
    var importDetail: String?

    private let gitService = GitService.shared
    private var modelContext: ModelContext?
    private var importTask: Task<Void, Never>?

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func loadRepos() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Repo>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        repos = (try? modelContext.fetch(descriptor)) ?? []
    }

    func importRepo(url: String) {
        guard let modelContext, !isImporting else { return }
        isImporting = true
        importError = nil
        importStatus = "Cloning repository..."
        importDetail = nil

        let repoId = UUID()

        importTask = Task {
            do {
                let repo = try await performImport(
                    url: url, repoId: repoId, modelContext: modelContext
                )
                loadRepos()
                selectedRepoId = repo.id
            } catch is CancellationError {
                cleanupPartialImport(repoId: repoId)
            } catch {
                importError = error.localizedDescription
                cleanupPartialImport(repoId: repoId)
            }

            isImporting = false
            importStatus = nil
            importDetail = nil
            importTask = nil
        }
    }

    private func performImport(
        url: String, repoId: UUID, modelContext: ModelContext
    ) async throws -> Repo {
        try Task.checkCancellation()
        let localPath = try await gitService.clone(
            url: url, repoId: repoId
        ) { [weak self] progress in
            DispatchQueue.main.async { self?.importDetail = progress }
        }

        try Task.checkCancellation()
        importStatus = "Detecting default branch..."
        importDetail = nil
        let defaultBranch = try await gitService.getDefaultBranch(repoPath: localPath)

        let repo = Repo(
            id: repoId,
            name: gitService.extractRepoName(url: url),
            url: url,
            localPath: localPath.path,
            defaultBranch: defaultBranch
        )
        modelContext.insert(repo)

        try Task.checkCancellation()
        importStatus = "Loading commits..."
        let commitInfos = try await gitService.getLog(
            repoPath: localPath, maxCount: 30
        )

        importStatus = "Saving \(commitInfos.count) commits..."
        try insertCommits(commitInfos, repo: repo, modelContext: modelContext)
        try modelContext.save()
        return repo
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
    }

    func deleteRepo(_ repo: Repo) async {
        guard let modelContext else { return }

        let localPath = URL(fileURLWithPath: repo.localPath)
        try? gitService.deleteRepo(repoPath: localPath)

        if selectedRepoId == repo.id {
            selectedRepoId = nil
        }

        modelContext.delete(repo)
        try? modelContext.save()
        loadRepos()
    }

    func syncRepo(_ repo: Repo) async {
        isSyncing = true
        syncError = nil

        do {
            let repoPath = URL(fileURLWithPath: repo.localPath)
            let newCount = try await gitService.pull(repoPath: repoPath)

            if newCount > 0 {
                let newCommits = try await gitService.getLog(
                    repoPath: repoPath,
                    maxCount: newCount
                )

                for info in newCommits {
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
                    modelContext?.insert(commit)
                }
            }

            repo.lastPolledAt = Date()
            repo.updatedAt = Date()
            try modelContext?.save()
            loadRepos()
        } catch {
            syncError = "Sync failed for \(repo.name): \(error.localizedDescription)"
        }

        isSyncing = false
    }

    var selectedRepo: Repo? {
        repos.first { $0.id == selectedRepoId }
    }

    // MARK: - Private

    private func insertCommits(
        _ infos: [CommitInfo], repo: Repo, modelContext: ModelContext
    ) throws {
        for info in infos {
            try Task.checkCancellation()
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
    }

    private func cleanupPartialImport(repoId: UUID) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gitnarrate")
        let repoPath = appSupport
            .appendingPathComponent("GitNarrate/repos")
            .appendingPathComponent(repoId.uuidString)
        try? FileManager.default.removeItem(at: repoPath)
    }
}
