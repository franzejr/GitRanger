package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"

	"github.com/franzejr/gitranger/cli/internal/domain"
)

const schema = `
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS routine_state (
  routine_id TEXT PRIMARY KEY,
  last_poll_at TEXT,
  next_poll_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY,
  routine_id TEXT NOT NULL,
  routine_name TEXT NOT NULL,
  repository_id TEXT NOT NULL,
  repository_name TEXT NOT NULL,
  pr_number INTEGER NOT NULL,
  pr_title TEXT NOT NULL,
  pr_author TEXT NOT NULL,
  pr_url TEXT NOT NULL,
  head_sha TEXT NOT NULL,
  status TEXT NOT NULL,
  last_event TEXT NOT NULL,
  error TEXT NOT NULL DEFAULT '',
  review_comment TEXT NOT NULL DEFAULT '',
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 3,
  next_attempt_at TEXT,
  queued_at TEXT NOT NULL,
  started_at TEXT,
  completed_at TEXT,
  UNIQUE(routine_id, repository_id, pr_number, head_sha)
);
CREATE INDEX IF NOT EXISTS idx_runs_status_attempt
  ON runs(status, next_attempt_at, queued_at);
CREATE TABLE IF NOT EXISTS agent_runs (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  agent_id TEXT NOT NULL,
  name TEXT NOT NULL,
  status TEXT NOT NULL,
  phase TEXT NOT NULL,
  provider TEXT NOT NULL DEFAULT '',
  model TEXT NOT NULL DEFAULT '',
  effort TEXT NOT NULL DEFAULT '',
  verdict INTEGER,
  output TEXT NOT NULL DEFAULT '',
  error TEXT NOT NULL DEFAULT '',
  started_at TEXT,
  ended_at TEXT,
  UNIQUE(run_id, agent_id)
);
CREATE TABLE IF NOT EXISTS events (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL,
  message TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_created_at ON events(created_at);
CREATE TABLE IF NOT EXISTS pr_cache (
  repository_id TEXT NOT NULL,
  pr_number INTEGER NOT NULL,
  head_sha TEXT NOT NULL,
  body TEXT NOT NULL,
  diff TEXT NOT NULL,
  fetched_at TEXT NOT NULL,
  PRIMARY KEY(repository_id, pr_number, head_sha)
);
CREATE TABLE IF NOT EXISTS publications (
  routine_id TEXT NOT NULL,
  repository_id TEXT NOT NULL,
  pr_number INTEGER NOT NULL,
  head_sha TEXT NOT NULL,
  posted_at TEXT NOT NULL,
  PRIMARY KEY(routine_id, repository_id, pr_number, head_sha)
);
INSERT OR IGNORE INTO schema_migrations(version, applied_at)
  VALUES(1, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
`

type Store struct {
	db *sql.DB
}

func Open(path string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	for _, pragma := range []string{
		"PRAGMA journal_mode=WAL",
		"PRAGMA foreign_keys=ON",
		"PRAGMA busy_timeout=5000",
		"PRAGMA synchronous=NORMAL",
	} {
		if _, err := db.Exec(pragma); err != nil {
			db.Close()
			return nil, fmt.Errorf("configure sqlite: %w", err)
		}
	}
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate sqlite: %w", err)
	}
	return &Store{db: db}, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) EnsureRoutine(ctx context.Context, id string, now time.Time) error {
	_, err := s.db.ExecContext(ctx, `
		INSERT OR IGNORE INTO routine_state(routine_id, next_poll_at)
		VALUES(?, ?)`, id, formatTime(now))
	return err
}

func (s *Store) RoutineDue(ctx context.Context, id string, now time.Time) (bool, error) {
	var raw string
	err := s.db.QueryRowContext(ctx,
		"SELECT next_poll_at FROM routine_state WHERE routine_id = ?", id,
	).Scan(&raw)
	if err != nil {
		return false, err
	}
	when, err := parseTime(raw)
	return !when.After(now), err
}

