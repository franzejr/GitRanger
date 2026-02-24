import { v4 as uuidv4 } from 'uuid';
import db, { RepoRow, CommitRow } from '../db/index.js';
import { gitService, CommitInfo } from './git.service.js';

export interface Repo {
  id: string;
  name: string;
  url: string;
  localPath: string;
  defaultBranch: string;
  lastPolledAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
  commitCount?: number;
}

export interface Commit {
  id: string;
  repoId: string;
  sha: string;
  message: string;
  authorName: string;
  authorEmail: string;
  committedAt: Date;
  filesChanged: number;
  insertions: number;
  deletions: number;
  summary?: {
    oneLiner: string;
    explanation: string;
    impact: string;
    categories: string[];
    relatedFiles?: string[];
    riskNotes?: string;
  };
  analyzedAt?: Date;
}

export interface CommitFilters {
  author?: string;
  since?: string;
  until?: string;
  limit?: number;
  offset?: number;
}

class RepoService {
  /**
   * Import a new repository
   */
  async importRepo(url: string): Promise<Repo> {
    // Check if repo already exists
    const existing = db
      .prepare('SELECT * FROM repos WHERE url = ?')
      .get(url) as RepoRow | undefined;

    if (existing) {
      throw new Error(`Repository already imported: ${url}`);
    }

    const id = uuidv4();
    const name = gitService.extractRepoName(url);

    // Clone the repository
    console.log(`Cloning repository: ${url}`);
    const localPath = await gitService.clone(url, id);

    // Get default branch
    const defaultBranch = await gitService.getDefaultBranch(localPath);

    // Insert repo into database
    const now = new Date().toISOString();
    db.prepare(
      `INSERT INTO repos (id, name, url, local_path, default_branch, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    ).run(id, name, url, localPath, defaultBranch, now, now);

    // Import commits
    console.log(`Importing commits for ${name}...`);
    await this.importCommits(id, localPath);

    return this.getRepoById(id) as Promise<Repo>;
  }

  /**
   * Import commits from a repository
   */
  async importCommits(repoId: string, localPath: string): Promise<number> {
    const commits = await gitService.getLog(localPath, { maxCount: 500 });

    const insertStmt = db.prepare(
      `INSERT OR IGNORE INTO commits
       (id, repo_id, sha, message, author_name, author_email, committed_at, files_changed, insertions, deletions)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    );

    let imported = 0;
    const insertMany = db.transaction((commits: CommitInfo[]) => {
      for (const commit of commits) {
        const result = insertStmt.run(
          uuidv4(),
          repoId,
          commit.sha,
          commit.message,
          commit.authorName,
          commit.authorEmail,
          commit.date.toISOString(),
          commit.filesChanged,
          commit.insertions,
          commit.deletions
        );
        if (result.changes > 0) imported++;
      }
    });

    insertMany(commits);
    console.log(`Imported ${imported} commits`);

    return imported;
  }

  /**
   * Get all repositories
   */
  async getAllRepos(): Promise<Repo[]> {
    const rows = db
      .prepare(
        `SELECT r.*, COUNT(c.id) as commit_count
         FROM repos r
         LEFT JOIN commits c ON c.repo_id = r.id
         GROUP BY r.id
         ORDER BY r.created_at DESC`
      )
      .all() as (RepoRow & { commit_count: number })[];

    return rows.map((row) => this.mapRepoRow(row));
  }

  /**
   * Get repository by ID
   */
  async getRepoById(id: string): Promise<Repo | null> {
    const row = db
      .prepare(
        `SELECT r.*, COUNT(c.id) as commit_count
         FROM repos r
         LEFT JOIN commits c ON c.repo_id = r.id
         WHERE r.id = ?
         GROUP BY r.id`
      )
      .get(id) as (RepoRow & { commit_count: number }) | undefined;

    return row ? this.mapRepoRow(row) : null;
  }

  /**
   * Delete a repository
   */
  async deleteRepo(id: string): Promise<boolean> {
    const repo = await this.getRepoById(id);
    if (!repo) return false;

    // Delete from filesystem
    await gitService.deleteRepo(repo.localPath);

    // Delete from database (cascades to commits and notifications)
    db.prepare('DELETE FROM repos WHERE id = ?').run(id);

    return true;
  }

