/**
 * IngestPanel — document ingestion with drag-and-drop file upload.
 *
 * Supports .txt, .md, .pdf via the POST /pipeline/ingest endpoint.
 * Shows real-time progress: uploading → processing → done with chunk count.
 *
 * Also has a "paste text" mode for quick ingestion without file save.
 */
import { useState, useRef, useCallback } from 'react'
import clsx from 'clsx'
import { useIngestFile, useIngestText, useDocuments, usePipelineStats } from '../../hooks/usePipeline.js'
import { formatDistanceToNow } from 'date-fns'

function DropZone({ onFiles, isDragging }) {
  return (
    <div
      className={clsx(
        'border-2 border-dashed rounded-xl p-8 text-center transition-colors cursor-pointer',
        isDragging
          ? 'border-brand-500 bg-brand-500/5'
          : 'border-slate-700 hover:border-slate-600 hover:bg-slate-800/30',
      )}
    >
      <div className="text-3xl mb-3">📄</div>
      <p className="text-sm text-slate-300 font-medium">
        Drop files here or{' '}
        <span className="text-brand-400 cursor-pointer">click to browse</span>
      </p>
      <p className="text-xs text-slate-600 mt-1">Supports .txt, .md, .pdf</p>
    </div>
  )
}

export default function IngestPanel() {
  const [isDragging, setIsDragging] = useState(false)
  const [mode, setMode] = useState('file') // 'file' | 'text'
  const [pasteText, setPasteText] = useState('')
  const [pasteFilename, setPasteFilename] = useState('pasted-text.txt')
  const [lastResult, setLastResult] = useState(null)
  const fileInputRef = useRef(null)

  const ingestFile = useIngestFile()
  const ingestText = useIngestText()
  const { data: docs = [], isLoading: docsLoading } = useDocuments()
  const { data: stats } = usePipelineStats()

  const handleFiles = useCallback(async (files) => {
    for (const file of files) {
      try {
        const result = await ingestFile.mutateAsync({ file })
        setLastResult(result)
      } catch (e) {
        console.error('Ingest failed:', e.message)
      }
    }
  }, [ingestFile])

  const onDrop = useCallback((e) => {
    e.preventDefault()
    setIsDragging(false)
    handleFiles([...e.dataTransfer.files])
  }, [handleFiles])

  const onDragOver = (e) => { e.preventDefault(); setIsDragging(true) }
  const onDragLeave = () => setIsDragging(false)

  const handlePasteSubmit = async () => {
    if (!pasteText.trim()) return
    try {
      const result = await ingestText.mutateAsync({ text: pasteText, filename: pasteFilename })
      setLastResult(result)
      setPasteText('')
    } catch (e) {
      console.error('Ingest failed:', e.message)
    }
  }

  const isLoading = ingestFile.isPending || ingestText.isPending

  return (
    <div className="space-y-5">
      {/* Stats bar */}
      {stats && (
        <div className="glass rounded-xl px-5 py-3 flex items-center gap-6 text-xs">
          <div>
            <span className="text-slate-500">Collection: </span>
            <span className="text-slate-300 font-mono">{stats.collection_name}</span>
          </div>
          <div>
            <span className="text-slate-500">Chunks indexed: </span>
            <span className="text-brand-400 font-semibold">{stats.document_count}</span>
          </div>
          <div>
            <span className="text-slate-500">Model: </span>
            <span className="text-slate-300">{stats.embedding_model}</span>
          </div>
          <div>
            <span className="text-slate-500">Retrieval: </span>
            <span className="text-slate-300">MMR top-{stats.top_k}</span>
          </div>
        </div>
      )}

      {/* Mode toggle */}
      <div className="flex rounded-lg overflow-hidden border border-slate-700 w-fit">
        {['file', 'text'].map((m) => (
          <button
            key={m}
            onClick={() => setMode(m)}
            className={clsx(
              'px-4 py-1.5 text-xs font-medium transition-colors capitalize',
              mode === m ? 'bg-brand-500 text-white' : 'text-slate-400 hover:text-slate-200',
            )}
          >
            {m === 'file' ? '📁 File Upload' : '✏️ Paste Text'}
          </button>
        ))}
      </div>

      {/* File upload */}
      {mode === 'file' && (
        <div
          onDrop={onDrop}
          onDragOver={onDragOver}
          onDragLeave={onDragLeave}
          onClick={() => fileInputRef.current?.click()}
        >
          <input
            ref={fileInputRef}
            type="file"
            multiple
            accept=".txt,.md,.pdf"
            className="hidden"
            onChange={(e) => handleFiles([...e.target.files])}
          />
          {isLoading ? (
            <div className="border-2 border-dashed border-brand-500/50 rounded-xl p-8 text-center">
              <div className="text-2xl mb-2 animate-pulse">⚙️</div>
              <p className="text-sm text-brand-300">Processing document…</p>
            </div>
          ) : (
            <DropZone onFiles={handleFiles} isDragging={isDragging} />
          )}
        </div>
      )}

      {/* Paste text */}
      {mode === 'text' && (
        <div className="glass rounded-xl p-4 space-y-3">
          <input
            type="text"
            value={pasteFilename}
            onChange={(e) => setPasteFilename(e.target.value)}
            placeholder="Document name (e.g., my-corpus.txt)"
            className="w-full bg-slate-800 border border-slate-700 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder-slate-600 focus:outline-none focus:border-brand-500"
          />
          <textarea
            value={pasteText}
            onChange={(e) => setPasteText(e.target.value)}
            placeholder="Paste document text here…"
            rows={6}
            className="w-full bg-slate-800 border border-slate-700 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder-slate-600 focus:outline-none focus:border-brand-500 resize-none"
          />
          <button
            onClick={handlePasteSubmit}
            disabled={!pasteText.trim() || isLoading}
            className="w-full py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium transition-colors disabled:opacity-50"
          >
            {isLoading ? 'Ingesting…' : 'Ingest Text'}
          </button>
        </div>
      )}

      {/* Success result */}
      {lastResult && !isLoading && (
        <div className="rounded-xl border border-emerald-500/30 bg-emerald-500/5 px-4 py-3 text-xs">
          <p className="text-emerald-400 font-medium">✓ Ingested successfully</p>
          <p className="text-slate-400 mt-1">
            <span className="font-mono">{lastResult.filename}</span>
            {' → '}
            <span className="text-emerald-300">{lastResult.chunks_created} chunks</span>
            {' in '}
            <span className="font-mono">{lastResult.collection_name}</span>
          </p>
        </div>
      )}

      {/* Error */}
      {(ingestFile.isError || ingestText.isError) && (
        <div className="rounded-xl border border-red-500/30 bg-red-500/5 px-4 py-3 text-xs">
          <p className="text-red-400">
            {ingestFile.error?.message ?? ingestText.error?.message}
          </p>
        </div>
      )}

      {/* Document list */}
      <div className="glass rounded-xl overflow-hidden">
        <div className="px-5 py-3 border-b border-slate-800">
          <h3 className="text-sm font-semibold text-slate-200">Ingested Documents</h3>
        </div>
        {docsLoading ? (
          <div className="p-4 space-y-2">
            {[...Array(3)].map((_, i) => <div key={i} className="skeleton h-8 rounded" />)}
          </div>
        ) : docs.length === 0 ? (
          <p className="px-5 py-6 text-xs text-slate-600 text-center">
            No documents ingested yet.
          </p>
        ) : (
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-slate-800 text-slate-500 uppercase tracking-wider">
                <th className="px-4 py-2.5 text-left font-medium">Filename</th>
                <th className="px-4 py-2.5 text-center font-medium">Chunks</th>
                <th className="px-4 py-2.5 text-left font-medium">Ingested</th>
              </tr>
            </thead>
            <tbody>
              {docs.slice(0, 20).map((doc) => (
                <tr key={doc.id} className="border-b border-slate-800/60 hover:bg-slate-800/20">
                  <td className="px-4 py-2.5 text-slate-300 font-mono">{doc.filename}</td>
                  <td className="px-4 py-2.5 text-center text-slate-400">{doc.chunk_count}</td>
                  <td className="px-4 py-2.5 text-slate-500">
                    {formatDistanceToNow(new Date(doc.ingested_at), { addSuffix: true })}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
