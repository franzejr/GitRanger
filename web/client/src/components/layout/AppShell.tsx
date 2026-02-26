import { RepoList } from '../repos/RepoList'
import { CommitList } from '../commits/CommitList'
import { CommitDetail } from '../commits/CommitDetail'
import { NarrativePanel } from '../commits/NarrativePanel'
import { AIStatusBar } from '../ai/AIStatusBar'
import { useAppStore } from '../../store/useAppStore'

interface AppShellProps {
  onAddRepo: () => void
}

export function AppShell({ onAddRepo }: AppShellProps) {
  const selectedRepoId = useAppStore((s) => s.selectedRepoId)
  const selectedCommitId = useAppStore((s) => s.selectedCommitId)
  const showNarrative = useAppStore((s) => s.showNarrative)

  return (
    <div className="flex h-screen flex-col bg-gray-900 text-white">
      {/* Header */}
      <header className="flex items-center justify-between border-b border-gray-800 px-4 py-3">
        <h1 className="text-lg font-bold">GitNarrate</h1>
        <div className="flex items-center gap-3">
          <AIStatusBar />
          <button
            onClick={onAddRepo}
            className="rounded-lg bg-blue-600 px-3 py-1.5 text-sm font-medium hover:bg-blue-500"
          >
            + Add Repository
          </button>
        </div>
      </header>

      {/* Main content */}
      <div className="flex flex-1 overflow-hidden">
        {/* Sidebar */}
        <aside className="w-70 flex-shrink-0 overflow-y-auto border-r border-gray-800">
          <RepoList />
        </aside>

        {/* Content area */}
        <main className="flex flex-1 overflow-hidden">
          {selectedRepoId ? (
            <>
              <div className={`overflow-y-auto ${(selectedCommitId || showNarrative) ? 'w-1/2' : 'flex-1'} border-r border-gray-800`}>
                <CommitList />
              </div>
              {showNarrative ? (
                <div className="flex-1 overflow-y-auto">
                  <NarrativePanel />
                </div>
              ) : selectedCommitId ? (
                <div className="flex-1 overflow-y-auto">
                  <CommitDetail />
                </div>
              ) : null}
            </>
          ) : (
            <div className="flex flex-1 items-center justify-center text-gray-500">
              <div className="text-center">
                <p className="text-xl font-medium">Select a repository</p>
                <p className="mt-1 text-sm">or import one to get started</p>
              </div>
            </div>
          )}
        </main>
      </div>
    </div>
  )
}
