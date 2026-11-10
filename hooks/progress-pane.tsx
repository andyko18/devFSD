import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Board, Job, StageMark } from '../types'
import { pollCi } from './ci-watch'
import { STAT_SCRIPT, outputPathOf, latestMtimeMs, redact, withActivity } from './core'

const PANE = 'devfsd-progress'
const TITLE = 'devFSD 진행'
const TICK_MS = 5000
const END_TICK_MS = 1000 // 끝난 명령이 카드에서 빠지는 순간을 맞추는 보조 틱
const RECENT_MS = 60_000 // 끝난 명령이 카드에 남는 시간(console.tsx 의 60_000 과 같다)
const RECENT_MAX = 5
// devFSD: 세션 시작 때 여는 패널은 관제판(console.tsx)이다. 진행 패널은 /devfsd-progress 로 연다.
const CONSOLE_PANE = 'devfsd-console'
const CONSOLE_TITLE = 'devFSD 관제판'
const PROGRESS_FILE = '.specops/session-progress.md'
const VERIFY_TIMEOUT_MS = 10_000
const REFRESH_TOOLS = ['Edit', 'Write', 'NotebookEdit'] // Bash·Agent·Skill 은 각자의 hook 안에서

// Change a tag when its value's fields change: it declines what an earlier
// version stored, which outlives a reload.
export const board = atom(
  { plugin: 'devfsd', key: 'board' } as const,
  { running: [], recent: [] } as Board,
  { shape: 'board-2' },
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
  demo: '데모',
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

const FID_RE = /^\d{8}-[a-z0-9-]+$/
const STAGES: readonly { key: string; cmd: string; label: string }[] = [
  { key: 'analyze', cmd: '/analyze', label: '분석' },
  { key: 'specify', cmd: '/specify', label: '명세' },
  { key: 'clarify', cmd: '/clarify', label: '명확화' },
  { key: 'plan', cmd: '/plan', label: '설계' },
  { key: 'tasks', cmd: '/tasks', label: '분해' },
  { key: 'implement', cmd: '/implement', label: '구현' },
  { key: 'verify', cmd: '/verify', label: '검증' },
  { key: 'security', cmd: '/security-review', label: '보안' },
  { key: 'integration', cmd: '/integration-test', label: '통합' },
  { key: 'performance', cmd: '/performance-test', label: '성능' },
  { key: 'demo', cmd: '/demo', label: '데모' },
  { key: 'pr', cmd: '/lifecycle', label: 'PR' },
]
const VERIFY_WORDS = ['PASS', 'STALE', 'FAIL', 'PARTIAL', 'NOT_RUN', 'WAIVED']

/** 활성 FID — active-fid 마커 우선, 없으면 FID 형식의 첫 `## ` 제목. */
export function activeFid(progress: string): string | undefined {
  const marked = progress.match(/<!--\s*active-fid:\s*(\S+)\s*-->/)?.[1]
  if (marked && FID_RE.test(marked)) return marked
  for (const line of progress.split('\n')) {
    const id = line.match(/^## (\S+)/)?.[1]
    if (id && FID_RE.test(id)) return id
  }

  return undefined
}

const STAMP_RE = /^- (\d{4}-\d{2}-\d{2} \d{2}:\d{2}) /

/** 활성 FID 섹션 맨 위 기록 줄의 시각(`YYYY-MM-DD HH:MM`, 최신이 위) — 기록 줄이 없으면 undefined. */
export function latestStamp(progress: string): string | undefined {
  const fid = activeFid(progress)
  if (!fid) return undefined
  const lines = progress.split('\n')
  const start = lines.findIndex(l => l.match(/^## (\S+)/)?.[1] === fid)
  if (start < 0) return undefined
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith('## ')) break
    const stamp = line.match(STAMP_RE)?.[1]
    if (stamp) return stamp
  }

  return undefined
}

/** `other` 기록이 `base` 보다 확실히 최근일 때만 true — 동률·판독 실패는 false(종전: base 우선). */
export function isNewer(other: string, base: string): boolean {
  const o = latestStamp(other)
  const b = latestStamp(base)

  return o !== undefined && b !== undefined && o > b
}

/** FID 섹션의 기록 줄(최신이 위)에서 `/<cmd> <첫 낱말>` 만 뽑는다. */
function recordsOf(progress: string, fid: string): { cmd: string; word: string }[] {
  const lines = progress.split('\n')
  const start = lines.findIndex(l => l.match(/^## (\S+)/)?.[1] === fid)
  if (start < 0) return []
  const out: { cmd: string; word: string }[] = []
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith('## ')) break
    const m = line.match(/^- \S+ \S+ (\/[a-z-]+) (\S+)/)
    if (m) out.push({ cmd: m[1] ?? '', word: m[2] ?? '' })
  }

  return out
}

function markOf(word: string): StageMark['mark'] {
  if (/^(완료|DONE|PASS)$/.test(word)) return '✓'
  if (word === 'SKIP') return '–'
  if (/^(FAIL|BLOCK|BLOCKED)$/.test(word)) return '✗' // PARTIAL·진행 등 그 밖은 ●

  return '●'
}

export function stagesOf(progress: string, fid: string): StageMark[] {
  const recs = recordsOf(progress, fid)

  return STAGES.flatMap(s => {
    const newest = recs.find(r => r.cmd === s.cmd)
    if (!newest && s.key === 'analyze') return []

    return [{ key: s.key, label: s.label, mark: newest ? markOf(newest.word) : '○' }]
  })
}

/** devFSD: 지금 하는 단계 — 가장 최근 기록의 단계, 그 기록이 완료면 다음 미완 단계. lifecycle 완료면 null. */
export function currentStageKey(progress: string, fid: string): string | null {
  if (isLifecycleDone(progress, fid)) return null
  const newest = recordsOf(progress, fid).find(r => STAGES.some(s => s.cmd === r.cmd))
  if (!newest) return null
  const at = STAGES.findIndex(s => s.cmd === newest.cmd)
  if (markOf(newest.word) !== '✓' && markOf(newest.word) !== '–') return STAGES[at]?.key ?? null

  return STAGES[at + 1]?.key ?? null
}

/** devFSD: 검증 배지 상태를 단계 막대에 맞춘다(기록 없는 ○ 는 그대로) + 현재 단계 표시. */
export function withVerifyMark(stages: StageMark[], verify: string | undefined, current: string | null): StageMark[] {
  const vm: StageMark['mark'] | null = verify === '검증 FAIL' ? '✗' : verify === '검증 STALE' || verify === '검증 PARTIAL' ? '!' : null

  return stages.map(s => ({
    ...s,
    ...(s.key === 'verify' && vm && s.mark !== '○' ? { mark: vm } : {}),
    ...(s.key === current ? { isCurrent: true } : {}),
  }))
}

export function isLifecycleDone(progress: string, fid: string): boolean {
  const top = recordsOf(progress, fid)[0]

  return top?.cmd === '/lifecycle' && top.word === 'DONE'
}

export function verifyWord(r: { exitCode: number; stdout: string }): string {
  const w = r.stdout.trim()

  return r.exitCode === 0 && VERIFY_WORDS.includes(w) ? `검증 ${w}` : '검증 ?'
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

/** 기록을 읽을 폴더 — [cwd, 프로젝트 폴더] 중 최신 기록 쪽. 동률·판독 실패·한쪽뿐이면 먼저 찾은 쪽(종전). */
async function readRecord($: EngineInterface, cwd: string): Promise<{ dir: string; progress: string } | undefined> {
  const found: { dir: string; progress: string }[] = []
  for (const dir of [...new Set([cwd, projectRoot(cwd)])]) {
    try {
      found.push({ dir, progress: await $.fs.read(`${dir}/${PROGRESS_FILE}`) })
    } catch {
      // 이 폴더에는 기록이 없다 — 다음 후보.
    }
  }
  const [first, second] = found

  return first && second && isNewer(second.progress, first.progress) ? second : first
}

async function readFid($: EngineInterface, cwd: string): Promise<string | undefined> {
  const record = await readRecord($, cwd)

  return record ? activeFid(record.progress) : undefined
}

/** 이 FID 의 verify 상태 낱말 — 읽기 전용 `current` 만 부른다. 판정 불가는 `검증 ?`. */
async function verifyFor($: EngineInterface, cwd: string, fid: string, preferred?: string): Promise<string> {
  // devFSD: FID 기록이 있는 첫 폴더를 진행 읽기와 같은 순서([cwd, 프로젝트 폴더])로 찾는다.
  //   새 FID 는 워크트리 안에 만들어질 수 있어 프로젝트 폴더 고정이면 `검증 ?` 가 된다.
  let root: string | undefined
  for (const dir of [...new Set([preferred ?? cwd, cwd, projectRoot(cwd)])]) {
    try {
      if (await $.fs.exists(`${dir}/.specops/${fid}`)) {
        root = dir
        break
      }
    } catch {
      // 판정 불가 — 다음 후보
    }
  }
  if (!root) return '검증 ?'
  const env: Record<string, string> = {}
  if (root !== cwd) {
    const g = await $.process.run(['git', '-C', cwd, 'rev-parse', '--absolute-git-dir'], { timeoutMs: VERIFY_TIMEOUT_MS })
    if (g.exitCode !== 0) return '검증 ?'
    env.GIT_DIR = g.stdout.trim()
    env.GIT_WORK_TREE = cwd
  }
  const r = await $.process.run(
    ['bash', `${$.plugin.root}/scripts/_internal/verification-state.sh`, 'current', fid],
    { cwd: root, env, timeoutMs: VERIFY_TIMEOUT_MS },
  )

  return verifyWord(r)
}

type RefreshGate = { refreshing: boolean; again: boolean }

/** 단계 막대·배지를 다시 계산한다. 겹치면 끝난 뒤 1회만 다시. 실패는 `?`. */
async function refreshStatus($: EngineInterface, cwd: string, gate: RefreshGate): Promise<void> {
  if (gate.refreshing) {
    gate.again = true

    return
  }
  gate.refreshing = true
  try {
    do {
      gate.again = false
      const record = await readRecord($, cwd)
      const progress = record?.progress ?? ''
      const fid = activeFid(progress)
      if (!fid) {
        await update($, board, b => ({ ...b, fid: undefined, stages: undefined, verify: undefined }))
        continue
      }
      const stages = stagesOf(progress, fid)
      const verify = isLifecycleDone(progress, fid) ? '완료' : await verifyFor($, cwd, fid, record?.dir).catch(() => '검증 ?')
      const marked = withVerifyMark(stages, verify, currentStageKey(progress, fid))
      await update($, board, b => ({ ...b, fid, stages: marked, verify }))
    } while (gate.again)
  } catch {
    await safe(() => update($, board, b => ({ ...b, verify: '검증 ?' })))
  } finally {
    gate.refreshing = false
  }
}

function startJob($: EngineInterface, job: Job): Promise<unknown> {
  return update($, board, b => ({
    ...b,
    running: [...b.running.filter(one => one.id !== job.id), job],
  }))
}

async function endJob($: EngineInterface, id: string, isFailed: boolean): Promise<void> {
  const endedAt = await $.clock.now()
  let isBash = false
  await update($, board, b => {
    const job = b.running.find(one => one.id === id)
    if (!job) return b
    isBash = job.kind === 'bash'
    const done: Job = { ...job, endedAt, isFailed }

    return {
      ...b,
      running: b.running.filter(one => one.id !== id),
      recent: [done, ...b.recent].slice(0, RECENT_MAX),
    }
  })
  if (isBash) startEndTicker($)
}

/** 끝난 명령이 카드에 머무는 60초(AC-10)를 5초 틱 정렬과 무관하게 맞춘다 — 1초 보조 틱을 돌리고, 할 일이 없으면 스스로 멈춘다. */
function startEndTicker($: EngineInterface): void {
  endTicker?.cancel()
  endTicker = $.clock.every(END_TICK_MS, () => {
    void safe(async () => {
      const b = await read($, board)
      const lastNow = await read($, now)
      if (!b.recent.some(j => j.kind === 'bash' && j.endedAt !== undefined && lastNow - j.endedAt < RECENT_MS + END_TICK_MS)) {
        endTicker?.cancel()
        endTicker = undefined

        return
      }
      const t = await $.clock.now()
      await update($, now, () => t)
    })
  })
}

export function textOf(content: readonly { type: string; [field: string]: unknown }[]): string {
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

/** 백그라운드 출력 파일들의 수정 시각을 읽어 활동 시각에 반영한다. 종료 코드는 보지 않고 stdout 만 해석한다. 던지면 호출자의 safe 가 삼킨다. */
async function scanOutputs($: EngineInterface, paths: readonly string[], at: number): Promise<void> {
  const r = await $.process.run(['bash', '-c', STAT_SCRIPT, '_', ...paths], { timeoutMs: 3_000 })
  const ms = latestMtimeMs(r.stdout)
  if (ms !== null) await update($, board, b => withActivity(b, Math.min(ms, at))) // 미래 시각은 지금으로 자른다
}

/** 시작한 작업에 출력 경로를 적는다. 경로가 없으면 아무것도 하지 않는다. */
async function noteOutput($: EngineInterface, id: string, text: string | undefined): Promise<void> {
  const outputPath = outputPathOf(text)
  if (!outputPath) return
  await update($, board, b => ({ ...b, running: b.running.map(j => (j.id === id ? { ...j, outputPath } : j)) }))
}

/** 진행 패널의 세션 시작 — 관제판(console.tsx)의 session.start 가 엔진 동작 뒤에 부른다.
 *  엔진은 같은 이벤트를 matcher 없이 두 번 등록하는 것을 거부하므로 session.start 는 한 곳에만 둔다. */
// 진행 패널의 세션 값 — 모듈 변수는 재로드 때 새로 시작하고, registerProgress 가 다시 비운다.
let cwd = ''
let ticker: { cancel(): void } | undefined
let ciTicker: { cancel(): void } | undefined
let endTicker: { cancel(): void } | undefined
let isCiPolling = false
let gate: RefreshGate = { refreshing: false, again: false }

/** devFSD: PR 의 CI 잡을 한 번 읽어 board.ci 에 쓴다. 겹치면 건너뛰고, 실패는 조용히 비운다. */
async function pollCiOnce($: EngineInterface): Promise<void> {
  if (isCiPolling) return
  isCiPolling = true
  try {
    const ci = await pollCi($, cwd)
    await update($, board, b => ({ ...b, ci }))
  } catch {
    // 관찰만 — 표시가 비는 것으로 충분하다.
  } finally {
    isCiPolling = false
  }
}

export async function progressStart($: EngineInterface, cwdNow: string, ciOpt?: { watch: boolean; intervalSec: number }): Promise<void> {
    cwd = cwdNow
    ciTicker?.cancel()
    ciTicker = undefined
    endTicker?.cancel()
    endTicker = undefined
    if (ciOpt?.watch) {
      void pollCiOnce($)
      ciTicker = $.clock.every(ciOpt.intervalSec * 1000, () => void pollCiOnce($))
    } else {
      // 이전 세션이 남긴 CI 잡이 합산되지 않게 비운다.
      void safe(() => update($, board, b => (b.ci ? { ...b, ci: undefined } : b)))
    }
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
          const lastNow = await read($, now) // 저장된 시계 — clock.now() 를 새로 부르지 않는다
          const isRecentEnd = b.recent.some(j => j.kind === 'bash' && j.endedAt !== undefined && lastNow - j.endedAt < 61_000)
          if (b.running.length > 0 || b.working === true || isRecentEnd) {
            const t = await $.clock.now()
            await update($, now, () => t)
            const paths = b.running.flatMap(j => (j.outputPath ? [j.outputPath] : []))
            if (paths.length > 0) await scanOutputs($, paths, t)
          }
        })
      })
    })
    if (await isGoverned($, cwd)) void $.ui.open({ id: CONSOLE_PANE, title: CONSOLE_TITLE, columns: 66, rows: 8 })
    void refreshStatus($, cwd, gate)
}

