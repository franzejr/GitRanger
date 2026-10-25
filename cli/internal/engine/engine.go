package engine

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/franzejr/gitranger/cli/internal/config"
	"github.com/franzejr/gitranger/cli/internal/domain"
	"github.com/franzejr/gitranger/cli/internal/review"
	"github.com/franzejr/gitranger/cli/internal/store"
)

type Source interface {
	List(context.Context, config.Repository, string) ([]domain.PullRequest, error)
	Content(context.Context, config.Repository, int, string) (string, string, error)
	HasComment(context.Context, config.Repository, int, string) (bool, error)
	PostComment(context.Context, config.Repository, int, string) error
}

type ReviewService interface {
	Run(
		context.Context,
		domain.Run,
		domain.PullRequest,
		string,
		string,
	) ([]domain.AgentRun, string, error)
}

type Engine struct {
	config    config.Config
	store     *store.Store
	source    Source
	reviewer  ReviewService
	logger    *slog.Logger
	queue     chan string
	startedAt time.Time

	mu         sync.Mutex
	runCancels map[string]context.CancelFunc
	waitGroup  sync.WaitGroup
}

func New(
	cfg config.Config,
	store *store.Store,
	source Source,
	reviewer ReviewService,
	logger *slog.Logger,
) *Engine {
	return &Engine{
		config: cfg, store: store, source: source, reviewer: reviewer,
		logger: logger, queue: make(chan string, cfg.Execution.MaxActiveReviews*4),
		startedAt: time.Now().UTC(), runCancels: make(map[string]context.CancelFunc),
	}
}

func (e *Engine) Start(ctx context.Context) error {
	now := time.Now().UTC()
	if err := e.store.RecoverInterrupted(ctx, now); err != nil {
		return err
	}
	for _, routine := range e.config.Routines {
		if err := e.store.EnsureRoutine(ctx, routine.ID, now); err != nil {
			return err
		}
	}
	for range e.config.Execution.MaxActiveReviews {
		e.waitGroup.Add(1)
		go e.worker(ctx)
	}
	e.waitGroup.Add(1)
	go e.scheduler(ctx)
	_ = e.store.AddEvent(ctx, "", "daemon.started", "Review daemon started")
	return nil
}

func (e *Engine) Wait() { e.waitGroup.Wait() }

func (e *Engine) scheduler(ctx context.Context) {
	defer e.waitGroup.Done()
	ticker := time.NewTicker(e.config.Execution.PollTick)
	defer ticker.Stop()
	e.tick(ctx)
	for {
		select {
		case <-ctx.Done():
			e.cancelAll()
			return
		case <-ticker.C:
			e.tick(ctx)
		}
	}
}

func (e *Engine) tick(ctx context.Context) {
	now := time.Now().UTC()
	for _, routine := range e.config.Routines {
		if !routine.Enabled {
			continue
		}
		due, err := e.store.RoutineDue(ctx, routine.ID, now)
		if err != nil {
			e.logger.Error("read routine schedule", "routine", routine.ID, "error", err)
			continue
		}
		if due {
			if err := e.pollRoutine(ctx, routine); err != nil {
				e.logger.Error("poll routine", "routine", routine.ID, "error", err)
				_ = e.store.AddEvent(ctx, "", "poll.failed",
					fmt.Sprintf("%s: %v", routine.Name, err))
			}
			_ = e.store.MarkRoutinePolled(ctx, routine.ID, now, now.Add(routine.Interval))
		}
	}
	ids, err := e.store.ReadyRunIDs(ctx, now, cap(e.queue))
	if err != nil {
		e.logger.Error("load review queue", "error", err)
		return
	}
	for _, id := range ids {
		select {
		case e.queue <- id:
		default:
			return
		}
	}
}

