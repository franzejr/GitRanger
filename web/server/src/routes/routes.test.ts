import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { createApp } from '../app.js';
import { runMigrations } from '../db/migrate.js';
import db from '../db/index.js';
import fs from 'fs';
import path from 'path';

const app = createApp();
const TEST_REPOS_PATH = path.join(process.cwd(), 'data', 'repos');
// Use a different repo than the service tests to avoid conflicts
const TEST_REPO_URL = 'https://github.com/sindresorhus/camelcase';

describe('API Routes', () => {
  let testRepoId: string;

  beforeAll(() => {
    runMigrations();
  });

  afterAll(() => {
    // Clean up test data
    if (testRepoId) {
      db.prepare('DELETE FROM repos WHERE id = ?').run(testRepoId);

      const repoPath = path.join(TEST_REPOS_PATH, testRepoId);
      if (fs.existsSync(repoPath)) {
        fs.rmSync(repoPath, { recursive: true, force: true });
      }
    }
  });

  describe('GET /api/health', () => {
    it('returns health status', async () => {
      const response = await request(app).get('/api/health');

      expect(response.status).toBe(200);
      expect(response.body.status).toBe('ok');
      expect(response.body.service).toBe('gitnarrate-server');
      expect(response.body.timestamp).toBeDefined();
    });
  });

  describe('POST /api/repos', () => {
    it('returns 400 when URL is missing', async () => {
      const response = await request(app).post('/api/repos').send({});

      expect(response.status).toBe(400);
      expect(response.body.error).toBe('Repository URL is required');
    });

    it('imports a repository', async () => {
      const response = await request(app)
        .post('/api/repos')
        .send({ url: 'https://github.com/sindresorhus/camelcase' });

      expect(response.status).toBe(201);
      expect(response.body.repo).toBeDefined();
      expect(response.body.repo.name).toBe('camelcase');
      expect(response.body.repo.commitCount).toBeGreaterThan(0);

      testRepoId = response.body.repo.id;
    }, 120000);

    it('returns 400 for duplicate import', async () => {
      const response = await request(app)
        .post('/api/repos')
        .send({ url: 'https://github.com/sindresorhus/camelcase' });

      expect(response.status).toBe(400);
      expect(response.body.error).toContain('already imported');
    });
  });

  describe('GET /api/repos', () => {
    it('lists all repositories', async () => {
      const response = await request(app).get('/api/repos');

      expect(response.status).toBe(200);
      expect(Array.isArray(response.body.repos)).toBe(true);

      const testRepo = response.body.repos.find(
        (r: { id: string }) => r.id === testRepoId
      );
      expect(testRepo).toBeDefined();
    });
  });

  describe('GET /api/repos/:id', () => {
    it('returns repository details', async () => {
      const response = await request(app).get(`/api/repos/${testRepoId}`);

      expect(response.status).toBe(200);
      expect(response.body.repo.id).toBe(testRepoId);
      expect(response.body.repo.name).toBe('camelcase');
    });

    it('returns 404 for non-existent repo', async () => {
      const response = await request(app).get('/api/repos/non-existent-id');

      expect(response.status).toBe(404);
      expect(response.body.error).toBe('Repository not found');
    });
  });

  describe('GET /api/repos/:id/commits', () => {
    it('returns paginated commits', async () => {
      const response = await request(app).get(
        `/api/repos/${testRepoId}/commits?limit=5`
      );

      expect(response.status).toBe(200);
      expect(response.body.commits).toHaveLength(5);
      expect(response.body.total).toBeGreaterThan(5);
      expect(response.body.limit).toBe(5);
      expect(response.body.offset).toBe(0);
    });

    it('filters by author', async () => {
      const response = await request(app).get(
        `/api/repos/${testRepoId}/commits?author=Sindre&limit=5`
      );

      expect(response.status).toBe(200);
      expect(response.body.commits.length).toBeGreaterThan(0);
      response.body.commits.forEach((commit: { authorName: string }) => {
        expect(commit.authorName.toLowerCase()).toContain('sindre');
      });
    });

    it('filters by date range', async () => {
      const response = await request(app).get(
        `/api/repos/${testRepoId}/commits?since=2020-01-01&until=2020-12-31`
      );

      expect(response.status).toBe(200);
      response.body.commits.forEach((commit: { committedAt: string }) => {
        const year = new Date(commit.committedAt).getFullYear();
        expect(year).toBe(2020);
      });
    });

    it('returns 404 for non-existent repo', async () => {
      const response = await request(app).get(
        '/api/repos/non-existent-id/commits'
      );

      expect(response.status).toBe(404);
    });
  });

  describe('GET /api/commits/:id', () => {
    it('returns commit with diff', async () => {
      // Get a commit ID first
      const listResponse = await request(app).get(
        `/api/repos/${testRepoId}/commits?limit=1`
      );
      const commitId = listResponse.body.commits[0].id;

      const response = await request(app).get(`/api/commits/${commitId}`);

      expect(response.status).toBe(200);
      expect(response.body.commit).toBeDefined();
      expect(response.body.diff).toBeDefined();
      expect(typeof response.body.diff).toBe('string');
    });

    it('returns 404 for non-existent commit', async () => {
      const response = await request(app).get('/api/commits/non-existent-id');

      expect(response.status).toBe(404);
      expect(response.body.error).toBe('Commit not found');
    });
  });

  describe('DELETE /api/repos/:id', () => {
    it('returns 404 for non-existent repo', async () => {
      const response = await request(app).delete('/api/repos/non-existent-id');

      expect(response.status).toBe(404);
    });

    // Note: We don't test actual deletion here to preserve the test repo
    // for other tests. Deletion is tested in repo.service.test.ts
  });
});
