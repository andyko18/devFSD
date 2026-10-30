export type JobKind = 'agent' | 'bash'

export type Job = {
  id: string
  kind: JobKind
  label: string
  detail: string
  startedAt: number
  endedAt?: number
  isFailed?: boolean
}

export type Board = {
  running: Job[]
  recent: Job[]
  stage?: string
  fid?: string
}

declare module 'claude-code' {
  interface PluginState {
    'devfsd': {
      board: Shaped<Board>
      now: Shaped<number>
    }
  }
}