func (e *Engine) PollNow(ctx context.Context, routineID string) error {
	routine, ok := e.routine(routineID)
	if !ok {
		return fmt.Errorf("routine %q not found", routineID)
	}
	if err := e.pollRoutine(ctx, routine); err != nil {
		return err
	}
	now := time.Now().UTC()
	if err := e.store.MarkRoutinePolled(ctx, routine.ID, now, now.Add(routine.Interval)); err != nil {
		return err
	}
	e.tick(ctx)
	return nil
}

func (e *Engine) pollRoutine(ctx context.Context, routine config.Routine) error {
	for _, repositoryID := range routine.RepositoryIDs {
		repository, ok := e.config.Repository(repositoryID)
		if !ok {
			continue
		}
		pullRequests, err := e.source.List(ctx, repository, routine.Scope)
		if err != nil {
			return fmt.Errorf("poll %s: %w", repository.Name, err)
		}
		enqueued := 0
		for _, pullRequest := range pullRequests {
			if routine.SkipDrafts && pullRequest.Draft {
				continue
			}
			if enqueued >= routine.MaxPullRequestsPerPoll {
				break
			}
			runID := uuid.NewString()
			run := domain.Run{
				ID: runID, RoutineID: routine.ID, RoutineName: routine.Name,
				RepositoryID: repository.ID, Repository: repository.Name,
				PRNumber: pullRequest.Number, PRTitle: pullRequest.Title,
				PRAuthor: pullRequest.Author, PRURL: pullRequest.URL,
				HeadSHA: pullRequest.HeadSHA, Status: domain.RunQueued,
				LastEvent: "Waiting for review capacity", MaxAttempts: routine.MaxAttempts,
				QueuedAt: time.Now().UTC(),
			}
			agents := review.NewAgents(runID, routine.Agents, e.config.Provider)
			created, err := e.store.EnqueueRun(ctx, run, agents)
			if err != nil {
				return err
			}
			if created {
				enqueued++
			}
		}
	}
	return nil
}

func (e *Engine) worker(ctx context.Context) {
	defer e.waitGroup.Done()
	for {
		select {
		case <-ctx.Done():
			return
		case runID := <-e.queue:
			e.execute(ctx, runID)
		}
	}
}

func (e *Engine) execute(parent context.Context, runID string) {
	claimed, err := e.store.ClaimRun(parent, runID, time.Now().UTC())
	if err != nil || !claimed {
		return
	}
	ctx, cancel := context.WithTimeout(parent, e.config.Execution.ReviewTimeout)
	e.mu.Lock()
	e.runCancels[runID] = cancel
	e.mu.Unlock()
	defer func() {
		cancel()
		e.mu.Lock()
		delete(e.runCancels, runID)
		e.mu.Unlock()
	}()

	run, err := e.store.Run(ctx, runID)
	if err != nil {
		e.fail(parent, runID, err)
		return
	}
	repository, ok := e.config.Repository(run.RepositoryID)
	if !ok {
		e.fail(parent, runID, errors.New("repository no longer exists in config"))
		return
	}
	body, diff, cached, err := e.store.CachedPR(ctx, run.RepositoryID, run.PRNumber, run.HeadSHA)
	if err != nil {
		e.fail(parent, runID, err)
		return
	}
	if !cached {
		body, diff, err = e.source.Content(ctx, repository, run.PRNumber, run.HeadSHA)
		if err != nil {
			e.fail(parent, runID, err)
			return
		}
		if err := e.store.CachePR(ctx, run.RepositoryID, run.PRNumber, run.HeadSHA, body, diff); err != nil {
			e.logger.Warn("cache pull request", "run", runID, "error", err)
		}
	}
	if err := e.store.UpdateRun(ctx, runID, domain.RunReviewing, "Running review agents"); err != nil {
		e.fail(parent, runID, err)
		return
	}
	_ = e.store.StartAgents(ctx, runID, time.Now().UTC())
	run, err = e.store.Run(ctx, runID)
	if err != nil {
		e.fail(parent, runID, err)
		return
	}
	pullRequest := domain.PullRequest{
		Number: run.PRNumber, Title: run.PRTitle, Author: run.PRAuthor,
		URL: run.PRURL, HeadSHA: run.HeadSHA, Body: body,
	}
	agents, comment, err := e.reviewer.Run(ctx, run, pullRequest, body, diff)
	_ = e.store.SaveAgents(parent, agents)
	if err != nil {
		e.fail(parent, runID, err)
		return
	}
	if err := e.store.UpdateRun(ctx, runID, domain.RunAggregating, "Combining agent findings"); err != nil {
		e.fail(parent, runID, err)
		return
	}
	routine, ok := e.routine(run.RoutineID)
	if !ok || routine.Delivery == "preview" {
		_ = e.store.CompleteRun(parent, runID, domain.RunCompleted,
			"Review ready for preview", comment, time.Now().UTC())
		return
	}
	if err := e.store.UpdateRun(ctx, runID, domain.RunPosting, "Checking publication marker"); err != nil {
		e.fail(parent, runID, err)
		return
	}
	marker := review.PublicationMarker(run.RoutineID, run.HeadSHA)
	exists, err := e.source.HasComment(ctx, repository, run.PRNumber, marker)
	if err != nil {
		e.fail(parent, runID, err)
		return
	}
	if !exists {
		if err := e.source.PostComment(ctx, repository, run.PRNumber, comment); err != nil {
			e.fail(parent, runID, err)
			return
		}
	}
	_ = e.store.MarkPublished(parent, run, time.Now().UTC())
	_ = e.store.CompleteRun(parent, runID, domain.RunPosted,
		"Review posted", comment, time.Now().UTC())
}

