# GitRanger Terminal

GitRanger Terminal is an independent Go client for continuous pull request
reviews. It combines a responsive terminal interface with a durable background
daemon, so routines continue to run after the interface closes.

## What is included

- A responsive Bubble Tea dashboard for routines, runs, agents, and settings.
- A headless daemon with a local Unix socket API and SSE event stream.
- A durable `Poll → Review → Post` scheduler backed by SQLite WAL.
- Bounded review workers, cancellation, timeouts, crash recovery, and retries.
- Immutable PR content caching by repository, PR number, and head SHA.
- Run deduplication by routine, repository, PR number, and head SHA.
- Remote publication markers that make automatic comments idempotent.
- GitHub support through the authenticated `gh` CLI.
- Human-readable commands plus `--json` output for automation.

## Requirements

- Go 1.26 or later when building from source.
- `gh`, authenticated with `gh auth login`.
- A review provider CLI that accepts the prompt on standard input.

The default provider command is `claude`. Provider authentication remains with
the provider CLI; no credentials are stored in `config.yaml`.

## Build and run

```bash
cd cli
go build -o gitranger ./cmd/gitranger

./gitranger config init \
  --repo https://github.com/owner/repository.git \
  --name repository

./gitranger doctor
./gitranger
```

Running `gitranger` starts the daemon when needed and opens the TUI. To keep the
daemon managed by the operating system:

```bash
gitranger daemon install
```

This installs a user LaunchAgent on macOS or a user systemd service on Linux.

## Commands

```text
gitranger                         Open the TUI and ensure the daemon is running
gitranger attach                  Attach the TUI to an existing daemon
gitranger status                  Show daemon and queue status
gitranger doctor                  Validate config, gh, and the review provider
gitranger config init             Create versioned configuration
gitranger config edit             Edit configuration with $EDITOR
gitranger routine list            List routines
gitranger routine run <id>        Poll a routine immediately
gitranger run list                List recent runs
gitranger run show <id>           Show a review and agent output
gitranger run retry <id>          Retry a terminal run
gitranger run cancel <id>         Cancel an active run
gitranger logs --follow           Stream durable operational events
gitranger daemon run              Run the daemon in the foreground
gitranger daemon start            Start a detached daemon
gitranger daemon stop             Stop the daemon
gitranger daemon install          Install the user service
```

Add `--json` to status, list, show, or logs commands for machine-readable output.

## Configuration

The default path is the operating system user configuration directory under
`gitranger/config.yaml`. See [`config.example.yaml`](config.example.yaml).

Configuration is versioned and intentionally contains no secrets. Routine IDs
must remain stable because they are part of local and remote idempotency keys.
Restart the daemon after editing configuration.

## Storage and local API

Runtime state is kept under `~/.local/share/gitranger` unless
`GITRANGER_DATA_DIR` is set:

- `state.db`: SQLite WAL database and migrations.
- `daemon.sock`: mode `0600` local control socket.
- `daemon.log`: structured daemon logs.

The TUI is a client of the daemon. Closing it never cancels scheduled routines.

## Development

```bash
make check
```

Tests use fake SCM and review implementations and never require network access.

## Current first-release boundaries

- GitHub is the first supported SCM; GitLab support follows the same adapter
  boundary but is not included yet.
- Configuration editing uses `$EDITOR`; a full-screen form editor is planned.
- The Swift application and terminal client do not read each other's private
  databases. A neutral import/export contract is the next interoperability step.
- Service installation currently targets macOS and Linux.
