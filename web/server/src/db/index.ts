import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';

const DATA_DIR = process.env.DATA_DIR || path.join(process.cwd(), 'data');
const DB_PATH = path.join(DATA_DIR, 'gitnarrate.db');

// Ensure data directory exists
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// Create database connection
const db = new Database(DB_PATH);

// Enable foreign keys and WAL mode for better performance
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

export default db;

// Helper types
export interface RepoRow {
  id: string;
  name: string;
  url: string;
  local_path: string;
  default_branch: string;
  last_polled_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface CommitRow {
  id: string;
  repo_id: string;
  sha: string;
  message: string;
  author_name: string;
  author_email: string;
  committed_at: string;
  files_changed: number;
  insertions: number;
  deletions: number;
  summary_one_liner: string | null;
  summary_explanation: string | null;
  summary_impact: string | null;
  summary_categories: string | null;
  summary_related_files: string | null;
  summary_risk_notes: string | null;
  analyzed_at: string | null;
  created_at: string;
}

export interface NotificationRow {
  id: string;
  repo_id: string;
  commit_id: string | null;
  type: string;
  title: string;
  message: string | null;
  read: number;
  created_at: string;
}

export interface SettingRow {
  key: string;
  value: string;
  updated_at: string;
}
