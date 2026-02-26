import { create } from 'zustand'
import { api } from '../api/client'
import type { Repo, Commit, AIStatus, CommitFilters, NarrativeResponse } from '../types/api'

interface CommitDetail {
  commit: Commit
  diff: string
}

interface AppState {
  repos: Repo[]
  selectedRepoId: string | null
  commits: Commit[]
  commitTotal: number
  selectedCommitId: string | null
  commitDetail: CommitDetail | null
  aiStatus: AIStatus | null
  commitFilters: CommitFilters

  checkedCommitIds: string[]
  narrative: string | null
  narrativeTimespan: { from: string; to: string } | null
  narrativeLoading: boolean
  narrativeError: string | null
  showNarrative: boolean

  reposLoading: boolean
  commitsLoading: boolean
  commitDetailLoading: boolean
  importLoading: boolean
  analyzeLoading: boolean
  importError: string | null
  analyzeError: string | null

  fetchRepos: () => Promise<void>
  importRepo: (url: string) => Promise<void>
  deleteRepo: (id: string) => Promise<void>
  selectRepo: (id: string) => void
  fetchCommits: (repoId: string, filters?: CommitFilters) => Promise<void>
  loadMoreCommits: () => Promise<void>
  selectCommit: (id: string) => Promise<void>
  analyzeCommit: (id: string) => Promise<void>
  fetchAIStatus: () => Promise<void>
  setCommitFilters: (filters: Partial<CommitFilters>) => void
  clearImportError: () => void
  toggleCommitCheck: (id: string) => void
  clearCheckedCommits: () => void
  generateNarrative: () => Promise<void>
  dismissNarrative: () => void
}

export const useAppStore = create<AppState>((set, get) => ({
  repos: [],
  selectedRepoId: null,
  commits: [],
  commitTotal: 0,
  selectedCommitId: null,
  commitDetail: null,
  aiStatus: null,
  commitFilters: { limit: 50 },

  checkedCommitIds: [],
  narrative: null,
  narrativeTimespan: null,
  narrativeLoading: false,
  narrativeError: null,
  showNarrative: false,

  reposLoading: false,
  commitsLoading: false,
  commitDetailLoading: false,
  importLoading: false,
  analyzeLoading: false,
  importError: null,
  analyzeError: null,

  fetchRepos: async () => {
    set({ reposLoading: true })
    try {
      const { repos } = await api.repos.list()
      set({ repos, reposLoading: false })
    } catch {
      set({ reposLoading: false })
    }
  },

  importRepo: async (url: string) => {
    set({ importLoading: true, importError: null })
    try {
      await api.repos.create(url)
      await get().fetchRepos()
      set({ importLoading: false })
    } catch (e) {
      set({
        importLoading: false,
        importError: e instanceof Error ? e.message : 'Import failed',
      })
    }
  },

  deleteRepo: async (id: string) => {
    const prev = get().repos
    set({ repos: prev.filter((r) => r.id !== id) })
    try {
      await api.repos.delete(id)
      if (get().selectedRepoId === id) {
        set({ selectedRepoId: null, commits: [], commitTotal: 0, commitDetail: null })
      }
    } catch {
      set({ repos: prev })
    }
  },

  selectRepo: (id: string) => {
    set({
      selectedRepoId: id,
      selectedCommitId: null,
      commitDetail: null,
      commits: [],
      commitTotal: 0,
      commitFilters: { limit: 50 },
      checkedCommitIds: [],
      narrative: null,
      showNarrative: false,
    })
    get().fetchCommits(id)
  },

  fetchCommits: async (repoId: string, filters?: CommitFilters) => {
    set({ commitsLoading: true })
    try {
      const f = filters ?? get().commitFilters
      const { commits, total } = await api.repos.commits(repoId, f)
      set({ commits, commitTotal: total, commitsLoading: false })
    } catch {
      set({ commitsLoading: false })
    }
  },

  loadMoreCommits: async () => {
    const { selectedRepoId, commits, commitFilters } = get()
    if (!selectedRepoId) return
    const offset = commits.length
    set({ commitsLoading: true })
    try {
      const { commits: more, total } = await api.repos.commits(selectedRepoId, {
        ...commitFilters,
        offset,
      })
      set({ commits: [...commits, ...more], commitTotal: total, commitsLoading: false })
    } catch {
      set({ commitsLoading: false })
    }
  },

  selectCommit: async (id: string) => {
    set({ selectedCommitId: id, commitDetailLoading: true, commitDetail: null })
    try {
      const data = await api.commits.get(id)
      set({ commitDetail: data, commitDetailLoading: false })
    } catch {
      set({ commitDetailLoading: false })
    }
  },

  analyzeCommit: async (id: string) => {
    set({ analyzeLoading: true, analyzeError: null })
    try {
      const { commit: updated } = await api.commits.analyze(id)
      const { commits, commitDetail } = get()
      set({
        analyzeLoading: false,
        commits: commits.map((c) => (c.id === id ? updated : c)),
        commitDetail: commitDetail ? { ...commitDetail, commit: updated } : null,
      })
    } catch (e) {
      set({
        analyzeLoading: false,
        analyzeError: e instanceof Error ? e.message : 'Analysis failed',
      })
    }
  },

  fetchAIStatus: async () => {
    try {
      const status = await api.ai.status()
      set({ aiStatus: status })
    } catch {
      // silent fail
    }
  },

  setCommitFilters: (filters: Partial<CommitFilters>) => {
    const updated = { ...get().commitFilters, ...filters, offset: 0 }
    set({ commitFilters: updated })
    const { selectedRepoId } = get()
    if (selectedRepoId) {
      get().fetchCommits(selectedRepoId, updated)
    }
  },

  clearImportError: () => set({ importError: null }),

  toggleCommitCheck: (id: string) => {
    const current = get().checkedCommitIds
    const next = current.includes(id)
      ? current.filter((cid) => cid !== id)
      : [...current, id]
    set({ checkedCommitIds: next })
  },

  clearCheckedCommits: () => {
    set({ checkedCommitIds: [], showNarrative: false, narrative: null, narrativeError: null })
  },

  generateNarrative: async () => {
    const { checkedCommitIds } = get()
    if (checkedCommitIds.length < 2) return

    set({ narrativeLoading: true, narrativeError: null, showNarrative: true })
    try {
      const result = await api.commits.narrative(checkedCommitIds)
      set({
        narrative: result.narrative,
        narrativeTimespan: result.timespan,
        narrativeLoading: false,
      })
    } catch (e) {
      set({
        narrativeLoading: false,
        narrativeError: e instanceof Error ? e.message : 'Narrative generation failed',
      })
    }
  },

  dismissNarrative: () => {
    set({ showNarrative: false, narrative: null, narrativeError: null })
  },
}))
