package engine

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/franzejr/gitranger/cli/internal/config"
	"github.com/franzejr/gitranger/cli/internal/domain"
	"github.com/franzejr/gitranger/cli/internal/store"
)

type fakeSource struct {
	mu        sync.Mutex
	posts     int
	listCalls int
	commented bool
}

func (f *fakeSource) List(context.Context, config.Repository, string) ([]domain.PullRequest, error) {
	f.mu.Lock()
	f.listCalls++
	f.mu.Unlock()
	return []domain.PullRequest{{
		Number: 7, Title: "Durable reviews", Author: "octocat",
		URL: "https://github.com/acme/repo/pull/7", HeadSHA: "head-1",
		UpdatedAt: time.Now(),
	}}, nil
}

func (*fakeSource) Content(context.Context, config.Repository, int) (string, string, error) {
	return "Description", "+ durable scheduler", nil
}

func (f *fakeSource) HasComment(context.Context, config.Repository, int, string) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.commented, nil
}

func (f *fakeSource) PostComment(context.Context, config.Repository, int, string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.posts++
	f.commented = true
	return nil
}

type fakeReviewer struct{}

func (fakeReviewer) Run(
	_ context.Context,
	run domain.Run,
	_ domain.PullRequest,
	_ string,
	_ string,
) ([]domain.AgentRun, string, error) {
	agents := run.Agents
	now := time.Now()
	pass := true
	for index := range agents {
		agents[index].Status = domain.AgentCompleted
		agents[index].Phase = "Review complete"
		agents[index].Verdict = &pass
		agents[index].Output = "No issues found."
		agents[index].EndedAt = &now
	}
	return agents, "review comment", nil
}

func TestPollReviewPostIsDurableAndIdempotent(t *testing.T) {
	database, err := store.Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	cfg := config.Config{
		Version: config.CurrentVersion,
		Execution: config.Execution{
			MaxActiveReviews: 1, ReviewTimeout: time.Second, PollTick: 10 * time.Millisecond,
		},
		Provider:     config.Provider{Name: "Fake", Command: "fake", Effort: "low"},
		Repositories: []config.Repository{{ID: "repo", Name: "Repo", URL: "https://github.com/acme/repo"}},
		Routines: []config.Routine{{
			ID: "routine", Name: "Routine", Enabled: true, RepositoryIDs: []string{"repo"},
			Interval: time.Hour, Scope: "open", MaxPullRequestsPerPoll: 1,
			Agents: []string{"summary"}, Delivery: "automatic_comment", MaxAttempts: 3,
		}},
	}
	source := &fakeSource{}
	ctx, cancel := context.WithCancel(context.Background())
	routineEngine := New(cfg, database, source, fakeReviewer{}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := routineEngine.Start(ctx); err != nil {
		t.Fatal(err)
	}
	defer func() { cancel(); routineEngine.Wait() }()
	if err := routineEngine.PollNow(ctx, "routine"); err != nil {
		t.Fatal(err)
	}
	waitFor(t, time.Second, func() bool {
		snapshot, _ := routineEngine.Snapshot(ctx, "test")
		return len(snapshot.RecentRuns) == 1 && snapshot.RecentRuns[0].Status == domain.RunPosted
	})
	if err := routineEngine.PollNow(ctx, "routine"); err != nil {
		t.Fatal(err)
	}
	time.Sleep(50 * time.Millisecond)
	snapshot, err := routineEngine.Snapshot(ctx, "test")
	if err != nil {
		t.Fatal(err)
	}
	if len(snapshot.RecentRuns) != 1 {
		t.Fatalf("runs = %d, want 1", len(snapshot.RecentRuns))
	}
	source.mu.Lock()
	posts := source.posts
	source.mu.Unlock()
	if posts != 1 {
		t.Fatalf("posts = %d, want 1", posts)
	}
}

func waitFor(t *testing.T, timeout time.Duration, condition func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("condition was not met before timeout")
}
