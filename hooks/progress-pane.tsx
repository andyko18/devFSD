import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Board, Job } from '../types'

const PANE = 'devfsd-progress'
const TITLE = 'devFSD 진행'
const TICK_MS = 5000
const RECENT_MAX = 5
const PROGRESS_FILE = '.specops/session-progress.md'

// Change a tag when its value's fields change: it declines what an earlier
// version stored, which outlives a reload.
const board = atom(
  { plugin: 'devfsd', key: 'board' } as const,
  { running: [], recent: [] } as Board,
  { shape: 'board-1' },
)
const now = atom({ plugin: 'devfsd', key: 'now' } as const, 0, {
  shape: 'now-1',
})

const STAGE_NAMES: Record<string, string> = {
  'using-specops': '진입',
  analyzing: '분석',
  specifying: '명세',
  clarifying: '명확화',
  planning: '설계',
  decomposing: '분해',
  implementing: '구현',
  'verifying-evidence': '검증',
  'requesting-code-review': '리뷰 요청',
  'receiving-code-review': '리뷰 반영',
  'security-review': '보안 리뷰',
  'integration-test': '통합 테스트',
  'performance-test': '성능 테스트',
  'finishing-a-development-branch': 'PR',
  release: '릴리즈',
}

/** `devfsd:planning-ko` → `설계 (planning-ko)`; anything else → undefined. */
export function stageOf(skill: string): string | undefined {
  const match = skill.match(/^(?:devfsd|specops-ko):(.+)$/)
  const name = match?.[1]
  if (!name) return undefined
  const base = name.replace(/-ko$/, '')
  const label = STAGE_NAMES[base]

  return label ? `${label} (${name})` : name
}

/** First `## <FID>` heading of session-progress.md. */
export function fidOf(progress: string): string | undefined {
  const match = progress.match(/^## (\S+)/m)

  return match?.[1]
}

/** A task notification's tool-use id and whether it failed. */
export function notificationOf(
  text: string,
): { id: string; isFailed: boolean } | undefined {
  const id = text.match(/<tool-use-id>([^<]+)<\/tool-use-id>/)?.[1]
  if (!id) return undefined
  const status = text.match(/<status>([^<]+)<\/status>/)?.[1] ?? ''

  return { id: id.trim(), isFailed: /fail|error|kill/i.test(status) }
}

/** `3m12s` style, from milliseconds. */
export function elapsed(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000))
  const minutes = Math.floor(total / 60)
  const seconds = total % 60

  return minutes > 0 ? `${minutes}m${String(seconds).padStart(2, '0')}s` : `${seconds}s`
}

const WORKTREE_MARKERS = ['/.claude/worktrees/', '/.worktrees/']

/** The project folder a worktree belongs to, or the folder itself. */
export function projectRoot(cwd: string): string {
  const cuts = WORKTREE_MARKERS.map(m => cwd.indexOf(m)).filter(at => at >= 0)

  return cuts.length > 0 ? cwd.slice(0, Math.min(...cuts)) : cwd
}

/** devFSD 관할: cwd 또는 그 worktree 의 프로젝트 폴더에 `.specops/` 가 있다. */
async function isGoverned($: EngineInterface, cwd: string): Promise<boolean> {
  for (const dir of [cwd, projectRoot(cwd)]) {
    try {
      if (await $.fs.exists(`${dir}/.specops`)) return true
    } catch {
      // 판정 불가 — 다음 후보, 끝내 못 찾으면 열지 않는다.
    }
  }

  return false
}

async function readFid($: EngineInterface, cwd: string): Promise<string | undefined> {
  for (const dir of [cwd, projectRoot(cwd)]) {
    try {
      return fidOf(await $.fs.read(`${dir}/${PROGRESS_FILE}`))
    } catch {
      // No progress file here: try the project folder, then give up.
    }
  }

  return undefined
}

function startJob($: EngineInterface, job: Job): Promise<unknown> {
  return update($, board, b => ({
    ...b,
    running: [...b.running.filter(one => one.id !== job.id), job],
  }))
}

async function endJob($: EngineInterface, id: string, isFailed: boolean): Promise<void> {
  const endedAt = await $.clock.now()
  await update($, board, b => {
    const job = b.running.find(one => one.id === id)
    if (!job) return b
    const done: Job = { ...job, endedAt, isFailed }

    return {
      ...b,
      running: b.running.filter(one => one.id !== id),
      recent: [done, ...b.recent].slice(0, RECENT_MAX),
    }
  })
}

