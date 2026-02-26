import SwiftUI

struct NarrativeView: View {
    @Bindable var viewModel: NarrativeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Commit Narrative")
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let timespan = viewModel.timespan {
                        Text("\(viewModel.commitCount) commits \u{2022} \(timespan.from, style: .date) \u{2013} \(timespan.to, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    viewModel.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.isLoading {
                        loadingState
                    } else if let error = viewModel.error {
                        errorState(error)
                    } else if let narrative = viewModel.narrative {
                        narrativeContent(narrative)
                    }
                }
                .padding()
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Crafting the story...")
                .foregroundStyle(.secondary)
            Text("This may take a moment for \(viewModel.commitCount) commits.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private func errorState(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Failed to generate narrative")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private func narrativeContent(_ narrative: String) -> some View {
        let paragraphs = narrative.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
            Text(paragraph.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }
}
