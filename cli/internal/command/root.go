package command

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"
	"github.com/google/uuid"
	"github.com/spf13/cobra"

	"github.com/franzejr/gitranger/cli/internal/config"
	"github.com/franzejr/gitranger/cli/internal/daemon"
	"github.com/franzejr/gitranger/cli/internal/domain"
	"github.com/franzejr/gitranger/cli/internal/scm"
	"github.com/franzejr/gitranger/cli/internal/tui"
)

type Options struct {
	Version    string
	ConfigPath string
	JSON       bool
	Out        io.Writer
	Err        io.Writer
}

func New(version string) *cobra.Command {
	defaultConfig, _ := config.DefaultPath()
	options := &Options{
		Version: version, ConfigPath: defaultConfig, Out: os.Stdout, Err: os.Stderr,
	}
	root := &cobra.Command{
		Use:          "gitranger",
		Short:        "Continuous pull request review from your terminal",
		SilenceUsage: true,
		RunE: func(command *cobra.Command, _ []string) error {
			return options.openTUI(command.Context(), true)
		},
	}
	root.SetOut(options.Out)
	root.SetErr(options.Err)
	root.PersistentFlags().StringVar(&options.ConfigPath, "config", defaultConfig, "configuration file")
	root.PersistentFlags().BoolVar(&options.JSON, "json", false, "print machine-readable JSON")
	root.AddCommand(
		options.daemonCommand(), options.attachCommand(), options.statusCommand(),
		options.routineCommand(), options.runCommand(), options.configCommand(),
		options.logsCommand(), options.doctorCommand(),
		&cobra.Command{
			Use: "version", Short: "Print the version",
			Run: func(_ *cobra.Command, _ []string) { fmt.Fprintln(options.Out, version) },
		},
	)
	return root
}

func (o *Options) daemonCommand() *cobra.Command {
	command := &cobra.Command{Use: "daemon", Short: "Manage the durable background engine"}
	command.AddCommand(
		&cobra.Command{
			Use: "run", Short: "Run the daemon in the foreground",
			RunE: func(command *cobra.Command, _ []string) error {
				return daemon.Run(command.Context(), o.ConfigPath, o.Version, true)
			},
		},
		&cobra.Command{
			Use: "start", Short: "Start the daemon in the background",
			RunE: func(command *cobra.Command, _ []string) error {
				paths, err := daemon.DefaultPaths()
				if err != nil {
					return err
				}
				if err := os.MkdirAll(paths.DataDir, 0o700); err != nil {
					return err
				}
				if err := daemon.StartDetached(command.Context(), o.ConfigPath, paths); err != nil {
					return err
				}
				fmt.Fprintln(o.Out, "Review daemon started")
				return nil
			},
		},
		&cobra.Command{
			Use: "stop", Short: "Stop the running daemon",
			RunE: func(command *cobra.Command, _ []string) error {
				client, err := o.client()
				if err != nil {
					return err
				}
				return client.Shutdown(command.Context())
			},
		},
		&cobra.Command{
			Use: "status", Short: "Show daemon health",
			RunE: func(command *cobra.Command, _ []string) error {
				return o.printStatus(command.Context())
			},
		},
		&cobra.Command{
			Use: "install", Short: "Install and start the user service",
			RunE: func(_ *cobra.Command, _ []string) error {
				paths, err := daemon.DefaultPaths()
				if err != nil {
					return err
				}
				path, err := daemon.InstallService(o.ConfigPath, paths)
				if err != nil {
					return err
				}
				fmt.Fprintf(o.Out, "Installed service at %s\n", path)
				return nil
			},
		},
	)
	return command
}

func (o *Options) attachCommand() *cobra.Command {
	return &cobra.Command{
		Use: "attach", Short: "Attach the TUI to a running daemon",
		RunE: func(command *cobra.Command, _ []string) error {
			return o.openTUI(command.Context(), false)
		},
	}
}

func (o *Options) statusCommand() *cobra.Command {
	return &cobra.Command{
		Use: "status", Short: "Show current review activity",
		RunE: func(command *cobra.Command, _ []string) error {
			return o.printStatus(command.Context())
		},
	}
}

func (o *Options) routineCommand() *cobra.Command {
	command := &cobra.Command{Use: "routine", Short: "Inspect and run routines"}
	command.AddCommand(
		&cobra.Command{
			Use: "list", Short: "List configured routines",
			RunE: func(_ *cobra.Command, _ []string) error {
				cfg, err := config.Load(o.ConfigPath)
				if err != nil {
					return err
				}
				if o.JSON {
					return json.NewEncoder(o.Out).Encode(cfg.Routines)
				}
				for _, routine := range cfg.Routines {
					fmt.Fprintf(o.Out, "%s\t%s\tevery %s\t%s\n", routine.ID,
						routine.Name, routine.IntervalRaw, routine.Delivery)
				}
				return nil
			},
		},
		&cobra.Command{
			Use: "run ROUTINE_ID", Short: "Poll a routine immediately", Args: cobra.ExactArgs(1),
			RunE: func(command *cobra.Command, args []string) error {
				client, err := o.client()
				if err != nil {
					return err
				}
				return client.PollRoutine(command.Context(), args[0])
			},
		},
	)
	return command
}

