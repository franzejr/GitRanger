package tui

import (
	"context"
	"fmt"
	"image/color"
	"strings"
	"time"

	"charm.land/bubbles/v2/spinner"
	"charm.land/bubbles/v2/viewport"
	tea "charm.land/bubbletea/v2"
	"charm.land/glamour/v2"
	"charm.land/lipgloss/v2"

	"github.com/franzejr/gitranger/cli/internal/config"
	"github.com/franzejr/gitranger/cli/internal/domain"
)

type screen int

const (
	dashboardScreen screen = iota
	routinesScreen
	runsScreen
	settingsScreen
)

type snapshotMsg struct {
	snapshot domain.Snapshot
	err      error
}

type refreshMsg time.Time

type actionMsg struct {
	label string
	err   error
}

type API interface {
	Snapshot(context.Context) (domain.Snapshot, error)
	PollRoutine(context.Context, string) error
	CancelRun(context.Context, string) error
	RetryRun(context.Context, string) error
}

type Model struct {
	client     API
	config     config.Config
	snapshot   domain.Snapshot
	spinner    spinner.Model
	viewport   viewport.Model
	screen     screen
	selected   int
	width      int
	height     int
	loading    bool
	error      string
	detailOpen bool

	routineSelected int
	actionPending   bool
	notice          string
	noticeError     bool
	detailVersion   uint64
	detailCached    bool
	detailRunID     string
}

var (
	accent       = lipgloss.Color("#FF754B")
	accentSoft   = lipgloss.Color("#713927")
	green        = lipgloss.Color("#65DFA4")
	yellow       = lipgloss.Color("#F5B74C")
	red          = lipgloss.Color("#FF7474")
	muted        = lipgloss.Color("#8B8D98")
	surface      = lipgloss.Color("#202126")
	border       = lipgloss.Color("#34353D")
	primary      = lipgloss.Color("#E8E8EA")
	titleStyle   = lipgloss.NewStyle().Bold(true).Foreground(primary)
	mutedStyle   = lipgloss.NewStyle().Foreground(muted)
	accentStyle  = lipgloss.NewStyle().Foreground(accent).Bold(true)
	sectionStyle = lipgloss.NewStyle().Foreground(muted).Bold(true)
	cardStyle    = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).
			BorderForeground(border).Background(surface).Padding(1, 2)
)

func New(client API, cfg config.Config) Model {
	activity := spinner.New()
	activity.Spinner = spinner.Dot
	activity.Style = lipgloss.NewStyle().Foreground(accent)
	view := viewport.New(viewport.WithWidth(80), viewport.WithHeight(24))
	view.SoftWrap = true
	return Model{
		client: client, config: cfg, spinner: activity, viewport: view,
		loading: true,
	}
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(m.spinner.Tick, m.loadSnapshot(), refreshAfter())
}

