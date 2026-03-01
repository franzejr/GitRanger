import AppKit
import SwiftUI

private enum AddRepoMode: String, CaseIterable {
    case clone = "Clone from URL"
    case local = "Open Local"
}

struct AddRepoSheet: View {
    @Bindable var viewModel: RepoListViewModel
    @Binding var isPresented: Bool
    @State private var mode: AddRepoMode = .clone
    @State private var repoURL = ""
    @State private var selectedPath: URL?

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Repository")
                .font(.title2)
                .fontWeight(.semibold)

            Picker("", selection: $mode) {
                ForEach(AddRepoMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isImporting)

            switch mode {
            case .clone:
                cloneModeContent
            case .local:
                localModeContent
            }

            errorAndProgress

            actionButtons
        }
        .padding(24)
        .frame(width: 420)
    }

    // MARK: - Clone Mode

    private var cloneModeContent: some View {
        VStack(spacing: 8) {
            Text("Enter an HTTPS or SSH git URL to import.")
                .foregroundStyle(.secondary)

            TextField(
                "https://github.com/user/repo  or  git@github.com:user/repo",
                text: $repoURL
            )
            .textFieldStyle(.roundedBorder)
            .disabled(viewModel.isImporting)
            .onSubmit { importFromURL() }

            Text("Uses your local git credentials (SSH keys, credential helpers).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Local Mode

    private var localModeContent: some View {
        VStack(spacing: 8) {
            Text("Choose a folder that contains a git repository.")
                .foregroundStyle(.secondary)

            if let path = selectedPath {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    Text(path.path)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button("Change") { chooseFolder() }
                        .controlSize(.small)
                }
                .padding(8)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isImporting)
            }
        }
    }

    // MARK: - Shared

    @ViewBuilder
    private var errorAndProgress: some View {
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
    }

    private var actionButtons: some View {
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
                addButton
            }
        }
    }

    @ViewBuilder
    private var addButton: some View {
        switch mode {
        case .clone:
            Button("Import") { importFromURL() }
                .buttonStyle(.borderedProminent)
                .disabled(repoURL.isEmpty)
                .keyboardShortcut(.defaultAction)
        case .local:
            Button("Add") { addLocal() }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPath == nil)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    private func importFromURL() {
        guard !repoURL.isEmpty, !viewModel.isImporting else { return }
        viewModel.importRepo(url: repoURL)
        waitForCompletion()
    }

    private func addLocal() {
        guard let path = selectedPath, !viewModel.isImporting else { return }
        Task {
            await viewModel.addLocalRepo(path: path)
            if viewModel.importError == nil {
                isPresented = false
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository folder"
        panel.prompt = "Open"

        if panel.runModal() == .OK {
            selectedPath = panel.url
        }
    }

    private func waitForCompletion() {
        Task {
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
