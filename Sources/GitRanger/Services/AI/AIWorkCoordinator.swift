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
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private var waiters: [Waiter] = []

    init(maxConcurrentJobs: Int) {
        self.maxConcurrentJobs = max(1, maxConcurrentJobs)
    }

    func acquire() async throws {
        try Task.checkCancellation()
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if activeJobs < maxConcurrentJobs {
                    activeJobs += 1
                    continuation.resume()
                } else {
                    waiters.append(Waiter(
                        id: waiterID,
                        continuation: continuation
                    ))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
        if Task.isCancelled {
            release()
            throw CancellationError()
        }
    }

    func release() {
        if waiters.isEmpty {
            activeJobs = max(0, activeJobs - 1)
        } else {
            // The released slot is transferred directly to the next FIFO job.
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        waiters.remove(at: index).continuation.resume(
            throwing: CancellationError()
        )
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
    var modelName: String { base.modelName }
    var reasoningEffort: String { base.reasoningEffort }
    var requiresAPIKey: Bool { base.requiresAPIKey }

    func isAvailable() async -> Bool {
        await base.isAvailable()
    }

    func availabilityStatus() async -> AIAvailabilityStatus {
        await base.availabilityStatus()
    }

    func summarize(
        commitMessage: String,
        diff: String,
        repoPath: URL?
    ) async throws -> CommitSummary {
        try await coordinator.acquire()
        do {
            try Task.checkCancellation()
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
        try await performGenerate(
            prompt: prompt,
            repoPath: repoPath,
            timeout: nil
        )
    }

    func generate(
        prompt: String,
        repoPath: URL?,
        timeout: TimeInterval
    ) async throws -> String {
        try await performGenerate(
            prompt: prompt,
            repoPath: repoPath,
            timeout: timeout
        )
    }

    private func performGenerate(
        prompt: String,
        repoPath: URL?,
        timeout: TimeInterval?
    ) async throws -> String {
        try await coordinator.acquire()
        do {
            try Task.checkCancellation()
            let result = if let timeout {
                try await base.generate(
                    prompt: prompt,
                    repoPath: repoPath,
                    timeout: timeout
                )
            } else {
                try await base.generate(prompt: prompt, repoPath: repoPath)
            }
            await coordinator.release()
            return result
        } catch {
            await coordinator.release()
            throw error
        }
    }
}
