import Foundation
import SwiftData

// MARK: - Cache Operations

extension PRReviewViewModel {
    struct SubAgentCacheKey {
        let repoUrl: String
        let prNumber: Int
        let headSha: String
        let agentKind: String
        let reviewText: String
        let providerName: String
    }

    func findCachedReview(
        repoUrl: String, prNumber: Int, headSha: String
    ) -> PRReview? {
        guard let modelContext else { return nil }
        do {
            var descriptor = FetchDescriptor<PRReview>(
                predicate: #Predicate { review in
                    review.repoUrl == repoUrl
                        && review.prNumber == prNumber
                        && review.headSha == headSha
                }
            )
            descriptor.fetchLimit = 1
            return try modelContext.fetch(descriptor).first
        } catch {
            return nil
        }
    }

    func updateCachedSecondReview(
        repoUrl: String,
        prNumber: Int,
        headSha: String,
        secondReviewText: String
    ) {
        guard let cached = findCachedReview(
            repoUrl: repoUrl, prNumber: prNumber, headSha: headSha
        ) else { return }
        cached.secondReviewText = secondReviewText
        try? modelContext?.save()
    }

    func saveReview(
        repoUrl: String,
        prNumber: Int,
        headSha: String,
        reviewText: String,
        providerName: String
    ) {
        guard let modelContext else { return }
        let review = PRReview(
            repoUrl: repoUrl,
            prNumber: prNumber,
            headSha: headSha,
            reviewText: reviewText,
            providerName: providerName
        )
        modelContext.insert(review)
        try? modelContext.save()
    }

    func loadCachedSubAgentReviews(
        repoUrl: String, prNumber: Int, headSha: String
    ) {
        guard let modelContext else { return }
        do {
            let descriptor = FetchDescriptor<SubAgentReview>(
                predicate: #Predicate { review in
                    review.repoUrl == repoUrl
                        && review.prNumber == prNumber
                        && review.headSha == headSha
                }
            )
            for cached in try modelContext.fetch(descriptor) {
                loadCachedAgent(cached)
            }
        } catch { }
    }

    private func loadCachedAgent(_ cached: SubAgentReview) {
        if let agent = ReviewAgent(rawValue: cached.agentKind) {
            agentReviews[agent] = cached.reviewText
            agentCached.insert(agent)
            agentVerdicts[agent] = Self.parseVerdict(
                cached.reviewText
            )
        } else if cached.agentKind.hasPrefix("custom_") {
            let customId = String(
                cached.agentKind.dropFirst("custom_".count)
            )
            customAgentReviews[customId] = cached.reviewText
            customAgentCached.insert(customId)
            customAgentVerdicts[customId] = Self.parseVerdict(
                cached.reviewText
            )
        }
    }

    func saveSubAgentReview(_ key: SubAgentCacheKey) {
        guard let modelContext else { return }
        let repoUrl = key.repoUrl
        let prNumber = key.prNumber
        let headSha = key.headSha
        let agentKind = key.agentKind

        let descriptor = FetchDescriptor<SubAgentReview>(
            predicate: #Predicate { review in
                review.repoUrl == repoUrl
                    && review.prNumber == prNumber
                    && review.headSha == headSha
                    && review.agentKind == agentKind
            }
        )
        let existingReviews = (try? modelContext.fetch(
            descriptor
        )) ?? []
        for existing in existingReviews {
            modelContext.delete(existing)
        }

        let review = SubAgentReview(
            repoUrl: key.repoUrl,
            prNumber: key.prNumber,
            headSha: key.headSha,
            agentKind: key.agentKind,
            reviewText: key.reviewText,
            providerName: key.providerName
        )
        modelContext.insert(review)
        try? modelContext.save()
    }
}
