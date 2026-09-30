import Foundation
import SwiftData

@Model
final class Commit {
    @Attribute(.unique) var id: UUID
    var sha: String
    var message: String
    var authorName: String
    var authorEmail: String
    var committedAt: Date
    var filesChanged: Int
    var insertions: Int
    var deletions: Int

    // AI summary fields (nil until analyzed)
    var summaryOneLiner: String?
    var summaryExplanation: String?
    var summaryImpact: String?
    var summaryCategories: String? // JSON array as string
    var summaryRelatedFiles: String? // JSON array as string
    var summaryRiskNotes: String?
    var analyzedAt: Date?

    var repo: Repo?

    var isAnalyzed: Bool { analyzedAt != nil }

    var summary: CommitSummary? {
        guard let oneLiner = summaryOneLiner,
              let explanation = summaryExplanation,
              let impact = summaryImpact else {
            return nil
        }

        let categories: [String] = {
            guard let json = summaryCategories,
                  let data = json.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return array
        }()

        let relatedFiles: [String]? = {
            guard let json = summaryRelatedFiles,
                  let data = json.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return nil
            }
            return array
        }()

        return CommitSummary(
            oneLiner: oneLiner,
            explanation: explanation,
            impact: impact,
            categories: categories,
            relatedFiles: relatedFiles,
            riskNotes: summaryRiskNotes
        )
    }

    var impactLevel: ImpactLevel? {
        guard let impact = summaryImpact else { return nil }
        return ImpactLevel(rawValue: impact)
    }

    var firstLine: String {
        message.components(separatedBy: "\n").first ?? message
    }

    var shortSha: String {
        String(sha.prefix(7))
    }

    init(
        id: UUID = UUID(),
        sha: String,
        message: String,
        authorName: String,
        authorEmail: String,
        committedAt: Date,
        filesChanged: Int = 0,
        insertions: Int = 0,
        deletions: Int = 0,
        repo: Repo? = nil
    ) {
        self.id = id
        self.sha = sha
        self.message = message
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.committedAt = committedAt
        self.filesChanged = filesChanged
        self.insertions = insertions
        self.deletions = deletions
        self.repo = repo
    }

    func applySummary(_ summary: CommitSummary) {
        summaryOneLiner = summary.oneLiner
        summaryExplanation = summary.explanation
        summaryImpact = summary.impact
        summaryCategories = {
            guard let data = try? JSONEncoder().encode(summary.categories) else { return nil }
            return String(data: data, encoding: .utf8)
        }()
        summaryRelatedFiles = {
            guard let files = summary.relatedFiles,
                  let data = try? JSONEncoder().encode(files) else { return nil }
            return String(data: data, encoding: .utf8)
        }()
        summaryRiskNotes = summary.riskNotes
        analyzedAt = Date()
    }
}
