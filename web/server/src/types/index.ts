export interface CommitSummary {
  one_liner: string;
  explanation: string;
  impact: 'patch' | 'minor' | 'major' | 'breaking';
  categories: string[];
  related_files?: string[];
  risk_notes?: string | null;
}

export interface AIService {
  name: string;
  requiresAPIKey: boolean;
  isAvailable(): Promise<boolean>;
  summarize(
    commitMessage: string,
    diff: string,
    repoPath?: string
  ): Promise<CommitSummary>;
  generate(prompt: string, repoPath?: string): Promise<string>;
}

export type AIProvider = 'claude_code' | 'anthropic_api' | 'openai' | 'ollama';

export interface Repository {
  id: string;
  name: string;
  url: string;
  localPath: string;
  createdAt: Date;
  lastPolledAt?: Date;
}

export interface Commit {
  sha: string;
  message: string;
  author: string;
  authorEmail: string;
  date: Date;
  filesChanged: number;
  insertions: number;
  deletions: number;
  summary?: CommitSummary;
}
