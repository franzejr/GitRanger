import type { CommitSummary } from '../../types/index.js';

export function buildPrompt(commitMessage: string, diff: string): string {
  return `Analyze this git commit diff. Respond ONLY with valid JSON matching this schema:
{
  "one_liner": "one sentence summary of what changed",
  "explanation": "2-3 sentences explaining context and impact",
  "impact": "patch|minor|major|breaking",
  "categories": ["bugfix", "feature", "refactor", "docs", "test", "chore"],
  "related_files": ["optionally affected files"],
  "risk_notes": "potential risks or null"
}

Commit message: ${commitMessage}

Diff:
${diff}`;
}

interface NarrativeCommit {
  sha: string;
  message: string;
  authorName: string;
  committedAt: string;
  diff: string;
  filesChanged: number;
  insertions: number;
  deletions: number;
}

const NARRATIVE_DIFF_BUDGET = 30000;

export function buildNarrativePrompt(repoName: string, commits: NarrativeCommit[]): string {
  const perCommitBudget = Math.floor(NARRATIVE_DIFF_BUDGET / commits.length);

  const commitSections = commits.map((c, i) => {
    const truncatedDiff = c.diff.slice(0, perCommitBudget);
    return `--- Commit ${i + 1} of ${commits.length} ---
SHA: ${c.sha.slice(0, 7)}
Author: ${c.authorName}
Date: ${c.committedAt}
Message: ${c.message}
Stats: ${c.filesChanged} files changed, +${c.insertions} -${c.deletions}

Diff (truncated):
${truncatedDiff}`;
  }).join('\n\n');

  return `You are a technical storyteller. Below are ${commits.length} git commits from the "${repoName}" repository, listed in chronological order (oldest first).

Write a narrative that tells the story of these changes as a cohesive account. Your narrative should:

1. Be written in clear, engaging prose (not bullet points or JSON)
2. Follow chronological order, showing how the codebase evolved
3. Explain the "why" behind changes, not just the "what"
4. Connect related changes across commits
5. Highlight the overall arc — what was the developer trying to accomplish?
6. Be 2-5 paragraphs long, depending on the number and complexity of commits

Do NOT output JSON. Write plain prose. Do NOT use markdown headers. Use paragraph breaks only.

${commitSections}`;
}

export function parseCommitSummary(raw: string): CommitSummary {
  const clean = raw.replace(/```json\s*/g, '').replace(/```\s*/g, '').trim();
  const parsed = JSON.parse(clean) as CommitSummary;

  if (!parsed.one_liner || !parsed.explanation || !parsed.impact || !Array.isArray(parsed.categories)) {
    throw new Error('AI response missing required fields');
  }

  return parsed;
}
