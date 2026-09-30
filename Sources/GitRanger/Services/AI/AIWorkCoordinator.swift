import Foundation

/// Keeps expensive AI providers from flooding the machine with CLI processes.
///
/// Claude Code and Codex each start a local process. Running every reviewer plus
/// an unrelated narrative or commit analysis at once makes the whole app feel
/// blocked. This FIFO coordinator allows useful parallelism while bounding the
/// total amount of AI work across the app.
actor AIWorkCoordinator {
    static let shared = AIWorkCoordinator(maxConcurrentJobs: 2)

    let maxConcurrentJobs: Int
    private var activeJobs = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrentJobs: Int) {
        self.maxConcurrentJobs = max(1, maxConcurrentJobs)
    }

    func acquire() async {
        if activeJobs < maxConcurrentJobs {
            activeJobs += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            activeJobs = max(0, activeJobs - 1)
        } else {
            // The released slot is transferred directly to the next FIFO job.
            waiters.removeFirst().resume()
        }
    }
}

/// Applies the shared concurrency policy without coupling individual features
/// to the scheduler.
final class CoordinatedAIService: AIServiceProtocol {
    private let base: any AIServiceProtocol
    private let coordinator: AIWorkCoordinator

    init(
        base: any AIServiceProtocol,
        coordinator: AIWorkCoordinator = .shared
    ) {
        self.base = base
        self.coordinator = coordinator
    }

    var displayName: String { base.displayName }
    var requiresAPIKey: Bool { base.requiresAPIKey }

    func isAvailable() async -> Bool {
        await base.isAvailable()
    }

    func summarize(
        commitMessage: String,
        diff: String,
        repoPath: URL?
    ) async throws -> CommitSummary {
        await coordinator.acquire()
        do {
            let result = try await base.summarize(
                commitMessage: commitMessage,
                diff: diff,
                repoPath: repoPath
            )
            await coordinator.release()
            return result
        } catch {
            await coordinator.release()
            throw error
        }
    }

    func generate(prompt: String, repoPath: URL?) async throws -> String {
        await coordinator.acquire()
        do {
            let result = try await base.generate(
                prompt: prompt,
                repoPath: repoPath
            )
            await coordinator.release()
            return result
        } catch {
            await coordinator.release()
            throw error
        }
    }
}
