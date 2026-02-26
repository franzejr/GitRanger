import { repoService, type Commit } from './repo.service.js';
import { gitService } from './git.service.js';
import { aiServiceFactory } from './ai/ai-factory.service.js';
import { buildNarrativePrompt } from './ai/prompt.js';

export interface NarrativeResult {
  narrative: string;
  commitCount: number;
  timespan: { from: string; to: string };
}

class NarrativeService {
  async generateNarrative(commitIds: string[]): Promise<NarrativeResult> {
    if (commitIds.length < 2) {
      throw new Error('At least 2 commits required for a narrative');
    }
    if (commitIds.length > 20) {
      throw new Error('Maximum 20 commits allowed per narrative');
    }

    console.log(`[narrative] Generating narrative for ${commitIds.length} commits`);

    const commits: Commit[] = [];
    for (const id of commitIds) {
      const commit = await repoService.getCommitById(id);
      if (!commit) throw new Error(`Commit not found: ${id}`);
      commits.push(commit);
    }

    const repoIds = new Set(commits.map((c) => c.repoId));
    if (repoIds.size > 1) {
      throw new Error('All commits must belong to the same repository');
    }

    const repo = await repoService.getRepoById(commits[0].repoId);
    if (!repo) throw new Error('Repository not found');

    commits.sort(
      (a, b) => new Date(a.committedAt).getTime() - new Date(b.committedAt).getTime()
    );

    console.log(`[narrative] Fetching diffs for ${commits.length} commits...`);
    const commitsWithDiffs = await Promise.all(
      commits.map(async (commit) => {
        const diffData = await gitService.getDiff(repo.localPath, commit.sha);
        return {
          sha: commit.sha,
          message: commit.message,
          authorName: commit.authorName,
          committedAt: new Date(commit.committedAt).toISOString(),
          diff: diffData.patch,
          filesChanged: commit.filesChanged,
          insertions: commit.insertions,
          deletions: commit.deletions,
        };
      })
    );

    const prompt = buildNarrativePrompt(repo.name, commitsWithDiffs);
    console.log(`[narrative] Prompt length: ${prompt.length} chars`);

    const aiService = aiServiceFactory.getActiveProvider();
    console.log(`[narrative] Calling AI provider: ${aiService.name}...`);

    const start = Date.now();
    const narrative = await aiService.generate(prompt, repo.localPath);
    const ms = Date.now() - start;

    console.log(`[narrative] AI response in ${ms}ms (${narrative.length} chars)`);

    return {
      narrative,
      commitCount: commits.length,
      timespan: {
        from: new Date(commits[0].committedAt).toISOString(),
        to: new Date(commits[commits.length - 1].committedAt).toISOString(),
      },
    };
  }
}

export const narrativeService = new NarrativeService();
