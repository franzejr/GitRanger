import SwiftUI

struct CommitItemView: View {
    let commit: Commit
    let isChecked: Bool
    var isSelected: Bool = false
    var onToggleCheck: () -> Void
    var onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox for narrative selection
            Button {
                onToggleCheck()
            } label: {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            // Main content
            VStack(alignment: .leading, spacing: 3) {
                Text(commit.firstLine)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(commit.shortSha)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text(commit.authorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(commit.committedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    if commit.insertions > 0 {
                        Text("+\(commit.insertions)")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if commit.deletions > 0 {
                        Text("-\(commit.deletions)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
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
        .onTapGesture { onSelect() }
    }
}
