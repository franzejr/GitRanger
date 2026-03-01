import SwiftUI

// MARK: - Markdown Rendering

extension PRReviewView {
    private enum MarkdownBlock {
        case line(String)
        case code(String)
        case empty
    }

    func markdownView(_ text: String) -> some View {
        let blocks = parseMarkdownBlocks(text)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .empty:
                    Spacer().frame(height: 4)
                case .code(let code):
                    codeBlockView(code)
                case .line(let line):
                    markdownLine(line)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func parseMarkdownBlocks(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var inCodeBlock = false
        var codeLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                codeLines.append(line)
            } else if trimmed.isEmpty {
                blocks.append(.empty)
            } else {
                blocks.append(.line(trimmed))
            }
        }

        if !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }

        return blocks
    }

    private func codeBlockView(_ code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.quaternary)
        )
    }

    @ViewBuilder
    private func markdownLine(_ line: String) -> some View {
        if line.hasPrefix("# ") {
            Text(inlineMarkdown(String(line.dropFirst(2))))
                .font(.title2.bold())
                .padding(.top, 4)
        } else if line.hasPrefix("## ") {
            Text(inlineMarkdown(String(line.dropFirst(3))))
                .font(.title3.bold())
                .padding(.top, 4)
        } else if line.hasPrefix("### ") {
            Text(inlineMarkdown(String(line.dropFirst(4))))
                .font(.headline)
                .padding(.top, 2)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("\u{2022}")
                    .foregroundStyle(.secondary)
                Text(inlineMarkdown(String(line.dropFirst(2))))
                    .font(.body)
                    .lineSpacing(3)
            }
            .padding(.leading, 8)
        } else if line.match(#"^\d+\. "#) {
            numberedListItem(line)
        } else {
            Text(inlineMarkdown(line))
                .font(.body)
                .lineSpacing(3)
        }
    }

    private func numberedListItem(_ line: String) -> some View {
        let parts = line.split(separator: ".", maxSplits: 1)
        let number = parts.first.map(String.init) ?? ""
        let content = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespaces)
            : ""
        return HStack(alignment: .top, spacing: 6) {
            Text("\(number).")
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            Text(inlineMarkdown(content))
                .font(.body)
                .lineSpacing(3)
        }
        .padding(.leading, 4)
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options))
            ?? AttributedString(text)
    }
}
