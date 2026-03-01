import SwiftUI

struct ChangedFileRow: View {
    let file: ChangedFile
    let onToggle: () -> Void
    let onDiscard: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onToggle()
            } label: {
                Image(systemName: file.isStaged ? "checkmark.square.fill" : "square")
                    .foregroundStyle(file.isStaged ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            statusBadge

            Text(file.fileName)
                .font(.body)
                .lineLimit(1)

            if let dir = file.directory {
                Text(dir)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if !file.isStaged && file.status != .untracked, let onDiscard {
                Button {
                    onDiscard()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Discard changes")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button(file.isStaged ? "Unstage" : "Stage") {
                onToggle()
            }
            if let onDiscard {
                Divider()
                Button("Discard Changes", role: .destructive) {
                    onDiscard()
                }
            }
        }
    }

    private var statusBadge: some View {
        Text(file.status.rawValue)
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .foregroundStyle(statusColor)
            .frame(width: 16)
    }

    private var statusColor: Color {
        switch file.status {
        case .modified: .orange
        case .added, .untracked: .green
        case .deleted: .red
        case .renamed: .blue
        }
    }
}
