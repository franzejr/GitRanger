export interface Repo {
  id: string
  name: string
  url: string
  localPath: string
  defaultBranch: string
  lastPolledAt: string | null
  createdAt: string
  updatedAt: string
  commitCount: number
}

export interface CommitSummary {
  oneLiner: string
  explanation: string
  impact: 'patch' | 'minor' | 'major' | 'breaking'
  categories: string[]
  relatedFiles?: string[]
  riskNotes?: string
}

export interface Commit {
  id: string
  repoId: string
  sha: string
  message: string
  authorName: string
  authorEmail: string
  committedAt: string
  filesChanged: number
  insertions: number
  deletions: number
  summary?: CommitSummary
  analyzedAt?: string
}

export type AIProvider = 'claude_code' | 'anthropic_api' | 'openai' | 'ollama'

export interface AIProviderStatus {
  provider: AIProvider
  name: string
  available: boolean
  requiresAPIKey: boolean
}

export interface AIStatus {
  providers: AIProviderStatus[]
  activeProvider: AIProvider
}

export interface NarrativeResponse {
  narrative: string
  commitCount: number
  timespan: { from: string; to: string }
}

export interface CommitFilters {
  author?: string
  since?: string
  until?: string
  limit?: number
  offset?: number
}