export function registerProgress(on: Parameters<Register>[0]): void {
  cwd = ''
  ticker?.cancel()
  ticker = undefined
  ciTicker?.cancel()
  ciTicker = undefined
  endTicker?.cancel()
  endTicker = undefined
  isCiPolling = false
  gate = { refreshing: false, again: false }

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
    if (!isLaunched) {
      await safe(() => endJob($, e.tool_use_id, ran.deny !== undefined || ran.isError === true))
      void refreshStatus($, cwd, gate)
    } else {
      await safe(() => noteOutput($, e.tool_use_id, ran.text))
    }

    return ran
  }).catch(($, e, next) => next(e))

  // Background commands: done on their notification.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    if (e.agentId) return next(e)
    if (e.run_in_background !== true) {
      const done = await next(e)
      void refreshStatus($, cwd, gate)

      return done
    }
    await safe(async () => {
      const startedAt = await $.clock.now()
      await startJob($, {
        id: e.tool_use_id,
        kind: 'bash',
        label: e.description === undefined ? redact(e.command).slice(0, 40) : redact(e.description), // 비밀은 자르기 전에 가린다 — 카드·로그가 이 라벨을 그대로 쓴다
        detail: '백그라운드',
        startedAt,
      })
    })
    const ran = await next(e)
    if (ran.deny !== undefined) await safe(() => endJob($, e.tool_use_id, true))
    else await safe(() => noteOutput($, e.tool_use_id, ran.text))
    void refreshStatus($, cwd, gate)

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

    const ran = await next(e)
    if (stage) void refreshStatus($, cwd, gate)

    return ran
  }).catch(($, e, next) => next(e))

  for (const tool of REFRESH_TOOLS) {
    on('tool.call', { tool }, async ($, e, next) => {
      const ran = await next(e)
      if (!e.agentId) void refreshStatus($, cwd, gate)

      return ran
    }).catch(($, e, next) => next(e))
  }

  on('session.append', async ($, e, next) => {
    const stored = await next(e)
    if (!e.agentId && e.message.type === 'user') {
      const note = notificationOf(textOf(e.message.content))
      if (note) {
        await safe(async () => {
          const t = await $.clock.now() // update 콜백은 동기여야 하므로 시각을 먼저 읽는다
          await update($, board, b => withActivity(b, t))
        })
        await safe(() => endJob($, note.id, note.isFailed))
        void refreshStatus($, cwd, gate)
      }
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
        {b.stages && <Text>{b.stages.map(s => `${s.label}${s.mark}`).join(' ')}</Text>}
        {b.verify && <Text bold={b.verify !== '완료' && b.verify !== '검증 PASS'}>{b.verify}</Text>}
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
