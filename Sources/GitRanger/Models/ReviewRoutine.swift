import Foundation
import SwiftData

enum RoutinePRScope: String, CaseIterable, Codable, Sendable {
    case open = "Open pull requests"
    case pendingMyReview = "Waiting for my review"
}

enum RoutinePublishingMode: String, CaseIterable, Codable, Sendable {
    case preview = "Preview only"
    case automaticComment = "Post comment automatically"
}

enum RoutineRunTrigger: String, Codable, Sendable {
    case schedule
    case manual
}

enum RoutineRunStatus: String, Codable, Sendable {
    case queued
    case loading
    case reviewing
    case aggregating
    case posting
    case completed
    case posted
    case failed
    case cancelled

    var isActive: Bool {
        switch self {
        case .queued, .loading, .reviewing, .aggregating, .posting: true
        case .completed, .posted, .failed, .cancelled: false
        }
    }

    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .loading: "Loading PR"
        case .reviewing: "Reviewing"
        case .aggregating: "Aggregating"
        case .posting: "Posting"
        case .completed: "Complete"
        case .posted: "Posted"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

enum RoutineAgentStatus: String, Codable, Sendable {
    case queued
    case reviewing
    case completed
    case failed
    case cancelled
}

struct RoutineAgentSnapshot: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    var status: RoutineAgentStatus
    var phase: String
    var providerName: String?
    var modelName: String?
    var reasoningEffort: String?
    var reviewText: String?
    var verdict: Bool?
    var error: String?
    var startedAt: Date?
    var completedAt: Date?
}

extension Array where Element == RoutineAgentSnapshot {
    func cancellingActiveAgents(
        phase: String = "Cancelled",
        at date: Date = Date()
    ) -> [RoutineAgentSnapshot] {
        map { snapshot in
            guard snapshot.status == .queued || snapshot.status == .reviewing else {
                return snapshot
            }
            var cancelled = snapshot
            cancelled.status = .cancelled
            cancelled.phase = phase
            cancelled.completedAt = date
            return cancelled
        }
    }
}

struct RoutineRunIdentity: Hashable, Sendable {
    let routineID: UUID
    let repoURL: String
    let prNumber: Int
    let headSHA: String
}

@Model
final class ReviewRoutine {
    @Attribute(.unique) var id: UUID
    var name: String
    var isEnabled: Bool
    var repoIDs: [UUID]
    var intervalMinutes: Int
    var maxPullRequestsPerRun: Int
    var scopeRawValue: String
    var skipDrafts: Bool
    var agentIDs: [String]
    var providerRawValue: String?
    var modelName: String?
    var publishingRawValue: String
    var lastRunAt: Date?
    var nextRunAt: Date
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    var scope: RoutinePRScope {
        get { RoutinePRScope(rawValue: scopeRawValue) ?? .open }
        set { scopeRawValue = newValue.rawValue }
    }

    var publishingMode: RoutinePublishingMode {
        get {
            RoutinePublishingMode(rawValue: publishingRawValue) ?? .preview
        }
        set { publishingRawValue = newValue.rawValue }
    }

    var provider: AIProvider? {
        get { providerRawValue.flatMap(AIProvider.init(rawValue:)) }
        set { providerRawValue = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        repoIDs: [UUID],
        intervalMinutes: Int = 15,
        maxPullRequestsPerRun: Int = 1,
        scope: RoutinePRScope = .open,
        skipDrafts: Bool = true,
        agentIDs: [String] = ReviewAgent.allCases.map(\.rawValue),
        provider: AIProvider? = nil,
        modelName: String? = nil,
        publishingMode: RoutinePublishingMode = .preview,
        isEnabled: Bool = true
    ) {
        let now = Date()
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.repoIDs = repoIDs
        self.intervalMinutes = max(1, intervalMinutes)
        self.maxPullRequestsPerRun = max(1, maxPullRequestsPerRun)
        self.scopeRawValue = scope.rawValue
        self.skipDrafts = skipDrafts
        self.agentIDs = agentIDs
        self.providerRawValue = provider?.rawValue
        self.modelName = modelName
        self.publishingRawValue = publishingMode.rawValue
        self.nextRunAt = now.addingTimeInterval(
            TimeInterval(max(1, intervalMinutes) * 60)
        )
        self.createdAt = now
        self.updatedAt = now
    }

    func markScheduled(from date: Date = Date()) {
        lastRunAt = date
        nextRunAt = date.addingTimeInterval(
            TimeInterval(max(1, intervalMinutes) * 60)
        )
        updatedAt = date
    }
}

@Model
final class RoutineRun {
    @Attribute(.unique) var id: UUID
    var routineID: UUID
    var routineName: String
    var repoID: UUID
    var repoName: String
    var repoURL: String
    var prNumber: Int
    var prTitle: String
    var prAuthorLogin: String?
    var prCreatedAt: Date?
    var metadataBackfillAttemptedAt: Date?
    var prURL: String
    var headSHA: String
    var triggerRawValue: String
    var statusRawValue: String
    var publishingRawValue: String
    var lastEvent: String
    var agentSnapshotsData: Data?
    var reviewComment: String?
    var errorMessage: String?
    var queuedAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var postedAt: Date?

