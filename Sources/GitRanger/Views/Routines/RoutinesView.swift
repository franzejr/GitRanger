// swiftlint:disable file_length
import SwiftUI

private struct RoutineEditorRequest: Identifiable {
    let id = UUID()
    let routine: ReviewRoutine?
}

@MainActor
struct RoutineListView: View {
    @Bindable var engine: RoutineEngine
    let repositories: [Repo]
    @Binding var selectedRoutineID: UUID?
    @State private var editorRequest: RoutineEditorRequest?

    var body: some View {
        VStack(spacing: 0) {
            header

            if engine.routines.isEmpty {
                ContentUnavailableView {
                    Label("No Routines", systemImage: "clock.arrow.2.circlepath")
                } description: {
                    Text("Create a routine to review new pull requests automatically.")
                } actions: {
                    Button("New Routine") { presentEditor(nil) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(engine.routines, id: \.id) { routine in
                            routineRow(routine)
                        }
                    }
                    .padding(12)
                }
            }

            activityFooter
        }
        .sheet(
            item: $editorRequest,
            onDismiss: {
                if selectedRoutineID == nil {
                    selectedRoutineID = engine.routines.first?.id
                }
            },
            content: { request in
                RoutineEditorView(
                    engine: engine,
                    repositories: repositories,
                    routine: request.routine
                )
            }
        )
        .alert(
            "Routine Error",
            isPresented: Binding(
                get: { engine.error != nil },
                set: { if !$0 { engine.error = nil } }
            )
        ) {
            Button("OK") { engine.error = nil }
        } message: {
            Text(engine.error ?? "Unknown error")
        }
        .onAppear {
            if selectedRoutineID == nil {
                selectedRoutineID = engine.routines.first?.id
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ROUTINES")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                Text("Automated PR reviews")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if engine.isPolling {
                ProgressView().controlSize(.small)
            }
            Button {
                presentEditor(nil)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("New Routine")
        }
        .padding(14)
        .overlay(alignment: .bottom) { Divider() }
    }

    // swiftlint:disable:next function_body_length
    private func routineRow(_ routine: ReviewRoutine) -> some View {
        let selected = selectedRoutineID == routine.id
        return Button {
            selectedRoutineID = routine.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(routine.isEnabled ? GRTheme.success : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text(routine.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if routine.lastError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(GRTheme.danger)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { routine.isEnabled },
                        set: { engine.setEnabled($0, for: routine) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }

                HStack(spacing: 5) {
                    Text("Every \(routine.intervalMinutes) min")
                    Text("·")
                    Text("\(routine.agentIDs.count) agents")
                    Text("·")
                    Text("\(routine.maxPullRequestsPerRun) PR/run")
                    Text("·")
                    Text(routine.publishingMode == .automaticComment
                        ? "Auto-post" : "Preview")
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)

                if routine.isEnabled {
                    Text(
                        "Next run at " + routine.nextRunAt.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                    )
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(11)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.12) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Run Now") { Task { await engine.runNow(routine) } }
            Button("Edit") { presentEditor(routine) }
            Divider()
            Button("Delete", role: .destructive) {
                if selectedRoutineID == routine.id { selectedRoutineID = nil }
                engine.delete(routine)
            }
        }
    }

    private var activityFooter: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(engine.activeRuns.isEmpty
                    ? Color.secondary : GRTheme.success)
            Text(engine.activeRuns.isEmpty
                ? "No active agents"
                : "\(engine.activeRuns.count) active PR reviews")
            Spacer()
            Button("Poll now") { Task { await engine.pollNow() } }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(engine.isPolling)
        }
        .font(.system(size: 10.5))
        .padding(12)
        .overlay(alignment: .top) { Divider() }
    }

    private func presentEditor(_ routine: ReviewRoutine?) {
        editorRequest = RoutineEditorRequest(routine: routine)
    }
}

@MainActor
struct RoutineDashboardView: View {
    @Bindable var engine: RoutineEngine
    let selectedRoutineID: UUID?
    @Environment(\.colorScheme) private var colorScheme

