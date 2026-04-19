/**
 * hooks/useEvalRuns.js â€” React Query hooks for eval runs + regression data.
 * TanStack Query v5: refetchInterval receives { data, query } not data directly.
 */
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { listEvalRuns, getRegressions, startSampleEval, deleteEvalRun, getEvalStatus } from '../api/client.js'

export const EVAL_RUNS_KEY = ['eval-runs']
export const REGRESSIONS_KEY = ['regressions']

export function useEvalRuns({ limit = 50 } = {}) {
  return useQuery({
    queryKey: [...EVAL_RUNS_KEY, limit],
    queryFn: () => listEvalRuns({ limit }),
    // v5 API: refetchInterval receives { data } destructure, not raw data
    refetchInterval: ({ data } = {}) => {
      const hasRunning = data?.some((r) => r.status === 'running')
      return hasRunning ? 8_000 : 30_000
    },
  })
}

export function useRegressions() {
  return useQuery({
    queryKey: REGRESSIONS_KEY,
    queryFn: getRegressions,
    refetchInterval: 30_000,
  })
}

export function useEvalStatus() {
  return useQuery({
    queryKey: ['eval-status'],
    queryFn: getEvalStatus,
    refetchInterval: 10_000,
  })
}

export function useStartSampleEval() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (versionTag) => startSampleEval(versionTag),
    onSuccess: () => qc.invalidateQueries({ queryKey: EVAL_RUNS_KEY }),
  })
}

export function useDeleteEvalRun() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (runId) => deleteEvalRun(runId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: EVAL_RUNS_KEY })
      qc.invalidateQueries({ queryKey: REGRESSIONS_KEY })
    },
  })
}