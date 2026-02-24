import { Router, Request, Response } from 'express';
import { repoService } from '../services/repo.service.js';

export const reposRouter = Router();

// GET /api/repos - List all repositories
reposRouter.get('/', async (_req: Request, res: Response) => {
  try {
    const repos = await repoService.getAllRepos();
    res.json({ repos });
  } catch (error) {
    console.error('Error listing repos:', error);
    res.status(500).json({ error: 'Failed to list repositories' });
  }
});

// POST /api/repos - Import a new repository
reposRouter.post('/', async (req: Request, res: Response) => {
  const { url } = req.body;

  if (!url) {
    res.status(400).json({ error: 'Repository URL is required' });
    return;
  }

  try {
    const repo = await repoService.importRepo(url);
    res.status(201).json({ repo });
  } catch (error) {
    console.error('Error importing repo:', error);
    const message = error instanceof Error ? error.message : 'Failed to import repository';
    res.status(400).json({ error: message });
  }
});

// GET /api/repos/:id - Get repository details
reposRouter.get('/:id', async (req: Request, res: Response) => {
  const { id } = req.params;

  try {
    const repo = await repoService.getRepoById(id);
    if (!repo) {
      res.status(404).json({ error: 'Repository not found' });
      return;
    }
    res.json({ repo });
  } catch (error) {
    console.error('Error getting repo:', error);
    res.status(500).json({ error: 'Failed to get repository' });
  }
});

// DELETE /api/repos/:id - Delete a repository
reposRouter.delete('/:id', async (req: Request, res: Response) => {
  const { id } = req.params;

  try {
    const deleted = await repoService.deleteRepo(id);
    if (!deleted) {
      res.status(404).json({ error: 'Repository not found' });
      return;
    }
    res.json({ success: true, message: 'Repository deleted' });
  } catch (error) {
    console.error('Error deleting repo:', error);
    res.status(500).json({ error: 'Failed to delete repository' });
  }
});

// POST /api/repos/:id/sync - Sync repository (pull new commits)
reposRouter.post('/:id/sync', async (req: Request, res: Response) => {
  const { id } = req.params;

  try {
    const result = await repoService.syncRepo(id);
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('Error syncing repo:', error);
    const message = error instanceof Error ? error.message : 'Failed to sync repository';
    res.status(400).json({ error: message });
  }
});

// GET /api/repos/:id/commits - List commits with pagination and filters
reposRouter.get('/:id/commits', async (req: Request, res: Response) => {
  const { id } = req.params;
  const { author, since, until, limit, offset } = req.query;

  try {
    const repo = await repoService.getRepoById(id);
    if (!repo) {
      res.status(404).json({ error: 'Repository not found' });
      return;
    }

    const result = await repoService.getCommits(id, {
      author: author as string | undefined,
      since: since as string | undefined,
      until: until as string | undefined,
      limit: limit ? parseInt(limit as string, 10) : undefined,
      offset: offset ? parseInt(offset as string, 10) : undefined,
    });

    res.json({
      commits: result.commits,
      total: result.total,
      limit: limit ? parseInt(limit as string, 10) : 50,
      offset: offset ? parseInt(offset as string, 10) : 0,
    });
  } catch (error) {
    console.error('Error listing commits:', error);
    res.status(500).json({ error: 'Failed to list commits' });
  }
});
