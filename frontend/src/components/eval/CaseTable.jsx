/**
 * CaseTable — per-question score table for a single eval run.
 *
 * Color coding: green ≥ 0.80, yellow ≥ 0.60, red < 0.60
 * Truncates question and answer for display; tooltip shows full text.
 * Supports pagination via the useEvalCases hook.
 */
import { useState } from 'react'
import clsx from 'clsx'
import { useEvalCases } from '../../hooks/useEvalDetails.js'
import { scoreColorClass, fmtScore } from '../../utils/scoreColor.js'

function ScoreCell({ score }) {
  const colorClass = scoreColorClass(score, 'text')
  const bgClass = scoreColorClass(score, 'bg')
  return (
    <td className="px-3 py-2.5 text-center">
      <span className={clsx(
        'inline-block text-xs font-mono tabular-nums px-2 py-0.5 rounded-md',
        colorClass,
        score >= 0.8 ? 'bg-emerald-500/10' :
        score >= 0.6 ? 'bg-amber-500/10' :
        score != null ? 'bg-red-500/10' : 'bg-slate-800',
      )}>
        {fmtScore(score)}
      </span>
    </td>
  )
}

function SkeletonTable() {
  return (
    <div className="space-y-2">
      {[...Array(5)].map((_, i) => (
        <div key={i} className="skeleton h-10 w-full rounded-lg" />
      ))}
    </div>
  )
}

export default function CaseTable({ runId }) {
  const [page, setPage] = useState(1)
  const PAGE_SIZE = 20

  const { data, isLoading, isFetching } = useEvalCases(runId, { page, pageSize: PAGE_SIZE })

  const cases = data?.cases ?? []
  const total = data?.total ?? 0
  const totalPages = Math.ceil(total / PAGE_SIZE)

  const exportCSV = () => {
    if (!cases.length) return
    const headers = ['question', 'answer', 'faithfulness', 'answer_relevancy', 'context_precision', 'context_recall']
    const rows = cases.map((c) => [
      `"${c.question.replace(/"/g, '""')}"`,
      `"${c.answer.replace(/"/g, '""')}"`,
      c.faithfulness_score ?? '',
      c.answer_relevancy_score ?? '',
      c.context_precision_score ?? '',
      c.context_recall_score ?? '',
    ])
    const csv = [headers, ...rows].map((r) => r.join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `eval-cases-${runId.slice(0, 8)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="glass rounded-xl overflow-hidden">
      <div className="px-5 py-4 border-b border-slate-800 flex items-center justify-between">
        <div>
          <h3 className="text-sm font-semibold text-slate-200">Per-Case Scores</h3>
          {total > 0 && (
            <p className="text-xs text-slate-500 mt-0.5">{total} test cases</p>
          )}
        </div>
        <button
          onClick={exportCSV}
          disabled={!cases.length}
          className="text-xs text-slate-400 hover:text-slate-200 border border-slate-700 hover:border-slate-600 px-3 py-1.5 rounded-lg transition-colors disabled:opacity-40"
        >
          Export CSV
        </button>
      </div>

      {isLoading ? (
        <div className="p-5"><SkeletonTable /></div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-slate-800 text-slate-500 uppercase tracking-wider">
                <th className="px-3 py-2.5 text-left font-medium w-[35%]">Question</th>
                <th className="px-3 py-2.5 text-left font-medium w-[25%]">Answer</th>
                <th className="px-3 py-2.5 text-center font-medium">Faith.</th>
                <th className="px-3 py-2.5 text-center font-medium">Relev.</th>
                <th className="px-3 py-2.5 text-center font-medium">Prec.</th>
                <th className="px-3 py-2.5 text-center font-medium">Recall</th>
              </tr>
            </thead>
            <tbody>
              {cases.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-3 py-8 text-center text-slate-600">
                    No cases found.
                  </td>
                </tr>
              )}
              {cases.map((c, i) => (
                <tr
                  key={c.id}
                  className={clsx(
                    'border-b border-slate-800/60 hover:bg-slate-800/20 transition-colors',
                    i % 2 === 0 ? '' : 'bg-slate-900/30',
                  )}
                >
                  <td className="px-3 py-2.5 text-slate-300 max-w-0">
                    <span title={c.question} className="block truncate">{c.question}</span>
                  </td>
                  <td className="px-3 py-2.5 text-slate-500 max-w-0">
                    <span title={c.answer} className="block truncate">{c.answer}</span>
                  </td>
                  <ScoreCell score={c.faithfulness_score} />
                  <ScoreCell score={c.answer_relevancy_score} />
                  <ScoreCell score={c.context_precision_score} />
                  <ScoreCell score={c.context_recall_score} />
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="px-5 py-3 border-t border-slate-800 flex items-center justify-between">
          <p className="text-xs text-slate-500">
            Page {page} of {totalPages} ({total} cases)
          </p>
          <div className="flex gap-2">
            <button
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page === 1 || isFetching}
              className="text-xs px-3 py-1.5 rounded-lg border border-slate-700 text-slate-400 hover:text-slate-200 disabled:opacity-40 transition-colors"
            >
              ← Prev
            </button>
            <button
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              disabled={page === totalPages || isFetching}
              className="text-xs px-3 py-1.5 rounded-lg border border-slate-700 text-slate-400 hover:text-slate-200 disabled:opacity-40 transition-colors"
            >
              Next →
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