    private var routine: ReviewRoutine? {
        engine.routines.first { $0.id == selectedRoutineID }
    }

    private var visibleRuns: [RoutineRun] {
        guard let selectedRoutineID else { return engine.runs }
        return engine.runs.filter { $0.routineID == selectedRoutineID }
    }

    var body: some View {
        if let routine {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    routineHeader(routine)
                    pipelineStatus(routine)
                    metrics
                    activitySection
                }
                .padding(24)
            }
            .background(GRTheme.background(colorScheme))
        } else {
            ContentUnavailableView(
                "Select a Routine",
                systemImage: "clock.arrow.2.circlepath",
                description: Text("Choose a routine or create a new one.")
            )
        }
    }

    private func routineHeader(_ routine: ReviewRoutine) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(routine.name)
                    .font(.system(size: 24, weight: .bold))
                Text("\(routine.scope.rawValue) · every \(routine.intervalMinutes) minutes")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                "Post reviews automatically",
                isOn: Binding(
                    get: { routine.publishingMode == .automaticComment },
                    set: { engine.setAutomaticPosting($0, for: routine) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Post the completed review as a pull request comment")
            Button("Run Now") {
                Task { await engine.runNow(routine) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(engine.isPolling)
        }
    }

    private func pipelineStatus(_ routine: ReviewRoutine) -> some View {
        HStack(spacing: 12) {
            pipelineStage(
                icon: "arrow.clockwise",
                title: "Poll",
                detail: routine.isEnabled ? "Every \(routine.intervalMinutes) min" : "Paused"
            )
            pipelineArrow
            pipelineStage(
                icon: "sparkles",
                title: "Review",
                detail: "\(routine.agentIDs.count) agents · one AI run"
            )
            pipelineArrow
            pipelineStage(
                icon: routine.publishingMode == .automaticComment
                    ? "paperplane.fill" : "doc.text.magnifyingglass",
                title: routine.publishingMode == .automaticComment ? "Post" : "Preview",
                detail: routine.publishingMode == .automaticComment
                    ? "Automatic comment" : "Manual approval"
            )
            Spacer()
            Label(
                routine.isEnabled ? "Monitoring continuously" : "Routine paused",
                systemImage: routine.isEnabled ? "dot.radiowaves.left.and.right" : "pause.circle"
            )
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(routine.isEnabled ? GRTheme.success : Color.secondary)
        }
        .padding(14)
        .grCard()
    }

    private func pipelineStage(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GRTheme.accent)
                .frame(width: 28, height: 28)
                .background(GRTheme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pipelineArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private var metrics: some View {
        let posted = visibleRuns.filter { $0.status == .posted }.count
        let failed = visibleRuns.filter { $0.status == .failed }.count
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 130), spacing: 10)],
            spacing: 10
        ) {
            metricCard("Active", value: "\(visibleRuns.filter { $0.status.isActive }.count)")
            metricCard("Posted", value: "\(posted)")
            metricCard("Needs attention", value: "\(failed)")
            metricCard("Total runs", value: "\(visibleRuns.count)")
        }
    }

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .grCard()
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GRSectionLabel(title: "Agent Activity")
                if !engine.activeRuns.isEmpty {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Text("Live and recent runs")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if visibleRuns.isEmpty {
                ContentUnavailableView(
                    "No Runs Yet",
                    systemImage: "sparkles",
                    description: Text("Run this routine or wait for its next schedule.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
                .grCard()
            } else {
                ForEach(visibleRuns.prefix(20), id: \.id) { run in
                    RoutineRunCard(engine: engine, run: run)
                }
            }
        }
    }
}

@MainActor
private struct RoutineRunCard: View {
    @Bindable var engine: RoutineEngine
    let run: RoutineRun
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedAgentID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            runHeader

