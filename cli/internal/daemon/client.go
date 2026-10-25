package daemon

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/franzejr/gitranger/cli/internal/domain"
)

type Client struct {
	http *http.Client
}

func NewClient(socketPath string) *Client {
	transport := &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", socketPath)
		},
	}
	return &Client{http: &http.Client{Transport: transport, Timeout: 5 * time.Second}}
}

func (c *Client) Snapshot(ctx context.Context) (domain.Snapshot, error) {
	var snapshot domain.Snapshot
	err := c.getJSON(ctx, "/v1/status", &snapshot)
	return snapshot, err
}

func (c *Client) Run(ctx context.Context, id string) (domain.Run, error) {
	var run domain.Run
	err := c.getJSON(ctx, "/v1/runs/"+url.PathEscape(id), &run)
	return run, err
}

func (c *Client) PollRoutine(ctx context.Context, id string) error {
	return c.post(ctx, "/v1/routines/"+url.PathEscape(id)+"/run")
}

func (c *Client) CancelRun(ctx context.Context, id string) error {
	return c.post(ctx, "/v1/runs/"+url.PathEscape(id)+"/cancel")
}

func (c *Client) RetryRun(ctx context.Context, id string) error {
	return c.post(ctx, "/v1/runs/"+url.PathEscape(id)+"/retry")
}

func (c *Client) Events(ctx context.Context, after int64) ([]domain.Event, error) {
	var events []domain.Event
	err := c.getJSON(ctx, fmt.Sprintf("/v1/events/recent?after=%d", after), &events)
	return events, err
}

func (c *Client) Shutdown(ctx context.Context) error {
	return c.post(ctx, "/v1/shutdown")
}

func (c *Client) Watch(
	ctx context.Context,
	after int64,
	events chan<- domain.Event,
) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet,
		fmt.Sprintf("http://local/v1/events?after=%d", after), nil)
	if err != nil {
		return err
	}
	client := *c.http
	client.Timeout = 0
	response, err := client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(response.Body, 1024))
		return fmt.Errorf("daemon returned %s: %s", response.Status, body)
	}
	scanner := bufio.NewScanner(response.Body)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "data: ") {
			continue
		}
		var event domain.Event
		if err := json.Unmarshal([]byte(strings.TrimPrefix(line, "data: ")), &event); err != nil {
			continue
		}
		select {
		case events <- event:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return scanner.Err()
}

func (c *Client) getJSON(ctx context.Context, path string, destination any) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://local"+path, nil)
	if err != nil {
		return err
	}
	response, err := c.http.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(response.Body, 1024))
		return fmt.Errorf("daemon returned %s: %s", response.Status, body)
	}
	return json.NewDecoder(response.Body).Decode(destination)
}

func (c *Client) post(ctx context.Context, path string) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"http://local"+path, bytes.NewReader(nil))
	if err != nil {
		return err
	}
	response, err := c.http.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(response.Body, 1024))
		return fmt.Errorf("daemon returned %s: %s", response.Status, body)
	}
	return nil
}

func ParseAfter(raw string) int64 {
	value, _ := strconv.ParseInt(raw, 10, 64)
	return value
}
