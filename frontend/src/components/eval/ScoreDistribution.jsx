/**
 * ScoreDistribution — histogram showing score distribution for one metric.
 *
 * Buckets scores into bins [0-0.2, 0.2-0.4, 0.4-0.6, 0.6-0.8, 0.8-1.0].
 * Each bar is colored by the bin's threshold (green/amber/red).
 * Shows count + percentage per bin on hover.
 *
 * WHY THIS IS USEFUL:
 * An average faithfulness of 0.75 could mean "all cases around 0.75"
 * OR "half at 0.95, half at 0.55". The distribution reveals which.
 * The second scenario is a retrieval gap problem; the first is uniform drift.
 */
import {
  ResponsiveContainer, BarChart, Bar, XAxis, YAxis,
  CartesianGrid, Tooltip, Cell,
} from 'recharts'
import { METRIC_LABELS } from '../../utils/scoreColor.js'

const BINS = [
  { label: '0–20%',  min: 0.0, max: 0.2, color: '#f87171' },
  { label: '20–40%', min: 0.2, max: 0.4, color: '#fb923c' },
  { label: '40–60%', min: 0.4, max: 0.6, color: '#fbbf24' },
  { label: '60–80%', min: 0.6, max: 0.8, color: '#a3e635' },
  { label: '80–100%',min: 0.8, max: 1.01,color: '#34d399' },
]

function buildHistogram(scores) {
  const total = scores.length
  return BINS.map((bin) => {
    const count = scores.filter((s) => s >= bin.min && s < bin.max).length
    return { ...bin, count, pct: total > 0 ? (count / total * 100).toFixed(1) : '0' }
  })
}

const CustomTooltip = ({ active, payload }) => {
  if (!active || !payload?.length) return null
  const d = payload[0].payload
  return (
    <div className="bg-slate-800 border border-slate-700 rounded-lg p-2.5 text-xs shadow-xl">
      <p className="text-slate-300 font-medium">{d.label}</p>
      <p className="text-slate-400 mt-1">{d.count} cases ({d.pct}%)</p>
    </div>
  )
}

export default function ScoreDistribution({ cases = [], metric }) {
  const scores = cases
    .map((c) => c[`${metric}_score`])
    .filter((s) => s != null)

  if (scores.length === 0) {
    return (
      <div className="h-36 flex items-center justify-center text-slate-600 text-xs">
        No scores available
      </div>
    )
  }

  const data = buildHistogram(scores)

  return (
    <div>
      <p className="text-xs text-slate-500 mb-2">{METRIC_LABELS[metric]}</p>
      <ResponsiveContainer width="100%" height={130}>
        <BarChart data={data} margin={{ top: 0, right: 0, bottom: 0, left: -20 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#1e293b" vertical={false} />
          <XAxis
            dataKey="label"
            tick={{ fill: '#475569', fontSize: 10 }}
            axisLine={false}
            tickLine={false}
          />
          <YAxis
            tick={{ fill: '#475569', fontSize: 10 }}
            axisLine={false}
            tickLine={false}
          />
          <Tooltip content={<CustomTooltip />} cursor={{ fill: 'rgba(255,255,255,0.03)' }} />
          <Bar dataKey="count" radius={[3, 3, 0, 0]}>
            {data.map((entry, i) => (
              <Cell key={i} fill={entry.color} fillOpacity={0.85} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}
