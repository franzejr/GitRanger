import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { repoService } from './repo.service.js';
import db from '../db/index.js';
import { runMigrations } from '../db/migrate.js';
import fs from 'fs';
import path from 'path';

const TEST_REPO_URL = 'https://github.com/sindresorhus/is';
const TEST_REPOS_PATH = path.join(process.cwd(), 'data', 'repos');

describe('RepoService', () => {
  let testRepoId: string;

  beforeAll(() => {
    // Ensure migrations are run
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

  describe('importRepo', () => {
    it('imports a repository and extracts commits', async () => {
      const repo = await repoService.importRepo(TEST_REPO_URL);
      testRepoId = repo.id;

      expect(repo).toHaveProperty('id');
      expect(repo.name).toBe('is');
      expect(repo.url).toBe(TEST_REPO_URL);
      expect(repo.defaultBranch).toBe('main');
      expect(repo.commitCount).toBeGreaterThan(0);
      expect(fs.existsSync(repo.localPath)).toBe(true);
    }, 120000);

    it('throws error for duplicate import', async () => {
      await expect(repoService.importRepo(TEST_REPO_URL)).rejects.toThrow(
        /already imported/
      );
    });
  });

  describe('getAllRepos', () => {
    it('returns list of repositories', async () => {
      const repos = await repoService.getAllRepos();

      expect(Array.isArray(repos)).toBe(true);
      expect(repos.length).toBeGreaterThan(0);

      const testRepo = repos.find((r) => r.id === testRepoId);
      expect(testRepo).toBeDefined();
      expect(testRepo?.name).toBe('is');
    });
  });

  describe('getRepoById', () => {
    it('returns repository by ID', async () => {
      const repo = await repoService.getRepoById(testRepoId);

      expect(repo).not.toBeNull();
      expect(repo?.id).toBe(testRepoId);
      expect(repo?.name).toBe('is');
    });

    it('returns null for non-existent ID', async () => {
      const repo = await repoService.getRepoById('non-existent-id');
      expect(repo).toBeNull();
    });
  });

  describe('getCommits', () => {
    it('returns paginated commits', async () => {
      const result = await repoService.getCommits(testRepoId, { limit: 10 });

      expect(result.commits).toHaveLength(10);
      expect(result.total).toBeGreaterThan(10);
      expect(result.commits[0]).toHaveProperty('sha');
      expect(result.commits[0]).toHaveProperty('message');
      expect(result.commits[0]).toHaveProperty('authorName');
    });

    it('filters by author', async () => {
      const result = await repoService.getCommits(testRepoId, {
        author: 'Sindre',
        limit: 5,
      });

      expect(result.commits.length).toBeGreaterThan(0);
      result.commits.forEach((commit) => {
        expect(commit.authorName.toLowerCase()).toContain('sindre');
      });
    });

    it('filters by date range', async () => {
      const result = await repoService.getCommits(testRepoId, {
        since: '2020-01-01',
        until: '2020-12-31',
        limit: 100,
      });

      result.commits.forEach((commit) => {
        const year = commit.committedAt.getFullYear();
        expect(year).toBe(2020);
      });
    });

    it('supports pagination offset', async () => {
      const page1 = await repoService.getCommits(testRepoId, { limit: 5, offset: 0 });
      const page2 = await repoService.getCommits(testRepoId, { limit: 5, offset: 5 });

      expect(page1.commits[0].sha).not.toBe(page2.commits[0].sha);
    });
  });

  describe('getCommitById', () => {
    it('returns commit by ID', async () => {
      const { commits } = await repoService.getCommits(testRepoId, { limit: 1 });
      const commit = await repoService.getCommitById(commits[0].id);

      expect(commit).not.toBeNull();
      expect(commit?.sha).toBe(commits[0].sha);
    });

    it('returns null for non-existent ID', async () => {
      const commit = await repoService.getCommitById('non-existent-id');
      expect(commit).toBeNull();
    });
  });

  describe('getCommitWithDiff', () => {
    it('returns commit with diff', async () => {
      const { commits } = await repoService.getCommits(testRepoId, { limit: 1 });
      const result = await repoService.getCommitWithDiff(commits[0].id);

      expect(result).not.toBeNull();
      expect(result?.commit.sha).toBe(commits[0].sha);
      expect(typeof result?.diff).toBe('string');
    });
  });

  describe('deleteRepo', () => {
    it('deletes repository and cleans up files', async () => {
      // Import a new repo to delete
      const repo = await repoService.importRepo('https://github.com/sindresorhus/slugify');
      const repoPath = repo.localPath;

      expect(fs.existsSync(repoPath)).toBe(true);

      const deleted = await repoService.deleteRepo(repo.id);

      expect(deleted).toBe(true);
      expect(fs.existsSync(repoPath)).toBe(false);

      const fetchedRepo = await repoService.getRepoById(repo.id);
      expect(fetchedRepo).toBeNull();
    }, 120000);

    it('returns false for non-existent repo', async () => {
      const deleted = await repoService.deleteRepo('non-existent-id');
      expect(deleted).toBe(false);
    });
  });
});
