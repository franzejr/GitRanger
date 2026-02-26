import SwiftUI

struct PRItemView: View {
    let pr: PullRequest
    var isSelected: Bool = false

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

                if pr.isDraft {
                    Text("DRAFT")
                        .font(.system(.caption2, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
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
}
