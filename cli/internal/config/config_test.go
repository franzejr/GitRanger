package config

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestSaveAndLoadVersionedConfiguration(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := Default()
	cfg.Repositories = []Repository{{
		ID: "example", Name: "Example", URL: "https://github.com/acme/example.git",
	}}
	cfg.Routines = []Routine{{
		ID: "routine-1", Name: "Review new pull requests", Enabled: true,
		RepositoryIDs: []string{"example"}, IntervalRaw: "5m", Scope: "open",
		SkipDrafts: true, MaxPullRequestsPerPoll: 1,
		Agents: []string{"summary", "security"}, Delivery: "preview", MaxAttempts: 3,
	}}
	if err := Save(path, cfg); err != nil {
		t.Fatal(err)
	}
	loaded, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Version != CurrentVersion {
		t.Fatalf("version = %d, want %d", loaded.Version, CurrentVersion)
	}
	if loaded.Routines[0].Interval != 5*time.Minute {
		t.Fatalf("interval = %s", loaded.Routines[0].Interval)
	}
	if loaded.Execution.ReviewTimeout != 3*time.Minute {
		t.Fatalf("timeout = %s", loaded.Execution.ReviewTimeout)
	}
}

func TestLoadRejectsUnknownRepositoryReference(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	data := []byte(`version: 1
provider:
  name: Test
  command: test-provider
routines:
  - id: routine-1
    name: Broken
    enabled: true
    repositories: [missing]
    interval: 5m
`)
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(path); err == nil {
		t.Fatal("expected invalid repository reference")
	}
}
