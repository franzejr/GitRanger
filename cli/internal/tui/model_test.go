package tui

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/franzejr/gitranger/cli/internal/config"
	"github.com/franzejr/gitranger/cli/internal/domain"
)

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
	model.setDetailContent()
	rendered := model.viewport.View()
	for _, expected := range []string{"Security", "model-x", "low", "request timed out"} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("detail missing %q:\n%s", expected, rendered)
		}
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
