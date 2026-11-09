package command

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/spf13/cobra"
)

func TestTailscaleProfile(t *testing.T) {
	for _, tc := range []struct {
		name, profile string
		passed, fail  bool
		want          string
	}{
		{name: "omitted"},
		{name: "account", profile: "personal@example.com", passed: true, want: "switch\npersonal@example.com\n"},
		{name: "literal name", profile: "Personal account; echo test", passed: true, want: "switch\nPersonal account; echo test\n"},
		{name: "empty", passed: true, fail: true},
		{name: "flag injection", profile: "--list", passed: true, fail: true},
		{name: "unknown account", profile: "missing", passed: true, fail: true, want: "switch\nmissing\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			record := filepath.Join(dir, "args")
			t.Setenv("TAILSCALE_TEST_ARGS", record)
			t.Setenv("PATH", dir)
			script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$TAILSCALE_TEST_ARGS\"\nif [ \"$2\" = missing ]; then echo 'unknown account' >&2; exit 1; fi\n"
			if err := os.WriteFile(filepath.Join(dir, "tailscale"), []byte(script), 0700); err != nil {
				t.Fatal(err)
			}
			ran := false
			command := &cobra.Command{Use: "test", SilenceUsage: true, SilenceErrors: true, Run: func(*cobra.Command, []string) { ran = true }}
			withTailscaleProfile(command)
			args := []string{}
			if tc.passed {
				args = append(args, "--tailscale-profile", tc.profile)
			}
			command.SetArgs(args)
			err := command.ExecuteContext(context.Background())
			if (err != nil) != tc.fail {
				t.Fatalf("error = %v", err)
			}
			if ran == tc.fail {
				t.Fatalf("command executed = %v", ran)
			}
			data, _ := os.ReadFile(record)
			if string(data) != tc.want {
				t.Fatalf("args = %q, want %q", data, tc.want)
			}
			if tc.profile == "missing" && !strings.Contains(err.Error(), "unknown account") {
				t.Fatal(err)
			}
		})
	}
}

func TestTailscaleProfileCommands(t *testing.T) {
	for _, args := range [][]string{nil, {"daemon", "run"}, {"daemon", "start"}, {"routine", "run"}} {
		command, _, err := New("test").Find(args)
		if err != nil {
			t.Fatal(err)
		}
		if command.Flags().Lookup("tailscale-profile") == nil {
			t.Fatalf("missing flag on %v", args)
		}
	}
}

func TestTailscaleUnavailable(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	if err := switchTailscaleProfile(context.Background(), "personal"); err == nil {
		t.Fatal("expected an error when Tailscale is unavailable")
	}
}