func (o *Options) runCommand() *cobra.Command {
	command := &cobra.Command{Use: "run", Short: "Inspect and control review runs"}
	command.AddCommand(
		&cobra.Command{
			Use: "list", Short: "List recent review runs",
			RunE: func(command *cobra.Command, _ []string) error {
				client, err := o.client()
				if err != nil {
					return err
				}
				snapshot, err := client.Snapshot(command.Context())
				if err != nil {
					return err
				}
				if o.JSON {
					return json.NewEncoder(o.Out).Encode(snapshot.RecentRuns)
				}
				for _, run := range snapshot.RecentRuns {
					fmt.Fprintf(o.Out, "%s\t%s\t%s #%d\t%s\n", run.ID, run.Status,
						run.Repository, run.PRNumber, run.PRTitle)
				}
				return nil
			},
		},
		&cobra.Command{
			Use: "show RUN_ID", Short: "Show one review run", Args: cobra.ExactArgs(1),
			RunE: func(command *cobra.Command, args []string) error {
				client, err := o.client()
				if err != nil {
					return err
				}
				run, err := client.Run(command.Context(), args[0])
				if err != nil {
					return err
				}
				if o.JSON {
					return json.NewEncoder(o.Out).Encode(run)
				}
				fmt.Fprintf(o.Out, "%s #%d · %s\nStatus: %s\nEvent: %s\n%s\n",
					run.Repository, run.PRNumber, run.PRTitle, run.Status,
					run.LastEvent, run.ReviewComment)
				return nil
			},
		},
		runActionCommand("retry", "Retry a failed or cancelled run", func(ctx context.Context, client *daemon.Client, id string) error {
			return client.RetryRun(ctx, id)
		}),
		runActionCommand("cancel", "Cancel an active run", func(ctx context.Context, client *daemon.Client, id string) error {
			return client.CancelRun(ctx, id)
		}),
	)
	return command
}

func runActionCommand(
	name string,
	description string,
	action func(context.Context, *daemon.Client, string) error,
) *cobra.Command {
	return &cobra.Command{
		Use: name + " RUN_ID", Short: description, Args: cobra.ExactArgs(1),
		RunE: func(command *cobra.Command, args []string) error {
			paths, err := daemon.DefaultPaths()
			if err != nil {
				return err
			}
			return action(command.Context(), daemon.NewClient(paths.Socket), args[0])
		},
	}
}

func (o *Options) configCommand() *cobra.Command {
	command := &cobra.Command{Use: "config", Short: "Manage versioned configuration"}
	var repositoryURL, repositoryName string
	var force bool
	initCommand := &cobra.Command{
		Use: "init", Short: "Create a starter configuration",
		RunE: func(_ *cobra.Command, _ []string) error {
			if _, err := os.Stat(o.ConfigPath); err == nil && !force {
				return errors.New("configuration already exists; use --force to replace it")
			}
			cfg := config.Default()
			if repositoryURL != "" {
				if repositoryName == "" {
					repositoryName = strings.TrimSuffix(filepath.Base(repositoryURL), ".git")
				}
				repositoryID := strings.ToLower(strings.ReplaceAll(repositoryName, " ", "-"))
				cfg.Repositories = []config.Repository{{
					ID: repositoryID, Name: repositoryName, URL: repositoryURL,
				}}
				cfg.Routines = []config.Routine{{
					ID: uuid.NewString(), Name: "New pull requests", Enabled: true,
					RepositoryIDs: []string{repositoryID}, IntervalRaw: "15m",
					Scope: "open", SkipDrafts: true, MaxPullRequestsPerPoll: 1,
					Agents:   []string{"summary", "security", "performance", "code_quality", "bug_detector"},
					Delivery: "preview", MaxAttempts: 3,
				}}
			}
			if err := config.Save(o.ConfigPath, cfg); err != nil {
				return err
			}
			fmt.Fprintf(o.Out, "Created %s\n", o.ConfigPath)
			return nil
		},
	}
	initCommand.Flags().StringVar(&repositoryURL, "repo", "", "GitHub repository URL")
	initCommand.Flags().StringVar(&repositoryName, "name", "", "repository display name")
	initCommand.Flags().BoolVar(&force, "force", false, "replace existing configuration")
	command.AddCommand(initCommand)
	command.AddCommand(&cobra.Command{
		Use: "path", Short: "Print the active configuration path",
		Run: func(_ *cobra.Command, _ []string) { fmt.Fprintln(o.Out, o.ConfigPath) },
	})
	command.AddCommand(&cobra.Command{
		Use: "edit", Short: "Edit configuration with $EDITOR",
		RunE: func(command *cobra.Command, _ []string) error {
			editor := os.Getenv("EDITOR")
			if editor == "" {
				editor = "vi"
			}
			parts := strings.Fields(editor)
			process := exec.CommandContext(command.Context(), parts[0], append(parts[1:], o.ConfigPath)...)
			process.Stdin, process.Stdout, process.Stderr = os.Stdin, os.Stdout, os.Stderr
			return process.Run()
		},
	})
	return command
}

