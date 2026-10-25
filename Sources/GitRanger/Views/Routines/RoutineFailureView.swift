import SwiftUI

@MainActor
struct RoutineFailureView: View {
    let error: String
    let retryMessage: String

    private var summary: String {
        if GitHubPRDiffLoader.isTooLarge(error) {
            return "GitHub could not provide the full diff for this large PR. "
                + "Update the app and use Retry to load file patches."
        }
        if error.lowercased().contains("incomplete pr diff") {
            return "GitHub returned incomplete file patches. Review locally or split the PR before retrying."
        }
        if error.lowercased().contains("timeout") || error.lowercased().contains("timed out") {
            return "The review operation exceeded its time limit. Open the technical details for the cause."
        }
        return "The review could not finish. Open the technical details for the reported cause."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(summary, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(GRTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
            Text(retryMessage)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Technical details") {
                Text(error)
                    .textSelection(.enabled)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .font(.system(size: 11))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GRTheme.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
