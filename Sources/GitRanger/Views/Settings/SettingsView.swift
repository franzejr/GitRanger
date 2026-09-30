import AppKit
import SwiftUI

struct SettingsView: View {
    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case aiProvider = "AI Provider"
        case reviews = "Reviews"
        case monitoring = "Monitoring"
        case accounts = "Accounts"
    }

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("claudePath") private var claudePath = ""
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("ghPath") private var ghPath = ""
    @AppStorage("glabPath") private var glabPath = ""
    @AppStorage("gitlabHost") private var gitlabHost = ""
    @AppStorage("pollInterval") private var pollInterval = 300
    @State private var selectedTab: SettingsTab
    @State private var settingsVM = AISettingsViewModel()

    init(initialTab: SettingsTab = .aiProvider) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Group {
                switch selectedTab {
                case .general: generalTab
                case .aiProvider: AIProviderSettingsView(settingsVM: settingsVM)
                case .reviews: ReviewSettingsView()
                case .monitoring: monitoringTab
                case .accounts: accountsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(
            minWidth: 1_080,
            idealWidth: 1_180,
            minHeight: 780,
            idealHeight: 900
        )
        .background(GRTheme.background(colorScheme))
        .tint(GRTheme.accent)
        .task { await settingsVM.checkAvailability() }
    }

    private var tabBar: some View {
        HStack(spacing: 22) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight:
                                selectedTab == tab ? .semibold : .regular))
                        Rectangle()
                            .fill(selectedTab == tab ? GRTheme.accent : .clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    selectedTab == tab ? Color.primary : GRTheme.muted(colorScheme)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48, alignment: .bottom)
        .background(GRTheme.sidebar(colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(GRTheme.line(colorScheme)).frame(height: 1)
        }
    }

    private var generalTab: some View {
        settingsPage(title: "General", subtitle: "GitRanger application preferences.") {
            settingsCard {
                let location = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first?.appendingPathComponent("GitNarrate/repos").path ?? "Unknown"
                settingsRow("Repos location") {
                    Text(location)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var monitoringTab: some View {
        settingsPage(
            title: "Monitoring",
            subtitle: "Choose how often repositories are checked for updates."
        ) {
            settingsCard {
                settingsRow("Poll interval") {
                    Picker("Poll Interval", selection: $pollInterval) {
                        Text("Every minute").tag(60)
                        Text("Every 5 minutes").tag(300)
                        Text("Every 15 minutes").tag(900)
                        Text("Every 30 minutes").tag(1_800)
                        Text("Every hour").tag(3_600)
                    }.labelsHidden()
                }
            }
        }
    }

    private var accountsTab: some View {
        settingsPage(
            title: "Accounts",
            subtitle: "Configure GitHub and GitLab command-line access."
        ) {
            settingsCard {
                settingsRow("Claude Code") {
                    pathField(
                        value: $claudePath,
                        placeholder: "Auto-detect claude",
                        message: "Select claude"
                    )
                }
                settingsRow("Codex CLI") {
                    pathField(
                        value: $codexPath,
                        placeholder: "Auto-detect codex",
                        message: "Select codex"
                    )
                }
                settingsRow("GitHub CLI") {
                    pathField(value: $ghPath, placeholder: "Auto-detect gh", message: "Select gh")
                }
                settingsRow("GitLab CLI") {
                    pathField(value: $glabPath, placeholder: "Auto-detect glab", message: "Select glab")
                }
                settingsRow("GitLab host") {
                    TextField("gitlab.com", text: $gitlabHost)
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
    }

    private func settingsPage<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                }
                content()
            }
            .padding(28)
        }
    }

    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(14)
            .grCard()
    }

    private func settingsRow<Content: View>(
        _ label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 12) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(GRTheme.mutedSecondary(colorScheme))
                .frame(width: 140, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pathField(
        value: Binding<String>,
        placeholder: String,
        message: String
    ) -> some View {
        HStack {
            TextField(placeholder, text: value)
                .font(.system(size: 11, design: .monospaced))
            Button("Browse...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.message = message
                if panel.runModal() == .OK, let url = panel.url {
                    value.wrappedValue = url.path
                }
            }
        }
    }

}
