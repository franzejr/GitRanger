import Foundation

// MARK: - Log Parsing

extension GitService {
    struct StatResult {
        let filesChanged: Int
        let insertions: Int
        let deletions: Int

        static let zero = StatResult(
            filesChanged: 0, insertions: 0, deletions: 0
        )
    }

    func parseLogOutput(
        _ output: String,
        separator: String
    ) -> [CommitInfo] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        var commits: [CommitInfo] = []
        let lines = output.components(separatedBy: "\n")
        var lineIndex = 0

        while lineIndex < lines.count {
            guard let commit = parseNextCommit(
                lines: lines, index: &lineIndex,
                separator: separator,
                dateFormatter: dateFormatter
            ) else {
                lineIndex += 1
                continue
            }
            commits.append(commit)
        }

        return commits
    }

    private func parseNextCommit(
        lines: [String], index lineIndex: inout Int,
        separator: String, dateFormatter: ISO8601DateFormatter
    ) -> CommitInfo? {
        let line = lines[lineIndex]
        guard line.contains(separator) else { return nil }

        let parts = line.components(separatedBy: separator)
        guard parts.count >= 5 else { return nil }

        var statBlock = parts.count > 5 ? parts[5] : ""
        lineIndex += 1
        while lineIndex < lines.count
                && !lines[lineIndex].contains(separator) {
            statBlock += "\n" + lines[lineIndex]
            lineIndex += 1
        }

        let stat = parseStatBlock(statBlock)
        return CommitInfo(
            sha: parts[0], message: parts[1],
            authorName: parts[2], authorEmail: parts[3],
            date: dateFormatter.date(from: parts[4]) ?? Date(),
            filesChanged: stat.filesChanged,
            insertions: stat.insertions,
            deletions: stat.deletions
        )
    }

    private func parseStatBlock(_ block: String) -> StatResult {
        let pattern = #"(\d+) files? changed"#
            + #"(?:, (\d+) insertions?\(\+\))?"#
            + #"(?:, (\d+) deletions?\(-\))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: block,
                  range: NSRange(block.startIndex..., in: block)
              ) else {
            return .zero
        }

        func intAt(_ idx: Int) -> Int {
            guard idx < match.numberOfRanges,
                  let range = Range(
                      match.range(at: idx), in: block
                  ) else { return 0 }
            return Int(block[range]) ?? 0
        }

        return StatResult(
            filesChanged: intAt(1),
            insertions: intAt(2),
            deletions: intAt(3)
        )
    }
}
