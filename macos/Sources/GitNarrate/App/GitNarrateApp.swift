import AppKit
import SwiftData
import SwiftUI

@main
struct GitNarrateApp: App {
    @State private var pollService = PollService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Repo.self, Commit.self, PRReview.self])
        let config = ModelConfiguration(
            "GitNarrate",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Activate the app window (needed for SPM builds without app bundle)
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)

                    let context = sharedModelContainer.mainContext
                    pollService.start(modelContext: context)
                }
        }
        .modelContainer(sharedModelContainer)

        Settings {
            SettingsView()
        }

        MenuBarExtra("GitNarrate", systemImage: "text.book.closed") {
            if pollService.isPolling {
                Label("Syncing...", systemImage: "arrow.triangle.2.circlepath")
            } else if let lastPoll = pollService.lastPollDate {
                Text("Last sync: \(lastPoll, style: .relative) ago")
            } else {
                Text("Not yet synced")
            }

            Text("\(pollService.repoCount) repositories")

            Divider()

            Button("Sync All Now") {
                pollService.pollNow()
            }
            .disabled(pollService.isPolling)

            Divider()

            SettingsLink {
                Text("Settings...")
            }
        }
    }
}
