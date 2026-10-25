package review

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/franzejr/gitranger/cli/internal/config"
	"github.com/franzejr/gitranger/cli/internal/domain"
	proc "github.com/franzejr/gitranger/cli/internal/process"
)

const maxDiffBytes = 30_000

var agentNames = map[string]string{
	"summary":      "Summary",
	"security":     "Security",
	"performance":  "Performance",
	"code_quality": "Code Quality",
	"bug_detector": "Bug Detector",
}

type Reviewer struct {
	Provider config.Provider
}

func (r Reviewer) Run(
	ctx context.Context,
	run domain.Run,
	pullRequest domain.PullRequest,
	body string,
	diff string,
) ([]domain.AgentRun, string, error) {
	startedAt := time.Now().UTC()
	agents := run.Agents
	for index := range agents {
		agents[index].Status = domain.AgentReviewing
		agents[index].Phase = "Reviewing pull request"
		agents[index].StartedAt = &startedAt
	}
	reviewDiff, coverageWarning := reviewCoverage(diff)
	prompt := buildPrompt(
		pullRequest, body, reviewDiff, agents, r.Provider.Effort, coverageWarning,
	)
	arguments := append([]string(nil), r.Provider.Arguments...)
	if r.Provider.Model != "" {
		arguments = append(arguments, "--model", r.Provider.Model)
	}
	result, err := proc.Run(
		ctx, r.Provider.Command, arguments, "", []byte(prompt), nil,
	)
	endedAt := time.Now().UTC()
	if err != nil {
		for index := range agents {
			agents[index].Status = domain.AgentFailed
			agents[index].Phase = "Review failed"
			agents[index].Error = err.Error()
			agents[index].EndedAt = &endedAt
		}
		return agents, "", err
	}
	response := unwrapResponse(result.Stdout)
	sections := parseSections(response, agents)
	var missing []string
	for index := range agents {
		section := sections[agents[index].AgentID]
		agents[index].EndedAt = &endedAt
		if section == "" {
			agents[index].Status = domain.AgentFailed
			agents[index].Phase = "Review failed"
			agents[index].Error = "The provider response omitted this agent section."
			missing = append(missing, agents[index].Name)
			continue
		}
		agents[index].Status = domain.AgentCompleted
		agents[index].Phase = "Review complete"
		agents[index].Output = stripVerdict(section)
		verdict := !strings.Contains(strings.ToUpper(firstLine(section)), "VERDICT: FAIL")
		agents[index].Verdict = &verdict
	}
	if len(missing) > 0 {
		return agents, "", fmt.Errorf("provider omitted agent sections: %s", strings.Join(missing, ", "))
	}
	comment := buildComment(run, agents, coverageWarning)
	return agents, comment, nil
}

func NewAgents(runID string, ids []string, provider config.Provider) []domain.AgentRun {
	agents := make([]domain.AgentRun, 0, len(ids))
	for _, id := range ids {
		name := agentNames[id]
		if name == "" {
			name = strings.ReplaceAll(strings.Title(strings.ReplaceAll(id, "_", " ")), "  ", " ")
		}
		agents = append(agents, domain.AgentRun{
			ID: runID + ":" + id, RunID: runID, AgentID: id, Name: name,
			Status: domain.AgentQueued, Phase: "Waiting for review capacity",
			Provider: provider.Name, Model: defaultValue(provider.Model, "provider default"),
			Effort: defaultValue(provider.Effort, "low"),
		})
	}
	return agents
}

