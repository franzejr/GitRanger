import SwiftUI

struct ChangesDetailView: View {
    @Bindable var viewModel: ChangesViewModel

    var body: some View {
        if let file = viewModel.selectedFile {
            fileDetail(file)
        } else {
            ContentUnavailableView(
                "Select a File",
                systemImage: "doc.text",
                description: Text("Choose a changed file to view its diff.")
            )
        }
    }

    private func fileDetail(_ file: ChangedFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            fileHeader(file)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let diff = viewModel.fileDiff, !diff.isEmpty {
                        GroupBox {
                            DiffView(diff: diff)
                        }
                    } else if file.status == .untracked {
                        Text("New file — stage it to see the diff.")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        Text("No changes to display.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .padding()
            }
        }
    }

    private func fileHeader(_ file: ChangedFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: fileIcon(for: file.status))
                .foregroundStyle(fileColor(for: file.status))

            Text(file.path)
                .font(.system(.headline, design: .monospaced))
                .lineLimit(1)

            Text(file.status.label)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(fileColor(for: file.status).opacity(0.15))
                .foregroundStyle(fileColor(for: file.status))
                .clipShape(Capsule())

            if file.isStaged {
                Text("Staged")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func fileIcon(for status: FileStatus) -> String {
        switch status {
        case .modified: "pencil.circle.fill"
        case .added, .untracked: "plus.circle.fill"
        case .deleted: "minus.circle.fill"
        case .renamed: "arrow.right.circle.fill"
        }
    }

    private func fileColor(for status: FileStatus) -> Color {
        switch status {
        case .modified: .orange
        case .added, .untracked: .green
        case .deleted: .red
        case .renamed: .blue
        }
    }
}