func (m Model) Update(message tea.Msg) (tea.Model, tea.Cmd) {
	var commands []tea.Cmd
	switch message := message.(type) {
	case tea.WindowSizeMsg:
		m.width = message.Width
		m.height = message.Height
		m.resizeViewport()
	case tea.KeyPressMsg:
		switch message.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "1":
			m.screen, m.detailOpen = dashboardScreen, false
		case "2":
			m.screen, m.detailOpen = routinesScreen, false
		case "3":
			m.screen, m.detailOpen = runsScreen, false
		case "4":
			m.screen, m.detailOpen = settingsScreen, false
		case "tab":
			m.screen = (m.screen + 1) % 4
			m.detailOpen = false
		case "shift+tab":
			m.screen = (m.screen + 3) % 4
			m.detailOpen = false
		case "j", "down":
			if !m.detailOpen {
				if m.screen == routinesScreen && m.routineSelected+1 < len(m.config.Routines) {
					m.routineSelected++
				} else if m.screen != routinesScreen && m.selected+1 < len(m.snapshot.RecentRuns) {
					m.selected++
				}
			}
		case "k", "up":
			if !m.detailOpen {
				if m.screen == routinesScreen && m.routineSelected > 0 {
					m.routineSelected--
				} else if m.screen != routinesScreen && m.selected > 0 {
					m.selected--
				}
			}
		case "enter":
			if m.screen == routinesScreen {
				if command := m.pollSelectedRoutine(); command != nil {
					commands = append(commands, command)
				}
			} else if len(m.snapshot.RecentRuns) > 0 {
				m.detailOpen = true
				m.setDetailContent(true)
			}
		case "esc", "backspace":
			m.detailOpen = false
		case "r":
			if command := m.beginSnapshotRefresh(); command != nil {
				commands = append(commands, command)
			}
		case "p":
			if command := m.pollSelectedRoutine(); command != nil {
				commands = append(commands, command)
			}
		case "R":
			if command := m.retrySelectedRun(); command != nil {
				commands = append(commands, command)
			}
		case "x":
			if command := m.cancelSelectedRun(); command != nil {
				commands = append(commands, command)
			}
		}
	case snapshotMsg:
		m.loading = false
		if message.err != nil {
			m.error = message.err.Error()
		} else {
			selectedRunID := ""
			if m.selected >= 0 && m.selected < len(m.snapshot.RecentRuns) {
				selectedRunID = runIdentity(m.snapshot.RecentRuns[m.selected])
			}
			m.error = ""
			m.snapshot = message.snapshot
			if selectedRunID != "" {
				for index, run := range m.snapshot.RecentRuns {
					if runIdentity(run) == selectedRunID {
						m.selected = index
						break
					}
				}
			}
			if len(m.snapshot.RecentRuns) == 0 {
				m.selected = 0
				m.detailOpen = false
				m.detailCached = false
				m.detailRunID = ""
			} else if m.selected < 0 || m.selected >= len(m.snapshot.RecentRuns) {
				m.selected = max(0, len(m.snapshot.RecentRuns)-1)
			}
			if m.routineSelected >= len(m.config.Routines) {
				m.routineSelected = max(0, len(m.config.Routines)-1)
			}
			if m.detailOpen {
				m.setDetailContent(false)
			}
		}
	case refreshMsg:
		if command := m.beginSnapshotRefresh(); command != nil {
			commands = append(commands, command)
		}
		commands = append(commands, refreshAfter())
	case actionMsg:
		m.actionPending = false
		m.noticeError = message.err != nil
		if message.err != nil {
			m.notice = message.label + ": " + message.err.Error()
		} else {
			m.notice = message.label
		}
		if command := m.beginSnapshotRefresh(); command != nil {
			commands = append(commands, command)
		}
	}
	var command tea.Cmd
	m.spinner, command = m.spinner.Update(message)
	commands = append(commands, command)
	if m.detailOpen {
		m.viewport, command = m.viewport.Update(message)
		commands = append(commands, command)
	}
	return m, tea.Batch(commands...)
}

func (m Model) View() tea.View {
	view := tea.NewView(m.render())
	view.AltScreen = true
	view.WindowTitle = "GitRanger · Review Routines"
	return view
}

func (m Model) render() string {
	width := max(60, m.width)
	header := m.renderHeader(width)
	footer := m.renderFooter(width)
	if m.detailOpen {
		return header + "\n" + m.viewport.View() + "\n" + footer
	}
	contentHeight := max(8, m.height-lipgloss.Height(header)-lipgloss.Height(footer)-2)
	content := m.renderScreen(width, contentHeight)
	return header + "\n" + content + "\n" + footer
}

func (m Model) renderHeader(width int) string {
	logo := accentStyle.Render("GR") + "  " + titleStyle.Render("GitRanger")
	state := lipgloss.NewStyle().Foreground(green).Render("● daemon online")
	if m.error != "" {
		state = lipgloss.NewStyle().Foreground(red).Render("● daemon unavailable")
	}
	metrics := fmt.Sprintf("%d active  ·  %d queued  ·  %d failed",
		m.snapshot.ActiveRuns, m.snapshot.QueuedRuns, m.snapshot.FailedRuns)
	right := state + "  " + mutedStyle.Render(metrics)
	space := max(1, width-lipgloss.Width(logo)-lipgloss.Width(right)-2)
	return lipgloss.NewStyle().Width(width).Padding(0, 1).
		Render(logo + strings.Repeat(" ", space) + right)
}

func (m Model) renderFooter(width int) string {
	help := "1 dashboard   2 routines   3 runs   4 settings   j/k navigate   enter details   r refresh   q quit"
	if m.detailOpen {
		help = "↑/↓ scroll   pgup/pgdn page   esc back   r refresh   q quit"
	} else if m.screen == routinesScreen {
		help = "j/k select   enter/p poll now   r refresh   q quit"
	} else if m.screen == runsScreen || m.screen == dashboardScreen {
		help = "j/k select   enter details   R retry   x cancel   r refresh   q quit"
	}
	return lipgloss.NewStyle().Width(width).Foreground(muted).
		BorderStyle(lipgloss.NormalBorder()).BorderTop(true).
		BorderForeground(border).Padding(0, 1).Render(help)
}

