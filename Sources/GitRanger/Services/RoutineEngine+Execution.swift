import Foundation

actor RoutineExecutionCoordinator {
    static let shared = RoutineExecutionCoordinator(maxConcurrentRuns: 2)

    private let maxConcurrentRuns: Int
    private var activeRuns = 0
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private var waiters: [Waiter] = []

    init(maxConcurrentRuns: Int) {
        self.maxConcurrentRuns = max(1, maxConcurrentRuns)
    }

    func acquire() async throws {
        try Task.checkCancellation()
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if activeRuns < maxConcurrentRuns {
                    activeRuns += 1
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
            activeRuns = max(0, activeRuns - 1)
        } else {
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

@MainActor
extension RoutineEngine {
    func schedule(
        runID: UUID,
        request: RoutinePipelineRequest
    ) {
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await RoutineExecutionCoordinator.shared.acquire()
            } catch is CancellationError {
                self.markCancelled(runID)
                return
            } catch {
                self.fail(runID, message: error.localizedDescription)
                return
            }
            await self.execute(runID: runID, request: request)
            await RoutineExecutionCoordinator.shared.release()
        }
        activeTasks[runID] = task
    }

    func execute(
        runID: UUID,
        request: RoutinePipelineRequest
    ) async {
        guard let run = run(withID: runID) else { return }
        run.startedAt = Date()

        do {
            let output = try await RoutineReviewPipeline.shared.run(request) { [weak self] event in
                await self?.apply(event, to: runID)
            }
            try Task.checkCancellation()
            try await finish(runID: runID, request: request, output: output)
        } catch is CancellationError {
            markCancelled(runID)
        } catch {
            fail(runID, message: error.localizedDescription)
        }

        activeTasks.removeValue(forKey: runID)
    }

    func finish(
        runID: UUID,
        request: RoutinePipelineRequest,
        output: RoutinePipelineOutput
    ) async throws {
        guard let run = run(withID: runID) else { return }
        let combinedOutput = RoutinePipelineOutput(
            agents: run.agentSnapshots,
            comment: output.comment
        )
        guard !combinedOutput.hasFailures else {
            fail(
                runID,
                message: combinedOutput.failureSummary
                    ?? "One or more review agents failed. Nothing was posted."
            )
            return
        }

        let comment = RoutineReviewPipeline.buildComment(
            request: request,
            agents: combinedOutput.agents,
            coverageWarning: output.coverageWarning
        )
        run.reviewComment = comment
        try? modelContext?.save()

        guard run.publishingMode == .automaticComment else {
            complete(runID, status: .completed, event: "Review ready for preview")
            return
        }
        update(
            runID,
            status: .posting,
            event: "Checking and posting the review comment"
        )
        let marker = RoutinePublicationMarker.value(
            routineID: request.routineID,
            headSHA: request.pullRequest.headRefOid
        )
        _ = try await RoutineReviewPublisher.shared.publish(
            comment: comment,
            marker: marker,
            repository: request.repository,
            pullRequest: request.pullRequest
        )
        complete(runID, status: .posted, event: "Review posted")
    }

    func post(_ run: RoutineRun) async {
        guard run.status == .completed,
              let comment = run.reviewComment,
              let repo = repositories().first(where: { $0.id == run.repoID }) else {
            return
        }
        let (repository, pullRequest) = publicationContext(
            for: run,
            repository: repo
        )
        update(
            run.id,
            status: .posting,
            event: "Checking and posting the review comment"
        )

        do {
            let marker = RoutinePublicationMarker.value(
                routineID: run.routineID,
                headSHA: run.headSHA
            )
            _ = try await RoutineReviewPublisher.shared.publish(
                comment: comment,
                marker: marker,
                repository: repository,
                pullRequest: pullRequest
            )
            complete(run.id, status: .posted, event: "Review posted")
        } catch {
            fail(run.id, message: error.localizedDescription)
        }
    }

    private func publicationContext(
        for run: RoutineRun,
        repository repo: Repo
    ) -> (RoutineRepositoryContext, PullRequest) {
        let repository = RoutineRepositoryContext(
            id: repo.id,
            name: repo.name,
            url: repo.url,
            localPath: repo.localPath,
            githubAccount: repo.ghAccount,
            gitlabHost: repo.glHost,
            agentPrompts: repo.agentPrompts ?? [:],
            customAgents: repo.customAgents
        )
        let pullRequest = PullRequest(
            number: run.prNumber,
            title: run.prTitle,
            authorLogin: run.prAuthorLogin ?? "",
            state: "OPEN",
            headRefName: "",
            headRefOid: run.headSHA,
            baseRefName: "",
            createdAt: run.prCreatedAt ?? run.queuedAt,
            updatedAt: run.queuedAt,
            additions: 0,
            deletions: 0,
            changedFiles: 0,
            url: run.prURL,
            isDraft: false,
            reviewDecision: "",
            reviewRequests: [],
            latestReviews: []
        )
        return (repository, pullRequest)
    }

    func apply(
        _ event: RoutinePipelineEvent,
        to runID: UUID
    ) {
        guard let run = run(withID: runID) else { return }
        switch event {
        case .run(let status, let message):
            run.status = status
            run.lastEvent = message
        case .agent(let snapshot):
            var snapshots = run.agentSnapshots
            if let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) {
                snapshots[index] = snapshot
            } else {
                snapshots.append(snapshot)
            }
            run.agentSnapshots = snapshots
            run.lastEvent = "\(snapshot.name): \(snapshot.phase)"
        }
        try? modelContext?.save()
    }

    func update(
        _ runID: UUID,
        status: RoutineRunStatus,
        event: String
    ) {
        guard let run = run(withID: runID) else { return }
        run.status = status
        run.lastEvent = event
        try? modelContext?.save()
    }

    func complete(
        _ runID: UUID,
        status: RoutineRunStatus,
        event: String
    ) {
        guard let run = run(withID: runID) else { return }
        run.status = status
        run.lastEvent = event
        run.completedAt = Date()
        if status == .posted { run.postedAt = Date() }
        try? modelContext?.save()
    }

    func fail(_ runID: UUID, message: String) {
        guard let run = run(withID: runID) else { return }
        run.status = .failed
        run.lastEvent = "Review failed"
        run.errorMessage = message
        run.completedAt = Date()
        let failures = runs.filter { $0.identity == run.identity && $0.status == .failed }.count
        if !RoutineRunPolicy.isTransientFailure(message) || failures >= 3 {
            run.lastEvent = "Review failed; automatic retries paused for this commit"
        } else {
            run.lastEvent = "Review failed; automatic retry after \(failures == 1 ? 5 : 15) minutes"
        }
        try? modelContext?.save()
        activeTasks.removeValue(forKey: runID)
    }

    func markCancelled(_ runID: UUID) {
        guard let run = run(withID: runID) else { return }
        run.agentSnapshots = run.agentSnapshots.cancellingActiveAgents()
        run.status = .cancelled
        run.lastEvent = "Cancelled"
        run.completedAt = Date()
        try? modelContext?.save()
        activeTasks.removeValue(forKey: runID)
    }

}