function textOf(content: readonly { type: string; [field: string]: unknown }[]): string {
  return content
    .filter(block => block.type === 'text' && typeof block.text === 'string')
    .map(block => block.text as string)
    .join('\n')
}

/** 관찰은 실패해도 조용히 넘어간다 — 원 호출의 결과·실행 횟수에 영향 금지. */
async function safe(work: () => Promise<unknown>): Promise<void> {
  try {
    await work()
  } catch {
    // 표시만 어긋날 뿐 동작은 그대로 둔다.
  }
}

export const register: Register = on => {
  let cwd = ''
  let ticker: { cancel(): void } | undefined

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    cwd = e.cwd
    await $.command.register({
      name: 'devfsd-progress',
      description: 'devFSD 진행 패널 열기',
    })
    await safe(async () => {
      const fid = await readFid($, cwd)
      await update($, board, b => ({ ...b, fid }))
      const t = await $.clock.now()
      await update($, now, () => t)
      // Keeps elapsed times moving while something runs. A restart replaces the old timer.
      ticker?.cancel()
      ticker = $.clock.every(TICK_MS, () => {
        void safe(async () => {
          const b = await read($, board)
          if (b.running.length > 0) {
            const t = await $.clock.now()
            await update($, now, () => t)
          }
        })
      })
    })
    if (await isGoverned($, cwd)) void $.ui.open({ id: PANE, title: TITLE })

    return started
  })

  on('command.run', { command: 'devfsd-progress' }, async $ => {
    await $.ui.open({ id: PANE, title: TITLE })

    return { text: 'devFSD 진행 패널을 열었습니다.' }
  })

  // Subagents: done when a foreground call returns, else on its notification.
  on('tool.call', { tool: 'Agent' }, async ($, e, next) => {
    if (e.agentId) return next(e)
    await safe(async () => {
      const startedAt = await $.clock.now()
      await startJob($, {
        id: e.tool_use_id,
        kind: 'agent',
        label: e.description,
        detail: e.subagent_type ?? 'general-purpose',
        startedAt,
      })
    })
    const ran = await next(e)
    const isLaunched = ran.deny === undefined && /launched|background/i.test(ran.text ?? '')
    if (!isLaunched) await safe(() => endJob($, e.tool_use_id, ran.deny !== undefined || ran.isError === true))

    return ran
  }).catch(($, e, next) => next(e))

  // Background commands: done on their notification.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    if (e.agentId || e.run_in_background !== true) return next(e)
    await safe(async () => {
      const startedAt = await $.clock.now()
      await startJob($, {
        id: e.tool_use_id,
        kind: 'bash',
        label: e.description ?? e.command.slice(0, 40),
        detail: '백그라운드',
        startedAt,
      })
    })
    const ran = await next(e)
    if (ran.deny !== undefined) await safe(() => endJob($, e.tool_use_id, true))

    return ran
  }).catch(($, e, next) => next(e))

  on('tool.call', { tool: 'Skill' }, async ($, e, next) => {
    const stage = e.agentId ? undefined : stageOf(e.skill)
    if (stage) {
      await safe(async () => {
        const fid = await readFid($, cwd)
        await update($, board, b => ({ ...b, stage, fid: fid ?? b.fid }))
      })
    }

    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.append', async ($, e, next) => {
    const stored = await next(e)
    if (!e.agentId && e.message.type === 'user') {
      const note = notificationOf(textOf(e.message.content))
      if (note) await safe(() => endJob($, note.id, note.isFailed))
    }

    return stored
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const b = await read($, board)
    const at = await read($, now)
    const head = ['devFSD', b.fid, b.stage].filter(Boolean).join(' · ')

    return (
      <Box flexDirection="column">
        <Text bold>{head}</Text>
        <Text> </Text>
        <Text bold>▶ 실행 중 ({b.running.length})</Text>
        {b.running.length === 0 && <Text dimColor>  없음</Text>}
        {b.running.map(job => (
          <Text>
            {'  '}
            {job.label} · {job.detail} · {elapsed(at - job.startedAt)}
          </Text>
        ))}
        <Text> </Text>
        <Text bold>최근 완료</Text>
        {b.recent.length === 0 && <Text dimColor>  없음</Text>}
        {b.recent.map(job => (
          <Text dimColor={!job.isFailed}>
            {'  '}
            {job.isFailed ? '✗' : '✓'} {job.label} · {elapsed((job.endedAt ?? at) - job.startedAt)}
          </Text>
        ))}
      </Box>
    )
  })
}
