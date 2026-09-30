import SwiftUI

struct PRItemView: View {
    let pr: PullRequest
    var isSelected: Bool = false
    var currentUser: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("#\(pr.number)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(pr.title)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                Spacer()

                reviewBadge

                if pr.isDraft {
                    draftBadge
                }
            }

            HStack(spacing: 8) {
                Text(pr.authorLogin)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(pr.headRefName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.blue)
                    .lineLimit(1)

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text(pr.baseRefName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer()

                reviewerInfo

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
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var reviewBadge: some View {
        if pr.state == "MERGED" {
            badge("MERGED", icon: "arrow.triangle.merge", color: .purple)
        } else if pr.state == "CLOSED" {
            badge("CLOSED", icon: "xmark.circle.fill", color: .red)
        } else if pr.isApproved {
            badge("APPROVED", icon: "checkmark.circle.fill", color: .green)
        } else if pr.hasChangesRequested {
            badge("CHANGES", icon: "exclamationmark.circle.fill", color: .orange)
        } else if let user = currentUser, pr.isAwaitingReview(by: user) {
            badge("REVIEW", icon: "clock.fill", color: .yellow)
        }
    }

    private var draftBadge: some View {
        Text("DRAFT")
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var reviewerInfo: some View {
        if let user = currentUser, let status = pr.wasReviewedBy(user) {
            Text(reviewLabel(for: status.state))
                .font(.caption2)
                .foregroundStyle(reviewColor(for: status.state))
        }
    }

    private func reviewLabel(for state: String) -> String {
        switch state {
        case "APPROVED": "Approved"
        case "CHANGES_REQUESTED": "Changes requested"
        case "COMMENTED": "Commented"
        case "PENDING": "Pending"
        default: state.capitalized
        }
    }

    private func badge(
        _ label: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.system(.caption2, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }

    private func reviewColor(for state: String) -> Color {
        switch state {
        case "APPROVED": .green
        case "CHANGES_REQUESTED": .orange
        default: .secondary
        }
    }
}
