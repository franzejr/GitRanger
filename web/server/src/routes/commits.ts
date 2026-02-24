import { Router, Request, Response } from 'express';
import { repoService } from '../services/repo.service.js';

export const commitsRouter = Router();

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
