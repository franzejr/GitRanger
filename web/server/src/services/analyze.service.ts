import db from '../db/index.js';
import { repoService, type Commit } from './repo.service.js';
import { gitService } from './git.service.js';
import { aiServiceFactory } from './ai/ai-factory.service.js';

class AnalyzeService {
  async analyzeCommit(commitId: string): Promise<Commit> {
    const start = Date.now();

    console.log(`[analyze] Starting analysis for commit ${commitId}`);

    const commit = await repoService.getCommitById(commitId);
    if (!commit) {
      throw new Error(`Commit not found: ${commitId}`);
    }

    const repo = await repoService.getRepoById(commit.repoId);
    if (!repo) {
      throw new Error(`Repository not found for commit: ${commitId}`);
    }

    console.log(`[analyze] Repo: ${repo.name} | Commit: ${commit.sha.slice(0, 7)} "${commit.message.split('\n')[0]}"`);

    console.log(`[analyze] Fetching diff...`);
    const diffData = await gitService.getDiff(repo.localPath, commit.sha);
    const fullDiff = `${diffData.stat}\n\n${diffData.patch}`;
    console.log(`[analyze] Diff size: ${fullDiff.length} chars | ${commit.filesChanged} files changed`);

    const aiService = aiServiceFactory.getActiveProvider();
    console.log(`[analyze] Calling AI provider: ${aiService.name}...`);

    const aiStart = Date.now();
    const summary = await aiService.summarize(commit.message, fullDiff, repo.localPath);
    const aiMs = Date.now() - aiStart;

    console.log(`[analyze] AI response in ${aiMs}ms | Impact: ${summary.impact} | "${summary.one_liner}"`);

    db.prepare(`
      UPDATE commits SET
        summary_one_liner = ?,
        summary_explanation = ?,
        summary_impact = ?,
        summary_categories = ?,
        summary_related_files = ?,
        summary_risk_notes = ?,
        analyzed_at = ?
      WHERE id = ?
    `).run(
      summary.one_liner,
      summary.explanation,
      summary.impact,
      JSON.stringify(summary.categories),
      summary.related_files ? JSON.stringify(summary.related_files) : null,
      summary.risk_notes ?? null,
      new Date().toISOString(),
      commitId
    );

    const totalMs = Date.now() - start;
    console.log(`[analyze] Done in ${totalMs}ms | Saved summary for ${commit.sha.slice(0, 7)}`);

    const updated = await repoService.getCommitById(commitId);
    return updated!;
  }
}

export const analyzeService = new AnalyzeService();
