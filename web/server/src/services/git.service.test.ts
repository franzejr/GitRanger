import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { gitService } from './git.service.js';
import fs from 'fs';
import path from 'path';

const TEST_REPO_URL = 'https://github.com/sindresorhus/is';
const TEST_REPO_ID = 'test-repo-git-service';
const TEST_REPO_PATH = path.join(process.cwd(), 'data', 'repos', TEST_REPO_ID);

describe('GitService', () => {
  describe('extractRepoName', () => {
    it('extracts name from HTTPS URL', () => {
      expect(gitService.extractRepoName('https://github.com/user/my-repo.git')).toBe('my-repo');
    });

    it('extracts name from HTTPS URL without .git', () => {
      expect(gitService.extractRepoName('https://github.com/user/my-repo')).toBe('my-repo');
    });

    it('extracts name from SSH URL', () => {
      expect(gitService.extractRepoName('git@github.com:user/my-repo.git')).toBe('my-repo');
    });
  });

  describe('clone and repository operations', () => {
    beforeAll(async () => {
      // Clean up any existing test repo
      if (fs.existsSync(TEST_REPO_PATH)) {
        fs.rmSync(TEST_REPO_PATH, { recursive: true, force: true });
      }
    }, 120000);

    afterAll(async () => {
      // Clean up test repo
      if (fs.existsSync(TEST_REPO_PATH)) {
        fs.rmSync(TEST_REPO_PATH, { recursive: true, force: true });
      }
    });

    it('clones a repository', async () => {
      const localPath = await gitService.clone(TEST_REPO_URL, TEST_REPO_ID);

      expect(localPath).toBe(TEST_REPO_PATH);
      expect(fs.existsSync(localPath)).toBe(true);
      expect(fs.existsSync(path.join(localPath, '.git'))).toBe(true);
    }, 120000);

    it('throws error when cloning to existing path', async () => {
      await expect(gitService.clone(TEST_REPO_URL, TEST_REPO_ID)).rejects.toThrow(
        /already exists/
      );
    });

    it('detects valid repository', async () => {
      const isRepo = await gitService.isRepo(TEST_REPO_PATH);
      expect(isRepo).toBe(true);
    });

    it('detects invalid repository', async () => {
      const isRepo = await gitService.isRepo('/tmp/not-a-repo');
      expect(isRepo).toBe(false);
    });

    it('gets default branch', async () => {
      const branch = await gitService.getDefaultBranch(TEST_REPO_PATH);
      expect(branch).toBe('main');
    });

    it('gets commit log', async () => {
      const commits = await gitService.getLog(TEST_REPO_PATH, { maxCount: 5 });

      expect(commits).toHaveLength(5);
      expect(commits[0]).toHaveProperty('sha');
      expect(commits[0]).toHaveProperty('message');
      expect(commits[0]).toHaveProperty('authorName');
      expect(commits[0]).toHaveProperty('authorEmail');
      expect(commits[0]).toHaveProperty('date');
    });

    it('gets commit diff', async () => {
      const commits = await gitService.getLog(TEST_REPO_PATH, { maxCount: 1 });
      const diff = await gitService.getDiff(TEST_REPO_PATH, commits[0].sha);

      expect(diff).toHaveProperty('sha', commits[0].sha);
      expect(diff).toHaveProperty('stat');
      expect(diff).toHaveProperty('patch');
    });

    it('deletes repository', async () => {
      await gitService.deleteRepo(TEST_REPO_PATH);
      expect(fs.existsSync(TEST_REPO_PATH)).toBe(false);
    });
  });
});
