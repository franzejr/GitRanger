import { Router, Request, Response } from 'express';
import { repoService } from '../services/repo.service.js';
import { analyzeService } from '../services/analyze.service.js';
import { narrativeService } from '../services/narrative.service.js';

export const commitsRouter = Router();

// POST /api/commits/narrative - Generate narrative for multiple commits
commitsRouter.post('/narrative', async (req: Request, res: Response) => {
  const { commitIds } = req.body;

  if (!Array.isArray(commitIds) || commitIds.length === 0) {
    res.status(400).json({ error: 'commitIds must be a non-empty array' });
    return;
  }

  try {
    const result = await narrativeService.generateNarrative(commitIds);
    res.json(result);
  } catch (error) {
    console.error('Error generating narrative:', error);
    const message = error instanceof Error ? error.message : 'Narrative generation failed';
    if (message.includes('not found')) {
      res.status(404).json({ error: message });
      return;
    }
    if (message.includes('At least') || message.includes('Maximum') || message.includes('same repository')) {
      res.status(400).json({ error: message });
      return;
    }
    res.status(500).json({ error: message });
  }
});

// GET /api/commits/:id - Get commit details with diff
commitsRouter.get('/:id', async (req: Request, res: Response) => {
  const { id } = req.params;

  try {
    const result = await repoService.getCommitWithDiff(id);
    if (!result) {
      res.status(404).json({ error: 'Commit not found' });
      return;
    }

    res.json({
      commit: result.commit,
      diff: result.diff,
    });
  } catch (error) {
    console.error('Error getting commit:', error);
    res.status(500).json({ error: 'Failed to get commit' });
  }
});

// POST /api/commits/:id/analyze - Analyze commit with AI
commitsRouter.post('/:id/analyze', async (req: Request, res: Response) => {
  const { id } = req.params;

  try {
    const commit = await analyzeService.analyzeCommit(id);
    res.json({ commit });
  } catch (error) {
    console.error('Error analyzing commit:', error);
    const message = error instanceof Error ? error.message : 'Analysis failed';
    if (message.includes('not found')) {
      res.status(404).json({ error: message });
      return;
    }
    res.status(500).json({ error: message });
  }
});