func (m Model) renderScreen(width, height int) string {
	if m.error != "" {
		return cardStyle.BorderForeground(red).Width(max(20, width-6)).Render(
			titleStyle.Render("Daemon connection failed") + "\n\n" + m.error +
				"\n\nRun `gitranger daemon start` and press r.")
	}
	if width >= 100 {
		sidebarWidth := 24
		sidebar := m.renderSidebar(sidebarWidth, height)
		main := m.renderMain(width-sidebarWidth-3, height)
		return lipgloss.JoinHorizontal(lipgloss.Top, sidebar, "  ", main)
	}
	return m.renderTopNav(width) + "\n" + m.renderMain(width, height-3)
}

func (m Model) renderSidebar(width, height int) string {
	items := []string{"Dashboard", "Routines", "Runs", "Settings"}
	var lines []string
	lines = append(lines, sectionStyle.Render("NAVIGATION"), "")
	for index, item := range items {
		style := lipgloss.NewStyle().Foreground(muted).Width(width-4).Padding(0, 1)
		prefix := "  "
		if screen(index) == m.screen {
			style = style.Foreground(primary).Background(accentSoft).Bold(true)
			prefix = "▸ "
		}
		lines = append(lines, style.Render(prefix+item))
	}
	lines = append(lines, "", sectionStyle.Render("PIPELINE"), "",
		pipelineLine("1", "Poll", true),
		pipelineLine("2", "Review", m.snapshot.ActiveRuns > 0),
		pipelineLine("3", "Post", false), "")
	if m.loading {
		lines = append(lines, m.spinner.View()+" Syncing activity")
	} else if m.snapshot.NextPollAt != nil {
		lines = append(lines, mutedStyle.Render("Next poll "+relativeTime(*m.snapshot.NextPollAt)))
	}
	return lipgloss.NewStyle().Width(width).Height(height).
		BorderStyle(lipgloss.NormalBorder()).BorderRight(true).
		BorderForeground(border).Padding(1, 1).Render(strings.Join(lines, "\n"))
}

func pipelineLine(number, label string, active bool) string {
	color := muted
	marker := "○"
	if active {
		color, marker = accent, "●"
	}
	return lipgloss.NewStyle().Foreground(color).Render(fmt.Sprintf("%s %s  %s", marker, number, label))
}

func (m Model) renderTopNav(width int) string {
	items := []string{"1 Dashboard", "2 Routines", "3 Runs", "4 Settings"}
	for index := range items {
		style := mutedStyle
		if screen(index) == m.screen {
			style = accentStyle
		}
		items[index] = style.Render(items[index])
	}
	return lipgloss.NewStyle().Width(width).Padding(0, 1).Render(strings.Join(items, "   "))
}

func (m Model) renderMain(width, height int) string {
	var content string
	switch m.screen {
	case routinesScreen:
		content = m.renderRoutines(width, height)
	case runsScreen:
		content = m.renderRuns(width, height)
	case settingsScreen:
		content = m.renderSettings(width, height)
	default:
		content = m.renderDashboard(width, height)
	}
	if m.notice == "" {
		return content
	}
	style := lipgloss.NewStyle().Foreground(green)
	if m.noticeError {
		style = style.Foreground(red)
	}
	return style.Render(m.notice) + "\n" + content
}

func (m Model) renderDashboard(width, height int) string {
	title := titleStyle.Render("Review operations") + "\n" +
		mutedStyle.Render("Continuous Poll → Review → Post pipeline")
	cards := []string{
		metricCard("ACTIVE", m.snapshot.ActiveRuns, accent, max(15, (width-6)/4)),
		metricCard("QUEUED", m.snapshot.QueuedRuns, yellow, max(15, (width-6)/4)),
		metricCard("FAILED", m.snapshot.FailedRuns, red, max(15, (width-6)/4)),
		metricCard("ROUTINES", m.snapshot.Routines, green, max(15, (width-6)/4)),
	}
	metrics := lipgloss.JoinHorizontal(lipgloss.Top, intersperse(cards, " ")...)
	activity := m.runList(width, max(5, height-lipgloss.Height(metrics)-5), 6)
	return title + "\n\n" + metrics + "\n\n" + sectionStyle.Render("LIVE AND RECENT RUNS") + "\n" + activity
}

