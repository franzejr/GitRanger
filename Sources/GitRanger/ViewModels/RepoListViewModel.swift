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
    var syncErrorDetail: String?
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
            let vm = self
            Task { @MainActor in vm?.importDetail = progress }
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

    func addLocalRepo(path: URL) async {
        guard let modelContext else { return }
        isImporting = true
        importError = nil
        importStatus = "Validating repository..."

        guard gitService.isGitRepo(path: path) else {
            importError = "The selected folder is not a git repository."
            isImporting = false
            importStatus = nil
            return
        }

        do {
            importStatus = "Detecting default branch..."
            let defaultBranch = try await gitService.getDefaultBranch(repoPath: path)

            let remoteURL = await gitService.getRemoteURL(repoPath: path)
            let name = path.lastPathComponent
            let url = remoteURL ?? path.path

            let repo = Repo(
                id: UUID(),
                name: name,
                url: url,
                localPath: path.path,
                defaultBranch: defaultBranch
            )
            modelContext.insert(repo)

            importStatus = "Loading commits..."
            let commitInfos = try await gitService.getLog(
                repoPath: path, maxCount: 30
            )

            importStatus = "Saving \(commitInfos.count) commits..."
            try insertCommits(commitInfos, repo: repo, modelContext: modelContext)
            try modelContext.save()

            loadRepos()
            selectedRepoId = repo.id
        } catch {
            importError = error.localizedDescription
        }

        isImporting = false
        importStatus = nil
        importDetail = nil
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
    }

    func deleteRepo(_ repo: Repo) async {
        guard let modelContext else { return }

        // Only delete from disk if it's inside the app's managed repos directory.
        // Local repos added via "Open Local" point to the user's own folder
        // and must NOT be deleted.
        if isManagedPath(repo.localPath) {
            let localPath = URL(fileURLWithPath: repo.localPath)
            try? gitService.deleteRepo(repoPath: localPath)
        }

        if selectedRepoId == repo.id {
            selectedRepoId = nil
        }

        modelContext.delete(repo)
        try? modelContext.save()
        loadRepos()
    }

    private func isManagedPath(_ path: String) -> Bool {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.path ?? ""
        return !appSupport.isEmpty && path.hasPrefix(appSupport)
    }

    func syncRepo(_ repo: Repo) async {
        isSyncing = true
        syncError = nil
        syncErrorDetail = nil

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
            let raw = error.localizedDescription
            syncError = friendlySyncError(raw, repoName: repo.name)
            syncErrorDetail = raw
        }

        isSyncing = false
    }

    var selectedRepo: Repo? {
        repos.first { $0.id == selectedRepoId }
    }

    private func friendlySyncError(_ raw: String, repoName: String) -> String {
        let lowered = raw.lowercased()

        if lowered.contains("unstaged changes") || lowered.contains("uncommitted changes") {
            return "You have uncommitted changes in \"\(repoName)\". Commit or stash them before syncing."
        }
        if lowered.contains("could not resolve host") || lowered.contains("unable to access") {
            return "Network error syncing \"\(repoName)\". Check your internet connection."
        }
        if lowered.contains("permission denied") || lowered.contains("publickey") {
            return "SSH authentication failed for \"\(repoName)\". Check your SSH keys."
        }
        if lowered.contains("merge conflict") || lowered.contains("fix conflicts") {
            return "Merge conflicts in \"\(repoName)\". Resolve conflicts manually before syncing."
        }
        if lowered.contains("not a git repository") {
            return "\"\(repoName)\" is no longer a valid git repository."
        }

        return "Sync failed for \"\(repoName)\"."
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
        // Preserve the legacy location because persisted Repo paths point here.
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
