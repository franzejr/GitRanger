package scm

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/franzejr/gitranger/cli/internal/config"
	"github.com/franzejr/gitranger/cli/internal/domain"
	proc "github.com/franzejr/gitranger/cli/internal/process"
)

type GitHub struct {
	Command string
}

func NewGitHub(command string) *GitHub {
	if command == "" {
		command = "gh"
	}
	return &GitHub{Command: command}
}

func (g *GitHub) List(
	ctx context.Context,
	repository config.Repository,
	scope string,
) ([]domain.PullRequest, error) {
	slug, err := repositorySlug(repository.URL)
	if err != nil {
		return nil, err
	}
	fields := "number,title,author,url,headRefName,headRefOid,baseRefName,isDraft,createdAt,updatedAt"
	arguments := []string{
		"pr", "list", "-R", slug, "--state", "open", "--limit", "50",
		"--json", fields,
	}
	if scope == "pending_my_review" {
		arguments = append(arguments, "--search", "review-requested:@me")
	}
	result, err := proc.Run(ctx, g.Command, arguments, "", nil, nil)
	if err != nil {
		return nil, err
	}
	var raw []struct {
		Number int    `json:"number"`
		Title  string `json:"title"`
		Author struct {
			Login string `json:"login"`
		} `json:"author"`
		URL         string `json:"url"`
		HeadRefName string `json:"headRefName"`
		HeadRefOID  string `json:"headRefOid"`
		BaseRefName string `json:"baseRefName"`
		IsDraft     bool   `json:"isDraft"`
		CreatedAt   string `json:"createdAt"`
		UpdatedAt   string `json:"updatedAt"`
	}
	if err := json.Unmarshal([]byte(result.Stdout), &raw); err != nil {
		return nil, fmt.Errorf("decode gh pull requests: %w", err)
	}
	pullRequests := make([]domain.PullRequest, 0, len(raw))
	for _, item := range raw {
		createdAt, _ := time.Parse(time.RFC3339, item.CreatedAt)
		updatedAt, _ := time.Parse(time.RFC3339, item.UpdatedAt)
		pullRequests = append(pullRequests, domain.PullRequest{
			Number: item.Number, Title: item.Title, Author: item.Author.Login,
			URL: item.URL, HeadRef: item.HeadRefName, HeadSHA: item.HeadRefOID,
			BaseRef: item.BaseRefName, Draft: item.IsDraft,
			CreatedAt: createdAt, UpdatedAt: updatedAt,
		})
	}
	sort.SliceStable(pullRequests, func(i, j int) bool {
		return pullRequests[i].UpdatedAt.After(pullRequests[j].UpdatedAt)
	})
	return pullRequests, nil
}

func (g *GitHub) Content(
	ctx context.Context,
	repository config.Repository,
	prNumber int,
) (body string, diff string, err error) {
	slug, err := repositorySlug(repository.URL)
	if err != nil {
		return "", "", err
	}
	detailContext, cancelDetail := context.WithCancel(ctx)
	defer cancelDetail()
	diffContext, cancelDiff := context.WithCancel(ctx)
	defer cancelDiff()
	type outcome struct {
		kind   string
		result proc.Result
		err    error
	}
	results := make(chan outcome, 2)
	go func() {
		result, runErr := proc.Run(detailContext, g.Command, []string{
			"pr", "view", fmt.Sprint(prNumber), "-R", slug, "--json", "body",
		}, "", nil, nil)
		results <- outcome{kind: "detail", result: result, err: runErr}
	}()
	go func() {
		result, runErr := proc.Run(diffContext, g.Command, []string{
			"pr", "diff", fmt.Sprint(prNumber), "-R", slug,
		}, "", nil, nil)
		results <- outcome{kind: "diff", result: result, err: runErr}
	}()
	for range 2 {
		outcome := <-results
		if outcome.err != nil {
			cancelDetail()
			cancelDiff()
			return "", "", outcome.err
		}
		if outcome.kind == "diff" {
			diff = outcome.result.Stdout
			continue
		}
		var detail struct {
			Body string `json:"body"`
		}
		if err := json.Unmarshal([]byte(outcome.result.Stdout), &detail); err != nil {
			return "", "", fmt.Errorf("decode gh pull request: %w", err)
		}
		body = detail.Body
	}
	return body, diff, nil
}

func (g *GitHub) HasComment(
	ctx context.Context,
	repository config.Repository,
	prNumber int,
	marker string,
) (bool, error) {
	slug, err := repositorySlug(repository.URL)
	if err != nil {
		return false, err
	}
	result, err := proc.Run(ctx, g.Command, []string{
		"api", fmt.Sprintf("repos/%s/issues/%d/comments", slug, prNumber),
		"--paginate", "--jq", ".[].body",
	}, "", nil, nil)
	return strings.Contains(result.Stdout, marker), err
}

func (g *GitHub) PostComment(
	ctx context.Context,
	repository config.Repository,
	prNumber int,
	comment string,
) error {
	slug, err := repositorySlug(repository.URL)
	if err != nil {
		return err
	}
	_, err = proc.Run(ctx, g.Command, []string{
		"pr", "comment", fmt.Sprint(prNumber), "-R", slug, "--body-file", "-",
	}, "", []byte(comment), nil)
	return err
}

func (g *GitHub) Doctor(ctx context.Context) error {
	_, err := proc.Run(ctx, g.Command, []string{"auth", "status"}, "", nil, nil)
	return err
}

func repositorySlug(raw string) (string, error) {
	cleaned := strings.TrimSuffix(strings.TrimRight(raw, "/"), ".git")
	if strings.HasPrefix(cleaned, "git@") {
		parts := strings.SplitN(cleaned, ":", 2)
		if len(parts) == 2 && strings.Contains(parts[1], "/") {
			return parts[1], nil
		}
	}
	parsed, err := url.Parse(cleaned)
	if err == nil && parsed.Host != "" {
		path := strings.Trim(filepath.ToSlash(parsed.Path), "/")
		if strings.Contains(path, "/") {
			return path, nil
		}
	}
	return "", errors.New("repository URL must be a GitHub HTTPS or SSH URL")
}
