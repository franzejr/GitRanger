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
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
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
    @Environment(\.colorScheme) var colorScheme
    var repo: Repo?
    @State var copied = false
    @State var selectedTab: ReviewTab = .review
    @State var expandedAgents: Set<ReviewAgent> = []
    @State var expandedCustomAgents: Set<String> = []
    @State var showActionSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailToolbar

            if viewModel.isLoading && viewModel.review == nil && viewModel.diff == nil {
                loadingState("Loading PR data...")
            } else if let error = viewModel.error,
                      viewModel.review == nil,
                      viewModel.diff == nil {
                errorState(error)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        prHeader
                        actionMessage
                        reviewSection
                        diffSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(GRTheme.background(colorScheme))
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

    private var detailToolbar: some View {
        HStack(spacing: 8) {
            Spacer()

            if let pr = viewModel.selectedPR,
               let url = URL(string: pr.url) {
                Button("Open on \(viewModel.githubService.isGitHubRepo(url: repo?.url ?? "") ? "GitHub" : "GitLab")") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if viewModel.selectedPR?.state == "OPEN" {
                Button {
                    showActionSheet = true
                } label: {
                    Image(systemName: "checkmark.message")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Approve or comment")
            }

            Button {
                guard let repo else { return }
                Task { await viewModel.generateSubAgentReviews(repo: repo) }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isAnyAgentLoading {
                        ProgressView().controlSize(.small)
                    }
                    Text(viewModel.hasSubAgentResults ? "Re-run all agents" : "Run all agents")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GRTheme.onAccent)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(GRTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isAnyAgentLoading || viewModel.diff == nil)
            .opacity(viewModel.isAnyAgentLoading || viewModel.diff == nil ? 0.45 : 1)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            Rectangle().fill(GRTheme.line(colorScheme)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var prHeader: some View {
        if let pr = viewModel.selectedPR {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Text("#\(pr.number)")
                    Text(pr.headRefName).foregroundStyle(GRTheme.link(colorScheme))
                    Text("→ \(pr.baseRefName)")
                    if pr.changedFiles > 0 { Text("\(pr.changedFiles) files") }
                    if pr.additions > 0 {
                        Text("+\(pr.additions)").foregroundStyle(GRTheme.success)
                    }
                    if pr.deletions > 0 {
                        Text("−\(pr.deletions)").foregroundStyle(GRTheme.danger)
                    }
                }
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(GRTheme.muted(colorScheme))

                Text(pr.title)
                    .font(.system(size: 18, weight: .medium))
                    .tracking(-0.2)
                    .lineLimit(3)
            }
        }
    }

    @ViewBuilder
    private var actionMessage: some View {
        if let success = viewModel.actionSuccess {
            Label(success, systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(GRTheme.success)
        }
        if let error = viewModel.actionError {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(GRTheme.danger)
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if viewModel.hasSubAgentResults {
            subAgentReviewContent
        } else if viewModel.review != nil
                    || (viewModel.isLoading && !viewModel.isAnyAgentLoading) {
            reviewWithTabs
        } else {
            generatePrompt
        }
    }

    private var generatePrompt: some View {
        let enabledBuiltIn = ReviewAgent.allCases.filter {
            !disabledAgentSet.contains($0.rawValue)
        }
        let totalEnabled = enabledBuiltIn.count + enabledCustomAgents.count

        return VStack(spacing: 18) {
            GRMonogram(size: 34)
            VStack(spacing: 4) {
                Text("AI Code Review")
                    .font(.system(size: 15, weight: .semibold))
                Text("Run all \(totalEnabled) reviewers in parallel, or choose one below.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
            }
            FlowLayout(spacing: 6) {
                ForEach(ReviewAgent.allCases) { agent in
                    agentLaunchButton(agent)
                }
            }
            Button("Run all agents") {
                guard let repo else { return }
                Task { await viewModel.generateSubAgentReviews(repo: repo) }
            }
            .buttonStyle(.borderedProminent)
            .tint(GRTheme.accent)
            .foregroundStyle(GRTheme.onAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .grCard()
    }

    private func agentLaunchButton(_ agent: ReviewAgent) -> some View {
        let isDisabled = disabledAgentSet.contains(agent.rawValue)
        return Button {
            guard let repo else { return }
            Task { await viewModel.regenerateSingleAgent(agent, repo: repo) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: agent.icon).font(.caption2)
                Text("Run \(agent.displayName)").font(.system(size: 10.5))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? .secondary : agent.iconColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(GRTheme.segment(colorScheme))
        .clipShape(Capsule())
        .opacity(isDisabled ? 0.5 : 1)
        .disabled(isDisabled || viewModel.diff == nil)
    }

    @ViewBuilder
    private var diffSection: some View {
        if let diff = viewModel.diff, !diff.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                GRSectionLabel(title: "Diff")
                DiffView(diff: diff)
            }
        }
    }

    private func loadingState(_ message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.system(size: 12))
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
                guard let repo, let pr = viewModel.selectedPR else { return }
                Task { await viewModel.loadPR(pr, repo: repo) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    func inlineError(
        _ message: String,
        retry: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
            Text(message).font(.system(size: 11))
            Spacer()
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .foregroundStyle(GRTheme.danger)
    }
}
