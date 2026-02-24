import simpleGit, { SimpleGit, LogResult, DefaultLogFields } from 'simple-git';
import path from 'path';
import fs from 'fs';

const REPOS_DIR = process.env.REPOS_DIR || path.join(process.cwd(), 'data', 'repos');

// Ensure repos directory exists
if (!fs.existsSync(REPOS_DIR)) {
  fs.mkdirSync(REPOS_DIR, { recursive: true });
}

export interface CommitInfo {
  sha: string;
  message: string;
  authorName: string;
  authorEmail: string;
  date: Date;
  filesChanged: number;
  insertions: number;
  deletions: number;
}

export interface CommitDiff {
  sha: string;
  stat: string;
  patch: string;
}

class GitService {
  /**
   * Clone a repository (shallow clone for speed)
   */
  async clone(url: string, repoId: string): Promise<string> {
    const localPath = path.join(REPOS_DIR, repoId);

    if (fs.existsSync(localPath)) {
      throw new Error(`Repository already exists at ${localPath}`);
    }

    const git = simpleGit();

    // Shallow clone with depth 100 for initial import (faster)
    // We can deepen later if needed
    await git.clone(url, localPath, ['--depth', '500']);

    return localPath;
  }

  /**
   * Get the default branch name
   */
  async getDefaultBranch(repoPath: string): Promise<string> {
    const git = this.getGit(repoPath);

    try {
      // Try to get the default branch from remote
      const remoteInfo = await git.remote(['show', 'origin']);
      const match = remoteInfo?.match(/HEAD branch: (\S+)/);
      if (match) {
        return match[1];
      }
    } catch {
      // Fallback to checking local branches
    }

    // Fallback: check if main or master exists
    const branches = await git.branchLocal();
    if (branches.all.includes('main')) return 'main';
    if (branches.all.includes('master')) return 'master';

    return branches.current || 'main';
  }

  /**
   * Get commit log for a repository
   */
  async getLog(
    repoPath: string,
    options: {
      branch?: string;
      maxCount?: number;
      since?: string;
      until?: string;
      author?: string;
    } = {}
  ): Promise<CommitInfo[]> {
    const git = this.getGit(repoPath);

    const logOptions: string[] = ['--stat'];

    if (options.maxCount) {
      logOptions.push(`-n`, `${options.maxCount}`);
    }
    if (options.since) {
      logOptions.push(`--since=${options.since}`);
    }
    if (options.until) {
      logOptions.push(`--until=${options.until}`);
    }
    if (options.author) {
      logOptions.push(`--author=${options.author}`);
    }

    const log: LogResult<DefaultLogFields> = await git.log(logOptions);

    return log.all.map((commit) => this.parseCommit(commit));
  }

  /**
   * Get diff for a specific commit
   */
  async getDiff(repoPath: string, sha: string): Promise<CommitDiff> {
    const git = this.getGit(repoPath);

    // Get stat (files changed, insertions, deletions)
    const stat = await git.show([sha, '--stat', '--no-color', '--format=']);

    // Get the actual patch
    const patch = await git.show([sha, '--patch', '--no-color', '--format=']);

    return {
      sha,
      stat: stat.trim(),
      patch: patch.trim(),
    };
  }

  /**
   * Pull latest changes
   */
  async pull(repoPath: string): Promise<{ newCommits: number }> {
    const git = this.getGit(repoPath);

    // Get current HEAD before pull
    const beforeHead = await git.revparse(['HEAD']);

    // Unshallow if needed, then pull
    try {
      await git.fetch(['--unshallow']);
    } catch {
      // Already unshallowed or not shallow, ignore
    }

    await git.pull();

    // Get current HEAD after pull
    const afterHead = await git.revparse(['HEAD']);

    if (beforeHead === afterHead) {
      return { newCommits: 0 };
    }

    // Count new commits
    const log = await git.log([`${beforeHead}..${afterHead}`]);
    return { newCommits: log.total };
  }

  /**
   * Check if a path is a valid git repository
   */
  async isRepo(repoPath: string): Promise<boolean> {
    if (!fs.existsSync(repoPath)) {
      return false;
    }

    const git = this.getGit(repoPath);
    try {
      await git.status();
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Delete a repository from disk
   */
  async deleteRepo(repoPath: string): Promise<void> {
    if (fs.existsSync(repoPath)) {
      fs.rmSync(repoPath, { recursive: true, force: true });
    }
  }

  /**
   * Extract repo name from URL
   */
  extractRepoName(url: string): string {
    // Handle various URL formats:
    // https://github.com/user/repo.git
    // git@github.com:user/repo.git
    // https://github.com/user/repo

    const cleaned = url.replace(/\.git$/, '');
    const parts = cleaned.split('/');
    return parts[parts.length - 1] || 'unknown';
  }

  private getGit(repoPath: string): SimpleGit {
    return simpleGit(repoPath);
  }

  private parseCommit(commit: DefaultLogFields): CommitInfo {
    // Parse the diff stat from the commit body
    // Format: "3 files changed, 50 insertions(+), 10 deletions(-)"
    const body = commit.body || '';
    const statMatch = body.match(
      /(\d+) files? changed(?:, (\d+) insertions?\(\+\))?(?:, (\d+) deletions?\(-\))?/
    );

    return {
      sha: commit.hash,
      message: commit.message,
      authorName: commit.author_name,
      authorEmail: commit.author_email,
      date: new Date(commit.date),
      filesChanged: statMatch ? parseInt(statMatch[1], 10) : 0,
      insertions: statMatch && statMatch[2] ? parseInt(statMatch[2], 10) : 0,
      deletions: statMatch && statMatch[3] ? parseInt(statMatch[3], 10) : 0,
    };
  }
}

export const gitService = new GitService();
