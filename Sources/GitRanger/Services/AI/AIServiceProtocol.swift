import Foundation

protocol AIServiceProtocol {
    var displayName: String { get }
    var requiresAPIKey: Bool { get }
    func isAvailable() async -> Bool
    func summarize(commitMessage: String, diff: String, repoPath: URL?) async throws -> CommitSummary
    func generate(prompt: String, repoPath: URL?) async throws -> String
}