func (s *Store) MarkRoutinePolled(
	ctx context.Context,
	id string,
	polledAt time.Time,
	next time.Time,
) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE routine_state SET last_poll_at = ?, next_poll_at = ?
		WHERE routine_id = ?`, formatTime(polledAt), formatTime(next), id)
	return err
}

func (s *Store) NextPoll(ctx context.Context) (*time.Time, error) {
	var raw sql.NullString
	if err := s.db.QueryRowContext(ctx,
		"SELECT MIN(next_poll_at) FROM routine_state",
	).Scan(&raw); err != nil {
		return nil, err
	}
	return nullableTime(raw)
}

func (s *Store) LastPoll(ctx context.Context) (*time.Time, error) {
	var raw sql.NullString
	if err := s.db.QueryRowContext(ctx,
		"SELECT MAX(last_poll_at) FROM routine_state",
	).Scan(&raw); err != nil {
		return nil, err
	}
	return nullableTime(raw)
}

func (s *Store) EnqueueRun(
	ctx context.Context,
	run domain.Run,
	agents []domain.AgentRun,
) (bool, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	result, err := tx.ExecContext(ctx, `
		INSERT OR IGNORE INTO runs(
		  id, routine_id, routine_name, repository_id, repository_name,
		  pr_number, pr_title, pr_author, pr_url, head_sha, status,
		  last_event, attempts, max_attempts, queued_at
		) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		run.ID, run.RoutineID, run.RoutineName, run.RepositoryID,
		run.Repository, run.PRNumber, run.PRTitle, run.PRAuthor, run.PRURL,
		run.HeadSHA, run.Status, run.LastEvent, run.Attempts, run.MaxAttempts,
		formatTime(run.QueuedAt),
	)
	if err != nil {
		return false, err
	}
	rows, err := result.RowsAffected()
	if err != nil || rows == 0 {
		return false, err
	}
	for _, agent := range agents {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO agent_runs(
			  id, run_id, agent_id, name, status, phase,
			  provider, model, effort
			) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			agent.ID, run.ID, agent.AgentID, agent.Name, agent.Status,
			agent.Phase, agent.Provider, agent.Model, agent.Effort,
		); err != nil {
			return false, err
		}
	}
	if err := insertEventTx(ctx, tx, run.ID, "run.queued", run.LastEvent); err != nil {
		return false, err
	}
	return true, tx.Commit()
}

func (s *Store) ClaimRun(ctx context.Context, id string, now time.Time) (bool, error) {
	result, err := s.db.ExecContext(ctx, `
		UPDATE runs
		SET status = ?, last_event = ?, attempts = attempts + 1,
		    started_at = ?, completed_at = NULL, error = '', next_attempt_at = NULL
		WHERE id = ? AND status IN (?, ?)`,
		domain.RunLoading, "Loading pull request", formatTime(now), id,
		domain.RunQueued, domain.RunRetrying,
	)
	if err != nil {
		return false, err
	}
	rows, err := result.RowsAffected()
	if rows == 1 {
		_ = s.AddEvent(ctx, id, "run.loading", "Loading pull request")
	}
	return rows == 1, err
}

func (s *Store) ReadyRunIDs(ctx context.Context, now time.Time, limit int) ([]string, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id FROM runs
		WHERE status = ? OR (status = ? AND next_attempt_at <= ?)
		ORDER BY queued_at ASC LIMIT ?`,
		domain.RunQueued, domain.RunRetrying, formatTime(now), limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (s *Store) RecoverInterrupted(ctx context.Context, now time.Time) error {
	result, err := s.db.ExecContext(ctx, `
		UPDATE runs SET status = ?, last_event = ?, error = ?,
		next_attempt_at = ?, completed_at = ?
		WHERE status IN (?, ?, ?, ?)`,
		domain.RunRetrying, "Interrupted; queued for recovery",
		"The daemon stopped before this run completed.", formatTime(now),
		formatTime(now), domain.RunLoading, domain.RunReviewing,
		domain.RunAggregating, domain.RunPosting)
	if err != nil {
		return err
	}
	rows, _ := result.RowsAffected()
	if rows > 0 {
		return s.AddEvent(ctx, "", "daemon.recovered",
			fmt.Sprintf("Recovered %d interrupted run(s)", rows))
	}
	return nil
}

func (s *Store) StartAgents(ctx context.Context, runID string, now time.Time) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE agent_runs SET status = ?, phase = ?, started_at = ?,
		ended_at = NULL, error = '' WHERE run_id = ?`,
		domain.AgentReviewing, "Reviewing pull request", formatTime(now), runID)
	return err
}

