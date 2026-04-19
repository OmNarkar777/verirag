/**
 * MetricCard — displays a single RAGAS metric score with trend delta.
 *
 * Shows: metric name, current score as %, delta from previous run with
 * direction arrow (↑ green / ↓ red), and status badge (Pass/Warn/Fail).
 *
 * Skeleton prop: render loading state without layout shift.
 */
import clsx from 'clsx'
import { scoreColorClass, scoreLabel, fmtScore, fmtDelta, deltaColorClass, METRIC_LABELS } from '../../utils/scoreColor.js'

function SkeletonCard() {
  return (
    <div className="glass rounded-xl p-5">
      <div className="skeleton h-3 w-28 mb-4" />
      <div className="skeleton h-8 w-20 mb-3" />
      <div className="skeleton h-3 w-16" />
    </div>
  )
}

export default function MetricCard({ metric, score, delta, loading = false }) {
  if (loading) return <SkeletonCard />

  const label = METRIC_LABELS[metric] ?? metric
  const scoreClass = scoreColorClass(score, 'text')
  const status = scoreLabel(score)
  const deltaStr = fmtDelta(delta)
  const deltaClass = deltaColorClass(delta)

  const statusBg = {
    Pass: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
    Warning: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
    Fail: 'bg-red-500/10 text-red-400 border-red-500/20',
    'N/A': 'bg-slate-800 text-slate-500 border-slate-700',
  }[status]

  return (
    <div className="glass rounded-xl p-5 hover:border-slate-700 transition-colors">
      {/* Header row */}
      <div className="flex items-center justify-between mb-3">
        <span className="text-xs font-medium text-slate-400 uppercase tracking-wider">
          {label}
        </span>
        <span className={clsx('text-xs px-2 py-0.5 rounded-full border font-medium', statusBg)}>
          {status}
        </span>
      </div>

      {/* Score */}
      <div className={clsx('text-3xl font-bold tabular-nums', scoreClass)}>
        {fmtScore(score)}
      </div>

      {/* Delta from previous run */}
      {deltaStr && (
        <div className={clsx('flex items-center gap-1 mt-2 text-xs font-medium', deltaClass)}>
          <span>{delta >= 0 ? '↑' : '↓'}</span>
          <span>{deltaStr} vs prev</span>
        </div>
      )}
      {!deltaStr && score != null && (
        <div className="mt-2 text-xs text-slate-600">No previous run</div>
      )}
    </div>
  )
}
