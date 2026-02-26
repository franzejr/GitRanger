import { useAppStore } from '../../store/useAppStore'
import { ImpactBadge } from '../ai/ImpactBadge'

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export function CommitDetail() {
  const commitDetail = useAppStore((s) => s.commitDetail)
  const commitDetailLoading = useAppStore((s) => s.commitDetailLoading)
  const analyzeLoading = useAppStore((s) => s.analyzeLoading)
  const analyzeError = useAppStore((s) => s.analyzeError)
  const analyzeCommit = useAppStore((s) => s.analyzeCommit)

  if (commitDetailLoading) {
    return (
      <div className="flex h-full items-center justify-center text-gray-500">
        <p className="text-sm">Loading commit...</p>
      </div>
    )
  }

  if (!commitDetail) return null

  const { commit, diff } = commitDetail
  const { summary } = commit

  return (
    <div className="p-4">
      {/* Header */}
      <div className="mb-4">
        <p className="text-sm font-medium whitespace-pre-wrap">{commit.message}</p>
        <div className="mt-2 flex items-center gap-3 text-xs text-gray-400">
          <span className="font-mono">{commit.sha.slice(0, 7)}</span>
          <span>{commit.authorName}</span>
          <span>{formatDate(commit.committedAt)}</span>
        </div>
        <div className="mt-1 flex gap-3 text-xs">
          <span className="text-gray-400">{commit.filesChanged} files</span>
          <span className="text-green-400">+{commit.insertions}</span>
          <span className="text-red-400">-{commit.deletions}</span>
        </div>
      </div>

      {/* AI Summary */}
      <div className="mb-4 rounded-lg border border-gray-700 bg-gray-800 p-3">
        <div className="mb-2 flex items-center justify-between">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">
            AI Summary
          </h3>
          {summary && <ImpactBadge impact={summary.impact} />}
        </div>

        {analyzeLoading ? (
          <div className="flex items-center gap-3 py-2">
            <div className="h-4 w-4 animate-spin rounded-full border-2 border-blue-500 border-t-transparent" />
            <div>
              <p className="text-sm text-blue-400">Analyzing with Claude Code...</p>
              <p className="mt-0.5 text-xs text-gray-500">This usually takes 5-10 seconds</p>
            </div>
          </div>
        ) : summary ? (
          <div>
            <p className="text-sm font-medium">{summary.oneLiner}</p>
            <p className="mt-1 text-sm text-gray-300">{summary.explanation}</p>
            <div className="mt-2 flex flex-wrap gap-1">
              {summary.categories.map((cat) => (
                <span
                  key={cat}
                  className="rounded bg-gray-700 px-1.5 py-0.5 text-xs text-gray-300"
                >
                  {cat}
                </span>
              ))}
            </div>
            {summary.riskNotes && (
              <p className="mt-2 text-xs text-yellow-400">Risk: {summary.riskNotes}</p>
            )}
          </div>
        ) : (
          <div>
            <p className="text-sm text-gray-500">Not yet analyzed</p>
            <button
              onClick={() => analyzeCommit(commit.id)}
              className="mt-2 rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-medium hover:bg-blue-500"
            >
              Analyze with AI
            </button>
            {analyzeError && (
              <p className="mt-1 text-xs text-red-400">{analyzeError}</p>
            )}
          </div>
        )}
      </div>

      {/* Diff */}
      <div className="rounded-lg border border-gray-700 bg-gray-950 p-3">
        <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-400">
          Diff
        </h3>
        <pre className="overflow-x-auto text-xs leading-5">
          {diff.split('\n').map((line, i) => {
            let className = 'text-gray-300'
            if (line.startsWith('+') && !line.startsWith('+++')) className = 'text-green-400'
            else if (line.startsWith('-') && !line.startsWith('---')) className = 'text-red-400'
            else if (line.startsWith('@@')) className = 'text-blue-400'
            return (
              <div key={i} className={className}>
                {line}
              </div>
            )
          })}
        </pre>
      </div>
    </div>
  )
}
