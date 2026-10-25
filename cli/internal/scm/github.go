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
	run     commandRunner
}

type commandRunner func(
	context.Context,
	string,
	[]string,
	string,
	[]byte,
	[]string,
) (proc.Result, error)

const (
	pullRequestFilesPerPage = 100
	maxPullRequestFiles     = 3000
)

func NewGitHub(command string) *GitHub {
	if command == "" {
		command = "gh"
	}
	return &GitHub{Command: command, run: proc.Run}
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
	result, err := g.command(ctx, arguments, nil)
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
	expectedHeadSHA string,
) (body string, diff string, err error) {
	slug, err := repositorySlug(repository.URL)
	if err != nil {
		return "", "", err
	}
	detail, err := g.detail(ctx, slug, prNumber)
	if err != nil {
		return "", "", err
	}
	if err := validateRevision(detail, expectedHeadSHA); err != nil {
		return "", "", err
	}
	if detail.ChangedFiles > maxPullRequestFiles {
		return "", "", permanentError{fmt.Errorf(
			"pull request contains %d files; GitHub exposes at most %d files for review",
			detail.ChangedFiles, maxPullRequestFiles,
		)}
	}
	diffResult, diffErr := g.command(ctx, []string{
		"pr", "diff", fmt.Sprint(prNumber), "-R", slug,
	}, nil)
	diff = diffResult.Stdout
	if diffErr != nil || countDiffFiles(diff) != detail.ChangedFiles {
		diff, err = g.paginatedDiff(ctx, slug, prNumber, detail.ChangedFiles)
		if err != nil {
			if diffErr != nil {
				return "", "", fmt.Errorf("fetch pull request diff (%v); fallback failed: %w", diffErr, err)
			}
			return "", "", err
		}
	}
	latest, err := g.detail(ctx, slug, prNumber)
	if err != nil {
		return "", "", fmt.Errorf("verify pull request revision: %w", err)
	}
	if latest.HeadSHA != detail.HeadSHA || latest.ChangedFiles != detail.ChangedFiles {
		return "", "", permanentError{errors.New(
			"pull request changed while its diff was loading; poll again to review the latest revision",
		)}
	}
	if err := validateRevision(latest, expectedHeadSHA); err != nil {
		return "", "", err
	}
	return detail.Body, diff, nil
}

type pullRequestDetail struct {
	Body         string `json:"body"`
	ChangedFiles int    `json:"changedFiles"`
	HeadSHA      string `json:"headRefOid"`
}

type pullRequestFile struct {
	Filename         string `json:"filename"`
	PreviousFilename string `json:"previous_filename"`
	Status           string `json:"status"`
	Additions        int    `json:"additions"`
	Deletions        int    `json:"deletions"`
	Patch            string `json:"patch"`
}

func (g *GitHub) detail(
	ctx context.Context,
	slug string,
	prNumber int,
) (pullRequestDetail, error) {
	result, err := g.command(ctx, []string{
		"pr", "view", fmt.Sprint(prNumber), "-R", slug,
		"--json", "body,changedFiles,headRefOid",
	}, nil)
	if err != nil {
		return pullRequestDetail{}, err
	}
	var detail pullRequestDetail
	if err := json.Unmarshal([]byte(result.Stdout), &detail); err != nil {
		return pullRequestDetail{}, fmt.Errorf("decode pull request details: %w", err)
	}
	return detail, nil
}

func (g *GitHub) paginatedDiff(
	ctx context.Context,
	slug string,
	prNumber int,
	expectedFiles int,
) (string, error) {
	if expectedFiles < 0 || expectedFiles > maxPullRequestFiles {
		return "", permanentError{fmt.Errorf(
			"pull request file count %d is outside the supported range", expectedFiles,
		)}
	}
	files := make([]pullRequestFile, 0, expectedFiles)
	seen := make(map[string]struct{}, expectedFiles)
	for page := 1; page <= maxPullRequestFiles/pullRequestFilesPerPage && len(files) < expectedFiles; page++ {
		endpoint := fmt.Sprintf(
			"repos/%s/pulls/%d/files?per_page=%d&page=%d",
			slug, prNumber, pullRequestFilesPerPage, page,
		)
		result, err := g.command(ctx, []string{"api", endpoint}, nil)
		if err != nil {
			return "", fmt.Errorf("fetch pull request files page %d: %w", page, err)
		}
		var pageFiles []pullRequestFile
		if err := json.Unmarshal([]byte(result.Stdout), &pageFiles); err != nil {
			return "", permanentError{fmt.Errorf("decode pull request files page %d: %w", page, err)}
		}
		if len(pageFiles) > pullRequestFilesPerPage {
			return "", permanentError{fmt.Errorf("GitHub returned %d files on page %d", len(pageFiles), page)}
		}
		for _, file := range pageFiles {
			if file.Filename == "" || file.Patch == "" {
				return "", permanentError{fmt.Errorf(
					"GitHub omitted the complete patch for a changed file; refusing a partial review",
				)}
			}
			if _, duplicate := seen[file.Filename]; duplicate {
				return "", permanentError{fmt.Errorf("GitHub returned duplicate file %q", file.Filename)}
			}
			seen[file.Filename] = struct{}{}
			files = append(files, file)
		}
		if len(pageFiles) < pullRequestFilesPerPage {
			break
		}
	}
	if len(files) != expectedFiles {
		return "", permanentError{fmt.Errorf(
			"GitHub returned %d of %d changed files; refusing a partial review",
			len(files), expectedFiles,
		)}
	}
	var builder strings.Builder
	for _, file := range files {
		previousFilename := file.Filename
		if file.PreviousFilename != "" {
			previousFilename = file.PreviousFilename
		}
		fmt.Fprintf(&builder, "diff --git a/%s b/%s\n", previousFilename, file.Filename)
		fmt.Fprintf(&builder, "# status: %s; additions: %d; deletions: %d\n",
			file.Status, file.Additions, file.Deletions)
		builder.WriteString(file.Patch)
		if !strings.HasSuffix(file.Patch, "\n") {
			builder.WriteByte('\n')
		}
	}
	return builder.String(), nil
}

func validateRevision(detail pullRequestDetail, expectedHeadSHA string) error {
	if detail.HeadSHA == "" {
		return permanentError{errors.New("GitHub did not return the pull request head revision")}
	}
	if expectedHeadSHA != "" && detail.HeadSHA != expectedHeadSHA {
		return permanentError{fmt.Errorf(
			"pull request head changed from %s to %s; poll again before reviewing",
			expectedHeadSHA, detail.HeadSHA,
		)}
	}
	return nil
}

func countDiffFiles(diff string) int {
	count := 0
	for _, line := range strings.Split(diff, "\n") {
		if strings.HasPrefix(line, "diff --git ") {
			count++
		}
	}
	return count
}

type permanentError struct{ error }

func (permanentError) Retryable() bool { return false }

func (g *GitHub) command(ctx context.Context, arguments []string, input []byte) (proc.Result, error) {
	runner := g.run
	if runner == nil {
		runner = proc.Run
	}
	return runner(ctx, g.Command, arguments, "", input, nil)
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
	result, err := g.command(ctx, []string{
		"api", fmt.Sprintf("repos/%s/issues/%d/comments", slug, prNumber),
		"--paginate", "--jq", ".[].body",
	}, nil)
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
	_, err = g.command(ctx, []string{
		"pr", "comment", fmt.Sprint(prNumber), "-R", slug, "--body-file", "-",
	}, []byte(comment))
	return err
}

func (g *GitHub) Doctor(ctx context.Context) error {
	_, err := g.command(ctx, []string{"auth", "status"}, nil)
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