func buildPrompt(
	pullRequest domain.PullRequest,
	body string,
	diff string,
	agents []domain.AgentRun,
	effort string,
	coverageWarning string,
) string {
	roles := make([]string, 0, len(agents))
	format := make([]string, 0, len(agents))
	for _, agent := range agents {
		roles = append(roles, fmt.Sprintf("Agent ID: %s\nAgent name: %s\nFocus only on %s.",
			agent.AgentID, agent.Name, strings.ToLower(agent.Name)))
		format = append(format, fmt.Sprintf(
			"<<<GITRANGER_AGENT:%s>>>\nVERDICT: PASS or VERDICT: FAIL\nConcise findings\n<<<GITRANGER_END_AGENT>>>",
			agent.AgentID))
	}
	coverage := "Coverage: the complete supplied diff is included."
	if coverageWarning != "" {
		coverage = "Coverage warning: " + coverageWarning +
			" Every agent must state that its findings are limited to the supplied prefix."
	}
	return fmt.Sprintf(`Perform a quick pull request review for every role below in one pass.
Use %s reasoning effort and finish within the configured deadline. Analyze only
the supplied context. Prefer concise, high-confidence findings. Return every
section exactly once and in the requested order.

%s

--- Roles ---
%s

--- Required output ---
%s

--- Pull Request ---
Title: %s
Author: %s
Branch: %s -> %s

Description:
%s

--- Diff ---
%s`, defaultValue(effort, "low"), coverage, strings.Join(roles, "\n\n"),
		strings.Join(format, "\n"), pullRequest.Title, pullRequest.Author,
		pullRequest.HeadRef, pullRequest.BaseRef, defaultValue(body, "(no description)"), diff)
}

func reviewCoverage(diff string) (string, string) {
	if len(diff) <= maxDiffBytes {
		return diff, ""
	}
	truncated := diff[:maxDiffBytes]
	for !utf8.ValidString(truncated) {
		truncated = truncated[:len(truncated)-1]
	}
	return truncated, fmt.Sprintf(
		"Partial review: the diff exceeded the %d-byte quick-review limit, so findings do not cover the entire change.",
		maxDiffBytes,
	)
}

func unwrapResponse(raw string) string {
	var envelope struct {
		Result string `json:"result"`
	}
	if json.Unmarshal([]byte(raw), &envelope) == nil && envelope.Result != "" {
		return envelope.Result
	}
	return strings.TrimSpace(raw)
}

func parseSections(response string, agents []domain.AgentRun) map[string]string {
	sections := make(map[string]string, len(agents))
	const end = "<<<GITRANGER_END_AGENT>>>"
	for _, agent := range agents {
		start := "<<<GITRANGER_AGENT:" + agent.AgentID + ">>>"
		startIndex := strings.Index(response, start)
		if startIndex < 0 {
			continue
		}
		body := response[startIndex+len(start):]
		endIndex := strings.Index(body, end)
		if endIndex < 0 {
			continue
		}
		sections[agent.AgentID] = strings.TrimSpace(body[:endIndex])
	}
	return sections
}

func buildComment(run domain.Run, agents []domain.AgentRun, coverageWarning string) string {
	lines := []string{
		"## AI Code Review Summary", "",
		fmt.Sprintf("> **Mode:** Quick review · **Agents:** %d · **Head:** `%s`",
			len(agents), shortSHA(run.HeadSHA)), "",
	}
	if coverageWarning != "" {
		lines = append(lines, "> ⚠️ **Partial review coverage:** "+coverageWarning, "")
	}
	for _, agent := range agents {
		icon := "✅"
		if agent.Verdict != nil && !*agent.Verdict {
			icon = "⚠️"
		}
		lines = append(lines, fmt.Sprintf("### %s %s", icon, agent.Name))
		lines = append(lines, fmt.Sprintf("_%s · %s · effort: %s_",
			agent.Provider, agent.Model, agent.Effort))
		lines = append(lines, agent.Output, "")
	}
	lines = append(lines, PublicationMarker(run.RoutineID, run.HeadSHA))
	return strings.Join(lines, "\n")
}

func PublicationMarker(routineID, headSHA string) string {
	return fmt.Sprintf("<!-- gitranger:routine=%s;head=%s -->", routineID, headSHA)
}

func firstLine(value string) string {
	if index := strings.IndexByte(value, '\n'); index >= 0 {
		return value[:index]
	}
	return value
}

func stripVerdict(value string) string {
	lines := strings.Split(value, "\n")
	if len(lines) > 0 && strings.Contains(strings.ToUpper(lines[0]), "VERDICT:") {
		return strings.TrimSpace(strings.Join(lines[1:], "\n"))
	}
	return strings.TrimSpace(value)
}

func shortSHA(value string) string {
	if len(value) <= 7 {
		return value
	}
	return value[:7]
}

func defaultValue(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}
