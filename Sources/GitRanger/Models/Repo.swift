import Foundation
import SwiftData

@Model
final class Repo {
    @Attribute(.unique) var id: UUID
    var name: String
    @Attribute(.unique) var url: String
    var localPath: String
    var defaultBranch: String
    var lastPolledAt: Date?
    var reviewPrompt: String?
    var ghAccount: String?
    var glHost: String?
    var agentPrompts: [String: String]?
    var disabledAgents: [String]?
    var customAgentsData: Data?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Commit.repo)
    var commits: [Commit] = []

    var commitCount: Int { commits.count }

    var customAgents: [CustomReviewAgent] {
        get {
            guard let data = customAgentsData else { return [] }
            return (try? JSONDecoder().decode([CustomReviewAgent].self, from: data)) ?? []
        }
        set {
            customAgentsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        url: String,
        localPath: String,
        defaultBranch: String = "main",
        lastPolledAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.localPath = localPath
        self.defaultBranch = defaultBranch
        self.lastPolledAt = lastPolledAt
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
