import type { Repo, Commit, AIStatus, AIProvider, CommitFilters, NarrativeResponse } from '../types/api'

interface APIError {
  error: string
}

async function fetchJSON<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, init)
  const body = await res.json()
  if (!res.ok) throw new Error((body as APIError).error ?? 'Request failed')
  return body as T
}

function buildParams(filters?: CommitFilters): string {
  if (!filters) return ''
  const params = new URLSearchParams()
  if (filters.author) params.set('author', filters.author)
  if (filters.since) params.set('since', filters.since)
  if (filters.until) params.set('until', filters.until)
  if (filters.limit) params.set('limit', String(filters.limit))
  if (filters.offset) params.set('offset', String(filters.offset))
  const str = params.toString()
  return str ? `?${str}` : ''
}

export const api = {
  repos: {
    list: () => fetchJSON<{ repos: Repo[] }>('/api/repos'),

    create: (url: string) =>
      fetchJSON<{ repo: Repo }>('/api/repos', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url }),
      }),

    get: (id: string) => fetchJSON<{ repo: Repo }>(`/api/repos/${id}`),

    delete: (id: string) =>
      fetchJSON<{ success: boolean }>(`/api/repos/${id}`, { method: 'DELETE' }),

    sync: (id: string) =>
      fetchJSON<{ newCommits: number }>(`/api/repos/${id}/sync`, { method: 'POST' }),

    commits: (id: string, filters?: CommitFilters) =>
      fetchJSON<{ commits: Commit[]; total: number; limit: number; offset: number }>(
        `/api/repos/${id}/commits${buildParams(filters)}`
      ),
  },

  commits: {
    get: (id: string) => fetchJSON<{ commit: Commit; diff: string }>(`/api/commits/${id}`),

    analyze: (id: string) =>
      fetchJSON<{ commit: Commit }>(`/api/commits/${id}/analyze`, { method: 'POST' }),

    narrative: (commitIds: string[]) =>
      fetchJSON<NarrativeResponse>('/api/commits/narrative', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ commitIds }),
      }),
  },

  ai: {
    status: () => fetchJSON<AIStatus>('/api/ai/status'),

    setProvider: (provider: AIProvider) =>
      fetchJSON<{ success: boolean; provider: AIProvider }>('/api/ai/provider', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ provider }),
      }),
  },
}
