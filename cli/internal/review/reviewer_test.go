package review

import (
	"strings"
	"testing"

	"github.com/franzejr/gitranger/cli/internal/config"
	"github.com/franzejr/gitranger/cli/internal/domain"
)

func TestParseSectionsAndBuildComment(t *testing.T) {
	run := domain.Run{RoutineID: "routine-1", HeadSHA: "abcdef123456"}
	agents := NewAgents(run.RoutineID, []string{"summary", "security"}, config.Provider{
		Name: "Test Provider", Model: "test-model", Effort: "low",
	})
	response := `<<<GITRANGER_AGENT:summary>>>
VERDICT: PASS
The change is focused.
<<<GITRANGER_END_AGENT>>>
<<<GITRANGER_AGENT:security>>>
VERDICT: FAIL
Validate untrusted input.
<<<GITRANGER_END_AGENT>>>`
	sections := parseSections(response, agents)
	if len(sections) != 2 {
		t.Fatalf("sections = %d", len(sections))
	}
	pass, fail := true, false
	agents[0].Status, agents[0].Verdict = domain.AgentCompleted, &pass
	agents[0].Output = stripVerdict(sections["summary"])
	agents[1].Status, agents[1].Verdict = domain.AgentCompleted, &fail
	agents[1].Output = stripVerdict(sections["security"])
	comment := buildComment(run, agents)
	for _, expected := range []string{
		"Quick review", "Test Provider · test-model · effort: low",
		"Validate untrusted input", PublicationMarker(run.RoutineID, run.HeadSHA),
	} {
		if !strings.Contains(comment, expected) {
			t.Fatalf("comment missing %q:\n%s", expected, comment)
		}
	}
}

func TestPromptTruncatesLargeDiff(t *testing.T) {
	agents := NewAgents("run", []string{"summary"}, config.Provider{})
	prompt := buildPrompt(domain.PullRequest{Title: "Test"}, "", strings.Repeat("x", 50_000), agents, "low")
	if strings.Contains(prompt, strings.Repeat("x", maxDiffBytes+1)) {
		t.Fatal("diff was not truncated")
	}
}
