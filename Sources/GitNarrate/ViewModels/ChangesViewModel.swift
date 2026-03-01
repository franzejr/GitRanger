import Foundation

@Observable
final class ChangesViewModel {
    var changedFiles: [ChangedFile] = []
    var selectedFile: ChangedFile?
    var fileDiff: String?
    var commitSummary = ""
    var commitDescription = ""
    var isLoading = false
    var isCommitting = false
    var isGeneratingMessage = false
    var error: String?
    var currentBranch: String?

    var stagedFiles: [ChangedFile] {
        changedFiles.filter(\.isStaged)
    }

    var unstagedFiles: [ChangedFile] {
        changedFiles.filter { !$0.isStaged }
    }

    var canCommit: Bool {
        !stagedFiles.isEmpty && !commitSummary.isEmpty && !isCommitting
    }

    private let gitService = GitService.shared

    func loadChanges(repo: Repo) async {
        isLoading = true
        error = nil

        let repoPath = URL(fileURLWithPath: repo.localPath)

        do {
            changedFiles = try await gitService.getStatus(repoPath: repoPath)
            currentBranch = await gitService.currentBranch(repoPath: repoPath)
        } catch {
            self.error = error.localizedDescription
        }

        // Refresh diff if a file is still selected
        if let selected = selectedFile {
            await refreshDiff(for: selected, repo: repo)
        }

        isLoading = false
    }

    func selectFile(_ file: ChangedFile?, repo: Repo) async {
        selectedFile = file
        guard let file else {
            fileDiff = nil
            return
        }
        await refreshDiff(for: file, repo: repo)
    }

    func toggleStaged(_ file: ChangedFile, repo: Repo) async {
        let repoPath = URL(fileURLWithPath: repo.localPath)

        do {
            if file.isStaged {
                try await gitService.unstageFile(repoPath: repoPath, path: file.path)
            } else {
                try await gitService.stageFile(repoPath: repoPath, path: file.path)
            }
            await loadChanges(repo: repo)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stageAll(repo: Repo) async {
        let repoPath = URL(fileURLWithPath: repo.localPath)
        do {
            for file in unstagedFiles {
                try await gitService.stageFile(repoPath: repoPath, path: file.path)
            }
            await loadChanges(repo: repo)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func unstageAll(repo: Repo) async {
        let repoPath = URL(fileURLWithPath: repo.localPath)
        do {
            for file in stagedFiles {
                try await gitService.unstageFile(repoPath: repoPath, path: file.path)
            }
            await loadChanges(repo: repo)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func discardChanges(_ file: ChangedFile, repo: Repo) async {
        let repoPath = URL(fileURLWithPath: repo.localPath)
        do {
            try await gitService.discardFile(repoPath: repoPath, path: file.path)
            if selectedFile?.path == file.path {
                selectedFile = nil
                fileDiff = nil
            }
            await loadChanges(repo: repo)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func commitChanges(repo: Repo) async {
        guard canCommit else { return }
        isCommitting = true
        error = nil

        let repoPath = URL(fileURLWithPath: repo.localPath)
        let desc = commitDescription.isEmpty ? nil : commitDescription

        do {
            try await gitService.commit(
                repoPath: repoPath,
                summary: commitSummary,
                description: desc
            )
            commitSummary = ""
            commitDescription = ""
            selectedFile = nil
            fileDiff = nil
            await loadChanges(repo: repo)
        } catch {
            self.error = error.localizedDescription
        }

        isCommitting = false
    }

    func generateCommitMessage(repo: Repo) async {
        guard !stagedFiles.isEmpty else { return }
        isGeneratingMessage = true
        error = nil

        let repoPath = URL(fileURLWithPath: repo.localPath)

        do {
            // Collect staged diffs
            var combinedDiff = ""
            for file in stagedFiles {
                let diff = try await gitService.diffFile(
                    repoPath: repoPath,
                    path: file.path,
                    staged: true
                )
                if !diff.isEmpty {
                    combinedDiff += "--- \(file.path) ---\n\(diff)\n\n"
                }
            }

            guard !combinedDiff.isEmpty else {
                error = "No diff content to analyze."
                isGeneratingMessage = false
                return
            }

            let prompt = PromptBuilder.buildCommitMessagePrompt(diff: combinedDiff)
            let provider = AIServiceFactory.activeProvider()
            let raw = try await provider.generate(
                prompt: prompt,
                repoPath: repoPath
            )

            let message = try PromptBuilder.parseCommitMessage(raw: raw)
            commitSummary = message.summary
            commitDescription = message.description
        } catch {
            self.error = error.localizedDescription
        }

        isGeneratingMessage = false
    }

    func clear() {
        changedFiles = []
        selectedFile = nil
        fileDiff = nil
        commitSummary = ""
        commitDescription = ""
        error = nil
        currentBranch = nil
    }

    private func refreshDiff(for file: ChangedFile, repo: Repo) async {
        let repoPath = URL(fileURLWithPath: repo.localPath)
        do {
            fileDiff = try await gitService.diffFile(
                repoPath: repoPath,
                path: file.path,
                staged: file.isStaged
            )
        } catch {
            fileDiff = nil
        }
    }
}
