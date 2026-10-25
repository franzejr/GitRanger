package tui

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/franzejr/gitranger/cli/internal/config"
	"github.com/franzejr/gitranger/cli/internal/domain"
)

type fakeAPI struct {
	snapshotCalls int
	polled        []string
	retried       []string
	cancelled     []string
}

func (f *fakeAPI) Snapshot(context.Context) (domain.Snapshot, error) {
	f.snapshotCalls++
	return domain.Snapshot{}, nil
}

func (f *fakeAPI) PollRoutine(_ context.Context, id string) error {
	f.polled = append(f.polled, id)
	return nil
}

func (f *fakeAPI) RetryRun(_ context.Context, id string) error {
	f.retried = append(f.retried, id)
	return nil
}

func (f *fakeAPI) CancelRun(_ context.Context, id string) error {
	f.cancelled = append(f.cancelled, id)
	return nil
}

func TestDashboardRendersWideAndNarrowLayouts(t *testing.T) {
	model := New(nil, config.Config{Routines: []config.Routine{{Name: "New PRs"}}})
	model.snapshot = domain.Snapshot{
		Version: "test", StartedAt: time.Now(), Routines: 1, ActiveRuns: 1,
		RecentRuns: []domain.Run{{
			PRNumber: 42, PRTitle: "Make the terminal smooth", Repository: "GitRanger",
			PRAuthor: "octocat", HeadSHA: "abcdef123", Status: domain.RunReviewing,
			Attempts: 1, MaxAttempts: 3,
		}},
	}
	model.width, model.height = 130, 40
	wide := model.render()
	if !strings.Contains(wide, "Review operations") || !strings.Contains(wide, "NAVIGATION") {
		t.Fatalf("wide dashboard is incomplete:\n%s", wide)
	}
	model.width, model.height = 80, 24
	narrow := model.render()
	if !strings.Contains(narrow, "1 Dashboard") || strings.Contains(narrow, "NAVIGATION") {
		t.Fatalf("narrow dashboard did not adapt:\n%s", narrow)
	}
}

func TestRunDetailIncludesModelAndEffort(t *testing.T) {
	model := New(nil, config.Config{})
	model.width, model.height = 100, 30
	model.resizeViewport()
	model.snapshot.RecentRuns = []domain.Run{{
		PRNumber: 1, PRTitle: "Review metadata", Repository: "Repo",
		PRAuthor: "author", HeadSHA: "abcdefghi", Status: domain.RunFailed,
		Agents: []domain.AgentRun{{
			Name: "Security", Status: domain.AgentFailed,
			Model: "model-x", Effort: "low", Error: "request timed out",
		}},
	}}
	model.detailOpen = true
	model.setDetailContent(true)
	rendered := model.viewport.View()
	for _, expected := range []string{"Security", "model-x", "low", "request timed out"} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("detail missing %q:\n%s", expected, rendered)
		}
	}
}

func TestSnapshotRefreshDoesNotOverlap(t *testing.T) {
	client := &fakeAPI{}
	model := New(client, config.Config{})
	if command := model.beginSnapshotRefresh(); command != nil {
		t.Fatal("started a second snapshot while the initial request was active")
	}
	model.loading = false
	command := model.beginSnapshotRefresh()
	if command == nil || !model.loading {
		t.Fatal("did not start an idle snapshot request")
	}
	if _, ok := command().(snapshotMsg); !ok {
		t.Fatal("snapshot command returned an unexpected message")
	}
	if client.snapshotCalls != 1 {
		t.Fatalf("snapshot calls = %d, want 1", client.snapshotCalls)
	}
}

func TestUnchangedDetailPreservesScrollPosition(t *testing.T) {
	model := New(nil, config.Config{})
	model.width, model.height = 80, 12
	model.resizeViewport()
	model.snapshot.RecentRuns = []domain.Run{{
		ID: "run-1", PRNumber: 1, PRTitle: "Long review", Repository: "Repo",
		HeadSHA: "abcdef1", Status: domain.RunCompleted,
		ReviewComment: strings.Repeat("review line\n\n", 80),
	}}
	model.detailOpen = true
	model.setDetailContent(true)
	model.viewport.SetYOffset(10)
	model.setDetailContent(false)
	if offset := model.viewport.YOffset(); offset != 10 {
		t.Fatalf("unchanged detail offset = %d, want 10", offset)
	}
	model.snapshot.RecentRuns[0].LastEvent = "Updated"
	model.setDetailContent(false)
	if offset := model.viewport.YOffset(); offset != 10 {
		t.Fatalf("updated detail offset = %d, want 10", offset)
	}
}

