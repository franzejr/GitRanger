import Foundation
import SwiftData
import UserNotifications

@MainActor @Observable
final class PollService {
    var lastPollDate: Date?
    var isPolling = false
    var repoCount = 0

    private var pollTask: Task<Void, Never>?
    private var modelContext: ModelContext?
    private let gitService = GitService.shared

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        requestNotificationPermission()
        schedulePoll()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func pollNow() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.pollAllRepos()
            self?.schedulePoll()
        }
    }

    private func schedulePoll() {
        pollTask?.cancel()
        let interval = UserDefaults.standard.integer(forKey: "pollInterval")
        let pollInterval = interval > 0 ? interval : 300

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                guard !Task.isCancelled else { break }
                await self?.pollAllRepos()
            }
        }
    }

    private func pollAllRepos() async {
        guard let modelContext else { return }
        isPolling = true

        let descriptor = FetchDescriptor<Repo>()
        let repos = (try? modelContext.fetch(descriptor)) ?? []
        repoCount = repos.count

        for repo in repos {
            let repoPath = URL(fileURLWithPath: repo.localPath)
            let repoName = repo.name
            do {
                // Git operations run off-main via ShellService
                let newCount = try await gitService.pull(repoPath: repoPath)

                if newCount > 0 {
                    let newCommits = try await gitService.getLog(
                        repoPath: repoPath,
                        maxCount: newCount
                    )

                    // SwiftData mutations happen on @MainActor
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
                        modelContext.insert(commit)
                    }

                    sendNotification(repoName: repoName, newCommitCount: newCount)
                }

                repo.lastPolledAt = Date()
                repo.updatedAt = Date()
            } catch {
                print("Poll error for \(repoName): \(error.localizedDescription)")
            }
        }

        try? modelContext.save()
        lastPollDate = Date()
        isPolling = false
    }

    /// Returns true if running inside a proper app bundle (Xcode-built).
    /// UNUserNotificationCenter crashes without a bundle identifier.
    private nonisolated var hasAppBundle: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private nonisolated func requestNotificationPermission() {
        guard hasAppBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    private nonisolated func sendNotification(repoName: String, newCommitCount: Int) {
        guard hasAppBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = "New Commits in \(repoName)"
        content.body = "\(newCommitCount) new commit\(newCommitCount == 1 ? "" : "s") found."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
