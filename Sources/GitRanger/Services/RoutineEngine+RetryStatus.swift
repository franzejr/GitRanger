import Foundation

@MainActor
extension RoutineEngine {
    func retryMessage(for run: RoutineRun) -> String {
        let matching = runs.filter { $0.identity == run.identity }
        if matching.contains(where: { $0.status == .posted || $0.status == .completed }) {
            return "This commit already has a completed review. This failure is kept in the history."
        }
        if matching.contains(where: { $0.status.isActive }) {
            return "Another attempt for this commit is queued or running."
        }
        guard let latest = matching.max(by: { $0.queuedAt < $1.queuedAt }), latest.id == run.id else {
            return "A newer attempt exists. Check its result in the activity list."
        }
        guard let routine = routines.first(where: { $0.id == run.routineID }), routine.isEnabled else {
            return "This routine is paused. Use Retry to start a manual attempt."
        }
        guard !matching.contains(where: { $0.status == .cancelled }) else {
            return "Automatic retries are paused after cancellation. Use Retry to try again."
        }
        let failures = matching.filter { $0.status == .failed }.count
        guard failures < 3, RoutineRunPolicy.isTransientFailure(run.errorMessage ?? "") else {
            return "Automatic retries are paused for this commit. Use Retry manually, or wait for a new commit."
        }
        let eligibleAt = (run.completedAt ?? run.queuedAt).addingTimeInterval(failures == 1 ? 300 : 900)
        let nextPoll = max(eligibleAt, routine.nextRunAt)
        return "Automatic retry \(failures) of 2 is eligible on the next poll after "
            + nextPoll.formatted(date: .abbreviated, time: .shortened) + "."
    }
}