func (s *Store) UpdateRun(
	ctx context.Context,
	id string,
	status domain.RunStatus,
	event string,
) error {
	_, err := s.db.ExecContext(ctx,
		"UPDATE runs SET status = ?, last_event = ? WHERE id = ?",
		status, event, id)
	if err == nil {
		err = s.AddEvent(ctx, id, "run."+string(status), event)
	}
	return err
}

func (s *Store) CompleteRun(
	ctx context.Context,
	id string,
	status domain.RunStatus,
	event string,
	comment string,
	now time.Time,
) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE runs SET status = ?, last_event = ?, review_comment = ?,
		completed_at = ?, next_attempt_at = NULL WHERE id = ?`,
		status, event, comment, formatTime(now), id)
	if err == nil {
		err = s.AddEvent(ctx, id, "run."+string(status), event)
	}
	return err
}

func (s *Store) FailRun(
	ctx context.Context,
	id string,
	message string,
	now time.Time,
) error {
	run, err := s.Run(ctx, id)
	if err != nil {
		return err
	}
	status := domain.RunFailed
	var retryAt any
	event := "Review failed"
	if run.Attempts < run.MaxAttempts {
		status = domain.RunRetrying
		delay := retryDelay(run.Attempts)
		when := now.Add(delay)
		retryAt = formatTime(when)
		event = fmt.Sprintf("Retrying in %s", delay.Round(time.Second))
	}
	_, err = s.db.ExecContext(ctx, `
		UPDATE runs SET status = ?, last_event = ?, error = ?,
		next_attempt_at = ?, completed_at = ? WHERE id = ?`,
		status, event, message, retryAt, formatTime(now), id)
	if err == nil {
		err = s.AddEvent(ctx, id, "run."+string(status), message)
	}
	return err
}

func retryDelay(attempt int) time.Duration {
	if attempt < 1 {
		attempt = 1
	}
	delay := 30 * time.Second * time.Duration(1<<(attempt-1))
	if delay > 10*time.Minute {
		return 10 * time.Minute
	}
	return delay
}

func (s *Store) CancelRun(ctx context.Context, id string, now time.Time) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE runs SET status = ?, last_event = ?, completed_at = ?,
		next_attempt_at = NULL WHERE id = ? AND status IN (?, ?, ?, ?, ?, ?)`,
		domain.RunCancelled, "Cancelled", formatTime(now), id,
		domain.RunQueued, domain.RunLoading, domain.RunReviewing,
		domain.RunAggregating, domain.RunPosting, domain.RunRetrying)
	if err == nil {
		err = s.AddEvent(ctx, id, "run.cancelled", "Cancelled")
	}
	return err
}

func (s *Store) RetryRun(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE runs SET status = ?, last_event = ?, attempts = 0,
		error = '', completed_at = NULL, next_attempt_at = NULL
		WHERE id = ? AND status IN (?, ?)`,
		domain.RunQueued, "Queued for retry", id,
		domain.RunFailed, domain.RunCancelled)
	if err == nil {
		err = s.AddEvent(ctx, id, "run.queued", "Queued for retry")
	}
	return err
}

func (s *Store) MarkAgentsCancelled(ctx context.Context, runID string, now time.Time) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE agent_runs SET status = ?, phase = ?, ended_at = ?
		WHERE run_id = ? AND status IN (?, ?)`, domain.AgentCancelled,
		"Cancelled", formatTime(now), runID, domain.AgentQueued,
		domain.AgentReviewing)
	return err
}

func (s *Store) SaveAgents(ctx context.Context, agents []domain.AgentRun) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, agent := range agents {
		var verdict any
		if agent.Verdict != nil {
			if *agent.Verdict {
				verdict = 1
			} else {
				verdict = 0
			}
		}
		_, err := tx.ExecContext(ctx, `
			UPDATE agent_runs SET status = ?, phase = ?, provider = ?, model = ?,
			effort = ?, verdict = ?, output = ?, error = ?, started_at = ?, ended_at = ?
			WHERE id = ?`,
			agent.Status, agent.Phase, agent.Provider, agent.Model, agent.Effort,
			verdict, agent.Output, agent.Error, nullableFormatted(agent.StartedAt),
			nullableFormatted(agent.EndedAt), agent.ID)
		if err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) Run(ctx context.Context, id string) (domain.Run, error) {
	runs, err := s.queryRuns(ctx, "WHERE r.id = ?", id)
	if err != nil {
		return domain.Run{}, err
	}
	if len(runs) == 0 {
		return domain.Run{}, sql.ErrNoRows
	}
	return runs[0], nil
}

