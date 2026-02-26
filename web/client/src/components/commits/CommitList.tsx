import { useAppStore } from '../../store/useAppStore'
import { CommitFilters } from './CommitFilters'
import { CommitItem } from './CommitItem'

export function CommitList() {
  const commits = useAppStore((s) => s.commits)
  const commitTotal = useAppStore((s) => s.commitTotal)
  const commitsLoading = useAppStore((s) => s.commitsLoading)
  const selectedCommitId = useAppStore((s) => s.selectedCommitId)
  const selectCommit = useAppStore((s) => s.selectCommit)
  const loadMoreCommits = useAppStore((s) => s.loadMoreCommits)
  const checkedCommitIds = useAppStore((s) => s.checkedCommitIds)
  const toggleCommitCheck = useAppStore((s) => s.toggleCommitCheck)
  const clearCheckedCommits = useAppStore((s) => s.clearCheckedCommits)
  const generateNarrative = useAppStore((s) => s.generateNarrative)
  const narrativeLoading = useAppStore((s) => s.narrativeLoading)

  const checkedCount = checkedCommitIds.length

  return (
    <div className="relative flex h-full flex-col">
      <CommitFilters />

      {commitsLoading && commits.length === 0 ? (
        <div className="flex flex-1 items-center justify-center text-gray-500">
          <p className="text-sm">Loading commits...</p>
        </div>
      ) : commits.length === 0 ? (
        <div className="flex flex-1 items-center justify-center text-gray-500">
          <p className="text-sm">No commits found</p>
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto">
          <div className="divide-y divide-gray-800/50">
            {commits.map((commit) => (
              <CommitItem
                key={commit.id}
                commit={commit}
                selected={commit.id === selectedCommitId}
                checked={checkedCommitIds.includes(commit.id)}
                onClick={() => selectCommit(commit.id)}
                onCheckToggle={() => toggleCommitCheck(commit.id)}
              />
            ))}
          </div>

          {commits.length < commitTotal && (
            <div className="p-3">
              <button
                onClick={loadMoreCommits}
                disabled={commitsLoading}
                className="w-full rounded-lg border border-gray-700 py-1.5 text-xs text-gray-400 hover:bg-gray-800 disabled:opacity-50"
              >
                {commitsLoading ? 'Loading...' : `Load more (${commitTotal - commits.length} remaining)`}
              </button>
            </div>
          )}
        </div>
      )}

      {checkedCount >= 2 && (
        <div className="sticky bottom-0 border-t border-gray-700 bg-gray-800/95 px-3 py-2 backdrop-blur-sm">
          <div className="flex items-center justify-between">
            <span className="text-xs text-gray-400">
              {checkedCount} commits selected
            </span>
            <div className="flex items-center gap-2">
              <button
                onClick={clearCheckedCommits}
                className="rounded px-2 py-1 text-xs text-gray-400 hover:text-white"
              >
                Clear
              </button>
              <button
                onClick={generateNarrative}
                disabled={narrativeLoading}
                className="rounded-lg bg-purple-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-purple-500 disabled:opacity-50"
              >
                {narrativeLoading ? 'Generating...' : 'Tell the Story'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
