import { useState, useEffect } from 'react'
import { useAppStore } from '../../store/useAppStore'

export function CommitFilters() {
  const commitFilters = useAppStore((s) => s.commitFilters)
  const setCommitFilters = useAppStore((s) => s.setCommitFilters)
  const [authorInput, setAuthorInput] = useState(commitFilters.author ?? '')

  // Debounce author filter
  useEffect(() => {
    const timer = setTimeout(() => {
      if (authorInput !== (commitFilters.author ?? '')) {
        setCommitFilters({ author: authorInput || undefined })
      }
    }, 300)
    return () => clearTimeout(timer)
  }, [authorInput, commitFilters.author, setCommitFilters])

  return (
    <div className="flex items-center gap-2 border-b border-gray-800 px-3 py-2">
      <input
        type="text"
        value={authorInput}
        onChange={(e) => setAuthorInput(e.target.value)}
        placeholder="Filter by author..."
        className="w-40 rounded border border-gray-700 bg-gray-900 px-2 py-1 text-xs text-white placeholder-gray-500 focus:border-blue-500 focus:outline-none"
      />
      <input
        type="date"
        value={commitFilters.since ?? ''}
        onChange={(e) => setCommitFilters({ since: e.target.value || undefined })}
        className="rounded border border-gray-700 bg-gray-900 px-2 py-1 text-xs text-white focus:border-blue-500 focus:outline-none"
      />
      <input
        type="date"
        value={commitFilters.until ?? ''}
        onChange={(e) => setCommitFilters({ until: e.target.value || undefined })}
        className="rounded border border-gray-700 bg-gray-900 px-2 py-1 text-xs text-white focus:border-blue-500 focus:outline-none"
      />
    </div>
  )
}
