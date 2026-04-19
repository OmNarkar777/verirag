/**
 * scoreColor.js — Consistent color + label system for RAGAS metric scores.
 *
 * Thresholds match backend metrics.py:
 *   >= 0.80  → green  (pass)
 *   >= 0.60  → yellow (warning)
 *   <  0.60  → red    (fail)
 *
 * Centralised here so MetricCard, CaseTable, ScoreDistribution all use
 * identical thresholds — one change propagates everywhere.
 */

export const THRESHOLDS = { PASS: 0.80, WARN: 0.60 }

/**
 * Returns Tailwind color classes for a score value.
 * @param {number|null} score
 * @param {'text'|'bg'|'border'} variant
 */
export function scoreColorClass(score, variant = 'text') {
  if (score == null) return `${variant}-slate-500`
  if (score >= THRESHOLDS.PASS) return `${variant}-emerald-400`
  if (score >= THRESHOLDS.WARN) return `${variant}-amber-400`
  return `${variant}-red-400`
}

/** Returns the status label for a score */
export function scoreLabel(score) {
  if (score == null) return 'N/A'
  if (score >= THRESHOLDS.PASS) return 'Pass'
  if (score >= THRESHOLDS.WARN) return 'Warning'
  return 'Fail'
}

/** Returns a hex color string for use inside Recharts (not Tailwind) */
export function scoreHex(score) {
  if (score == null) return '#64748b'
  if (score >= THRESHOLDS.PASS) return '#34d399'
  if (score >= THRESHOLDS.WARN) return '#fbbf24'
  return '#f87171'
}

/** Format 0-1 score as percentage string */
export function fmtScore(score) {
  if (score == null) return '—'
  return (score * 100).toFixed(1) + '%'
}

/** Format delta between two scores with +/- sign */
export function fmtDelta(delta) {
  if (delta == null) return null
  const sign = delta >= 0 ? '+' : ''
  return `${sign}${(delta * 100).toFixed(1)}%`
}

/** Returns Tailwind classes for a delta value (positive=green, negative=red) */
export function deltaColorClass(delta) {
  if (delta == null) return 'text-slate-500'
  if (delta > 0.01) return 'text-emerald-400'
  if (delta < -0.01) return 'text-red-400'
  return 'text-slate-400'
}

/** Human-readable metric names */
export const METRIC_LABELS = {
  faithfulness: 'Faithfulness',
  answer_relevancy: 'Answer Relevancy',
  context_precision: 'Context Precision',
  context_recall: 'Context Recall',
}

/** Recharts stroke colors — consistent across all charts */
export const METRIC_COLORS = {
  faithfulness: '#818cf8',      // indigo
  answer_relevancy: '#34d399',  // emerald
  context_precision: '#fbbf24', // amber
  context_recall: '#f472b6',    // pink
}
