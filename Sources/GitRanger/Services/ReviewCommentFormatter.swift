import Foundation

enum ReviewCommentFormatter {
    static func header(
        mode: String,
        agentCount: Int,
        headSHA: String
    ) -> [String] {
        [
            "## AI Code Review Summary",
            "",
            "> **Mode:** \(mode) · **Agents:** \(agentCount) · "
                + "**Head:** `\(String(headSHA.prefix(7)))`",
            ""
        ]
    }

    static func metadata(
        provider: String,
        model: String,
        reasoningEffort: String
    ) -> String {
        "_\(provider) · \(model) · effort: \(reasoningEffort)_"
    }
}
