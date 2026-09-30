import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import GitRanger

@MainActor
final class DesignRenderingTests: XCTestCase {
    func testReviewSettingsRemainWiredIntoSettingsWindow() throws {
        XCTAssertTrue(SettingsView.SettingsTab.allCases.contains(.reviews))

        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsSource = projectRoot
            .appendingPathComponent("Sources/GitRanger/Views/Settings/SettingsView.swift")
        let source = try String(contentsOf: settingsSource, encoding: .utf8)

        XCTAssertTrue(
            source.contains("case .reviews: ReviewSettingsView()"),
            "The Reviews tab must keep the full agent configuration view wired in."
        )

        let reviewSettingsSource = settingsSource
            .deletingLastPathComponent()
            .appendingPathComponent("ReviewSettingsView.swift")
        let reviewSettings = try String(
            contentsOf: reviewSettingsSource,
            encoding: .utf8
        )
        XCTAssertTrue(reviewSettings.contains("ReviewPromptSheet("))

        let promptSheetSource = settingsSource
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PRList/ReviewPromptSheet.swift")
        let promptSheet = try String(contentsOf: promptSheetSource, encoding: .utf8)
        XCTAssertTrue(promptSheet.contains("builtInAgentsSection"))
        XCTAssertTrue(promptSheet.contains("customAgentsSection"))

        let appSource = projectRoot
            .appendingPathComponent("Sources/GitRanger/App/GitRangerApp.swift")
        let app = try String(contentsOf: appSource, encoding: .utf8)
        XCTAssertTrue(
            app.contains("SettingsView()")
                && app.contains(".modelContainer(sharedModelContainer)"),
            "Settings must use the same repository database as the main window."
        )
    }

    func testRenderDesignReferences() throws {
        guard ProcessInfo.processInfo.environment["RENDER_DESIGN"] == "1" else {
            throw XCTSkip("Set RENDER_DESIGN=1 to export visual references")
        }

        try render(
            SettingsView().preferredColorScheme(.dark),
            size: CGSize(width: 1_180, height: 900),
            name: "gitranger-settings-dark"
        )
        try render(
            SettingsView().preferredColorScheme(.light),
            size: CGSize(width: 1_180, height: 900),
            name: "gitranger-settings-light"
        )
        try renderReviewSettings()

        let review = makeReviewView()
        try render(
            review.preferredColorScheme(.dark),
            size: CGSize(width: 900, height: 820),
            name: "gitranger-pr-dark"
        )

        try render(
            makeChangesView().preferredColorScheme(.dark),
            size: CGSize(width: 900, height: 600),
            name: "gitranger-changes-dark"
        )
    }

    private func renderReviewSettings() throws {
        let schema = Schema([Repo.self, Commit.self, PRReview.self, SubAgentReview.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        container.mainContext.insert(Repo(
            name: "adaflow",
            url: "https://github.com/example/adaflow.git",
            localPath: "/tmp/adaflow"
        ))

        try render(
            SettingsView(initialTab: .reviews)
                .modelContainer(container)
                .preferredColorScheme(.dark),
            size: CGSize(width: 1_180, height: 900),
            name: "gitranger-review-settings-dark"
        )
    }

    private func makeReviewView() -> PRReviewView {
        let viewModel = PRReviewViewModel()
        viewModel.selectedPR = PullRequest(
            number: 2_362,
            title: "fix(cpf): treat a missing birth date as not-found under Consulta CPF v3 [ADA-6W]",
            authorLogin: "app/claude",
            state: "OPEN",
            headRefName: "ada-6w-cpfs-missing-birth-date",
            headRefOid: "3f9a1c2b4d5e",
            baseRefName: "master",
            createdAt: Date(),
            updatedAt: Date(),
            additions: 20,
            deletions: 1,
            changedFiles: 2,
            url: "https://github.com/example/repo/pull/2362",
            isDraft: false,
            reviewDecision: "",
            reviewRequests: [],
            latestReviews: []
        )
        viewModel.diff = """
        @@ -1,6 +1,6 @@
         class CpfsController < ApplicationController
           def show
        -    registry = RegistryEntity.find_from_registry(params[:cpf], birth_date: birth_date)
        +    registry = find_registry
           private
        @@ -14,6 +14,13 @@ def show
        +  # Treat a missing birth date as a non-match.
        +  def find_registry
        +    RegistryEntity.find_from_registry(params[:cpf], birth_date: birth_date)
        +  rescue SerproClient::GetCpf::MissingBirthDate
        +    nil
        +  end
        """
        viewModel.agentReviews[.summary] = """
        VERDICT: PASS

        Anonymous CPF lookups without a birth date now return 404 instead of raising a 500. The new helper matches every other non-match path.
        """
        for agent in ReviewAgent.allCases {
            viewModel.agentReviews[agent] = viewModel.agentReviews[agent]
                ?? "VERDICT: PASS\n\nNo issues found."
            viewModel.agentVerdicts[agent] = agent != .bugDetector
        }

        let repo = Repo(
            name: "adaflow",
            url: "https://github.com/example/repo.git",
            localPath: "/tmp/repo"
        )
        return PRReviewView(viewModel: viewModel, repo: repo)
    }

    private func makeChangesView() -> some View {
        let viewModel = ChangesViewModel()
        let first = ChangedFile(
            path: "app/controllers/cpfs_controller.rb",
            status: .modified,
            isStaged: true
        )
        viewModel.changedFiles = [
            first,
            ChangedFile(
                path: "test/controllers/cpfs_controller_test.rb",
                status: .modified,
                isStaged: true
            ),
            ChangedFile(
                path: "app/services/serpro_client.rb",
                status: .modified,
                isStaged: false
            ),
            ChangedFile(
                path: "config/locales/pt-BR.yml",
                status: .modified,
                isStaged: false
            ),
            ChangedFile(
                path: "docs/cpf-v3.md",
                status: .added,
                isStaged: false
            )
        ]
        viewModel.selectedFile = first
        viewModel.currentBranch = "main"
        viewModel.commitSummary = "fix(cpf): return 404 when birth date is missing"
        viewModel.commitDescription = "Wrap registry lookup and treat a missing birth date as not-found."
        viewModel.fileDiff = """
        @@ -1,6 +1,6 @@
         class CpfsController < ApplicationController
           def show
        -    registry = RegistryEntity.find_from_registry(params[:cpf], birth_date: birth_date)
        +    registry = find_registry
           private
        @@ -14,6 +14,13 @@ def show
        +  # Treat a missing birth date as a non-match.
        +  def find_registry
        +    RegistryEntity.find_from_registry(params[:cpf], birth_date: birth_date)
        +  rescue SerproClient::GetCpf::MissingBirthDate
        +    nil
        +  end
        """
        let repo = Repo(
            name: "adaflow",
            url: "https://github.com/example/repo.git",
            localPath: "/tmp/missing-repo"
        )
        return HStack(spacing: 0) {
            ChangesListView(viewModel: viewModel, repo: repo)
                .frame(width: 280)
            ChangesDetailView(viewModel: viewModel, repo: repo)
        }
    }

    private func render<Content: View>(
        _ view: Content,
        size: CGSize,
        name: String
    ) throws {
        let hostingView = NSHostingView(
            rootView: view.frame(width: size.width, height: size.height)
        )
        hostingView.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            XCTFail("Failed to render \(name)")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to encode \(name)")
            return
        }
        try data.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
    }
}