func (e *Engine) fail(ctx context.Context, runID string, err error) {
	if errors.Is(err, context.Canceled) {
		now := time.Now().UTC()
		if e.store.CancelRun(ctx, runID, now) == nil {
			_ = e.store.MarkAgentsCancelled(ctx, runID, now)
		}
		return
	}
	_ = e.store.FailRun(ctx, runID, err.Error(), retryable(err), time.Now().UTC())
}

type retryableFailure interface {
	Retryable() bool
}

func retryable(err error) bool {
	var classified retryableFailure
	if errors.As(err, &classified) {
		return classified.Retryable()
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	message := strings.ToLower(err.Error())
	for _, signal := range []string{
		"timeout", "timed out", "temporarily unavailable", "rate limit",
		"too many requests", "connection reset", "connection refused",
		"bad gateway", "service unavailable", "gateway timeout",
		"provider omitted agent sections",
	} {
		if strings.Contains(message, signal) {
			return true
		}
	}
	return false
}

func (e *Engine) Cancel(ctx context.Context, runID string) error {
	e.mu.Lock()
	cancel := e.runCancels[runID]
	e.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	now := time.Now().UTC()
	if err := e.store.CancelRun(ctx, runID, now); err != nil {
		return err
	}
	return e.store.MarkAgentsCancelled(ctx, runID, now)
}

func (e *Engine) Retry(ctx context.Context, runID string) error {
	if err := e.store.RetryRun(ctx, runID); err != nil {
		return err
	}
	e.tick(ctx)
	return nil
}

func (e *Engine) Snapshot(ctx context.Context, version string) (domain.Snapshot, error) {
	return e.store.Snapshot(ctx, version, e.startedAt, len(e.config.Routines))
}

func (e *Engine) EventsAfter(ctx context.Context, sequence int64) ([]domain.Event, error) {
	return e.store.EventsAfter(ctx, sequence, 100)
}

func (e *Engine) routine(id string) (config.Routine, bool) {
	for _, routine := range e.config.Routines {
		if routine.ID == id {
			return routine, true
		}
	}
	return config.Routine{}, false
}

func (e *Engine) cancelAll() {
	e.mu.Lock()
	defer e.mu.Unlock()
	for _, cancel := range e.runCancels {
		cancel()
	}
}
