import Foundation

enum ReviewDiffScope {
    static let characterLimit = 30_000

    static func warning(for diff: String) -> String? {
        guard diff.count > characterLimit else { return nil }
        return "Partial review: only the first 30,000 of \(diff.count) diff characters "
            + "were supplied to the reviewers. Findings do not cover the entire PR."
    }

    static func promptDiff(_ diff: String) -> String {
        guard let warning = warning(for: diff) else { return diff }
        return "\(warning)\nDo not claim that unreviewed files are safe or ready to merge.\n\n"
            + String(diff.prefix(characterLimit))
    }
}