func (s *Store) RecentRuns(ctx context.Context, limit int) ([]domain.Run, error) {
	return s.queryRuns(ctx, "ORDER BY r.queued_at DESC LIMIT ?", limit)
}

func (s *Store) queryRuns(ctx context.Context, suffix string, args ...any) ([]domain.Run, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT r.id, r.routine_id, r.routine_name, r.repository_id,
		r.repository_name, r.pr_number, r.pr_title, r.pr_author, r.pr_url,
		r.head_sha, r.status, r.last_event, r.error, r.review_comment,
		r.attempts, r.max_attempts, r.next_attempt_at, r.queued_at,
		r.started_at, r.completed_at FROM runs r `+suffix, args...)
	if err != nil {
		return nil, err
	}
	var runs []domain.Run
	for rows.Next() {
		run, err := scanRun(rows)
		if err != nil {
			rows.Close()
			return nil, err
		}
		runs = append(runs, run)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return nil, err
	}
	if err := rows.Close(); err != nil {
		return nil, err
	}
	for index := range runs {
		runs[index].Agents, err = s.agents(ctx, runs[index].ID)
		if err != nil {
			return nil, err
		}
	}
	return runs, nil
}

type rowScanner interface{ Scan(...any) error }

func scanRun(row rowScanner) (domain.Run, error) {
	var run domain.Run
	var status string
	var nextAttempt, queuedAt, startedAt, completedAt sql.NullString
	err := row.Scan(
		&run.ID, &run.RoutineID, &run.RoutineName, &run.RepositoryID,
		&run.Repository, &run.PRNumber, &run.PRTitle, &run.PRAuthor,
		&run.PRURL, &run.HeadSHA, &status, &run.LastEvent, &run.Error,
		&run.ReviewComment, &run.Attempts, &run.MaxAttempts, &nextAttempt,
		&queuedAt, &startedAt, &completedAt,
	)
	if err != nil {
		return run, err
	}
	run.Status = domain.RunStatus(status)
	run.NextAttemptAt, err = nullableTime(nextAttempt)
	if err != nil {
		return run, err
	}
	queued, err := nullableTime(queuedAt)
	if err != nil || queued == nil {
		return run, fmt.Errorf("invalid queued_at: %w", err)
	}
	run.QueuedAt = *queued
	run.StartedAt, err = nullableTime(startedAt)
	if err != nil {
		return run, err
	}
	run.CompletedAt, err = nullableTime(completedAt)
	return run, err
}

func (s *Store) agents(ctx context.Context, runID string) ([]domain.AgentRun, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, run_id, agent_id, name, status, phase, provider, model,
		effort, verdict, output, error, started_at, ended_at
		FROM agent_runs WHERE run_id = ? ORDER BY rowid`, runID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var agents []domain.AgentRun
	for rows.Next() {
		var agent domain.AgentRun
		var status string
		var verdict sql.NullInt64
		var startedAt, endedAt sql.NullString
		if err := rows.Scan(
			&agent.ID, &agent.RunID, &agent.AgentID, &agent.Name, &status,
			&agent.Phase, &agent.Provider, &agent.Model, &agent.Effort,
			&verdict, &agent.Output, &agent.Error, &startedAt, &endedAt,
		); err != nil {
			return nil, err
		}
		agent.Status = domain.AgentStatus(status)
		if verdict.Valid {
			value := verdict.Int64 == 1
			agent.Verdict = &value
		}
		agent.StartedAt, err = nullableTime(startedAt)
		if err != nil {
			return nil, err
		}
		agent.EndedAt, err = nullableTime(endedAt)
		if err != nil {
			return nil, err
		}
		agents = append(agents, agent)
	}
	return agents, rows.Err()
}

