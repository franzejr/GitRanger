import SwiftData

struct PRReviewSessionKey: Hashable {
    let repoURL: String
    let prNumber: Int
    let headSHA: String

    init(repoURL: String, pullRequest: PullRequest) {
        self.repoURL = repoURL
        self.prNumber = pullRequest.number
        self.headSHA = pullRequest.headRefOid
    }
}

enum PRReviewActivity: Equatable {
    case loading
    case reviewing
}

/// Owns one review view model per pull request so background reviews are not
/// tied to whichever pull request happens to be visible.
@MainActor
@Observable
final class PRReviewSessionStore {
    private(set) var sessions: [PRReviewSessionKey: PRReviewViewModel] = [:]
    private(set) var selectedKey: PRReviewSessionKey?
    private var accessOrder: [PRReviewSessionKey] = []
    private let maxRetainedSessions: Int

    init(maxRetainedSessions: Int = 12) {
        self.maxRetainedSessions = max(1, maxRetainedSessions)
    }

    var selectedViewModel: PRReviewViewModel? {
        guard let selectedKey else { return nil }
        return sessions[selectedKey]
    }

    @discardableResult
    func select(
        _ pullRequest: PullRequest,
        repoURL: String,
        modelContext: ModelContext? = nil
    ) -> Bool {
        let key = PRReviewSessionKey(
            repoURL: repoURL,
            pullRequest: pullRequest
        )
        selectedKey = key
        markAccessed(key)

        if let existing = sessions[key] {
            existing.selectedPR = pullRequest
            if let modelContext {
                existing.setModelContext(modelContext)
            }
            return false
        }

        let viewModel = PRReviewViewModel()
        if let modelContext {
            viewModel.setModelContext(modelContext)
        }
        viewModel.prepareToLoad(pullRequest)
        sessions[key] = viewModel
        evictCompletedSessionsIfNeeded()
        return true
    }

    func activity(
        for pullRequest: PullRequest,
        repoURL: String
    ) -> PRReviewActivity? {
        let key = PRReviewSessionKey(
            repoURL: repoURL,
            pullRequest: pullRequest
        )
        return sessions[key]?.activity
    }

    func deselect() {
        selectedKey = nil
    }

    private func markAccessed(_ key: PRReviewSessionKey) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func evictCompletedSessionsIfNeeded() {
        while sessions.count > maxRetainedSessions {
            guard let key = accessOrder.first(where: {
                $0 != selectedKey && sessions[$0]?.activity == nil
            }) else {
                return
            }
            sessions.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }
}
