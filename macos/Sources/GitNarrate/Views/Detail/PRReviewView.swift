import AppKit
import SwiftUI

private extension String {
    func match(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}

private enum ReviewTab: String, CaseIterable {
    case review = "Review"
    case secondReview = "Second Review"
}

struct PRReviewView: View {
    @Bindable var viewModel: PRReviewViewModel
    var repo: Repo?
    @State private var copied = false
    @State private var selectedTab: ReviewTab = .review

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
                        reviewTabContent
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

    // MARK: - Review Tabs

    @ViewBuilder
    private var reviewTabContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            reviewTabHeader

            switch selectedTab {
            case .review:
                firstReviewContent
            case .secondReview:
                secondReviewContent
            }
        }
    }

    private var reviewTabHeader: some View {
        HStack {
            Picker("", selection: $selectedTab) {
                ForEach(ReviewTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            Spacer()

            if viewModel.isCached {
                Text("Cached")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }

            copyButton
        }
    }

    @ViewBuilder
    private var copyButton: some View {
        let textToCopy: String? = selectedTab == .review
            ? viewModel.review
            : viewModel.secondReview

        if let text = textToCopy {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                Label(
                    copied ? "Copied!" : "Copy",
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - First Review

    @ViewBuilder
    private var firstReviewContent: some View {
        if viewModel.isLoading && viewModel.review == nil {
            reviewLoadingState("Generating review...")
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

            Button("Re-run Review") {
                guard let repo else { return }
                Task { await viewModel.generateReview(repo: repo) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoading)
            .padding(.top, 4)
        } else {
            Button("Generate AI Review") {
                guard let repo else { return }
                Task { await viewModel.generateReview(repo: repo) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Second Review

    @ViewBuilder
    private var secondReviewContent: some View {
        if viewModel.review == nil {
            Text("Generate the first review before running a second review.")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else if viewModel.isLoadingSecondReview {
            reviewLoadingState("Validating review...")
        } else if let second = viewModel.secondReview {
            Text("AI re-examined the diff and validated each point from the first review.")
                .font(.caption)
                .foregroundStyle(.secondary)

            markdownView(second)

            Button("Re-run Second Review") {
                guard let repo else { return }
                Task { await viewModel.generateSecondReview(repo: repo) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Run a second pass to validate the first review. " +
                    "The AI will re-examine the diff and confirm " +
                    "which points hold up."
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                Button("Run Second Review") {
                    guard let repo else { return }
                    Task { await viewModel.generateSecondReview(repo: repo) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func reviewLoadingState(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
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