func (o *Options) logsCommand() *cobra.Command {
	var follow bool
	var after int64
	command := &cobra.Command{
		Use: "logs", Short: "Stream structured daemon events",
		RunE: func(command *cobra.Command, _ []string) error {
			client, err := o.client()
			if err != nil {
				return err
			}
			recent, err := client.Events(command.Context(), after)
			if err != nil {
				return err
			}
			for _, event := range recent {
				printEvent(o.Out, event, o.JSON)
				after = event.Sequence
			}
			if !follow {
				return nil
			}
			events := make(chan domain.Event, 16)
			errors := make(chan error, 1)
			ctx, cancel := context.WithCancel(command.Context())
			defer cancel()
			go func() { errors <- client.Watch(ctx, after, events) }()
			for {
				select {
				case event := <-events:
					printEvent(o.Out, event, o.JSON)
					after = event.Sequence
				case err := <-errors:
					return err
				case <-ctx.Done():
					return ctx.Err()
				}
			}
		},
	}
	command.Flags().BoolVarP(&follow, "follow", "f", false, "keep following events")
	command.Flags().Int64Var(&after, "after", 0, "start after this event sequence")
	return command
}

func printEvent(output io.Writer, event domain.Event, jsonOutput bool) {
	if jsonOutput {
		_ = json.NewEncoder(output).Encode(event)
		return
	}
	fmt.Fprintf(output, "%s  %-18s %s\n",
		event.CreatedAt.Local().Format("15:04:05"), event.Kind, event.Message)
}

func (o *Options) doctorCommand() *cobra.Command {
	return &cobra.Command{
		Use: "doctor", Short: "Validate configuration and external tools",
		RunE: func(command *cobra.Command, _ []string) error {
			cfg, err := config.Load(o.ConfigPath)
			if err != nil {
				return err
			}
			fmt.Fprintln(o.Out, "✓ Configuration is valid")
			if _, err := exec.LookPath("gh"); err != nil {
				return errors.New("gh was not found in PATH")
			}
			if err := scm.NewGitHub("gh").Doctor(command.Context()); err != nil {
				return fmt.Errorf("GitHub authentication failed: %w", err)
			}
			fmt.Fprintln(o.Out, "✓ GitHub CLI is authenticated")
			if _, err := exec.LookPath(cfg.Provider.Command); err != nil {
				return fmt.Errorf("review provider command %q was not found", cfg.Provider.Command)
			}
			fmt.Fprintf(o.Out, "✓ Review provider command %q is available\n", cfg.Provider.Command)
			return nil
		},
	}
}

func (o *Options) openTUI(ctx context.Context, ensure bool) error {
	paths, err := daemon.DefaultPaths()
	if err != nil {
		return err
	}
	if ensure {
		if err := os.MkdirAll(paths.DataDir, 0o700); err != nil {
			return err
		}
		if err := daemon.StartDetached(ctx, o.ConfigPath, paths); err != nil {
			return err
		}
	}
	client := daemon.NewClient(paths.Socket)
	probe, cancel := context.WithTimeout(ctx, time.Second)
	_, err = client.Snapshot(probe)
	cancel()
	if err != nil {
		return fmt.Errorf("daemon is unavailable: %w", err)
	}
	cfg, err := config.Load(o.ConfigPath)
	if err != nil {
		return err
	}
	program := tea.NewProgram(tui.New(client, cfg))
	_, err = program.Run()
	return err
}

func (o *Options) printStatus(ctx context.Context) error {
	client, err := o.client()
	if err != nil {
		return err
	}
	snapshot, err := client.Snapshot(ctx)
	if err != nil {
		return err
	}
	if o.JSON {
		return json.NewEncoder(o.Out).Encode(snapshot)
	}
	fmt.Fprintf(o.Out, "Daemon %s · uptime %s\n", snapshot.Version,
		time.Since(snapshot.StartedAt).Round(time.Second))
	fmt.Fprintf(o.Out, "%d routines · %d active · %d queued · %d failed\n",
		snapshot.Routines, snapshot.ActiveRuns, snapshot.QueuedRuns, snapshot.FailedRuns)
	return nil
}

func (o *Options) client() (*daemon.Client, error) {
	paths, err := daemon.DefaultPaths()
	if err != nil {
		return nil, err
	}
	return daemon.NewClient(paths.Socket), nil
}