func metricCard(label string, value int, color color.Color, width int) string {
	return cardStyle.Width(width).Render(
		sectionStyle.Render(label) + "\n" +
			lipgloss.NewStyle().Foreground(color).Bold(true).Render(fmt.Sprint(value)))
}

func (m Model) renderRoutines(width, height int) string {
	lines := []string{titleStyle.Render("Routines"), mutedStyle.Render("Durable schedules owned by the daemon"), ""}
	if len(m.config.Routines) == 0 {
		lines = append(lines, cardStyle.Width(max(20, width-6)).Render(
			"No routines configured.\n\nRun `gitranger config init`, then edit config.yaml."))
	}
	start, end := visibleWindow(
		len(m.config.Routines), m.routineSelected, max(1, height-3), 6, len(m.config.Routines),
	)
	for index := start; index < end; index++ {
		routine := m.config.Routines[index]
		state := lipgloss.NewStyle().Foreground(green).Render("● ENABLED")
		if !routine.Enabled {
			state = mutedStyle.Render("○ PAUSED")
		}
		delivery := strings.ReplaceAll(routine.Delivery, "_", " ")
		content := titleStyle.Render(routine.Name) + "  " + state + "\n" +
			mutedStyle.Render(fmt.Sprintf("Every %s  ·  %d repo(s)  ·  %d agents  ·  %s",
				routine.IntervalRaw, len(routine.RepositoryIDs), len(routine.Agents), delivery)) + "\n" +
			accentStyle.Render("Poll") + mutedStyle.Render("  →  ") +
			accentStyle.Render("Review") + mutedStyle.Render("  →  ") + accentStyle.Render("Post")
		style := cardStyle.Width(max(20, width-6))
		if index == m.routineSelected {
			style = style.BorderForeground(accent)
		}
		lines = append(lines, style.Render(content))
	}
	return trimHeight(strings.Join(lines, "\n"), height)
}

func (m Model) renderRuns(width, height int) string {
	header := titleStyle.Render("Runs") + "\n" + mutedStyle.Render("Select a run and press enter for the full review") + "\n\n"
	return header + m.runList(width, height-lipgloss.Height(header), 20)
}

func (m Model) runList(width, height, limit int) string {
	if len(m.snapshot.RecentRuns) == 0 {
		return mutedStyle.Render("No review runs yet.")
	}
	start, end := visibleWindow(len(m.snapshot.RecentRuns), m.selected, height, 6, limit)
	var cards []string
	for index := start; index < end; index++ {
		run := m.snapshot.RecentRuns[index]
		style := cardStyle.Width(max(20, width-6))
		if index == m.selected {
			style = style.BorderForeground(accent)
		}
		status := statusStyle(run.Status).Render(strings.ToUpper(string(run.Status)))
		title := fmt.Sprintf("#%d  %s", run.PRNumber, truncate(run.PRTitle, max(18, width-35)))
		meta := fmt.Sprintf("%s · opened by @%s · %s · attempt %d/%d",
			run.Repository, defaultText(run.PRAuthor, "unknown"), shortSHA(run.HeadSHA),
			run.Attempts, run.MaxAttempts)
		agents := renderAgentStrip(run.Agents, width-8)
		cards = append(cards, style.Render(
			titleStyle.Render(title)+"  "+status+"\n"+mutedStyle.Render(meta)+"\n"+agents))
	}
	return trimHeight(strings.Join(cards, "\n"), height)
}

func renderAgentStrip(agents []domain.AgentRun, width int) string {
	var items []string
	for _, agent := range agents {
		icon := "○"
		color := muted
		switch agent.Status {
		case domain.AgentReviewing:
			icon, color = "◌", accent
		case domain.AgentCompleted:
			icon, color = "●", green
			if agent.Verdict != nil && !*agent.Verdict {
				color = yellow
			}
		case domain.AgentFailed:
			icon, color = "●", red
		case domain.AgentCancelled:
			icon = "×"
		}
		items = append(items, lipgloss.NewStyle().Foreground(color).Render(icon+" "+agent.Name))
	}
	value := strings.Join(items, "   ")
	return truncate(value, width)
}