func (s *Store) Snapshot(
	ctx context.Context,
	version string,
	startedAt time.Time,
	routineCount int,
) (domain.Snapshot, error) {
	runs, err := s.RecentRuns(ctx, 50)
	if err != nil {
		return domain.Snapshot{}, err
	}
	snapshot := domain.Snapshot{
		Version: version, StartedAt: startedAt, Routines: routineCount,
		RecentRuns: runs,
	}
	for _, run := range runs {
		if run.Status.Active() {
			snapshot.ActiveRuns++
		}
		if run.Status == domain.RunQueued || run.Status == domain.RunRetrying {
			snapshot.QueuedRuns++
		}
		if run.Status == domain.RunFailed {
			snapshot.FailedRuns++
		}
	}
	snapshot.LastPollAt, err = s.LastPoll(ctx)
	if err != nil {
		return snapshot, err
	}
	snapshot.NextPollAt, err = s.NextPoll(ctx)
	return snapshot, err
}

func (s *Store) AddEvent(ctx context.Context, runID, kind, message string) error {
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO events(run_id, kind, message, created_at) VALUES(?, ?, ?, ?)`,
		runID, kind, message, formatTime(time.Now().UTC()))
	return err
}

func insertEventTx(
	ctx context.Context,
	tx *sql.Tx,
	runID string,
	kind string,
	message string,
) error {
	_, err := tx.ExecContext(ctx, `
		INSERT INTO events(run_id, kind, message, created_at) VALUES(?, ?, ?, ?)`,
		runID, kind, message, formatTime(time.Now().UTC()))
	return err
}

func (s *Store) EventsAfter(ctx context.Context, sequence int64, limit int) ([]domain.Event, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT sequence, run_id, kind, message, created_at FROM events
		WHERE sequence > ? ORDER BY sequence LIMIT ?`, sequence, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var events []domain.Event
	for rows.Next() {
		var event domain.Event
		var created string
		if err := rows.Scan(
			&event.Sequence, &event.RunID, &event.Kind, &event.Message, &created,
		); err != nil {
			return nil, err
		}
		when, err := parseTime(created)
		if err != nil {
			return nil, err
		}
		event.CreatedAt = when
		events = append(events, event)
	}
	return events, rows.Err()
}

func (s *Store) CachePR(
	ctx context.Context,
	repositoryID string,
	prNumber int,
	headSHA string,
	body string,
	diff string,
) error {
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO pr_cache(repository_id, pr_number, head_sha, body, diff, fetched_at)
		VALUES(?, ?, ?, ?, ?, ?)
		ON CONFLICT(repository_id, pr_number, head_sha) DO UPDATE SET
		body = excluded.body, diff = excluded.diff, fetched_at = excluded.fetched_at`,
		repositoryID, prNumber, headSHA, body, diff, formatTime(time.Now().UTC()))
	return err
}

func (s *Store) CachedPR(
	ctx context.Context,
	repositoryID string,
	prNumber int,
	headSHA string,
) (string, string, bool, error) {
	var body, diff string
	err := s.db.QueryRowContext(ctx, `
		SELECT body, diff FROM pr_cache
		WHERE repository_id = ? AND pr_number = ? AND head_sha = ?`,
		repositoryID, prNumber, headSHA).Scan(&body, &diff)
	if errors.Is(err, sql.ErrNoRows) {
		return "", "", false, nil
	}
	return body, diff, err == nil, err
}

func (s *Store) MarkPublished(ctx context.Context, run domain.Run, now time.Time) error {
	_, err := s.db.ExecContext(ctx, `
		INSERT OR IGNORE INTO publications(
		routine_id, repository_id, pr_number, head_sha, posted_at
		) VALUES(?, ?, ?, ?, ?)`, run.RoutineID, run.RepositoryID,
		run.PRNumber, run.HeadSHA, formatTime(now))
	return err
}

func formatTime(value time.Time) string { return value.UTC().Format(time.RFC3339Nano) }

func parseTime(value string) (time.Time, error) { return time.Parse(time.RFC3339Nano, value) }

func nullableFormatted(value *time.Time) any {
	if value == nil {
		return nil
	}
	return formatTime(*value)
}

func nullableTime(value sql.NullString) (*time.Time, error) {
	if !value.Valid || value.String == "" {
		return nil, nil
	}
	parsed, err := parseTime(value.String)
	if err != nil {
		return nil, err
	}
	return &parsed, nil
}
