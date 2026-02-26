import type { Commit } from '../../types/api'
import { ImpactBadge } from '../ai/ImpactBadge'

interface CommitItemProps {
  commit: Commit
  selected: boolean
  checked: boolean
  onClick: () => void
  onCheckToggle: () => void
}

function timeAgo(dateStr: string): string {
  const seconds = Math.floor((Date.now() - new Date(dateStr).getTime()) / 1000)
  if (seconds < 60) return 'just now'
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days < 30) return `${days}d ago`
  const months = Math.floor(days / 30)
  return `${months}mo ago`
}

export function CommitItem({ commit, selected, checked, onClick, onCheckToggle }: CommitItemProps) {
  const firstLine = commit.message.split('\n')[0]

  return (
    <button
      onClick={onClick}
      className={`w-full px-3 py-2 text-left transition-colors ${
        selected ? 'bg-gray-700' : 'hover:bg-gray-800/50'
      }`}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-start gap-2 min-w-0 flex-1">
          <input
            type="checkbox"
            checked={checked}
            onChange={onCheckToggle}
            onClick={(e) => e.stopPropagation()}
            className="mt-0.5 h-3.5 w-3.5 shrink-0 cursor-pointer accent-purple-500"
          />
          <p className="min-w-0 flex-1 truncate text-sm">{firstLine}</p>
        </div>
        {commit.summary && <ImpactBadge impact={commit.summary.impact} />}
      </div>
      <div className="mt-0.5 flex items-center gap-2 pl-5.5 text-xs text-gray-400">
        <span className="font-mono">{commit.sha.slice(0, 7)}</span>
        <span>{commit.authorName}</span>
        <span>{timeAgo(commit.committedAt)}</span>
        <span className="ml-auto">
          <span className="text-green-400">+{commit.insertions}</span>
          {' '}
          <span className="text-red-400">-{commit.deletions}</span>
        </span>
      </div>
    </button>
  )
}
