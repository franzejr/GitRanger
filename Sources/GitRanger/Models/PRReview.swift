import Foundation
import SwiftData

@Model
final class PRReview {
    @Attribute(.unique) var id: UUID
    var repoUrl: String
    var prNumber: Int
    var headSha: String
    var reviewText: String
    var reviewedAt: Date
    var providerName: String
    var secondReviewText: String?

    init(
        repoUrl: String,
        prNumber: Int,
        headSha: String,
        reviewText: String,
        providerName: String
    ) {
        self.id = UUID()
        self.repoUrl = repoUrl
        self.prNumber = prNumber
        self.headSha = headSha
        self.reviewText = reviewText
        self.reviewedAt = Date()
        self.providerName = providerName
    }
}
