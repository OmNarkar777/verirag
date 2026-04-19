import { useEvalStatus } from '../../hooks/useEvalRuns.js'

export default function Header({ title, subtitle }) {
  const { data: status } = useEvalStatus()

  return (
    <header className="h-14 px-6 border-b border-slate-800 bg-slate-900/50 flex items-center justify-between shrink-0">
      <div>
        <h1 className="text-base font-semibold text-slate-100">{title}</h1>
        {subtitle && <p className="text-xs text-slate-500">{subtitle}</p>}
      </div>

      <div className="flex items-center gap-4">
        {/* Live eval indicator */}
        {status?.active_evals > 0 && (
          <div className="flex items-center gap-2 text-xs text-amber-400">
            <span className="w-2 h-2 rounded-full bg-amber-400 animate-pulse-slow" />
            {status.active_evals} eval{status.active_evals > 1 ? 's' : ''} running
          </div>
        )}
        <a
          href="/docs"
          target="_blank"
          rel="noreferrer"
          className="text-xs text-slate-500 hover:text-slate-300 transition-colors"
        >
          API Docs ↗
        </a>
      </div>
    </header>
  )
}
