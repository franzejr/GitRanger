import SwiftUI

struct ChangedFileRow: View {
    let file: ChangedFile
    var isSelected = false
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onDiscard: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: file.isStaged ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(file.isStaged ? GRTheme.accent : .secondary)
            }
            .buttonStyle(.plain)

            Text(file.path)
                .font(.system(size: 10.5, design: .monospaced))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(file.status.rawValue)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isSelected ? GRTheme.selection(colorScheme) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(file.isStaged ? "Unstage" : "Stage", action: onToggle)
            if let onDiscard {
                Divider()
                Button("Discard Changes", role: .destructive, action: onDiscard)
            }
        }
    }

    private var statusColor: Color {
        switch file.status {
        case .modified: GRTheme.warning
        case .added, .untracked: GRTheme.success
        case .deleted: GRTheme.danger
        case .renamed: GRTheme.link(colorScheme)
        }
    }
}
