import { useAppStore } from '../../store/useAppStore'

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

export function NarrativePanel() {
  const narrative = useAppStore((s) => s.narrative)
  const narrativeLoading = useAppStore((s) => s.narrativeLoading)
  const narrativeError = useAppStore((s) => s.narrativeError)
  const narrativeTimespan = useAppStore((s) => s.narrativeTimespan)
  const checkedCommitIds = useAppStore((s) => s.checkedCommitIds)
  const dismissNarrative = useAppStore((s) => s.dismissNarrative)
  const generateNarrative = useAppStore((s) => s.generateNarrative)

  return (
    <div className="flex h-full flex-col">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-gray-800 px-4 py-3">
        <div>
          <h2 className="text-sm font-semibold">Commit Narrative</h2>
          {narrativeTimespan && (
            <p className="text-xs text-gray-400">
              {formatDate(narrativeTimespan.from)} &mdash; {formatDate(narrativeTimespan.to)}
              {' \u00b7 '}{checkedCommitIds.length} commits
            </p>
          )}
        </div>
        <button
          onClick={dismissNarrative}
          className="rounded px-2 py-1 text-xs text-gray-400 hover:text-white"
        >
          Close
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4">
        {narrativeLoading ? (
          <div className="flex flex-col items-center justify-center py-12">
            <div className="h-6 w-6 animate-spin rounded-full border-2 border-purple-500 border-t-transparent" />
            <p className="mt-3 text-sm text-purple-400">Crafting the story...</p>
            <p className="mt-1 text-xs text-gray-500">
              Analyzing {checkedCommitIds.length} commits. This may take 10-20 seconds.
            </p>
          </div>
        ) : narrativeError ? (
          <div className="rounded-lg border border-red-800 bg-red-900/20 p-4">
            <p className="text-sm text-red-400">{narrativeError}</p>
            <button
              onClick={generateNarrative}
              className="mt-3 rounded-lg bg-purple-600 px-3 py-1.5 text-xs font-medium hover:bg-purple-500"
            >
              Retry
            </button>
          </div>
        ) : narrative ? (
          <div>
            {narrative.split('\n\n').map((paragraph, i) => (
              <p key={i} className="mb-4 text-sm leading-relaxed text-gray-200">
                {paragraph}
              </p>
            ))}
          </div>
        ) : null}
      </div>
    </div>
  )
}
