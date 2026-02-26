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
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Commit.repo)
    var commits: [Commit] = []

    var commitCount: Int { commits.count }

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
