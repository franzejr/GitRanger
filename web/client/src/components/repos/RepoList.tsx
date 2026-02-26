import { useAppStore } from '../../store/useAppStore'
import { RepoItem } from './RepoItem'

export function RepoList() {
  const repos = useAppStore((s) => s.repos)
  const selectedRepoId = useAppStore((s) => s.selectedRepoId)
  const reposLoading = useAppStore((s) => s.reposLoading)
  const selectRepo = useAppStore((s) => s.selectRepo)
  const deleteRepo = useAppStore((s) => s.deleteRepo)

  if (reposLoading && repos.length === 0) {
    return (
      <div className="flex items-center justify-center p-8 text-gray-500">
        <p className="text-sm">Loading repositories...</p>
      </div>
    )
  }

  if (repos.length === 0) {
    return (
      <div className="flex items-center justify-center p-8 text-gray-500">
        <div className="text-center">
          <p className="text-sm font-medium">No repositories yet</p>
          <p className="mt-1 text-xs">Click "Add Repository" to import one</p>
        </div>
      </div>
    )
  }

  return (
    <div className="py-1">
      {repos.map((repo) => (
        <RepoItem
          key={repo.id}
          repo={repo}
          selected={repo.id === selectedRepoId}
          onSelect={() => selectRepo(repo.id)}
          onDelete={() => deleteRepo(repo.id)}
        />
      ))}
    </div>
  )
}
