import SwiftUI

struct AddRepoSheet: View {
    @Bindable var viewModel: RepoListViewModel
    @Binding var isPresented: Bool
    @State private var repoURL = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Repository")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter an HTTPS or SSH git URL to import.")
                .foregroundStyle(.secondary)

            TextField("https://github.com/user/repo  or  git@github.com:user/repo", text: $repoURL)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isImporting)
                .onSubmit { importRepo() }

            Text("Uses your local git credentials (SSH keys, credential helpers).")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let error = viewModel.importError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if viewModel.isImporting {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(viewModel.importStatus ?? "Importing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let detail = viewModel.importDetail {
                        Text(detail)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity)
                            .animation(.none, value: detail)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    cancelAndDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if viewModel.isImporting {
                    Button("Cancel Import") {
                        viewModel.cancelImport()
                    }
                    .foregroundStyle(.red)
                } else {
                    Button("Import") {
                        importRepo()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(repoURL.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func importRepo() {
        guard !repoURL.isEmpty, !viewModel.isImporting else { return }
        viewModel.importRepo(url: repoURL)

        // Watch for completion to auto-dismiss
        Task {
            // Poll until import finishes
            while viewModel.isImporting {
                try? await Task.sleep(for: .milliseconds(200))
            }
            if viewModel.importError == nil {
                isPresented = false
            }
        }
    }

    private func cancelAndDismiss() {
        if viewModel.isImporting {
            viewModel.cancelImport()
        }
        isPresented = false
    }
}
