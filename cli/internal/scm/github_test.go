package scm

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/franzejr/gitranger/cli/internal/config"
	proc "github.com/franzejr/gitranger/cli/internal/process"
)

type fakeGitHubRunner struct {
	mu             sync.Mutex
	changedFiles   int
	availableFiles int
	finalHeadSHA   string
	missingPatchAt int
	detailCalls    int
	pageCalls      int
}

func (f *fakeGitHubRunner) run(
	_ context.Context,
	_ string,
	arguments []string,
	_ string,
	_ []byte,
	_ []string,
) (proc.Result, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(arguments) >= 2 && arguments[0] == "pr" && arguments[1] == "diff" {
		return proc.Result{}, errors.New("diff too large")
	}
	if len(arguments) >= 2 && arguments[0] == "pr" && arguments[1] == "view" {
		f.detailCalls++
		head := "head-1"
		if f.detailCalls > 1 && f.finalHeadSHA != "" {
			head = f.finalHeadSHA
		}
		payload, _ := json.Marshal(pullRequestDetail{
			Body: "Description", ChangedFiles: f.changedFiles, HeadSHA: head,
		})
		return proc.Result{Stdout: string(payload)}, nil
	}
	if len(arguments) >= 2 && arguments[0] == "api" {
		f.pageCalls++
		page := queryInteger(arguments[1], "page")
		start := (page - 1) * pullRequestFilesPerPage
		end := min(start+pullRequestFilesPerPage, f.availableFiles)
		files := make([]pullRequestFile, 0, max(0, end-start))
		for index := start; index < end; index++ {
			patch := fmt.Sprintf("@@ -0,0 +1 @@\n+line %d", index)
			if index == f.missingPatchAt {
				patch = ""
			}
			files = append(files, pullRequestFile{
				Filename: fmt.Sprintf("file-%04d.go", index), Status: "modified",
				Additions: 1, Patch: patch,
			})
		}
		payload, _ := json.Marshal(files)
		return proc.Result{Stdout: string(payload)}, nil
	}
	return proc.Result{}, fmt.Errorf("unexpected arguments: %v", arguments)
}

func TestContentFallsBackToPaginatedDiffFor326Files(t *testing.T) {
	runner := &fakeGitHubRunner{
		changedFiles: 326, availableFiles: 326, missingPatchAt: -1,
	}
	github := &GitHub{Command: "fake-gh", run: runner.run}
	body, diff, err := github.Content(
		context.Background(),
		config.Repository{URL: "https://github.com/acme/repository.git"},
		42,
		"head-1",
	)
	if err != nil {
		t.Fatal(err)
	}
	if body != "Description" {
		t.Fatalf("body = %q", body)
	}
	if files := countDiffFiles(diff); files != 326 {
		t.Fatalf("diff files = %d, want 326", files)
	}
	if runner.pageCalls != 4 {
		t.Fatalf("page calls = %d, want 4", runner.pageCalls)
	}
	if runner.detailCalls != 2 {
		t.Fatalf("detail calls = %d, want 2", runner.detailCalls)
	}
}

func TestContentFailsClosedWhenFallbackIsIncomplete(t *testing.T) {
	runner := &fakeGitHubRunner{
		changedFiles: 326, availableFiles: 325, missingPatchAt: -1,
	}
	github := &GitHub{Command: "fake-gh", run: runner.run}
	_, _, err := github.Content(
		context.Background(),
		config.Repository{URL: "https://github.com/acme/repository"},
		42,
		"head-1",
	)
	if err == nil || !strings.Contains(err.Error(), "325 of 326") {
		t.Fatalf("error = %v", err)
	}
}

func TestContentFailsClosedWhenRevisionChanges(t *testing.T) {
	runner := &fakeGitHubRunner{
		changedFiles: 1, availableFiles: 1, finalHeadSHA: "head-2", missingPatchAt: -1,
	}
	github := &GitHub{Command: "fake-gh", run: runner.run}
	_, _, err := github.Content(
		context.Background(),
		config.Repository{URL: "git@github.com:acme/repository.git"},
		42,
		"head-1",
	)
	if err == nil || !strings.Contains(err.Error(), "changed while its diff was loading") {
		t.Fatalf("error = %v", err)
	}
}

func TestContentFailsClosedWhenFilePatchIsMissing(t *testing.T) {
	runner := &fakeGitHubRunner{
		changedFiles: 2, availableFiles: 2, missingPatchAt: 1,
	}
	github := &GitHub{Command: "fake-gh", run: runner.run}
	_, _, err := github.Content(
		context.Background(),
		config.Repository{URL: "https://github.com/acme/repository"},
		42,
		"head-1",
	)
	if err == nil || !strings.Contains(err.Error(), "omitted the complete patch") {
		t.Fatalf("error = %v", err)
	}
}

func queryInteger(endpoint string, key string) int {
	for _, pair := range strings.Split(strings.SplitN(endpoint, "?", 2)[1], "&") {
		parts := strings.SplitN(pair, "=", 2)
		if len(parts) == 2 && parts[0] == key {
			value, _ := strconv.Atoi(parts[1])
			return value
		}
	}
	return 0
}
