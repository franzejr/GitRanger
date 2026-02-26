import type { Repo } from '../../types/api'

interface RepoItemProps {
  repo: Repo
  selected: boolean
  onSelect: () => void
  onDelete: () => void
}

export function RepoItem({ repo, selected, onSelect, onDelete }: RepoItemProps) {
  return (
    <button
      onClick={onSelect}
      className={`flex w-full items-center justify-between px-3 py-2.5 text-left transition-colors ${
        selected
          ? 'border-l-2 border-blue-500 bg-gray-700'
          : 'border-l-2 border-transparent hover:bg-gray-800'
      }`}
    >
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium">{repo.name}</p>
        <p className="text-xs text-gray-400">{repo.commitCount} commits</p>
      </div>
      <button
        onClick={(e) => {
          e.stopPropagation()
          onDelete()
        }}
        className="ml-2 rounded p-1 text-gray-500 opacity-0 transition-opacity hover:bg-gray-600 hover:text-red-400 group-hover:opacity-100 [button:hover>&]:opacity-100"
        title="Delete repository"
      >
        <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </button>
  )
}
