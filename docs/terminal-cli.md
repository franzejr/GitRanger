# Terminal client architecture

## Goals

The terminal client provides the same review-routine concept as the macOS
application while remaining an independent executable. Its primary invariant is
that scheduled work belongs to a durable daemon, not to the lifetime of a TUI.

## Process model

```text
Terminal UI ── Unix socket HTTP/SSE ── Review daemon
                                           │
                            ┌──────────────┼──────────────┐
                            ▼              ▼              ▼
                         Polling        Reviews        Publishing
```

`gitranger` opens the TUI and starts a detached daemon when necessary.
`gitranger attach` only connects. `gitranger daemon run` is suitable for
launchd, systemd, containers, and foreground debugging.

The socket is created with mode `0600`. The daemon is the only process that
writes runtime state. TUI and non-interactive commands use the same local API.

## State machine

```text
queued → loading → reviewing → aggregating → completed
                                      └────→ posting → posted

Any active state → retrying → loading
Any active state → cancelled
Retry limit      → failed
```

Each transition is persisted before it is exposed through the event stream.
Interrupted active work becomes retryable when the daemon restarts.

## Concurrency

- Polling runs independently from review workers.
- Review concurrency is bounded by `execution.max_active_reviews`.
- Every review has a context deadline and subprocess process group.
- Cancellation terminates the whole process group on macOS and Linux.
- Retry delay grows exponentially from 30 seconds to a 10-minute ceiling.
- Queue claims are conditional state transitions, so duplicate queue messages
  cannot start the same run twice.

The TUI never performs network, database, or subprocess work in its render
loop. It refreshes immutable snapshots from the daemon and remains responsive
while reviews run.

## Idempotency

The durable run identity is:

```text
routine_id + repository_id + pr_number + head_sha
```

SQLite enforces that identity with a unique constraint. A new head creates a
new review; an unchanged head does not.

Automatic comments also include a remote marker:

```html
<!-- gitranger:routine=<routine-id>;head=<head-sha> -->
```

The publisher checks that marker before posting. This protects against a lost
or restored local database creating duplicate comments.

## Cache

PR descriptions and diffs are immutable cache entries keyed by repository, PR
number, and head SHA. Detail and diff are fetched concurrently by the GitHub
adapter and reused by retries. A changed head necessarily misses the cache.

## Configuration and secrets

`config.yaml` is a portable, versioned document. It contains repositories,
routines, execution limits, and provider command metadata. It must never contain
API keys or access tokens. GitHub and review provider authentication are owned
by their respective CLIs or injected through the service environment.

Private SwiftData storage is intentionally not accessed. Cross-product sharing
will use a versioned neutral import/export contract rather than database-level
coupling.

## Operational behavior

- `doctor` validates configuration, GitHub authentication, and provider
  availability from the same shell environment.
- Durable events are available as JSON snapshots and an SSE stream.
- Structured daemon logs go to `daemon.log` without prompts or diffs.
- `--json` makes status and control commands suitable for automation.

## Next phases

1. GitLab adapter parity.
2. Full-screen routine and provider form editor.
3. Neutral configuration import/export with the macOS application.
4. Per-host rate-limit telemetry and configurable jitter.
5. Windows named-pipe transport and service management.
