/**
 * RegressionAlert — prominent red banner when any metric regresses.
 *
 * This is the key differentiator feature: immediately surfacing when a
 * pipeline change caused quality to drop. Displayed at the top of the
 * dashboard, impossible to miss.
 *
 * Shows: which metrics regressed, before/after values, which run caused it.
 * Links to: the regression run's detail page.
 */
import { Link } from 'react-router-dom'
import { useRegressions } from '../../hooks/useEvalRuns.js'
import { METRIC_LABELS, fmtScore } from '../../utils/scoreColor.js'

export default function RegressionAlert() {
  const { data: regressions = [], isLoading } = useRegressions()

  // Only show the most recent regression — don't flood the dashboard
  const latest = regressions[0]
  if (isLoading || !latest) return null

  // Pull out metrics that actually regressed
  const flaggedMetrics = Object.entries(latest.regression_details || {})
    .filter(([, v]) => v?.is_regression)

  if (flaggedMetrics.length === 0) return null

  return (
    <div className="rounded-xl border border-red-500/40 bg-red-500/10 p-4 mb-6">
      {/* Header */}
      <div className="flex items-start gap-3">
        <div className="mt-0.5 w-5 h-5 rounded-full bg-red-500/20 border border-red-500/40 flex items-center justify-center shrink-0">
          <span className="text-red-400 text-xs">!</span>
        </div>
        <div className="flex-1">
          <div className="flex items-center gap-2 flex-wrap">
            <p className="text-sm font-semibold text-red-300">
              Regression detected in {latest.version_tag}
            </p>
            <Link
              to={`/runs/${latest.id}`}
              className="text-xs text-red-400/70 hover:text-red-300 underline underline-offset-2"
            >
              View run →
            </Link>
          </div>

          {/* Per-metric regression detail */}
          <div className="mt-2 flex flex-wrap gap-3">
            {flaggedMetrics.map(([metric, details]) => (
              <div
                key={metric}
                className="text-xs bg-red-900/30 border border-red-500/20 rounded-lg px-3 py-1.5"
              >
                <span className="text-red-300 font-medium">{METRIC_LABELS[metric]}</span>
                <span className="text-slate-400 mx-1">
                  {fmtScore(details.previous)} → {fmtScore(details.current)}
                </span>
                <span className="text-red-400 font-semibold">
                  ({(details.delta * 100).toFixed(1)}%)
                </span>
              </div>
            ))}
          </div>

          {/* Comparison context */}
          {latest.compared_to_run_id && (
            <p className="text-xs text-slate-500 mt-2">
              Compared against previous completed run
              {latest.langsmith_run_url && (
                <>
                  {' · '}
                  <a
                    href={latest.langsmith_run_url}
                    target="_blank"
                    rel="noreferrer"
                    className="text-slate-400 hover:text-slate-300 underline underline-offset-2"
                  >
                    LangSmith traces ↗
                  </a>
                </>
              )}
            </p>
          )}
        </div>
      </div>
    </div>
  )
}
