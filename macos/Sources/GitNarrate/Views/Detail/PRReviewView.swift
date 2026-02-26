import SwiftUI
import AppKit

private extension String {
    func match(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}

struct PRReviewView: View {
    @Bindable var viewModel: PRReviewViewModel
    var repo: Repo?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            prHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.isLoading && viewModel.review == nil && viewModel.diff == nil {
                        ProgressView("Loading PR...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 40)
                    } else if let error = viewModel.error, viewModel.review == nil, viewModel.diff == nil {
                        errorState(error)
                    } else {
                        reviewSection
                        diffSection
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Header

    private var prHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let pr = viewModel.selectedPR {
                    HStack(spacing: 6) {
                        Text("#\(pr.number)")
                            .font(.system(.headline, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Text(pr.title)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        Text(pr.authorLogin)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(pr.headRefName) -> \(pr.baseRefName)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.blue)

                        if pr.changedFiles > 0 {
                            Text("\(pr.changedFiles) files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if pr.additions > 0 {
                            Text("+\(pr.additions)")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        if pr.deletions > 0 {
                            Text("-\(pr.deletions)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Spacer()

            Button {
                viewModel.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Review Section

    @ViewBuilder
    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI Review")
                    .font(.headline)

                Spacer()

                if viewModel.isCached {
                    Text("Cached")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                if let review = viewModel.review {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(review, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Re-run Review") {
                        guard let repo else { return }
                        Task { await viewModel.generateReview(repo: repo) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isLoading)
                }
            }

            if viewModel.isLoading && viewModel.review == nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating review...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let error = viewModel.error, viewModel.review == nil {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)

                Button("Retry") {
                    guard let repo else { return }
                    Task { await viewModel.generateReview(repo: repo) }
                }
                .buttonStyle(.bordered)
            } else if let review = viewModel.review {
                markdownView(review)
            } else {
                Button("Generate AI Review") {
                    guard let repo else { return }
                    Task { await viewModel.generateReview(repo: repo) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Diff Section

    @ViewBuilder
    private var diffSection: some View {
        if let diff = viewModel.diff, !diff.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Diff")
                    .font(.headline)

                GroupBox {
                    DiffView(diff: diff)
                }
            }
        }
    }

    // MARK: - Markdown

    private func markdownView(_ text: String) -> some View {
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

    private enum MarkdownBlock {
        case line(String)
        case code(String)
        case empty
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

        // Unclosed code block
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
            let parts = line.split(separator: ".", maxSplits: 1)
            let number = parts.first.map(String.init) ?? ""
            let content = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            HStack(alignment: .top, spacing: 6) {
                Text("\(number).")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .trailing)
                Text(inlineMarkdown(content))
                    .font(.body)
                    .lineSpacing(3)
            }
            .padding(.leading, 4)
        } else {
            Text(inlineMarkdown(line))
                .font(.body)
                .lineSpacing(3)
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options))
            ?? AttributedString(text)
    }

    // MARK: - Error

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                guard let repo, let pr = viewModel.selectedPR else { return }
                Task { await viewModel.loadPR(pr, repo: repo) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
