package daemon

import (
	"context"
	"io"
	"log/slog"
	"os"

	"github.com/franzejr/gitranger/cli/internal/config"
	"github.com/franzejr/gitranger/cli/internal/engine"
	"github.com/franzejr/gitranger/cli/internal/review"
	"github.com/franzejr/gitranger/cli/internal/scm"
	"github.com/franzejr/gitranger/cli/internal/store"
)

func Run(ctx context.Context, configPath, version string, foreground bool) error {
	cfg, err := config.Load(configPath)
	if err != nil {
		return err
	}
	paths, err := DefaultPaths()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(paths.DataDir, 0o700); err != nil {
		return err
	}
	logFile, err := os.OpenFile(paths.Log, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer logFile.Close()
	var output io.Writer = logFile
	if foreground {
		output = io.MultiWriter(os.Stderr, logFile)
	}
	logger := slog.New(slog.NewJSONHandler(output, &slog.HandlerOptions{Level: slog.LevelInfo}))
	database, err := store.Open(paths.Database)
	if err != nil {
		return err
	}
	defer database.Close()
	runtimeContext, cancel := context.WithCancel(ctx)
	defer cancel()
	github := scm.NewGitHub("gh")
	pipeline := review.Reviewer{Provider: cfg.Provider}
	routineEngine := engine.New(cfg, database, github, pipeline, logger)
	if err := routineEngine.Start(runtimeContext); err != nil {
		return err
	}
	server := NewServer(routineEngine, database, paths, version, logger, cancel)
	if err := server.Serve(runtimeContext); err != nil {
		cancel()
		routineEngine.Wait()
		return err
	}
	cancel()
	routineEngine.Wait()
	return nil
}
