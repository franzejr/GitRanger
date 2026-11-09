# Review prompts

GitRanger Terminal sends one prompt to the configured provider for each pull
request. That single request asks for all selected review roles; it does not
start a separate model conversation for each role.

The implementation is in
[`internal/review/reviewer.go`](internal/review/reviewer.go), in `buildPrompt`.
The template below matches the default five roles and `low` effort. Replace the
braced placeholders with your PR metadata and diff, then paste it into your
preferred model or pass it to a CLI on standard input.

## Copyable default prompt

```text
Perform a quick pull request review for every role below in one pass.
Use low reasoning effort and finish within the configured deadline. Analyze only
the supplied context. Prefer concise, high-confidence findings. Return every
section exactly once and in the requested order.

Coverage: the complete supplied diff is included.

--- Roles ---
Agent ID: summary
Agent name: Summary
Focus only on summary.

Agent ID: security
Agent name: Security
Focus only on security.

Agent ID: performance
Agent name: Performance
Focus only on performance.

Agent ID: code_quality
Agent name: Code Quality
Focus only on code quality.

Agent ID: bug_detector
Agent name: Bug Detector
Focus only on bug detector.

--- Required output ---
<<<GITRANGER_AGENT:summary>>>
VERDICT: PASS or VERDICT: FAIL
Concise findings
<<<GITRANGER_END_AGENT>>>
<<<GITRANGER_AGENT:security>>>
VERDICT: PASS or VERDICT: FAIL
Concise findings
<<<GITRANGER_END_AGENT>>>
<<<GITRANGER_AGENT:performance>>>
VERDICT: PASS or VERDICT: FAIL
Concise findings
<<<GITRANGER_END_AGENT>>>
<<<GITRANGER_AGENT:code_quality>>>
VERDICT: PASS or VERDICT: FAIL
Concise findings
<<<GITRANGER_END_AGENT>>>
<<<GITRANGER_AGENT:bug_detector>>>
VERDICT: PASS or VERDICT: FAIL
Concise findings
<<<GITRANGER_END_AGENT>>>

--- Pull Request ---
Title: {PR title}
Author: {author login}
Branch: {head branch} -> {base branch}

Description:
{PR description, or (no description)}

--- Diff ---
{PR diff}
```

## Partial diff prompt

Quick reviews include at most 30,000 bytes of the diff, preserving UTF-8
boundaries. When the diff exceeds that limit, GitRanger supplies its prefix and
replaces the coverage sentence with this exact text:

```text
Coverage warning: Partial review: the diff exceeded the 30000-byte quick-review limit, so findings do not cover the entire change. Every agent must state that its findings are limited to the supplied prefix.
```

The final review also includes the partial-coverage warning. A completed review
of a truncated diff does not mean the entire PR was reviewed.

## Customization and output

- `routines[].agents` selects the roles and their order. GitRanger generates a
  role block and a required-output block for each selected role.
- `provider.effort` replaces `low` in the prompt. This is a textual instruction;
  it does not automatically set a provider CLI's reasoning flag.
- `provider.model`, when set, is passed separately as `--model`.
- Each response section must use the exact delimiters above. Missing or empty
  sections fail the run. Use either `VERDICT: PASS` or `VERDICT: FAIL` as its
  first line, followed by the findings.
- The application combines the sections into a Markdown comment. Publication
  depends on the routine's `delivery` setting (`preview` or `automatic_comment`).

This documents the terminal client's prompt. The native macOS application has
its own review implementation.
