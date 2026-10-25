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

func TestTransientFailuresUseBoundedRetryDeadlines(t *testing.T) {
	database, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	ctx := context.Background()
	run := testRun()
	if created, err := database.EnqueueRun(ctx, run, nil); err != nil || !created {
		t.Fatalf("enqueue = %v, %v", created, err)
	}
	if claimed, err := database.ClaimRun(ctx, run.ID, time.Now()); err != nil || !claimed {
		t.Fatalf("first claim = %v, %v", claimed, err)
	}
	firstFailure := time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)
	if err := database.FailRun(ctx, run.ID, "request timed out", true, firstFailure); err != nil {
		t.Fatal(err)
	}
	failed, err := database.Run(ctx, run.ID)
	if err != nil {
		t.Fatal(err)
	}
	if failed.Status != domain.RunRetrying || failed.NextAttemptAt == nil ||
		!failed.NextAttemptAt.Equal(firstFailure.Add(5*time.Minute)) {
		t.Fatalf("first retry = %s at %v", failed.Status, failed.NextAttemptAt)
	}
	if claimed, err := database.ClaimRun(ctx, run.ID, firstFailure.Add(4*time.Minute)); err != nil || claimed {
		t.Fatalf("early retry claim = %v, %v", claimed, err)
	}
	if claimed, err := database.ClaimRun(ctx, run.ID, firstFailure.Add(5*time.Minute)); err != nil || !claimed {
		t.Fatalf("second claim = %v, %v", claimed, err)
	}
	secondFailure := firstFailure.Add(6 * time.Minute)
	if err := database.FailRun(ctx, run.ID, "rate limited", true, secondFailure); err != nil {
		t.Fatal(err)
	}
	failed, err = database.Run(ctx, run.ID)
	if err != nil {
		t.Fatal(err)
	}
	if failed.Status != domain.RunRetrying || failed.NextAttemptAt == nil ||
		!failed.NextAttemptAt.Equal(secondFailure.Add(15*time.Minute)) {
		t.Fatalf("second retry = %s at %v", failed.Status, failed.NextAttemptAt)
	}
}

func TestPermanentFailureRequiresManualRetry(t *testing.T) {
	database, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	ctx := context.Background()
	run := testRun()
	if created, err := database.EnqueueRun(ctx, run, nil); err != nil || !created {
		t.Fatalf("enqueue = %v, %v", created, err)
	}
	if claimed, err := database.ClaimRun(ctx, run.ID, time.Now()); err != nil || !claimed {
		t.Fatalf("claim = %v, %v", claimed, err)
	}
	if err := database.FailRun(ctx, run.ID, "invalid configuration", false, time.Now()); err != nil {
		t.Fatal(err)
	}
	failed, err := database.Run(ctx, run.ID)
	if err != nil {
		t.Fatal(err)
	}
	if failed.Status != domain.RunFailed || failed.NextAttemptAt != nil {
		t.Fatalf("permanent failure = %s at %v", failed.Status, failed.NextAttemptAt)
	}
	if err := database.RetryRun(ctx, run.ID); err != nil {
		t.Fatal(err)
	}
	retried, err := database.Run(ctx, run.ID)
	if err != nil {
		t.Fatal(err)
	}
	if retried.Status != domain.RunQueued || retried.Attempts != 0 {
		t.Fatalf("manual retry = %s attempt %d", retried.Status, retried.Attempts)
	}
}

func TestCancelDoesNotOverwriteTerminalRun(t *testing.T) {
	database, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	ctx := context.Background()
	run := testRun()
	if created, err := database.EnqueueRun(ctx, run, nil); err != nil || !created {
		t.Fatalf("enqueue = %v, %v", created, err)
	}
	if claimed, err := database.ClaimRun(ctx, run.ID, time.Now()); err != nil || !claimed {
		t.Fatalf("claim = %v, %v", claimed, err)
	}
	if err := database.CompleteRun(ctx, run.ID, domain.RunCompleted, "Complete", "review", time.Now()); err != nil {
		t.Fatal(err)
	}
	if err := database.CancelRun(ctx, run.ID, time.Now()); err == nil {
		t.Fatal("terminal run was accepted for cancellation")
	}
	completed, err := database.Run(ctx, run.ID)
	if err != nil {
		t.Fatal(err)
	}
	if completed.Status != domain.RunCompleted {
		t.Fatalf("status = %s, want completed", completed.Status)
	}
}

func TestLateFailureAndCompletionCannotOverwriteCancellation(t *testing.T) {
	database, err := Open(filepath.Join(t.TempDir(), "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	ctx := context.Background()
	run := testRun()
	agent := domain.AgentRun{
		ID: run.ID + ":summary", RunID: run.ID, AgentID: "summary", Name: "Summary",
		Status: domain.AgentQueued, Phase: "Queued",
	}
	if created, err := database.EnqueueRun(ctx, run, []domain.AgentRun{agent}); err != nil || !created {
		t.Fatalf("enqueue = %v, %v", created, err)
	}
	if claimed, err := database.ClaimRun(ctx, run.ID, time.Now()); err != nil || !claimed {
		t.Fatalf("claim = %v, %v", claimed, err)
	}
	if err := database.UpdateRun(ctx, run.ID, domain.RunReviewing, "Reviewing"); err != nil {
		t.Fatal(err)
	}
	if err := database.StartAgents(ctx, run.ID, time.Now()); err != nil {
		t.Fatal(err)
	}
	if err := database.MarkAgentsCancelled(ctx, run.ID, time.Now()); err != nil {
		t.Fatal(err)
	}
	if err := database.CancelRun(ctx, run.ID, time.Now()); err != nil {
		t.Fatal(err)
	}
	if err := database.FailRun(ctx, run.ID, "late timeout", true, time.Now()); err != nil {
		t.Fatal(err)
	}
	if err := database.CompleteRun(ctx, run.ID, domain.RunCompleted, "Late completion", "review", time.Now()); err != nil {
		t.Fatal(err)
	}
	pass := true
	agent.Status, agent.Phase, agent.Verdict = domain.AgentCompleted, "Complete", &pass
	if err := database.SaveAgents(ctx, []domain.AgentRun{agent}); err != nil {
		t.Fatal(err)
	}
	cancelled, err := database.Run(ctx, run.ID)
	if err != nil {
		t.Fatal(err)
	}
	if cancelled.Status != domain.RunCancelled {
		t.Fatalf("status = %s, want cancelled", cancelled.Status)
	}
	if len(cancelled.Agents) != 1 || cancelled.Agents[0].Status != domain.AgentCancelled {
		t.Fatalf("agents = %#v", cancelled.Agents)
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
