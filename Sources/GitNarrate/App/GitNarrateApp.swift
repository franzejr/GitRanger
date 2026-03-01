import AppKit
import SwiftData
import SwiftUI

@main
struct GitNarrateApp: App {
    @State private var pollService = PollService()

    private func showAboutPanel() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "GitNarrate",
            .applicationVersion: "1.0.0",
            .version: "1",
            .credits: NSAttributedString(
                string: "AI-powered git history narration and code review.",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        ]

        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            options[.applicationIcon] = icon
        }

        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Repo.self, Commit.self, PRReview.self, SubAgentReview.self])
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

                    // Set app icon from bundled resource
                    if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
                       let icon = NSImage(contentsOf: iconURL) {
                        NSApplication.shared.applicationIconImage = icon
                    }

                    let context = sharedModelContainer.mainContext
                    pollService.start(modelContext: context)
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About GitNarrate") {
                    showAboutPanel()
                }
            }
        }

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
