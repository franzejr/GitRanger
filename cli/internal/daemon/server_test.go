package daemon

import (
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/franzejr/gitranger/cli/internal/config"
	"github.com/franzejr/gitranger/cli/internal/engine"
	"github.com/franzejr/gitranger/cli/internal/store"
)

func TestLocalSocketStatusEventsAndShutdown(t *testing.T) {
	// Unix domain sockets have a short platform path limit. Go's default test
	// temp path can exceed it on macOS, so keep the socket rooted directly in
	// the system temp directory.
	directory, err := os.MkdirTemp("", "gitranger-daemon-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	database, err := store.Open(filepath.Join(directory, "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	cfg := config.Config{
		Execution: config.Execution{
			MaxActiveReviews: 1, ReviewTimeout: time.Second, PollTick: time.Hour,
		},
	}
	ctx, cancel := context.WithCancel(context.Background())
	routineEngine := engine.New(
		cfg, database, nil, nil,
		slog.New(slog.NewTextHandler(io.Discard, nil)),
	)
	if err := routineEngine.Start(ctx); err != nil {
		t.Fatal(err)
	}
	paths := Paths{
		DataDir: directory, Database: filepath.Join(directory, "state.db"),
		Socket: filepath.Join(directory, "daemon.sock"), Log: filepath.Join(directory, "daemon.log"),
	}
	server := NewServer(
		routineEngine, database, paths, "test-version",
		slog.New(slog.NewTextHandler(io.Discard, nil)), cancel,
	)
	done := make(chan error, 1)
	go func() { done <- server.Serve(ctx) }()
	client := NewClient(paths.Socket)
	waitForServer(t, time.Second, func() bool {
		probe, probeCancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
		defer probeCancel()
		_, err := client.Snapshot(probe)
		return err == nil
	})
	snapshot, err := client.Snapshot(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.Version != "test-version" {
		t.Fatalf("version = %q", snapshot.Version)
	}
	events, err := client.Events(context.Background(), 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) == 0 || events[0].Kind != "daemon.started" {
		t.Fatalf("events = %#v", events)
	}
	if err := client.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("server did not shut down")
	}
	routineEngine.Wait()
}

func waitForServer(t *testing.T, timeout time.Duration, condition func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("server did not become ready")
}
