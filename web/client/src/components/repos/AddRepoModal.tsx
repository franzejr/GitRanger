import { useState, useEffect, useRef } from 'react'
import { useAppStore } from '../../store/useAppStore'

interface AddRepoModalProps {
  onClose: () => void
}

export function AddRepoModal({ onClose }: AddRepoModalProps) {
  const [url, setUrl] = useState('')
  const inputRef = useRef<HTMLInputElement>(null)
  const importRepo = useAppStore((s) => s.importRepo)
  const importLoading = useAppStore((s) => s.importLoading)
  const importError = useAppStore((s) => s.importError)
  const clearImportError = useAppStore((s) => s.clearImportError)
  const prevLoading = useRef(importLoading)

  useEffect(() => {
    inputRef.current?.focus()
    clearImportError()
  }, [clearImportError])

  // Close on successful import
  useEffect(() => {
    if (prevLoading.current && !importLoading && !importError) {
      onClose()
    }
    prevLoading.current = importLoading
  }, [importLoading, importError, onClose])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!url.trim() || importLoading) return
    importRepo(url.trim())
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" onClick={onClose}>
      <div
        className="w-full max-w-md rounded-xl border border-gray-700 bg-gray-800 p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => e.key === 'Escape' && onClose()}
      >
        <h2 className="text-lg font-semibold">Import Repository</h2>
        <p className="mt-1 text-sm text-gray-400">
          Paste a GitHub URL or any git repository URL
        </p>

        <form onSubmit={handleSubmit} className="mt-4">
          <input
            ref={inputRef}
            type="text"
            value={url}
            onChange={(e) => setUrl(e.target.value)}
            placeholder="https://github.com/owner/repo"
            className="w-full rounded-lg border border-gray-600 bg-gray-900 px-3 py-2 text-sm text-white placeholder-gray-500 focus:border-blue-500 focus:outline-none"
            disabled={importLoading}
          />

          {importError && (
            <p className="mt-2 text-sm text-red-400">{importError}</p>
          )}

          <div className="mt-4 flex justify-end gap-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg px-3 py-1.5 text-sm text-gray-400 hover:text-white"
              disabled={importLoading}
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!url.trim() || importLoading}
              className="rounded-lg bg-blue-600 px-4 py-1.5 text-sm font-medium hover:bg-blue-500 disabled:opacity-50"
            >
              {importLoading ? 'Importing...' : 'Import'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
