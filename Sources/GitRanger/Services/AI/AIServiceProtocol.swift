import Foundation

struct AIAvailabilityStatus: Sendable {
    let isAvailable: Bool
    let detail: String
    let checkedAt: Date

    init(
        isAvailable: Bool,
        detail: String,
        checkedAt: Date = Date()
    ) {
        self.isAvailable = isAvailable
        self.detail = detail
        self.checkedAt = checkedAt
    }
}

protocol AIServiceProtocol {
    var displayName: String { get }
    var requiresAPIKey: Bool { get }
    func isAvailable() async -> Bool
    func availabilityStatus() async -> AIAvailabilityStatus
    func summarize(commitMessage: String, diff: String, repoPath: URL?) async throws -> CommitSummary
    func generate(prompt: String, repoPath: URL?) async throws -> String
}

extension AIServiceProtocol {
    func availabilityStatus() async -> AIAvailabilityStatus {
        let available = await isAvailable()
        return AIAvailabilityStatus(
            isAvailable: available,
            detail: available
                ? "Connection check succeeded."
                : "Connection check failed."
        )
    }
}
