import AppKit
import SwiftUI

extension String {
    func match(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX,
               currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: .unspecified
            )
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

enum ReviewTab: String, CaseIterable {
    case review = "Review"
    case secondReview = "Second Review"
}

@MainActor
struct PRReviewView: View {
    @Bindable var viewModel: PRReviewViewModel
    var repo: Repo?
    @State var copied = false
    @State var selectedTab: ReviewTab = .review
    @State var expandedAgents: Set<ReviewAgent> = []
    @State var expandedCustomAgents: Set<String> = []
    @State var showActionSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            prHeader
            Divider()

            if viewModel.isLoading
                && viewModel.review == nil
                && viewModel.diff == nil {
                loadingState("Loading PR data...")
            } else if let error = viewModel.error,
                      viewModel.review == nil,
                      viewModel.diff == nil {
                errorState(error)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        reviewSection
                        diffSection
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Header

    private var prHeader: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let pr = viewModel.selectedPR {
                        prTitleRow(pr)
                        prMetadataRow(pr)
                    }
                }

                Spacer()

                if viewModel.selectedPR?.state == "OPEN" {
                    Button {
                        showActionSheet = true
                    } label: {
                        Label("Review", systemImage: "checkmark.message")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Approve or comment on this PR")
                }

                Button {
                    viewModel.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            if let success = viewModel.actionSuccess {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .transition(.opacity)
            }

            if let error = viewModel.actionError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .sheet(isPresented: $showActionSheet) {
            if let repo {
                PRActionSheet(
                    viewModel: viewModel,
                    repo: repo,
                    isPresented: $showActionSheet
                )
            }
        }
    }

    private func prTitleRow(_ pr: PullRequest) -> some View {
        HStack(spacing: 6) {
            Text("#\(pr.number)")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(pr.title)
                .font(.headline)
                .lineLimit(2)
        }
    }

    private func prMetadataRow(_ pr: PullRequest) -> some View {
        HStack(spacing: 8) {
            Text(pr.authorLogin)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text(pr.headRefName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.blue)

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text(pr.baseRefName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

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

    // MARK: - Review Section

    @ViewBuilder
    private var reviewSection: some View {
        if viewModel.hasSubAgentResults {
            subAgentReviewContent
        } else if viewModel.review != nil
                    || (viewModel.isLoading
                        && !viewModel.isAnyAgentLoading) {
            reviewWithTabs
        } else {
            generatePrompt
        }
    }

    private var generatePrompt: some View {
        let enabledBuiltIn = ReviewAgent.allCases.filter {
            !disabledAgentSet.contains($0.rawValue)
        }
        let totalEnabled = enabledBuiltIn.count
            + enabledCustomAgents.count

        return VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.blue.opacity(0.8))

            VStack(spacing: 4) {
                Text("AI Code Review")
                    .font(.headline)

                Text("Run \(totalEnabled) specialized reviewers in parallel.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            FlowLayout(spacing: 6) {
                ForEach(ReviewAgent.allCases) { agent in
                    agentChip(
                        icon: agent.icon,
                        name: agent.displayName,
                        color: agent.iconColor,
                        isDisabled: disabledAgentSet
                            .contains(agent.rawValue)
                    )
                }
                ForEach(
                    repo?.customAgents ?? [], id: \.id
                ) { agent in
                    agentChip(
                        icon: agent.icon,
                        name: agent.name,
                        color: agent.iconColor,
                        isDisabled: !agent.isEnabled
                    )
                }
            }
            .frame(maxWidth: 500)

            Button {
                guard let repo else { return }
                Task {
                    await viewModel.generateSubAgentReviews(repo: repo)
                }
            } label: {
                Label("Generate Reviews", systemImage: "sparkles")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func agentChip(
        icon: String, name: String,
        color: Color, isDisabled: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(isDisabled ? .secondary : color)
            Text(name)
                .font(.caption)
                .foregroundStyle(isDisabled ? .secondary : .primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isDisabled
                ? Color.secondary.opacity(0.1)
                : color.opacity(0.1)
        )
        .clipShape(Capsule())
        .opacity(isDisabled ? 0.5 : 1)
    }

    // MARK: - Diff Section

    @ViewBuilder
    private var diffSection: some View {
        if let diff = viewModel.diff, !diff.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Diff")
                        .font(.headline)
                    Spacer()
                }

                GroupBox {
                    DiffView(diff: diff)
                }
            }
        }
    }

    // MARK: - Error / Loading States

    private func loadingState(_ message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                guard let repo,
                      let pr = viewModel.selectedPR else { return }
                Task { await viewModel.loadPR(pr, repo: repo) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    func inlineError(
        _ message: String, retry: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.red)
                .font(.callout)
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
