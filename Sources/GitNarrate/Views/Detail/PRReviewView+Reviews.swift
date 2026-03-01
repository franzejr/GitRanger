import AppKit
import SwiftUI

// MARK: - Review Tab Content

extension PRReviewView {
    var reviewWithTabs: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviewTabBar
            VStack(alignment: .leading, spacing: 12) {
                switch selectedTab {
                case .review:
                    firstReviewContent
                case .secondReview:
                    secondReviewContent
                }
            }
            .padding(.top, 12)
        }
    }

    private var reviewTabBar: some View {
        HStack(spacing: 0) {
            ForEach(ReviewTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(
                            selectedTab == tab ? .semibold : .regular
                        ))
                        .foregroundStyle(
                            selectedTab == tab ? .primary : .secondary
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(
                    selectedTab == tab
                        ? Color.accentColor.opacity(0.1) : .clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer()

            if viewModel.isCached {
                cachedBadge
            }

            copyButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    var copyButton: some View {
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
    var firstReviewContent: some View {
        if viewModel.isLoading && viewModel.review == nil {
            reviewLoadingState("Generating review...")
        } else if let error = viewModel.error, viewModel.review == nil {
            inlineError(error) {
                guard let repo else { return }
                Task { await viewModel.generateReview(repo: repo) }
            }
        } else if let review = viewModel.review {
            markdownView(review)

            HStack {
                Button {
                    guard let repo else { return }
                    Task { await viewModel.generateReview(repo: repo) }
                } label: {
                    Label("Re-run Review", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isLoading)
            }
        }
    }

    // MARK: - Second Review

    @ViewBuilder
    var secondReviewContent: some View {
        if viewModel.review == nil {
            secondReviewPlaceholder
        } else if viewModel.isLoadingSecondReview {
            reviewLoadingState("Validating review...")
        } else if let second = viewModel.secondReview {
            secondReviewResult(second)
        } else {
            secondReviewPrompt
        }
    }

    private var secondReviewPlaceholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Generate the first review before running a second review.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func secondReviewResult(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.green)
            Text("AI re-examined the diff and validated each point.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        markdownView(text)

        Button {
            guard let repo else { return }
            Task { await viewModel.generateSecondReview(repo: repo) }
        } label: {
            Label("Re-run Second Review", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var secondReviewPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.title3)
                    .foregroundStyle(.blue.opacity(0.8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Validate the Review")
                        .font(.subheadline.weight(.medium))

                    Text("Re-examine the diff and confirm which points hold up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                guard let repo else { return }
                Task { await viewModel.generateSecondReview(repo: repo) }
            } label: {
                Label("Run Second Review", systemImage: "shield.checkered")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    func reviewLoadingState(_ message: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.7)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }
}
