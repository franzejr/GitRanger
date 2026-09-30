import SwiftUI

enum PRActionMode: String, CaseIterable {
    case approve = "Approve"
    case comment = "Comment"
}

@MainActor
struct PRActionSheet: View {
    @Bindable var viewModel: PRReviewViewModel
    var repo: Repo
    @Binding var isPresented: Bool

    @State private var mode: PRActionMode = .approve
    @State private var comment = ""

    private var prNumber: Int { viewModel.selectedPR?.number ?? 0 }
    private var prTitle: String { viewModel.selectedPR?.title ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Review #\(prNumber)")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Text(prTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Action picker
            Picker("Action", selection: $mode) {
                ForEach(PRActionMode.allCases, id: \.self) { action in
                    Text(action.rawValue).tag(action)
                }
            }
            .pickerStyle(.segmented)

            // Comment field
            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .approve ? "Comment (optional)" : "Comment")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $comment)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100, maxHeight: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            // Actions
            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        switch mode {
                        case .approve:
                            await viewModel.approvePR(repo: repo, comment: comment)
                        case .comment:
                            await viewModel.commentOnPR(repo: repo, message: comment)
                        }
                        if viewModel.actionError == nil {
                            isPresented = false
                        }
                    }
                } label: {
                    if viewModel.isSubmittingAction {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Text(mode == .approve ? "Approve" : "Submit Comment")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(mode == .approve ? .green : .blue)
                .disabled(viewModel.isSubmittingAction || (mode == .comment && comment.isEmpty))
                .keyboardShortcut(.defaultAction)
            }

            if let error = viewModel.actionError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