    var trigger: RoutineRunTrigger {
        get { RoutineRunTrigger(rawValue: triggerRawValue) ?? .schedule }
        set { triggerRawValue = newValue.rawValue }
    }

    var status: RoutineRunStatus {
        get { RoutineRunStatus(rawValue: statusRawValue) ?? .queued }
        set { statusRawValue = newValue.rawValue }
    }

    var publishingMode: RoutinePublishingMode {
        get {
            RoutinePublishingMode(rawValue: publishingRawValue) ?? .preview
        }
        set { publishingRawValue = newValue.rawValue }
    }

    var agentSnapshots: [RoutineAgentSnapshot] {
        get {
            guard let agentSnapshotsData else { return [] }
            return (try? JSONDecoder().decode(
                [RoutineAgentSnapshot].self,
                from: agentSnapshotsData
            )) ?? []
        }
        set {
            agentSnapshotsData = try? JSONEncoder().encode(newValue)
        }
    }

    var identity: RoutineRunIdentity {
        RoutineRunIdentity(
            routineID: routineID,
            repoURL: repoURL,
            prNumber: prNumber,
            headSHA: headSHA
        )
    }

    var needsMetadataBackfill: Bool {
        guard metadataBackfillAttemptedAt == nil else { return false }
        guard let author = prAuthorLogin, !author.isEmpty,
              let prCreatedAt else {
            return true
        }
        let earliestSupportedDate = Date(timeIntervalSince1970: 946_684_800)
        return prCreatedAt < earliestSupportedDate || prCreatedAt > queuedAt
    }

    init(
        routine: ReviewRoutine,
        repo: Repo,
        pullRequest: PullRequest,
        trigger: RoutineRunTrigger
    ) {
        self.id = UUID()
        self.routineID = routine.id
        self.routineName = routine.name
        self.repoID = repo.id
        self.repoName = repo.name
        self.repoURL = repo.url
        self.prNumber = pullRequest.number
        self.prTitle = pullRequest.title
        self.prAuthorLogin = pullRequest.authorLogin.isEmpty
            ? nil : pullRequest.authorLogin
        self.prCreatedAt = pullRequest.createdAt
        self.prURL = pullRequest.url
        self.headSHA = pullRequest.headRefOid
        self.triggerRawValue = trigger.rawValue
        self.statusRawValue = RoutineRunStatus.queued.rawValue
        self.publishingRawValue = routine.publishingMode.rawValue
        self.lastEvent = "Waiting for an execution slot"
        self.queuedAt = Date()
    }
}

enum RoutinePublicationMarker {
    static func value(routineID: UUID, headSHA: String) -> String {
        "<!-- gitranger:routine=\(routineID.uuidString);head=\(headSHA) -->"
    }
}

enum RoutineRunPolicy {
    static func shouldEnqueue(
        _ identity: RoutineRunIdentity,
        existingRuns: [RoutineRun],
        allowRetry: Bool = false,
        now: Date = Date()
    ) -> Bool {
        if allowRetry { return true }
        let matching = existingRuns.filter { $0.identity == identity }
        guard !matching.contains(where: {
            $0.status.isActive || $0.status == .completed || $0.status == .posted || $0.status == .cancelled
        }) else { return false }
        let failures = matching.filter { $0.status == .failed }
        guard let latest = failures.max(by: { $0.queuedAt < $1.queuedAt }) else { return true }
        guard failures.count < 3,
              isTransientFailure(latest.errorMessage ?? "") else { return false }
        let delay: TimeInterval = failures.count == 1 ? 300 : 900
        return now.timeIntervalSince(latest.completedAt ?? latest.queuedAt) >= delay
    }

    static func isTransientFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        guard !GitHubPRDiffLoader.isTooLarge(lower),
              !lower.contains("incomplete pr diff") else { return false }
        return [
            "timed out", "timeout", "http 429", "http 500", "http 502", "http 503", "http 504",
            "rate limit", "connection reset", "network", "offline", "could not resolve",
            "changed while downloading", "app stopped before"
        ].contains { lower.contains($0) }
    }
}
