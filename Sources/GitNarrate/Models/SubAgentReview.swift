import Foundation
import SwiftData

@Model
final class SubAgentReview {
    @Attribute(.unique) var id: UUID
    var repoUrl: String
    var prNumber: Int
    var headSha: String
    var agentKind: String
    var reviewText: String
    var reviewedAt: Date
    var providerName: String

    init(
        repoUrl: String,
        prNumber: Int,
        headSha: String,
        agentKind: String,
        reviewText: String,
        providerName: String
    ) {
        self.id = UUID()
        self.repoUrl = repoUrl
        self.prNumber = prNumber
        self.headSha = headSha
        self.agentKind = agentKind
        self.reviewText = reviewText
        self.reviewedAt = Date()
        self.providerName = providerName
    }
}
