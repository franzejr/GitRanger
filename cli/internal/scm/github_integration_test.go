package scm

import (
	"context"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/franzejr/gitranger/cli/internal/config"
)

func TestGitHubLargePullRequestReadOnlyIntegration(t *testing.T) {
	target := os.Getenv("GITRANGER_GITHUB_LARGE_PR")
	if target == "" {
		t.Skip("set GITRANGER_GITHUB_LARGE_PR=owner/repository#number to run")
	}
	separator := strings.LastIndexByte(target, '#')
	if separator <= 0 || separator == len(target)-1 {
		t.Fatal("GITRANGER_GITHUB_LARGE_PR must use owner/repository#number")
	}
	slug := target[:separator]
	prNumber, err := strconv.Atoi(target[separator+1:])
	if err != nil {
		t.Fatalf("parse pull request number: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	github := NewGitHub("gh")
	detail, err := github.detail(ctx, slug, prNumber)
	if err != nil {
		t.Fatal(err)
	}
	_, diff, err := github.Content(ctx, config.Repository{
		Name: slug, URL: "https://github.com/" + slug,
	}, prNumber, detail.HeadSHA)
	if err != nil {
		t.Fatal(err)
	}
	if files := countDiffFiles(diff); files != detail.ChangedFiles {
		t.Fatalf("complete diff contains %d of %d files", files, detail.ChangedFiles)
	}
	if expected := os.Getenv("GITRANGER_GITHUB_EXPECTED_FILES"); expected != "" {
		count, err := strconv.Atoi(expected)
		if err != nil {
			t.Fatalf("parse GITRANGER_GITHUB_EXPECTED_FILES: %v", err)
		}
		if detail.ChangedFiles != count {
			t.Fatalf("changed files = %d, want %d", detail.ChangedFiles, count)
		}
	}
	t.Logf("validated complete read-only diff for %s#%d (%d files)",
		slug, prNumber, detail.ChangedFiles)
}