func (m Model) renderSettings(width, height int) string {
	provider := m.config.Provider
	content := []string{
		titleStyle.Render("Settings"),
		mutedStyle.Render("Versioned config contains no secrets"), "",
		cardStyle.Width(max(20, width-6)).Render(
			sectionStyle.Render("EXECUTION") + "\n" +
				fmt.Sprintf("Max active reviews    %d\nReview timeout       %s\nScheduler tick       %s",
					m.config.Execution.MaxActiveReviews,
					m.config.Execution.ReviewTimeoutRaw,
					m.config.Execution.PollTickRaw)),
		cardStyle.Width(max(20, width-6)).Render(
			sectionStyle.Render("PROVIDER") + "\n" +
				fmt.Sprintf("Name                  %s\nCommand               %s\nModel                 %s\nEffort                %s",
					provider.Name, provider.Command, defaultText(provider.Model, "provider default"), provider.Effort)),
		cardStyle.Width(max(20, width-6)).Render(
			sectionStyle.Render("STORAGE") + "\n" +
				"SQLite WAL · durable queue · immutable PR cache\n" +
				"Configuration changes are applied after daemon restart."),
	}
	return trimHeight(strings.Join(content, "\n"), height)
}

func (m *Model) resizeViewport() {
	m.viewport.SetWidth(max(20, m.width-4))
	m.viewport.SetHeight(max(5, m.height-5))
}

func (m *Model) setDetailContent(force bool) {
	if len(m.snapshot.RecentRuns) == 0 {
		return
	}
	run := m.snapshot.RecentRuns[m.selected]
	version := detailFingerprint(run)
	if !force && m.detailCached && version == m.detailVersion {
		return
	}
	previousOffset := m.viewport.YOffset()
	previousRunID := m.detailRunID
	header := titleStyle.Render(fmt.Sprintf("#%d %s", run.PRNumber, run.PRTitle)) + "\n" +
		mutedStyle.Render(fmt.Sprintf("%s · @%s · %s · %s",
			run.Repository, run.PRAuthor, shortSHA(run.HeadSHA), run.Status)) + "\n\n"
	var body string
	if run.ReviewComment != "" {
		rendered, err := glamour.Render(run.ReviewComment, "dark")
		if err == nil {
			body = rendered
		} else {
			body = run.ReviewComment
		}
	} else {
		var agents []string
		for _, agent := range run.Agents {
			line := fmt.Sprintf("%s · %s · %s · effort: %s",
				agent.Name, agent.Status, agent.Model, agent.Effort)
			if agent.Error != "" {
				line += "\n  " + lipgloss.NewStyle().Foreground(red).Render(agent.Error)
			}
			agents = append(agents, line)
		}
		body = strings.Join(agents, "\n\n")
	}
	m.viewport.SetContent(header + body)
	m.detailVersion = version
	m.detailCached = true
	m.detailRunID = runIdentity(run)
	if force || previousRunID != m.detailRunID {
		m.viewport.GotoTop()
	} else {
		m.viewport.SetYOffset(previousOffset)
	}
}

func (m Model) loadSnapshot() tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		snapshot, err := m.client.Snapshot(ctx)
		return snapshotMsg{snapshot: snapshot, err: err}
	}
}

func (m *Model) beginSnapshotRefresh() tea.Cmd {
	if m.loading {
		return nil
	}
	m.loading = true
	return m.loadSnapshot()
}

func (m *Model) pollSelectedRoutine() tea.Cmd {
	if m.actionPending || m.client == nil || m.screen != routinesScreen ||
		m.routineSelected >= len(m.config.Routines) {
		return nil
	}
	routine := m.config.Routines[m.routineSelected]
	m.actionPending = true
	m.notice, m.noticeError = "Polling "+routine.Name+"…", false
	return actionCommand("Poll requested for "+routine.Name, func(ctx context.Context) error {
		return m.client.PollRoutine(ctx, routine.ID)
	})
}

func (m *Model) retrySelectedRun() tea.Cmd {
	run, ok := m.selectedRun()
	if !ok || m.actionPending || m.client == nil ||
		(run.Status != domain.RunFailed && run.Status != domain.RunCancelled) {
		return nil
	}
	m.actionPending = true
	m.notice, m.noticeError = fmt.Sprintf("Retrying %s #%d…", run.Repository, run.PRNumber), false
	return actionCommand(fmt.Sprintf("Retry queued for %s #%d", run.Repository, run.PRNumber), func(ctx context.Context) error {
		return m.client.RetryRun(ctx, run.ID)
	})
}

func (m *Model) cancelSelectedRun() tea.Cmd {
	run, ok := m.selectedRun()
	if !ok || m.actionPending || m.client == nil || !run.Status.Active() {
		return nil
	}
	m.actionPending = true
	m.notice, m.noticeError = fmt.Sprintf("Cancelling %s #%d…", run.Repository, run.PRNumber), false
	return actionCommand(fmt.Sprintf("Cancelled %s #%d", run.Repository, run.PRNumber), func(ctx context.Context) error {
		return m.client.CancelRun(ctx, run.ID)
	})
}

