import { useAppStore } from '../../store/useAppStore'

const providerLabels: Record<string, string> = {
  claude_code: 'Claude Code',
  anthropic_api: 'Anthropic',
  openai: 'OpenAI',
  ollama: 'Ollama',
}

export function AIStatusBar() {
  const aiStatus = useAppStore((s) => s.aiStatus)

  if (!aiStatus) return null

  const active = aiStatus.providers.find((p) => p.provider === aiStatus.activeProvider)
  const label = providerLabels[aiStatus.activeProvider] ?? aiStatus.activeProvider

  return (
    <div className="flex items-center gap-1.5 text-xs text-gray-400">
      <span
        className={`h-2 w-2 rounded-full ${active?.available ? 'bg-green-500' : 'bg-gray-500'}`}
      />
      <span>{label}</span>
    </div>
  )
}
