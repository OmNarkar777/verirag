/**
 * QueryPanel — interactive RAG query interface.
 *
 * Send a question → get the LLM answer + retrieved chunks with scores.
 * The "Use as Eval Case" button pre-fills an eval run form with
 * the question/answer/contexts — closing the loop between querying
 * and evaluating.
 */
import { useState } from 'react'
import clsx from 'clsx'
import { useQueryPipeline } from '../../hooks/usePipeline.js'
import { scoreColorClass, fmtScore } from '../../utils/scoreColor.js'

const EXAMPLE_QUESTIONS = [
  'What is the key innovation of the Transformer architecture?',
  'How does RAGAS measure faithfulness?',
  'Why does MMR retrieval improve context precision?',
]

export default function QueryPanel({ onEvalCase }) {
  const [question, setQuestion] = useState('')
  const [topK, setTopK] = useState(5)
  const queryMutation = useQueryPipeline()

  const handleQuery = () => {
    if (!question.trim()) return
    queryMutation.mutate({ question: question.trim(), topK })
  }

  const result = queryMutation.data

  const handleUseAsEval = () => {
    if (!result || !onEvalCase) return
    onEvalCase({
      question: result.question,
      answer: result.answer,
      contexts: result.retrieved_chunks.map((c) => c.content),
    })
  }

  return (
    <div className="space-y-5">
      {/* Input */}
      <div className="glass rounded-xl p-4 space-y-3">
        <div className="flex gap-2">
          <textarea
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && e.metaKey && handleQuery()}
            placeholder="Ask a question about your ingested documents…"
            rows={3}
            className="flex-1 bg-slate-800 border border-slate-700 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder-slate-600 focus:outline-none focus:border-brand-500 resize-none"
          />
        </div>

        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-xs text-slate-500">
            <span>Top-K chunks:</span>
            <select
              value={topK}
              onChange={(e) => setTopK(Number(e.target.value))}
              className="bg-slate-800 border border-slate-700 rounded px-2 py-0.5 text-slate-300 focus:outline-none"
            >
              {[3, 5, 8, 10].map((k) => <option key={k} value={k}>{k}</option>)}
            </select>
            <span className="text-slate-600 ml-2">⌘↵ to submit</span>
          </div>
          <button
            onClick={handleQuery}
            disabled={!question.trim() || queryMutation.isPending}
            className="px-4 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium transition-colors disabled:opacity-50"
          >
            {queryMutation.isPending ? 'Querying…' : 'Query Pipeline'}
          </button>
        </div>

        {/* Example questions */}
        <div className="flex flex-wrap gap-2 pt-1 border-t border-slate-800">
          <span className="text-xs text-slate-600">Examples:</span>
          {EXAMPLE_QUESTIONS.map((q) => (
            <button
              key={q}
              onClick={() => setQuestion(q)}
              className="text-xs text-slate-500 hover:text-slate-300 underline underline-offset-2 transition-colors"
            >
              {q.length > 50 ? q.slice(0, 50) + '…' : q}
            </button>
          ))}
        </div>
      </div>

      {/* Error */}
      {queryMutation.isError && (
        <div className="rounded-xl border border-red-500/30 bg-red-500/5 px-4 py-3 text-xs text-red-400">
          {queryMutation.error?.message}
        </div>
      )}

      {/* Result */}
      {result && (
        <div className="space-y-4">
          {/* Answer */}
          <div className="glass rounded-xl p-5">
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-sm font-semibold text-slate-200">Answer</h3>
              <div className="flex items-center gap-3">
                <span className="text-xs text-slate-600 font-mono">{result.model_used}</span>
                {onEvalCase && (
                  <button
                    onClick={handleUseAsEval}
                    className="text-xs text-brand-400 hover:text-brand-300 border border-brand-500/30 px-2.5 py-1 rounded-lg transition-colors"
                  >
                    + Use as Eval Case
                  </button>
                )}
              </div>
            </div>
            <p className="text-sm text-slate-300 leading-relaxed">{result.answer}</p>
          </div>

          {/* Retrieved chunks */}
          <div className="glass rounded-xl p-5">
            <h3 className="text-sm font-semibold text-slate-200 mb-3">
              Retrieved Chunks
              <span className="ml-2 text-xs text-slate-500 font-normal">
                ({result.retrieved_chunks.length} chunks — these become the <code className="text-slate-400">contexts</code> in RAGAS eval)
              </span>
            </h3>
            <div className="space-y-3">
              {result.retrieved_chunks.map((chunk, i) => (
                <div key={i} className="border border-slate-800 rounded-lg p-3">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-xs text-slate-500 font-mono">{chunk.source}</span>
                    <span className={clsx(
                      'text-xs font-mono tabular-nums',
                      scoreColorClass(chunk.score, 'text'),
                    )}>
                      score: {chunk.score.toFixed(3)}
                    </span>
                  </div>
                  <p className="text-xs text-slate-400 leading-relaxed">{chunk.content}</p>
                </div>
              ))}
            </div>
          </div>

          {/* LangSmith link */}
          {result.langsmith_trace_url && (
            <p className="text-xs text-slate-600">
              Trace:{' '}
              <a
                href={result.langsmith_trace_url}
                target="_blank"
                rel="noreferrer"
                className="text-slate-400 hover:text-slate-200 underline"
              >
                {result.langsmith_trace_url} ↗
              </a>
            </p>
          )}
        </div>
      )}
    </div>
  )
}