func TestSnapshotPrependPreservesSelectedRunAndDetailOffset(t *testing.T) {
	model := New(nil, config.Config{})
	model.width, model.height = 80, 12
	model.resizeViewport()
	selected := domain.Run{
		ID: "run-selected", PRNumber: 1, PRTitle: "Selected", Repository: "Repo",
		HeadSHA: "abcdef1", Status: domain.RunCompleted,
		ReviewComment: strings.Repeat("review line\n\n", 80),
	}
	model.snapshot.RecentRuns = []domain.Run{selected}
	model.detailOpen = true
	model.setDetailContent(true)
	model.viewport.SetYOffset(10)
	updatedModel, _ := model.Update(snapshotMsg{snapshot: domain.Snapshot{
		RecentRuns: []domain.Run{{
			ID: "run-new", PRNumber: 2, PRTitle: "New", Repository: "Repo",
			HeadSHA: "1234567", Status: domain.RunQueued,
		}, selected},
	}})
	updated := updatedModel.(Model)
	if updated.selected != 1 || runIdentity(updated.snapshot.RecentRuns[updated.selected]) != "run-selected" {
		t.Fatalf("selected index = %d, run = %s", updated.selected,
			runIdentity(updated.snapshot.RecentRuns[updated.selected]))
	}
	if offset := updated.viewport.YOffset(); offset != 10 {
		t.Fatalf("detail offset = %d, want 10", offset)
	}
}

func TestRoutineAndRunControlsCallDaemonAPI(t *testing.T) {
	client := &fakeAPI{}
	routineModel := New(client, config.Config{Routines: []config.Routine{{ID: "routine-1", Name: "Routine"}}})
	routineModel.screen = routinesScreen
	if message := routineModel.pollSelectedRoutine()(); message.(actionMsg).err != nil {
		t.Fatal(message.(actionMsg).err)
	}
	if len(client.polled) != 1 || client.polled[0] != "routine-1" {
		t.Fatalf("polled = %v", client.polled)
	}

	retryModel := New(client, config.Config{})
	retryModel.loading = false
	retryModel.screen = runsScreen
	retryModel.snapshot.RecentRuns = []domain.Run{{ID: "run-failed", Status: domain.RunFailed}}
	if message := retryModel.retrySelectedRun()(); message.(actionMsg).err != nil {
		t.Fatal(message.(actionMsg).err)
	}
	if len(client.retried) != 1 || client.retried[0] != "run-failed" {
		t.Fatalf("retried = %v", client.retried)
	}

	cancelModel := New(client, config.Config{})
	cancelModel.loading = false
	cancelModel.screen = runsScreen
	cancelModel.snapshot.RecentRuns = []domain.Run{{ID: "run-active", Status: domain.RunReviewing}}
	if message := cancelModel.cancelSelectedRun()(); message.(actionMsg).err != nil {
		t.Fatal(message.(actionMsg).err)
	}
	if len(client.cancelled) != 1 || client.cancelled[0] != "run-active" {
		t.Fatalf("cancelled = %v", client.cancelled)
	}
}

func TestRunWindowKeepsSelectionVisible(t *testing.T) {
	start, end := visibleWindow(20, 13, 12, 6, 20)
	if start > 13 || end <= 13 {
		t.Fatalf("window [%d,%d) does not contain selected run", start, end)
	}
}

func BenchmarkDashboardRender(b *testing.B) {
	model := New(nil, config.Config{Routines: []config.Routine{{Name: "Continuous review"}}})
	model.width, model.height = 140, 45
	model.snapshot = domain.Snapshot{
		Version: "benchmark", StartedAt: time.Now(), Routines: 1, ActiveRuns: 2,
	}
	for index := range 50 {
		model.snapshot.RecentRuns = append(model.snapshot.RecentRuns, domain.Run{
			PRNumber: index + 1, PRTitle: fmt.Sprintf("Pull request %d", index+1),
			Repository: "GitRanger", PRAuthor: "octocat", HeadSHA: "abcdef123",
			Status: domain.RunCompleted, Attempts: 1, MaxAttempts: 3,
			Agents: []domain.AgentRun{
				{Name: "Summary", Status: domain.AgentCompleted},
				{Name: "Security", Status: domain.AgentCompleted},
				{Name: "Performance", Status: domain.AgentCompleted},
			},
		})
	}
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		_ = model.render()
	}
}

func BenchmarkUnchangedDetailRefresh(b *testing.B) {
	model := New(nil, config.Config{})
	model.width, model.height = 120, 40
	model.resizeViewport()
	model.snapshot.RecentRuns = []domain.Run{{
		ID: "run-1", PRNumber: 42, PRTitle: "Large rendered review",
		Repository: "GitRanger", HeadSHA: "abcdef123", Status: domain.RunCompleted,
		ReviewComment: strings.Repeat("## Finding\n\nDetailed review result.\n\n", 100),
	}}
	model.detailOpen = true
	model.setDetailContent(true)
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		model.setDetailContent(false)
	}
}
