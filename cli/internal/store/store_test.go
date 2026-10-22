package store

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/franzejr/gitranger/cli/internal/domain"
)

func TestRunIdentityIsDeduplicated(t *testing.T) {
	database, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	run := testRun()
	agents := []domain.AgentRun{{
		ID: run.ID + ":summary", RunID: run.ID, AgentID: "summary",
		Name: "Summary", Status: domain.AgentQueued, Phase: "Queued",
	}}
	created, err := database.EnqueueRun(context.Background(), run, agents)
	if err != nil || !created {
		t.Fatalf("first enqueue = %v, %v", created, err)
	}
	duplicate := run
	duplicate.ID = "run-2"
	created, err = database.EnqueueRun(context.Background(), duplicate, nil)
	if err != nil {
		t.Fatal(err)
	}
	if created {
		t.Fatal("duplicate identity was enqueued")
	}
}

func TestInterruptedRunIsRecovered(t *testing.T) {
	database, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	run := testRun()
	created, err := database.EnqueueRun(context.Background(), run, nil)
	if err != nil || !created {
		t.Fatal(err)
	}
	claimed, err := database.ClaimRun(context.Background(), run.ID, time.Now())
	if err != nil || !claimed {
		t.Fatalf("claim = %v, %v", claimed, err)
	}
	if err := database.UpdateRun(context.Background(), run.ID, domain.RunReviewing, "Reviewing"); err != nil {
		t.Fatal(err)
	}
	if err := database.RecoverInterrupted(context.Background(), time.Now()); err != nil {
		t.Fatal(err)
	}
	recovered, err := database.Run(context.Background(), run.ID)
	if err != nil {
		t.Fatal(err)
	}
	if recovered.Status != domain.RunRetrying {
		t.Fatalf("status = %s", recovered.Status)
	}
}

func TestImmutablePRCache(t *testing.T) {
	database, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	ctx := context.Background()
	if err := database.CachePR(ctx, "repo", 42, "head-a", "body", "diff"); err != nil {
		t.Fatal(err)
	}
	body, diff, found, err := database.CachedPR(ctx, "repo", 42, "head-a")
	if err != nil || !found || body != "body" || diff != "diff" {
		t.Fatalf("cache = %q, %q, %v, %v", body, diff, found, err)
	}
	_, _, found, err = database.CachedPR(ctx, "repo", 42, "head-b")
	if err != nil || found {
		t.Fatalf("changed head found = %v, %v", found, err)
	}
}

func testRun() domain.Run {
	return domain.Run{
		ID: "run-1", RoutineID: "routine-1", RoutineName: "Routine",
		RepositoryID: "repo", Repository: "Repository", PRNumber: 42,
		PRTitle: "Improve scheduler", PRAuthor: "author",
		PRURL: "https://github.com/acme/repo/pull/42", HeadSHA: "abc123",
		Status: domain.RunQueued, LastEvent: "Queued", MaxAttempts: 3,
		QueuedAt: time.Now().UTC(),
	}
}
