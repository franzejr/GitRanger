const colorMap = {
  patch: 'bg-gray-600 text-gray-200',
  minor: 'bg-blue-600/30 text-blue-300',
  major: 'bg-yellow-600/30 text-yellow-300',
  breaking: 'bg-red-600/30 text-red-300',
}

interface ImpactBadgeProps {
  impact: 'patch' | 'minor' | 'major' | 'breaking'
}

export function ImpactBadge({ impact }: ImpactBadgeProps) {
  return (
    <span className={`inline-block rounded px-1.5 py-0.5 text-xs font-medium uppercase ${colorMap[impact]}`}>
      {impact}
    </span>
  )
}
