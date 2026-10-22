import Foundation
import SwiftData

struct RoutineDraft: Sendable {
    var id: UUID?
    var name: String
    var repoIDs: [UUID]
    var intervalMinutes: Int
    var maxPullRequestsPerRun: Int
    var scope: RoutinePRScope
    var skipDrafts: Bool
    var agentIDs: [String]
    var provider: AIProvider?
    var modelName: String?
    var publishingMode: RoutinePublishingMode
    var isEnabled: Bool
}

@MainActor
@Observable
final class RoutineEngine {
    var routines: [ReviewRoutine] = []
    var runs: [RoutineRun] = []
    var isPolling = false
    var lastPollDate: Date?
    var error: String?
    var retryingRunIDs: Set<UUID> = []

    var activeRuns: [RoutineRun] {
        runs.filter { $0.status.isActive }
    }

    var modelContext: ModelContext?
    var schedulerTask: Task<Void, Never>?
    var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var isStarted = false
    private var backgroundActivity: NSObjectProtocol?

    nonisolated init() {}

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        guard !isStarted else { return }
        isStarted = true
        loadPersistedState()
        recoverInterruptedRuns()
        updateBackgroundActivity()
        schedulePolling()
        Task { [weak self] in
            await self?.backfillMissingRunMetadata()
        }
    }

    func stop() {
        schedulerTask?.cancel()
        schedulerTask = nil
        for task in activeTasks.values { task.cancel() }
        activeTasks.removeAll()
        endBackgroundActivity()
        isStarted = false
    }

    func refresh() {
        loadPersistedState()
    }

    func save(_ draft: RoutineDraft) {
        guard let modelContext else { return }
        let routine: ReviewRoutine

        if let id = draft.id {
            guard let existing = routines.first(where: { $0.id == id }) else {
                error = "The routine could not be found. Refresh and try editing it again."
                return
            }
            routine = existing
            routine.name = draft.name
            routine.repoIDs = draft.repoIDs
            routine.intervalMinutes = max(1, draft.intervalMinutes)
            routine.maxPullRequestsPerRun = max(
                1,
                draft.maxPullRequestsPerRun
            )
            routine.scope = draft.scope
            routine.skipDrafts = draft.skipDrafts
            routine.agentIDs = draft.agentIDs
            routine.provider = draft.provider
            routine.modelName = draft.modelName
            routine.publishingMode = draft.publishingMode
            routine.isEnabled = draft.isEnabled
            routine.nextRunAt = Date().addingTimeInterval(
                TimeInterval(routine.intervalMinutes * 60)
            )
            routine.updatedAt = Date()
        } else {
            routine = ReviewRoutine(
                name: draft.name,
                repoIDs: draft.repoIDs,
                intervalMinutes: draft.intervalMinutes,
                maxPullRequestsPerRun: draft.maxPullRequestsPerRun,
                scope: draft.scope,
                skipDrafts: draft.skipDrafts,
                agentIDs: draft.agentIDs,
                provider: draft.provider,
                modelName: draft.modelName,
                publishingMode: draft.publishingMode,
                isEnabled: draft.isEnabled
            )
            modelContext.insert(routine)
        }

        persistAndRefresh()
        updateBackgroundActivity()
    }

    func setEnabled(_ enabled: Bool, for routine: ReviewRoutine) {
        routine.isEnabled = enabled
        routine.updatedAt = Date()
        if enabled, routine.nextRunAt < Date() {
            routine.nextRunAt = Date()
        }
        persistAndRefresh()
        updateBackgroundActivity()
    }

    func setAutomaticPosting(
        _ enabled: Bool,
        for routine: ReviewRoutine
    ) {
        routine.publishingMode = enabled ? .automaticComment : .preview
        routine.updatedAt = Date()
        persistAndRefresh()
    }

    func delete(_ routine: ReviewRoutine) {
        guard let modelContext else { return }
        for run in runs where run.routineID == routine.id {
            activeTasks[run.id]?.cancel()
            activeTasks.removeValue(forKey: run.id)
            modelContext.delete(run)
        }
        modelContext.delete(routine)
        persistAndRefresh()
        updateBackgroundActivity()
    }

    func runNow(_ routine: ReviewRoutine) async {
        await discoverPullRequests(for: routine, trigger: .manual)
    }

    func pollNow() async {
        guard !isPolling else { return }
        isPolling = true
        error = nil
        let enabled = routines.filter(\.isEnabled)
        for routine in enabled {
            await discoverPullRequests(for: routine, trigger: .manual)
        }
        lastPollDate = Date()
        isPolling = false
    }

    func cancel(_ run: RoutineRun) {
        activeTasks[run.id]?.cancel()
        activeTasks.removeValue(forKey: run.id)
        run.agentSnapshots = run.agentSnapshots.cancellingActiveAgents()
        run.status = .cancelled
        run.lastEvent = "Cancelled by user"
        run.completedAt = Date()
        persistAndRefresh()
    }

    func retry(_ run: RoutineRun) async {
        await enqueueRetry(run, agentIDs: nil, seedSnapshots: [])
    }

    func retryFailedAgents(_ run: RoutineRun) async {
        let retryIDs = run.agentSnapshots.compactMap { snapshot in
            snapshot.status == .completed ? nil : snapshot.id
        }
        guard !retryIDs.isEmpty else { return }
        let retrySnapshots = run.agentSnapshots.map { snapshot in
            var retry = snapshot
            if snapshot.status == .completed {
                retry.phase = "Reused from previous attempt"
            } else {
                retry.status = .queued
                retry.phase = "Queued for retry"
                retry.reviewText = nil
                retry.verdict = nil
                retry.error = nil
                retry.startedAt = nil
                retry.completedAt = nil
            }
            return retry
        }
        await enqueueRetry(
            run,
            agentIDs: retryIDs,
            seedSnapshots: retrySnapshots
        )
    }

    private func enqueueRetry(
        _ run: RoutineRun,
        agentIDs: [String]?,
        seedSnapshots: [RoutineAgentSnapshot]
    ) async {
        guard retryingRunIDs.insert(run.id).inserted else { return }
        defer { retryingRunIDs.remove(run.id) }
        guard let routine = routines.first(where: { $0.id == run.routineID }),
              let repo = repositories().first(where: { $0.id == run.repoID }) else {
            return
        }
        let pullRequests = try? await fetchPullRequests(
            for: repo,
            scope: routine.scope
        )
        guard let pullRequest = pullRequests?.first(where: {
            $0.number == run.prNumber && $0.headRefOid == run.headSHA
        }) else {
            error = "The pull request head changed or is no longer available."
            return
        }
        enqueue(
            routine: routine,
            repo: repo,
            pullRequest: pullRequest,
            trigger: .manual,
            allowRetry: true,
            agentIDs: agentIDs,
            seedSnapshots: seedSnapshots
        )
    }

    private func updateBackgroundActivity() {
        let hasEnabledRoutine = routines.contains { $0.isEnabled }
        if hasEnabledRoutine, backgroundActivity == nil {
            backgroundActivity = ProcessInfo.processInfo.beginActivity(
                options: [.background],
                reason: "Monitor pull requests for enabled review routines"
            )
        } else if !hasEnabledRoutine {
            endBackgroundActivity()
        }
    }

    private func endBackgroundActivity() {
        guard let backgroundActivity else { return }
        ProcessInfo.processInfo.endActivity(backgroundActivity)
        self.backgroundActivity = nil
    }

}
