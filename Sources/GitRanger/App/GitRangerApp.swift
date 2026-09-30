import AppKit
import SwiftData
import SwiftUI

private class _BundleFinder {}

extension Bundle {
    static var safeModule: Bundle? {
        let bundleName = "GitRanger_GitRanger"
        let candidates: [URL?] = [
            Bundle.main.resourceURL,
            Bundle(for: _BundleFinder.self).resourceURL,
            Bundle.main.bundleURL
        ]
        for candidate in candidates {
            if let url = candidate?.appendingPathComponent(bundleName + ".bundle"),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }
}

@main
struct GitRangerApp: App {
    @State private var pollService = PollService()

    private static let appVersion: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty, build != version {
            return "\(version) (\(build))"
        }
        return version
    }()

    private func showAboutPanel() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "GitRanger",
            .applicationVersion: version,
            .version: build,
            .credits: NSAttributedString(
                string: "AI-powered git history narration and code review.",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        ]

        if let iconURL = Bundle.safeModule?.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            options[.applicationIcon] = icon
        }

        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Repo.self, Commit.self, PRReview.self, SubAgentReview.self])
        // Keep the legacy store name so existing installations retain their data.
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
                .tint(GRTheme.accent)
                .onAppear {
                    // Activate the app window (needed for SPM builds without app bundle)
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)

                    // Set app icon from bundled resource
                    if let iconURL = Bundle.safeModule?.url(forResource: "AppIcon", withExtension: "icns"),
                       let icon = NSImage(contentsOf: iconURL) {
                        NSApplication.shared.applicationIconImage = icon
                    }

                    let context = sharedModelContainer.mainContext
                    pollService.start(modelContext: context)
                }
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1280, height: 820)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About GitRanger") {
                    showAboutPanel()
                }
            }
        }

        Settings {
            SettingsView()
                .tint(GRTheme.accent)
                .modelContainer(sharedModelContainer)
        }

        MenuBarExtra {
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
        } label: {
            menuBarLabel
        }
    }

    private var menuBarLabel: some View {
        let image: NSImage = {
            guard let url = Bundle.safeModule?.url(
                forResource: "MenuBarIcon", withExtension: "png"
            ), let img = NSImage(contentsOf: url) else {
                return NSImage(
                    systemSymbolName: "text.book.closed",
                    accessibilityDescription: "GitRanger"
                ) ?? NSImage()
            }
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            return img
        }()

        return Image(nsImage: image)
    }
}
