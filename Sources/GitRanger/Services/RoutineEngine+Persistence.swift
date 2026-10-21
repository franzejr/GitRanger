import Foundation
import SwiftData

@MainActor
extension RoutineEngine {
    func run(withID id: UUID) -> RoutineRun? {
        runs.first { $0.id == id }
    }

    func repositories() -> [Repo] {
        guard let modelContext else { return [] }
        return (try? modelContext.fetch(FetchDescriptor<Repo>())) ?? []
    }

    func loadPersistedState() {
        guard let modelContext else { return }
        let routineDescriptor = FetchDescriptor<ReviewRoutine>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let runDescriptor = FetchDescriptor<RoutineRun>(
            sortBy: [SortDescriptor(\.queuedAt, order: .reverse)]
        )
        routines = (try? modelContext.fetch(routineDescriptor)) ?? []
        runs = (try? modelContext.fetch(runDescriptor)) ?? []
    }

    func recoverInterruptedRuns() {
        var changed = false
        for run in runs {
            if run.status.isActive {
                run.status = .failed
                run.lastEvent = "Interrupted; retry from the activity view"
                run.errorMessage = "The app stopped before this run completed."
                run.completedAt = Date()
                changed = true
            }

            let phase = run.status == .cancelled ? "Cancelled" : "Interrupted"
            let normalized = run.agentSnapshots.cancellingActiveAgents(
                phase: phase
            )
            if normalized != run.agentSnapshots {
                run.agentSnapshots = normalized
                changed = true
            }
        }
        guard changed else { return }
        try? modelContext?.save()
    }

    func persistAndRefresh() {
        try? modelContext?.save()
        loadPersistedState()
    }
}