func (m Model) selectedRun() (domain.Run, bool) {
	if m.detailOpen || (m.screen != runsScreen && m.screen != dashboardScreen) ||
		m.selected < 0 || m.selected >= len(m.snapshot.RecentRuns) {
		return domain.Run{}, false
	}
	return m.snapshot.RecentRuns[m.selected], true
}

func actionCommand(label string, action func(context.Context) error) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return actionMsg{label: label, err: action(ctx)}
	}
}

func refreshAfter() tea.Cmd {
	return tea.Tick(time.Second, func(when time.Time) tea.Msg { return refreshMsg(when) })
}

func statusStyle(status domain.RunStatus) lipgloss.Style {
	color := accent
	switch status {
	case domain.RunCompleted, domain.RunPosted:
		color = green
	case domain.RunFailed:
		color = red
	case domain.RunRetrying:
		color = yellow
	case domain.RunCancelled:
		color = muted
	}
	return lipgloss.NewStyle().Foreground(color).Bold(true)
}

func relativeTime(value time.Time) string {
	delta := time.Until(value)
	if delta <= 0 {
		return "now"
	}
	if delta < time.Minute {
		return fmt.Sprintf("in %ds", int(delta.Seconds()))
	}
	return fmt.Sprintf("in %dm", int(delta.Minutes()))
}

func truncate(value string, width int) string {
	if width <= 1 || lipgloss.Width(value) <= width {
		return value
	}
	runes := []rune(value)
	for len(runes) > 0 && lipgloss.Width(string(runes))+1 > width {
		runes = runes[:len(runes)-1]
	}
	return string(runes) + "…"
}

func visibleWindow(total, selected, height, cardHeight, limit int) (int, int) {
	if total <= 0 || limit <= 0 {
		return 0, 0
	}
	visible := min(total, limit, max(1, height/max(1, cardHeight)))
	selected = min(max(0, selected), total-1)
	start := (selected / visible) * visible
	end := min(total, start+visible)
	return start, end
}

func detailFingerprint(run domain.Run) uint64 {
	hash := uint64(14695981039346656037)
	hash = hashDetailString(hash, runIdentity(run))
	hash = hashDetailString(hash, string(run.Status))
	hash = hashDetailString(hash, run.LastEvent)
	hash = hashDetailString(hash, run.Error)
	hash = hashDetailString(hash, run.ReviewComment)
	for _, agent := range run.Agents {
		hash = hashDetailString(hash, agent.ID)
		hash = hashDetailString(hash, agent.Name)
		hash = hashDetailString(hash, string(agent.Status))
		hash = hashDetailString(hash, agent.Phase)
		hash = hashDetailString(hash, agent.Provider)
		hash = hashDetailString(hash, agent.Model)
		hash = hashDetailString(hash, agent.Effort)
		hash = hashDetailString(hash, agent.Output)
		hash = hashDetailString(hash, agent.Error)
		if agent.Verdict == nil {
			hash = hashDetailString(hash, "unset")
		} else if *agent.Verdict {
			hash = hashDetailString(hash, "pass")
		} else {
			hash = hashDetailString(hash, "fail")
		}
	}
	return hash
}

func hashDetailString(hash uint64, value string) uint64 {
	const prime = uint64(1099511628211)
	for index := range len(value) {
		hash ^= uint64(value[index])
		hash *= prime
	}
	hash ^= 0
	hash *= prime
	return hash
}

func runIdentity(run domain.Run) string {
	if run.ID != "" {
		return run.ID
	}
	return fmt.Sprintf("%s#%d@%s", run.Repository, run.PRNumber, run.HeadSHA)
}

func trimHeight(value string, height int) string {
	lines := strings.Split(value, "\n")
	if len(lines) <= height {
		return value
	}
	return strings.Join(lines[:max(1, height-1)], "\n") + "\n" + mutedStyle.Render("…")
}

func shortSHA(value string) string {
	if len(value) <= 7 {
		return value
	}
	return value[:7]
}

func defaultText(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

func intersperse(values []string, separator string) []string {
	if len(values) < 2 {
		return values
	}
	result := make([]string, 0, len(values)*2-1)
	for index, value := range values {
		if index > 0 {
			result = append(result, separator)
		}
		result = append(result, value)
	}
	return result
}
