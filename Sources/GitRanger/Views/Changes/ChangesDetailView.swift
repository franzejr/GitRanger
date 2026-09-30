import SwiftUI

struct ChangesDetailView: View {
    @Bindable var viewModel: ChangesViewModel
    @Environment(\.colorScheme) private var colorScheme
    var repo: Repo?
    @State private var layout = DiffLayout.inline

    private enum DiffLayout: String, CaseIterable {
        case inline = "Inline"
        case split = "Split"
    }

    var body: some View {
        Group {
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
        .background(GRTheme.background(colorScheme))
    }

    private func fileDetail(_ file: ChangedFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            fileHeader(file)

            if let diff = viewModel.fileDiff, !diff.isEmpty {
                DiffView(
                    diff: diff,
                    presentation: layout == .inline ? .inline : .split
                )
                    .padding(12)
            } else if file.status == .untracked {
                Text("New file — stage it to see the diff.")
                    .foregroundStyle(.secondary)
                    .padding(24)
            } else {
                Text("No changes to display.")
                    .foregroundStyle(.secondary)
                    .padding(24)
            }
        }
    }

    private func fileHeader(_ file: ChangedFile) -> some View {
        HStack(spacing: 10) {
            Text(file.path)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)

            if additions > 0 {
                Text("+\(additions)")
                    .foregroundStyle(GRTheme.success)
            }
            if deletions > 0 {
                Text("−\(deletions)")
                    .foregroundStyle(GRTheme.danger)
            }

            Spacer()

            Picker("Layout", selection: $layout) {
                ForEach(DiffLayout.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 110)

            if !file.isStaged, file.status != .untracked {
                Button("Discard", role: .destructive) {
                    guard let repo else { return }
                    Task { await viewModel.discardChanges(file, repo: repo) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(GRTheme.danger)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 18)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(GRTheme.line(colorScheme)).frame(height: 1)
        }
    }

    private var additions: Int {
        diffLines.filter {
            $0.hasPrefix("+") && !$0.hasPrefix("+++")
        }.count
    }

    private var deletions: Int {
        diffLines.filter {
            $0.hasPrefix("-") && !$0.hasPrefix("---")
        }.count
    }

    private var diffLines: [String] {
        viewModel.fileDiff?.components(separatedBy: "\n") ?? []
    }
}
