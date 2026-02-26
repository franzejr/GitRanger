import { useState, useEffect } from 'react'
import { useAppStore } from './store/useAppStore'
import { AppShell } from './components/layout/AppShell'
import { AddRepoModal } from './components/repos/AddRepoModal'

function App() {
  const [showAddModal, setShowAddModal] = useState(false)
  const fetchRepos = useAppStore((s) => s.fetchRepos)
  const fetchAIStatus = useAppStore((s) => s.fetchAIStatus)

  useEffect(() => {
    fetchRepos()
    fetchAIStatus()
  }, [fetchRepos, fetchAIStatus])

  return (
    <>
      <AppShell onAddRepo={() => setShowAddModal(true)} />
      {showAddModal && <AddRepoModal onClose={() => setShowAddModal(false)} />}
    </>
  )
}

export default App
