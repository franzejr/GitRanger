import type Database from 'better-sqlite3';

export const up = (db: Database.Database): void => {
  db.exec(`
    -- Repositories table
    CREATE TABLE IF NOT EXISTS repos (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      url TEXT NOT NULL UNIQUE,
      local_path TEXT NOT NULL,
      default_branch TEXT DEFAULT 'main',
      last_polled_at TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    -- Commits table
    CREATE TABLE IF NOT EXISTS commits (
      id TEXT PRIMARY KEY,
      repo_id TEXT NOT NULL,
      sha TEXT NOT NULL,
      message TEXT NOT NULL,
      author_name TEXT NOT NULL,
      author_email TEXT NOT NULL,
      committed_at TEXT NOT NULL,
      files_changed INTEGER DEFAULT 0,
      insertions INTEGER DEFAULT 0,
      deletions INTEGER DEFAULT 0,
      -- AI summary fields (nullable until analyzed)
      summary_one_liner TEXT,
      summary_explanation TEXT,
      summary_impact TEXT,
      summary_categories TEXT, -- JSON array stored as text
      summary_related_files TEXT, -- JSON array stored as text
      summary_risk_notes TEXT,
      analyzed_at TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (repo_id) REFERENCES repos(id) ON DELETE CASCADE,
      UNIQUE(repo_id, sha)
    );

    -- Notifications table
    CREATE TABLE IF NOT EXISTS notifications (
      id TEXT PRIMARY KEY,
      repo_id TEXT NOT NULL,
      commit_id TEXT,
      type TEXT NOT NULL, -- 'new_commit', 'analysis_complete', 'error'
      title TEXT NOT NULL,
      message TEXT,
      read INTEGER DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (repo_id) REFERENCES repos(id) ON DELETE CASCADE,
      FOREIGN KEY (commit_id) REFERENCES commits(id) ON DELETE SET NULL
    );

    -- Settings table (key-value store)
    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    -- Indexes for performance
    CREATE INDEX IF NOT EXISTS idx_commits_repo_id ON commits(repo_id);
    CREATE INDEX IF NOT EXISTS idx_commits_committed_at ON commits(committed_at);
    CREATE INDEX IF NOT EXISTS idx_commits_author_email ON commits(author_email);
    CREATE INDEX IF NOT EXISTS idx_notifications_repo_id ON notifications(repo_id);
    CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(read);

    -- Migrations tracking table
    CREATE TABLE IF NOT EXISTS migrations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      applied_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);
};

export const down = (db: Database.Database): void => {
  db.exec(`
    DROP TABLE IF EXISTS notifications;
    DROP TABLE IF EXISTS commits;
    DROP TABLE IF EXISTS repos;
    DROP TABLE IF EXISTS settings;
    DROP TABLE IF EXISTS migrations;
  `);
};