            if !run.agentSnapshots.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(run.agentSnapshots) { agent in
                        agentCard(agent)
                    }
                }

                if let selectedAgent {
                    agentDetail(selectedAgent)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if let error = run.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .textSelection(.enabled)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(GRTheme.danger)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GRTheme.danger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(16)
        .grCard()
    }

    private var runHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("#\(run.prNumber)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(run.prTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Text(run.repoName)
                    if let author = run.prAuthorLogin, !author.isEmpty {
                        Text("·")
                        Label("Opened by @\(author)", systemImage: "person")
                            .foregroundStyle(.primary)
                    }
                    if let createdAt = run.prCreatedAt {
                        Text("·")
                        Label(
                            createdAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            ),
                            systemImage: "calendar"
                        )
                    }
                    Text("·")
                    Text(String(run.headSHA.prefix(7)))
                    Text("·")
                    Text(run.lastEvent)
                }
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if run.status.isActive {
                ProgressView().controlSize(.small)
            }
            statusBadge
            if let url = URL(string: run.prURL) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
            }
            runActions
        }
    }

    private var statusBadge: some View {
        Text(run.status.displayName.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var runActions: some View {
        if run.status.isActive {
            Button("Cancel") { engine.cancel(run) }
                .buttonStyle(.plain)
                .font(.system(size: 10))
        } else if run.status == .failed || run.status == .cancelled {
            if engine.retryingRunIDs.contains(run.id) {
                ProgressView().controlSize(.small)
            } else {
                if retryableAgentCount > 0 && completedAgentCount > 0 {
                    Button("Retry failed (\(retryableAgentCount))") {
                        Task { await engine.retryFailedAgents(run) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .help("Reuse completed results and rerun unfinished agents")
                }
                Button(retryableAgentCount > 0 ? "Retry all" : "Retry") {
                    Task { await engine.retry(run) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
            }
        } else if run.status == .completed, run.reviewComment != nil {
            Button("Post Review") { Task { await engine.post(run) } }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var retryableAgentCount: Int {
        run.agentSnapshots.filter { $0.status != .completed }.count
    }

    private var completedAgentCount: Int {
        run.agentSnapshots.filter { $0.status == .completed }.count
    }

    private var selectedAgent: RoutineAgentSnapshot? {
        run.agentSnapshots.first { $0.id == selectedAgentID }
    }

    private func agentCard(_ agent: RoutineAgentSnapshot) -> some View {
        Button {
            guard agent.isInspectable else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedAgentID = selectedAgentID == agent.id ? nil : agent.id
            }
        } label: {
            agentCardContent(agent)
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(GRTheme.background(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        selectedAgentID == agent.id
                            ? GRTheme.accent : GRTheme.line(colorScheme)
                    )
            }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(agent.isInspectable)
        .accessibilityHint(agent.isInspectable ? "Show review details" : "")
    }

    private func agentCardContent(_ agent: RoutineAgentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(agent.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                agentIndicator(agent)
                if agent.isInspectable {
                    Image(systemName: selectedAgentID == agent.id
                          ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(agent.phase)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            agentMetadata(agent)
            if let error = agent.error {
                Text(error)
                    .font(.system(size: 9.5))
                    .foregroundStyle(GRTheme.danger)
                    .lineLimit(3)
            } else if agent.status == .reviewing,
                      let startedAt = agent.startedAt {
                Text(startedAt, style: .timer)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func agentMetadata(_ agent: RoutineAgentSnapshot) -> some View {
        if let provider = agent.providerName, let model = agent.modelName {
            VStack(alignment: .leading, spacing: 5) {
                Text(provider)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Label(model, systemImage: "cpu")
                        .lineLimit(1)
                    if let effort = agent.reasoningEffort {
                        Text("Effort: \(effort)")
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(GRTheme.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(GRTheme.accent.opacity(0.1))
                .clipShape(Capsule())
            }
        }
    }

    private func agentDetail(_ agent: RoutineAgentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(agent.name) details")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                if let duration = agent.durationText {
                    Label(duration, systemImage: "clock")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedAgentID = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }

            agentMetadata(agent)

            if let review = agent.reviewText {
                Text(PRReviewViewModel.stripVerdictLine(review))
                    .font(.system(size: 11))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = agent.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(GRTheme.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GRTheme.background(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(GRTheme.line(colorScheme))
        }
    }

    @ViewBuilder
    private func agentIndicator(_ agent: RoutineAgentSnapshot) -> some View {
        switch agent.status {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .reviewing:
            ProgressView().controlSize(.mini)
        case .completed:
            Circle()
                .fill(agent.verdict == false ? GRTheme.warning : GRTheme.success)
                .frame(width: 8, height: 8)
        case .failed:
            Circle().fill(GRTheme.danger).frame(width: 8, height: 8)
        case .cancelled:
            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch run.status {
        case .posted, .completed: GRTheme.success
        case .failed: GRTheme.danger
        case .cancelled: .secondary
        case .queued, .loading, .reviewing, .aggregating, .posting: GRTheme.accent
        }
    }
}

private extension RoutineAgentSnapshot {
    var isInspectable: Bool {
        reviewText != nil || error != nil
    }

    var durationText: String? {
        guard let startedAt, let completedAt else { return nil }
        let seconds = max(0, Int(completedAt.timeIntervalSince(startedAt)))
        return seconds >= 60
            ? String(format: "%d:%02d", seconds / 60, seconds % 60)
            : "\(seconds)s"
    }
}

@MainActor
private struct RoutineEditorView: View {
    @Bindable var engine: RoutineEngine
    let repositories: [Repo]
    let routine: ReviewRoutine?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedRepoIDs: Set<UUID>
    @State private var intervalMinutes: Int
    @State private var maxPullRequestsPerRun: Int
    @State private var scope: RoutinePRScope
    @State private var skipDrafts: Bool
    @State private var selectedAgentIDs: Set<String>
    @State private var providerRawValue: String
    @State private var modelName: String
    @State private var publishingMode: RoutinePublishingMode
    @State private var isEnabled: Bool
    @State private var settingsVM = AISettingsViewModel()

    init(
        engine: RoutineEngine,
        repositories: [Repo],
        routine: ReviewRoutine?
    ) {
        self.engine = engine
        self.repositories = repositories
        self.routine = routine
        _name = State(initialValue: routine?.name ?? "PR Review")
        _selectedRepoIDs = State(initialValue: Set(
            routine?.repoIDs ?? repositories.first.map { [$0.id] } ?? []
        ))
        _intervalMinutes = State(initialValue: routine?.intervalMinutes ?? 15)
        _maxPullRequestsPerRun = State(initialValue:
            routine?.maxPullRequestsPerRun ?? 1
        )
        _scope = State(initialValue: routine?.scope ?? .open)
        _skipDrafts = State(initialValue: routine?.skipDrafts ?? true)
        _selectedAgentIDs = State(initialValue: Set(
            routine?.agentIDs ?? ReviewAgent.allCases.map(\.rawValue)
        ))
        _providerRawValue = State(initialValue: routine?.provider?.rawValue ?? "")
        _modelName = State(initialValue: routine?.modelName ?? "")
        _publishingMode = State(initialValue: routine?.publishingMode ?? .preview)
        _isEnabled = State(initialValue: routine?.isEnabled ?? true)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(routine == nil ? "New Review Routine" : "Edit Review Routine")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(18)

            Divider()

            Form {
                Section("Routine") {
                    TextField("Name", text: $name)
                    Picker("Schedule", selection: $intervalMinutes) {
                        Text("Every 5 minutes").tag(5)
                        Text("Every 15 minutes").tag(15)
                        Text("Every 30 minutes").tag(30)
                        Text("Every hour").tag(60)
                        Text("Every day").tag(1_440)
                    }
                    Picker("PRs per run", selection: $maxPullRequestsPerRun) {
                        Text("1 pull request").tag(1)
                        Text("2 pull requests").tag(2)
                        Text("3 pull requests").tag(3)
                    }
                    Toggle("Enabled", isOn: $isEnabled)
                    Text("Schedules run while GitRanger is open, including from the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Repositories") {
                    ForEach(repositories, id: \.id) { repo in
                        Toggle(repo.name, isOn: membershipBinding(repo.id))
                    }
                }

                Section("Pull requests") {
                    Picker("Scope", selection: $scope) {
                        ForEach(RoutinePRScope.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Toggle("Skip draft pull requests", isOn: $skipDrafts)
                }

                Section("Review agents") {
                    ForEach(ReviewAgent.allCases) { agent in
                        Toggle(
                            agent.displayName,
                            isOn: agentBinding(agent.rawValue)
                        )
                    }
                    ForEach(availableCustomAgents, id: \.id) { agent in
                        Toggle(
                            "\(agent.name) · Repository agent",
                            isOn: agentBinding("custom:\(agent.id)")
                        )
                    }
                }

                Section("Model") {
                    Picker("Provider", selection: $providerRawValue) {
                        Text("Use global default").tag("")
                        ForEach(AIProvider.allCases, id: \.rawValue) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    if let provider = AIProvider(rawValue: providerRawValue) {
                        routineModelPicker(provider)
                    }
                }

                Section("Delivery") {
                    Toggle(
                        "Post review automatically",
                        isOn: automaticPostingBinding
                    )
                    Text(publishingMode == .automaticComment
                        ? "Poll → Review → Post. Each PR head receives one idempotent comment."
                        : "Poll → Review → Preview. You decide when to post the result.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Automatic posting never approves or merges a pull request.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Routine") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        name.trimmingCharacters(in: .whitespaces).isEmpty
                            || selectedRepoIDs.isEmpty
                            || selectedAgentIDs.isEmpty
                    )
            }
            .padding(16)
        }
        .frame(width: 620, height: 720)
        .onChange(of: providerRawValue) { _, _ in
            modelName = ""
        }
        .task(id: providerRawValue) {
            guard let provider = AIProvider(rawValue: providerRawValue) else {
                return
            }
            await settingsVM.loadModels(for: provider)
        }
    }

    private func routineModelPicker(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Picker("Model", selection: $modelName) {
                    Text("Use provider setting").tag("")
                    ForEach(settingsVM.models(for: provider).filter {
                        !$0.id.isEmpty
                    }) { option in
                        Text(option.name).tag(option.id)
                    }
                }

                Button {
                    Task {
                        await settingsVM.loadModels(for: provider, force: true)
                    }
                } label: {
                    if settingsVM.loadingModels.contains(provider) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .disabled(settingsVM.loadingModels.contains(provider))
                .help("Refresh available models")
            }

            TextField("Exact model ID", text: $modelName)
                .font(.system(size: 10.5, design: .monospaced))

            if let error = settingsVM.modelLoadErrors[provider] {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(GRTheme.warning)
            }
        }
    }

    private var automaticPostingBinding: Binding<Bool> {
        Binding(
            get: { publishingMode == .automaticComment },
            set: { publishingMode = $0 ? .automaticComment : .preview }
        )
    }

    private func membershipBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedRepoIDs.contains(id) },
            set: { selected in
                if selected {
                    selectedRepoIDs.insert(id)
                } else {
                    selectedRepoIDs.remove(id)
                }
            }
        )
    }

    private func agentBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selectedAgentIDs.contains(id) },
            set: { selected in
                if selected {
                    selectedAgentIDs.insert(id)
                } else {
                    selectedAgentIDs.remove(id)
                }
            }
        )
    }

    private var availableCustomAgents: [CustomReviewAgent] {
        var seen: Set<String> = []
        return repositories
            .filter { selectedRepoIDs.contains($0.id) }
            .flatMap(\.customAgents)
            .filter { $0.isEnabled && seen.insert($0.id).inserted }
    }

    private func save() {
        engine.save(RoutineDraft(
            id: routine?.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            repoIDs: Array(selectedRepoIDs),
            intervalMinutes: intervalMinutes,
            maxPullRequestsPerRun: maxPullRequestsPerRun,
            scope: scope,
            skipDrafts: skipDrafts,
            agentIDs: ReviewAgent.allCases.map(\.rawValue)
                .filter(selectedAgentIDs.contains)
                + availableCustomAgents
                    .map { "custom:\($0.id)" }
                    .filter(selectedAgentIDs.contains),
            provider: AIProvider(rawValue: providerRawValue),
            modelName: modelName.isEmpty ? nil : modelName,
            publishingMode: publishingMode,
            isEnabled: isEnabled
        ))
        dismiss()
    }
}