  /**
   * Get commits for a repository with filters
   */
  async getCommits(repoId: string, filters: CommitFilters = {}): Promise<{ commits: Commit[]; total: number }> {
    const { author, since, until, limit = 50, offset = 0 } = filters;

    let whereClause = 'WHERE repo_id = ?';
    const params: (string | number)[] = [repoId];

    if (author) {
      whereClause += ' AND (author_name LIKE ? OR author_email LIKE ?)';
      params.push(`%${author}%`, `%${author}%`);
    }

    if (since) {
      whereClause += ' AND committed_at >= ?';
      params.push(since);
    }

    if (until) {
      whereClause += ' AND committed_at <= ?';
      params.push(until);
    }

    // Get total count
    const countResult = db
      .prepare(`SELECT COUNT(*) as total FROM commits ${whereClause}`)
      .get(...params) as { total: number };

    // Get commits with pagination
    const rows = db
      .prepare(
        `SELECT * FROM commits ${whereClause}
         ORDER BY committed_at DESC
         LIMIT ? OFFSET ?`
      )
      .all(...params, limit, offset) as CommitRow[];

    return {
      commits: rows.map((row) => this.mapCommitRow(row)),
      total: countResult.total,
    };
  }

  /**
   * Get a single commit by ID
   */
  async getCommitById(id: string): Promise<Commit | null> {
    const row = db
      .prepare('SELECT * FROM commits WHERE id = ?')
      .get(id) as CommitRow | undefined;

    return row ? this.mapCommitRow(row) : null;
  }

  /**
   * Get commit with its diff
   */
  async getCommitWithDiff(id: string): Promise<{ commit: Commit; diff: string } | null> {
    const commit = await this.getCommitById(id);
    if (!commit) return null;

    const repo = await this.getRepoById(commit.repoId);
    if (!repo) return null;

    const diffData = await gitService.getDiff(repo.localPath, commit.sha);

    return {
      commit,
      diff: diffData.patch,
    };
  }

  /**
   * Sync repository (pull new commits)
   */
  async syncRepo(id: string): Promise<{ newCommits: number }> {
    const repo = await this.getRepoById(id);
    if (!repo) {
      throw new Error(`Repository not found: ${id}`);
    }

    // Pull latest changes
    const { newCommits } = await gitService.pull(repo.localPath);

    if (newCommits > 0) {
      // Import new commits
      await this.importCommits(id, repo.localPath);
    }

    // Update last polled time
    db.prepare('UPDATE repos SET last_polled_at = ?, updated_at = ? WHERE id = ?').run(
      new Date().toISOString(),
      new Date().toISOString(),
      id
    );

    return { newCommits };
  }

  private mapRepoRow(row: RepoRow & { commit_count?: number }): Repo {
    return {
      id: row.id,
      name: row.name,
      url: row.url,
      localPath: row.local_path,
      defaultBranch: row.default_branch,
      lastPolledAt: row.last_polled_at ? new Date(row.last_polled_at) : null,
      createdAt: new Date(row.created_at),
      updatedAt: new Date(row.updated_at),
      commitCount: row.commit_count,
    };
  }

  private mapCommitRow(row: CommitRow): Commit {
    const commit: Commit = {
      id: row.id,
      repoId: row.repo_id,
      sha: row.sha,
      message: row.message,
      authorName: row.author_name,
      authorEmail: row.author_email,
      committedAt: new Date(row.committed_at),
      filesChanged: row.files_changed,
      insertions: row.insertions,
      deletions: row.deletions,
    };

    if (row.summary_one_liner) {
      commit.summary = {
        oneLiner: row.summary_one_liner,
        explanation: row.summary_explanation || '',
        impact: row.summary_impact || 'patch',
        categories: row.summary_categories ? JSON.parse(row.summary_categories) : [],
        relatedFiles: row.summary_related_files ? JSON.parse(row.summary_related_files) : undefined,
        riskNotes: row.summary_risk_notes || undefined,
      };
      commit.analyzedAt = row.analyzed_at ? new Date(row.analyzed_at) : undefined;
    }

    return commit;
  }
}

export const repoService = new RepoService();
