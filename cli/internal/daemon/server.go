package daemon

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/franzejr/gitranger/cli/internal/engine"
	"github.com/franzejr/gitranger/cli/internal/store"
)

type Server struct {
	engine  *engine.Engine
	store   *store.Store
	version string
	paths   Paths
	logger  *slog.Logger
	cancel  context.CancelFunc
	http    *http.Server
}

func NewServer(
	engine *engine.Engine,
	store *store.Store,
	paths Paths,
	version string,
	logger *slog.Logger,
	cancel context.CancelFunc,
) *Server {
	server := &Server{
		engine: engine, store: store, paths: paths, version: version,
		logger: logger, cancel: cancel,
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/status", server.status)
	mux.HandleFunc("GET /v1/runs/{id}", server.run)
	mux.HandleFunc("POST /v1/routines/{id}/run", server.pollRoutine)
	mux.HandleFunc("POST /v1/runs/{id}/cancel", server.cancelRun)
	mux.HandleFunc("POST /v1/runs/{id}/retry", server.retryRun)
	mux.HandleFunc("GET /v1/events/recent", server.recentEvents)
	mux.HandleFunc("GET /v1/events", server.events)
	mux.HandleFunc("POST /v1/shutdown", server.shutdown)
	server.http = &http.Server{
		Handler: mux, ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 30 * time.Second,
	}
	return server
}

func (s *Server) Serve(ctx context.Context) error {
	if err := os.MkdirAll(filepath.Dir(s.paths.Socket), 0o700); err != nil {
		return err
	}
	if _, err := os.Stat(s.paths.Socket); err == nil {
		probe, cancel := context.WithTimeout(ctx, 300*time.Millisecond)
		defer cancel()
		if _, err := NewClient(s.paths.Socket).Snapshot(probe); err == nil {
			return errors.New("daemon is already running")
		}
		if err := os.Remove(s.paths.Socket); err != nil {
			return fmt.Errorf("remove stale daemon socket: %w", err)
		}
	}
	listener, err := net.Listen("unix", s.paths.Socket)
	if err != nil {
		return err
	}
	if err := os.Chmod(s.paths.Socket, 0o600); err != nil {
		listener.Close()
		return err
	}
	defer os.Remove(s.paths.Socket)
	go func() {
		<-ctx.Done()
		shutdownContext, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = s.http.Shutdown(shutdownContext)
	}()
	s.logger.Info("daemon listening", "socket", s.paths.Socket)
	err = s.http.Serve(listener)
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

func (s *Server) status(writer http.ResponseWriter, request *http.Request) {
	snapshot, err := s.engine.Snapshot(request.Context(), s.version)
	writeJSON(writer, snapshot, err)
}

func (s *Server) run(writer http.ResponseWriter, request *http.Request) {
	run, err := s.store.Run(request.Context(), request.PathValue("id"))
	writeJSON(writer, run, err)
}

func (s *Server) pollRoutine(writer http.ResponseWriter, request *http.Request) {
	err := s.engine.PollNow(request.Context(), request.PathValue("id"))
	writeAccepted(writer, err)
}

func (s *Server) cancelRun(writer http.ResponseWriter, request *http.Request) {
	err := s.engine.Cancel(request.Context(), request.PathValue("id"))
	writeAccepted(writer, err)
}

func (s *Server) retryRun(writer http.ResponseWriter, request *http.Request) {
	err := s.engine.Retry(request.Context(), request.PathValue("id"))
	writeAccepted(writer, err)
}

func (s *Server) recentEvents(writer http.ResponseWriter, request *http.Request) {
	after, _ := strconv.ParseInt(request.URL.Query().Get("after"), 10, 64)
	events, err := s.engine.EventsAfter(request.Context(), after)
	writeJSON(writer, events, err)
}

func (s *Server) shutdown(writer http.ResponseWriter, _ *http.Request) {
	writer.WriteHeader(http.StatusAccepted)
	go func() {
		time.Sleep(50 * time.Millisecond)
		s.cancel()
	}()
}

func (s *Server) events(writer http.ResponseWriter, request *http.Request) {
	flusher, ok := writer.(http.Flusher)
	if !ok {
		http.Error(writer, "streaming unsupported", http.StatusInternalServerError)
		return
	}
	writer.Header().Set("Content-Type", "text/event-stream")
	writer.Header().Set("Cache-Control", "no-cache")
	writer.Header().Set("Connection", "keep-alive")
	sequence, _ := strconv.ParseInt(request.URL.Query().Get("after"), 10, 64)
	ticker := time.NewTicker(750 * time.Millisecond)
	defer ticker.Stop()
	for {
		events, err := s.engine.EventsAfter(request.Context(), sequence)
		if err != nil {
			return
		}
		for _, event := range events {
			data, _ := json.Marshal(event)
			_, _ = fmt.Fprintf(writer, "id: %d\ndata: %s\n\n", event.Sequence, data)
			sequence = event.Sequence
			flusher.Flush()
		}
		select {
		case <-request.Context().Done():
			return
		case <-ticker.C:
			if len(events) == 0 {
				_, _ = writer.Write([]byte(": keepalive\n\n"))
				flusher.Flush()
			}
		}
	}
}

func writeJSON(writer http.ResponseWriter, value any, err error) {
	if err != nil {
		status := http.StatusInternalServerError
		if strings.Contains(err.Error(), "no rows") {
			status = http.StatusNotFound
		}
		http.Error(writer, err.Error(), status)
		return
	}
	writer.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(writer).Encode(value)
}

func writeAccepted(writer http.ResponseWriter, err error) {
	if err != nil {
		http.Error(writer, err.Error(), http.StatusBadRequest)
		return
	}
	writer.WriteHeader(http.StatusAccepted)
}
