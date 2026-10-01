import SwiftUI

struct PRItemView: View {
    let pr: PullRequest
    var isSelected = false
    var currentUser: String?
    var reviewActivity: PRReviewActivity?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("#\(pr.number)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(GRTheme.muted(colorScheme))

                Text(pr.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 4)
                if reviewActivity != nil {
                    ProgressView()
                        .controlSize(.mini)
                        .help(activityLabel)
                }
                reviewBadge
                if pr.isDraft { badge("DRAFT", color: GRTheme.mutedSecondary(colorScheme)) }
            }

            HStack(spacing: 8) {
                Text(pr.authorLogin)
                Text(pr.headRefName)
                    .foregroundStyle(GRTheme.link(colorScheme))
                    .lineLimit(1)
                Text("→ \(pr.baseRefName)")
                    .lineLimit(1)
                Spacer(minLength: 4)
                if pr.additions > 0 {
                    Text("+\(pr.additions)").foregroundStyle(GRTheme.success)
                }
                if pr.deletions > 0 {
                    Text("−\(pr.deletions)").foregroundStyle(GRTheme.danger)
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(GRTheme.muted(colorScheme))

            if let reviewActivity {
                HStack(spacing: 5) {
                    Circle().fill(GRTheme.accent).frame(width: 5, height: 5)
                    Text(activityLabel(for: reviewActivity))
                        .font(.system(size: 10))
                        .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                }
            } else if let statusLine {
                HStack(spacing: 5) {
                    Circle().fill(statusLine.color).frame(width: 5, height: 5)
                    Text(statusLine.text)
                        .font(.system(size: 10))
                        .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                }
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? GRTheme.selection(colorScheme) : .clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? GRTheme.accent : .clear)
                .frame(width: 2)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(GRTheme.line(colorScheme)).frame(height: 1)
        }
        .contentShape(Rectangle())
    }

    private var activityLabel: String {
        guard let reviewActivity else { return "" }
        return activityLabel(for: reviewActivity)
    }

    private func activityLabel(for activity: PRReviewActivity) -> String {
        switch activity {
        case .loading: "Loading pull request..."
        case .reviewing: "AI review running in background"
        }
    }

    @ViewBuilder
    private var reviewBadge: some View {
        if pr.state == "MERGED" {
            badge("MERGED", color: .purple)
        } else if pr.state == "CLOSED" {
            badge("CLOSED", color: GRTheme.danger)
        } else if pr.isApproved {
            badge("APPROVED", color: GRTheme.success)
        } else if pr.hasChangesRequested {
            badge("CHANGES", color: GRTheme.warning)
        } else if let user = currentUser, pr.isAwaitingReview(by: user) {
            badge("REVIEW", color: GRTheme.warning, filled: true)
        }
    }

    private var statusLine: (text: String, color: Color)? {
        guard let currentUser, let review = pr.wasReviewedBy(currentUser) else {
            return nil
        }
        switch review.state {
        case "APPROVED": return ("Approved by you", GRTheme.success)
        case "CHANGES_REQUESTED": return ("Changes requested", GRTheme.warning)
        case "COMMENTED": return ("Reviewed by you", GRTheme.accent)
        default: return nil
        }
    }

    private func badge(
        _ text: String,
        color: Color,
        filled: Bool = false
    ) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(filled ? GRTheme.onAccent : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(filled ? color : GRTheme.segment(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
