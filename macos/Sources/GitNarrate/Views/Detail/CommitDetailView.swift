import SwiftUI

struct CommitDetailView: View {
    @Bindable var viewModel: CommitDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading {
                    ProgressView("Loading commit details...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let commit = viewModel.commit {
                    commitHeader(commit)
                    Divider()
                    aiSummarySection(commit)
                    Divider()
                    diffSection
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func commitHeader(_ commit: Commit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(commit.message)
                .font(.title3)
                .fontWeight(.medium)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Label(commit.shortSha, systemImage: "number")
                    .font(.system(.caption, design: .monospaced))
                Label(commit.authorName, systemImage: "person")
                    .font(.caption)
                Text(commit.committedAt, style: .date)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label("\(commit.filesChanged) files", systemImage: "doc")
                if commit.insertions > 0 {
                    Text("+\(commit.insertions)")
                        .foregroundStyle(.green)
                }
                if commit.deletions > 0 {
                    Text("-\(commit.deletions)")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func aiSummarySection(_ commit: Commit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Summary")
                .font(.headline)

            if viewModel.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Analyzing...")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let error = viewModel.analyzeError {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                    Button("Retry") {
                        Task { await viewModel.analyzeCommit() }
                    }
                    .buttonStyle(.bordered)
                }
            } else if let summary = commit.summary {
                summaryContent(summary, level: commit.impactLevel)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Not yet analyzed")
                        .foregroundStyle(.secondary)
                    Button("Analyze with AI") {
                        Task { await viewModel.analyzeCommit() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private func summaryContent(_ summary: CommitSummary, level: ImpactLevel?) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.oneLiner)
                    .font(.body)
                    .fontWeight(.medium)

                Text(summary.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if let level {
                        ImpactBadge(level: level)
                    }
                    ForEach(summary.categories, id: \.self) { category in
                        Text(category)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }

                if let riskNotes = summary.riskNotes, !riskNotes.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(riskNotes)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var diffSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diff")
                .font(.headline)

            if let diff = viewModel.diff, !diff.isEmpty {
                GroupBox {
                    DiffView(diff: diff)
                }
            } else {
                Text("No diff available")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
