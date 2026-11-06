// Ported from Claude Flightdeck (https://github.com/scasella/claude-flightdeck, v0.6.0)
// Copyright (c) 2026 Stephen Casella — MIT License. See NOTICE. Modified for devFSD.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderChildren } from 'claude-code'

import type { AgentCard, Architect, Bucket, Check, Gate, Layout, LogLine, Loop, Main, Roster, Turn, Usage, View } from '../types'
import {
  DEFAULT_ARCHITECT,
  addCard,
  resumeCard,
  DEFAULT_GATE,
  DEFAULT_MAIN,
  DEFAULT_ROSTER,
  DEFAULT_TURN,
  DEFAULT_USAGE,
  DEFAULT_VIEW,
  EDIT_TOOLS,
  SCHEMA_VERSION,
  afterCall,
  applyStep,
  bucketOf,
  cellWidth,
  piecesThatFit,
  cardTitle,
  afterCompactHooked,
  afterCompactRead,
  afterFillRead,
  afterResponse,
  claimCompactRead,
  compactMark,
  contextFill,
  faultKey,
  forgetCompactRead,
  titleLines,
  consultTimeline,
  describeInput,
  endConsult,
  fmtClock,
  fmtDuration,
  durationLabel,
  fmtTimer,
  fmtUsd,
  plural,
  gateSummary,
  gauge,
  isAdvising,
  isLoopActive,
  kTokens,
  lanes,
  limitLabel,
  limitOf,
  fmtResetIn,
  listOf,
  logRows,
  marksIn,
  momentOf,
  normalize,
  normalizeCard,
  normalizeGate,
  normalizeLog,
  noteTool,
  PALETTES,
  SVG_COLORS,
  parseConfig,
  stageProgress,
  prettyModel,
  promptLine,
  handbackOf,
  adviceLine,
  receiptOf,
  recordCheck,
  settleCheck,
  shorten,
  startConsult,
  stepSpeed,
  stepLoop,
  activityBadge,
  jobRow,
  oldestStart,
  gaugeColor,
  withActivity,
} from './core'
import type { Config, Panel } from './core'
// 이름·시간 글자색 — 어두운 바탕에서도 읽히게 core 의 SVG_COLORS.label 보다 밝게 둔다.
const SVG_LABEL = '#888780'

// devFSD: 진행 기록(FID·단계·verify)은 progress-pane 이 채우는 board 를 읽기만 한다.
import { notificationOf, progressStart, textOf } from './progress-pane'
import { ciLine, ciPending } from './ci-watch'
import type { Board, StageMark } from '../types'

// devFSD: progress-pane 이 쓰는 board 와 같은 상태(같은 ref·shape) — 여기서는 읽기만 한다.
// 검증기는 atom 을 읽는 파일 안에 그 정의가 있기를 요구한다.
const board = atom({ plugin: 'devfsd', key: 'board' } as const, { running: [], recent: [] } as Board, { shape: 'board-2' })

// devFSD: progress-pane 의 시계 atom 과 같은 ref·shape — 읽어 두면 시계가 돌 때 배지가 다시 그려진다.
const nowTick = atom({ plugin: 'devfsd', key: 'now' } as const, 0, { shape: 'now-1' })

const PANE = 'devfsd-console'
const TITLE = 'devFSD 관제판'


// ---------------------------------------------------------------- state

const meta = atom({ plugin: 'devfsd', key: 'meta' } as const, { schemaVersion: SCHEMA_VERSION })
const main = atom({ plugin: 'devfsd', key: 'main' } as const, DEFAULT_MAIN)
const usage = atom({ plugin: 'devfsd', key: 'usage' } as const, DEFAULT_USAGE)
const architect = atom({ plugin: 'devfsd', key: 'architect' } as const, DEFAULT_ARCHITECT)
const gate = atom({ plugin: 'devfsd', key: 'gate' } as const, DEFAULT_GATE)
const agents = atom({ plugin: 'devfsd', key: 'agents' } as const, [])
const loops = atom({ plugin: 'devfsd', key: 'loops' } as const, [])
const log = atom({ plugin: 'devfsd', key: 'log' } as const, [])
const turn = atom({ plugin: 'devfsd', key: 'turn' } as const, DEFAULT_TURN)
const receipt = atom({ plugin: 'devfsd', key: 'receipt' } as const, null)
const view = atom({ plugin: 'devfsd', key: 'view' } as const, DEFAULT_VIEW)
const roster = atom({ plugin: 'devfsd', key: 'roster' } as const, DEFAULT_ROSTER)

type ServerBlock = { type: string; id?: string; name?: string; tool_use_id?: string }

// Every read goes through these, so a value saved under an older shape still reads.
async function getMain($: EngineInterface): Promise<Main> {
  return normalize(DEFAULT_MAIN, await read($, main))
}
async function getUsage($: EngineInterface): Promise<Usage> {
  return normalize(DEFAULT_USAGE, await read($, usage))
}
async function getArchitect($: EngineInterface): Promise<Architect> {
  const a = normalize(DEFAULT_ARCHITECT, await read($, architect))
  return { ...a, consults: listOf(a.consults), ids: listOf(a.ids), seen: listOf(a.seen) }
}
async function getGate($: EngineInterface): Promise<Gate> {
  return normalizeGate(await read($, gate))
}
async function getCards($: EngineInterface): Promise<AgentCard[]> {
  return listOf<unknown>(await read($, agents)).map(normalizeCard)
}
async function getLoops($: EngineInterface): Promise<Loop[]> {
  return listOf<Loop>(await read($, loops))
}
async function getLog($: EngineInterface): Promise<LogLine[]> {
  return normalizeLog(await read($, log))
}
async function getTurn($: EngineInterface): Promise<Turn> {
  return normalize(DEFAULT_TURN, await read($, turn))
}
async function getView($: EngineInterface): Promise<View> {
  return normalize(DEFAULT_VIEW, await read($, view))
}
async function getRoster($: EngineInterface): Promise<Roster> {
  const r = normalize(DEFAULT_ROSTER, await read($, roster))
  return { architectTypes: listOf(r.architectTypes) }
}

/** 활동 시각을 올리고(선택) 메인 턴 열림 표시를 바꾼다. 관찰만 하므로 어떤 실패도 삼킨다. */
const touch = async ($: EngineInterface, working?: boolean): Promise<void> => {
  try {
    const at = await $.clock.now()
    const b = await read($, board)
    const next = withActivity(b, at)
    if (next === b && (working === undefined || b.working === working)) return
    await update($, board, cur => {
      const raised = withActivity(cur, at)

      return working === undefined || cur.working === working ? raised : { ...raised, working }
    })
  } catch {
    // 표시만 어긋날 뿐 도구 호출·턴은 그대로 간다.
  }
}

/** A stored shape older than this build's: drop what cannot be read, keep the rest. */
async function migrate($: EngineInterface) {
  const m = await read($, meta)
  if ((m?.schemaVersion ?? 0) >= SCHEMA_VERSION) return
  await update($, log, list => normalizeLog(list))
  await update($, agents, list => listOf<unknown>(list).map(normalizeCard))
  await update($, gate, g => normalizeGate(g))
  await update($, meta, () => ({ schemaVersion: SCHEMA_VERSION }))
}

async function say($: EngineInterface, who: string, text: string, kind: LogLine['kind'] = 'info', agentId: string | null = null) {
  const line: LogLine = { at: await $.clock.now(), who, text, kind, agentId }
  await update($, log, list => [...normalizeLog(list), line].slice(-60))
}

async function refreshStatus($: EngineInterface, cfg: Config) {
  if (!cfg.statusLine) return $.ui.status(undefined)
  const [u, a, g, cards] = await Promise.all([getUsage($), getArchitect($), getGate($), getCards($)])
  const running = cards.filter(c => c.status === 'running').length
  const s = gateSummary(g)
  const ctxFill = contextFill(u)
  const parts = [
    ctxFill.pct !== null ? `ctx ${Math.round(ctxFill.pct)}%` : null,
    cards.length > 0 ? `agents ${running}/${cards.length}` : null,
    a.consults.length > 0 || a.ids.length > 0 ? `${cfg.architectLabel.toLowerCase()} ${isAdvising(a) ? 'advising' : a.consults.length}` : null,
    s.deny > 0 ? `denied ${s.deny}` : null,
  ]
  // Only fields with something to say; with none, no status entry at all.
  const shown = parts.filter(Boolean)
  $.ui.status(shown.length > 0 ? shown.join(' · ') : undefined)
}

async function whoIs($: EngineInterface, agentId: string | undefined) {
  if (!agentId) return 'main'
  const card = (await getCards($)).find(c => c.id === agentId)
  return card ? shorten(cardTitle(card), 14) : 'agent'
}

async function consultStarted($: EngineInterface, cfg: Config, id: string, via: string) {
  const t = await getTurn($)
  const moment = momentOf(t)
  const at = await $.clock.now()
  await update($, architect, a => startConsult(normalize(DEFAULT_ARCHITECT, a), { id, at, moment, via }))
  if (moment === 'before done') await update($, turn, x => ({ ...normalize(DEFAULT_TURN, x), isReviewing: true }))
  await say($, cfg.architectLabel.toLowerCase(), cfg.moments ? `${moment} · ${via}` : `consulted · ${via}`, 'consult')
  await refreshStatus($, cfg)
}

async function consultEnded($: EngineInterface, cfg: Config, advice: string | null, id?: string) {
  const at = await $.clock.now()
  const first = advice?.split('\n').find(l => l.trim()) ?? null
  const text = first ? shorten(first.replace(/^[#>*\s-]+/, ''), 160) : null
  await update($, architect, a => endConsult(normalize(DEFAULT_ARCHITECT, a), at, text, id))
  await update($, turn, t => ({ ...normalize(DEFAULT_TURN, t), isReviewing: false }))
  await say($, cfg.architectLabel.toLowerCase(), text ? `advice: ${shorten(text, 60)}` : 'advice returned', 'consult')
  await refreshStatus($, cfg)
}

async function noteAdvice($: EngineInterface, cfg: Config, advice: string) {
  await update($, architect, x => ({ ...normalize(DEFAULT_ARCHITECT, x), lastAdvice: advice }))
  await say($, cfg.architectLabel.toLowerCase(), `advice: ${shorten(advice, 60)}`, 'consult')
}

async function isArchitectType($: EngineInterface, cfg: Config, type: string) {
  return cfg.architect.test(type) || (await getRoster($)).architectTypes.includes(type)
}

async function openPane($: EngineInterface, cfg: Config) {
  // columns apply when docked beside the transcript, rows when seated inline above the prompt.
  return $.ui.open({ id: PANE, title: TITLE, columns: cfg.paneColumns, rows: 8 })
}

async function resetAll($: EngineInterface) {
  await update($, main, m => ({ ...DEFAULT_MAIN, model: normalize(DEFAULT_MAIN, m).model, mode: normalize(DEFAULT_MAIN, m).mode }))
  await update($, architect, () => DEFAULT_ARCHITECT)
  await update($, gate, () => DEFAULT_GATE)
  await update($, agents, () => [])
  await update($, loops, () => [])
  await update($, log, () => [])
  await update($, turn, () => DEFAULT_TURN)
  await update($, receipt, () => null)
  await update($, view, () => DEFAULT_VIEW)
  // The context gauge waits for the next measurement rather than showing the pre-clear fill.
  await update($, usage, x => ({ ...normalize(DEFAULT_USAGE, x), pct: null, tokens: null }))
}

/**
 * Stores the compaction window for the model window `window`. A `summary` breakdown estimates locally
 * and sends no request; until the host gives one, the gauge stays on the model's window (afterCompactRead).
 */
async function readCompactWindow($: EngineInterface, window: number) {
  const r = await $.session.usage({ breakdown: 'summary' }).catch(() => null)
  await update($, usage, x => afterCompactRead(normalize(DEFAULT_USAGE, x), window, r?.context.breakdown))
}

/** The session's cost read fresh, not from the last measurement: the receipt subtracts two of these. */
async function costNow($: EngineInterface): Promise<number | null> {
  const u = await $.session.usage().catch(() => null)
  return u?.cost?.usd ?? null
}

async function noteMode($: EngineInterface, mode: string | undefined) {
  if (mode) await update($, main, m => (normalize(DEFAULT_MAIN, m).mode === mode ? normalize(DEFAULT_MAIN, m) : { ...normalize(DEFAULT_MAIN, m), mode }))
}

// ---------------------------------------------------------------- hooks

/** devFSD: session.start 는 여기 한 곳 — 엔진 동작 뒤에 진행 패널의 시작(progressStart)을 부른다. */
export function registerConsole(on: Parameters<Register>[0], options: Parameters<Register>[1]): void {
  const cfg = parseConfig(options)
  const C = PALETTES[cfg.palette]
  // tool.check carries no loop id; the tool.call around it does, keyed by the call's id.
  const callLoop = new Map<string, string | null>()

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'devfsd',
      description: 'devFSD 관제판 (live agent dashboard): open, close, reset, or set the layout',
      argumentHint: '[open|close|reset|layout auto|compact|wide|mini]',
    })
    await migrate($)
    // A host without usage (headless, an SDK host, a session not yet bound) just starts without it.
    const u = await $.session.usage().catch(() => null)
    // A resumed session has a fill to draw already: its compaction window is read now, not at its first
    // measurement. Any other start forgets the last reading (the setting may have changed) for that one to read.
    const resumedWindow = u && u.context.tokens !== undefined && u.context.window > 0 ? u.context.window : 0
    if (u) {
      await update($, usage, x => ({
        ...normalize(DEFAULT_USAGE, x),
        pct: u.context.percent ?? null,
        tokens: u.context.tokens ?? null,
        window: u.context.window,
        compactFor: resumedWindow,
        compactMisses: 0,
        hasFill: u.context.tokens !== undefined,
        costUsd: u.cost?.usd ?? null,
        limits: u.rateLimits.map(limitOf),
      }))
    }
    if (cfg.openOnStart) void openPane($, cfg).catch(() => undefined)
    await refreshStatus($, cfg)
    const done = await next(e)
    await progressStart($, e.cwd, { watch: cfg.ciWatch, intervalSec: cfg.ciIntervalSec })
    if (resumedWindow > 0) {
      await readCompactWindow($, resumedWindow)
      await refreshStatus($, cfg)
    }
    return done
  })

  on('session.end', async ($, e, next) => {
    if (e.reason === 'clear') {
      await resetAll($)
      await refreshStatus($, cfg)
    }
    // The process goes on in another conversation, whose first request may find no fill: no compaction.
    if (e.reason === 'clear' || e.reason === 'resume') await update($, usage, x => ({ ...normalize(DEFAULT_USAGE, x), hasFill: false }))
    return next(e)
  })

  on('command.run', { command: 'devfsd' }, async ($, e) => {
    const [verb = 'open', arg = ''] = e.args.trim().split(/\s+/)
    if (verb === 'close') {
      await $.ui.close({ id: PANE })
      return { text: 'devFSD 관제판 closed.' }
    }
    if (verb === 'reset') {
      await resetAll($)
      await refreshStatus($, cfg)
      return { text: 'devFSD 관제판 reset.' }
    }
    if (verb === 'layout') {
      const layout: Layout | null = arg === 'compact' || arg === 'wide' || arg === 'auto' || arg === 'mini' ? arg : null
      if (!layout) return { text: 'Usage: /devfsd layout auto|compact|wide|mini' }
      await update($, view, v => ({ ...normalize(DEFAULT_VIEW, v), layout }))
      const opened = await openPane($, cfg)
      return { text: opened.isPlaced ? `devFSD 관제판 layout: ${layout}.` : `Layout set to ${layout}; the pane is not shown yet: ${opened.reason}` }
    }
    const opened = await openPane($, cfg)
    if (!opened.isPlaced) return { text: `devFSD 관제판 is not shown yet: ${opened.reason}` }
    return { text: 'devFSD 관제판 opened. Focus it with ctrl+x tab; 1-6 expand cards, f/s/o open the gate rows.' }
  })

  on('classic.UserPromptSubmit', async ($, e, next) => {
    await noteMode($, e.permission_mode)
    return next(e)
  }).catch(($, e, next) => next(e)) // devFSD: 관제판은 관찰만 한다 — 처리기가 던져도 도구 호출·프롬프트는 통과한다

  on('agent.offer', async ($, e, next) => {
    const offered = await next(e)
    if (cfg.architect.test(e.agent) || (cfg.matchDescriptions && cfg.architect.test(e.description))) {
      await update($, roster, r => {
        const x = normalize(DEFAULT_ROSTER, r)
        return x.architectTypes.includes(e.agent) ? x : { architectTypes: [...listOf<string>(x.architectTypes), e.agent].slice(-20) }
      })
    }
    return offered
  })

  on('turn.start', async ($, e, next) => {
    // A subagent's turn (its spawn, or a resume by SendMessage) is its card's, not the main turn's.
    if (e.agentId !== undefined) return next(e)
    await touch($, true)
    const [now, cost] = await Promise.all([$.clock.now(), costNow($)])
    await update($, turn, () => ({ ...DEFAULT_TURN, startedAt: now, costAtStart: cost }))
    await update($, main, m => ({ ...normalize(DEFAULT_MAIN, m), isRunning: true }))
    // A background architect's report reaches the main loop as the text opening this turn. The
    // SubagentHandback tool call (in tool.call) normally carries it first; this is the fallback.
    const back = e.text ? handbackOf(e.text) : null
    const a = back ? await getArchitect($) : null
    if (back && a && a.ids.includes(back.from)) {
      const advice = adviceLine(back.body)
      if (advice && advice !== a.lastAdvice) await noteAdvice($, cfg, advice)
    } else if (e.text) {
      const p = promptLine(e.text)
      await say($, p.who, p.text)
    }
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    // The main loop's model is known when its request starts; a long first request shouldn't read "—".
    if (!e.agentId) {
      await touch($)
      let isNewModel = false
      await update($, main, m => {
        const x = normalize(DEFAULT_MAIN, m)
        isNewModel = x.model !== '' && x.model !== e.model
        return { ...x, model: e.model, effort: String(e.effort ?? x.effort), steps: x.steps + 1 }
      })
      if (isNewModel) await update($, usage, x => forgetCompactRead(normalize(DEFAULT_USAGE, x)))
      // Under the built-in guard session.compact never runs here. A request that finds the context
      // emptied after a response came back follows a compaction: counted as an estimate (afterFillRead).
      const [u0, live, at] = await Promise.all([getUsage($), $.session.usage().catch(() => null), $.clock.now()])
      let hasFill = u0.hasFill
      if (live) {
        const read = afterFillRead(u0, live.context.tokens !== undefined, at)
        hasFill = read.usage.hasFill
        let isCompaction = false
        if (read.usage !== u0) {
          await update($, usage, x => {
            const r = afterFillRead(normalize(DEFAULT_USAGE, x), live.context.tokens !== undefined, at)
            isCompaction = r.isCompaction
            return r.usage
          })
        }
        if (isCompaction) await say($, 'main', 'context compacted (estimated)')
      }
      // Time the response as it passes: its first piece that is neither the engine's envelope nor the
      // stop. One clock read in the stream and nothing stored until it has ended.
      const sentAt = await $.clock.now()
      let firstAt: number | null = null
      const s = next(e)
      for await (const c of s) {
        if (firstAt === null && c.kind !== 'engine' && c.kind !== 'stop') firstAt = await $.clock.now()
        yield c
      }
      const result = await s.result
      const speed = result.usage ? stepSpeed(sentAt, firstAt) : null
      if (speed) await update($, main, m => ({ ...normalize(DEFAULT_MAIN, m), speed }))
      // Marked here, not at the next request: two compactions can come with one response between them.
      if (result.usage && !hasFill) await update($, usage, x => afterResponse(normalize(DEFAULT_USAGE, x)))
      return result
    }
    const id = e.agentId
    // A step from an agent whose card finished means it was resumed (SendMessage): it runs again.
    const before = (await getCards($)).find(c => c.id === id)
    if (before && before.status !== 'running') {
      // Flipped in the write: a resume its agent.spawn already logged is not logged again.
      let isResumed = false
      await update($, agents, list =>
        listOf<unknown>(list)
          .map(normalizeCard)
          .map(c => {
            if (c.id !== id || c.status === 'running') return c
            isResumed = true
            return resumeCard(c)
          }),
      )
      if (isResumed) {
        await say($, await whoIs($, id), 'resumed', 'info', id)
        await refreshStatus($, cfg)
      }
    }
    const result = yield* next(e)
    const [cards, a] = await Promise.all([getCards($), getArchitect($)])
    if (cards.some(c => c.id === id)) {
      const step = { model: e.model, usage: result.usage, stopReason: result.stopReason }
      await update($, agents, list => listOf<unknown>(list).map(normalizeCard).map(c => (c.id === id ? applyStep(c, step) : c)))
      if (result.stopReason === 'max_tokens') await say($, await whoIs($, id), 'hit max_tokens', 'error', id)
    } else if (!a.ids.includes(id)) {
      const now = await $.clock.now()
      await update($, loops, l => stepLoop(listOf<Loop>(l), id, now))
    }
    return result
  })

  on('session.measure', async ($, e, next) => {
    // The compaction window is read once per model window, not on every measurement (a breakdown
    // estimates every category each time): claimed here, in the same write, so no two reads overlap.
    let isStale = false
    await update($, usage, x => {
      const claim = claimCompactRead(normalize(DEFAULT_USAGE, x), e.context.window)
      isStale = claim.isClaimed
      return {
        ...claim.usage,
        pct: e.context.percent ?? null,
        tokens: e.context.tokens ?? null,
        window: e.context.window,
        costUsd: e.cost?.usd ?? null,
        limits: e.rateLimits.map(limitOf),
      }
    })
    if (e.changed.includes('context')) await refreshStatus($, cfg)
    const done = await next(e)
    if (isStale) {
      await readCompactWindow($, e.context.window)
      await refreshStatus($, cfg)
    }
    return done
  })

  on('session.compact', async ($, e, next) => {
    // Any compaction reaching this hook, a subagent's or a precompute too, means the guard isn't in the way.
    if (!(await getUsage($)).isCompactHooked) await update($, usage, x => afterCompactHooked(normalize(DEFAULT_USAGE, x)))
    const done = await next(e)
    // A skip is a veto, by a plugin or a blocking PreCompact hook: the conversation stays as it was.
    if (!done.skip && !e.agentId && e.trigger !== 'precompute') {
      const now = await $.clock.now()
      await update($, usage, x => {
        const u = normalize(DEFAULT_USAGE, x)
        return { ...u, compactions: u.compactions + 1, lastCompactAt: now }
      })
      await say($, 'main', `context compacted (${e.trigger})`)
    }
    return done
  })

  on('tool.check', async ($, e, next) => {
    const verdict = await next(e)
    if (e.tool_use_id) {
      const check: Check = {
        id: e.tool_use_id,
        tool: e.tool,
        bucket: bucketOf(e.tool),
        verdict: verdict.decision === 'allow' ? 'rule' : verdict.decision,
        inSubagent: Boolean(callLoop.get(e.tool_use_id)),
        detail: shorten(describeInput(e.tool, e.input), 90),
        at: await $.clock.now(),
      }
      await update($, gate, g => recordCheck(normalizeGate(g), check))
      // The status line updates when the call settles; only a refusal ends here.
      if (verdict.decision === 'deny') {
        await say($, 'gate', `denied by rule · ${check.detail}`, 'error')
        await refreshStatus($, cfg)
      }
    }
    return verdict
  }).catch(($, e, next) => next(e)) // devFSD: 관제판은 관찰만 한다 — 처리기가 던져도 도구 호출·프롬프트는 통과한다

  on('tool.call', async ($, e, next) => {
    callLoop.set(e.tool_use_id, e.agentId ?? null)
    await touch($)
    const ran = await next(e).finally(() => callLoop.delete(e.tool_use_id))
    const didRun = ran.deny === undefined
    // Settle this call's pending ask, if it had one; skip the write (and the redraw) otherwise.
    const g0 = await getGate($)
    const isSettled = settleCheck(g0, e.tool_use_id, didRun) !== g0
    if (isSettled) await update($, gate, g => settleCheck(normalizeGate(g), e.tool_use_id, didRun))
    // A background agent hands its report back through this tool; an architect's report is its advice.
    if (String(e.tool) === 'SubagentHandback') {
      const message = (e as unknown as { message?: unknown }).message
      const a = e.agentId ? await getArchitect($) : null
      if (a && e.agentId && a.ids.includes(e.agentId) && typeof message === 'string') {
        const advice = adviceLine(message)
        if (advice && advice !== a.lastAdvice) await noteAdvice($, cfg, advice)
      }
      return ran
    }
    if (e.tool === 'Agent') {
      if (isSettled) await refreshStatus($, cfg)
      return ran
    }
    const hasFailed = didRun && ran.isError === true
    const isEdit = !hasFailed && didRun && EDIT_TOOLS.has(e.tool)
    const t0 = await getTurn($)
    if (isEdit || hasFailed || (!e.agentId && t0.errorStreak > 0)) {
      await update($, turn, t => afterCall(normalize(DEFAULT_TURN, t), { inSubagent: Boolean(e.agentId), hasFailed, isEdit }))
    }
    const text = shorten(describeInput(e.tool, e), 64)
    if (e.agentId) {
      const id = e.agentId
      await update($, agents, list =>
        listOf<unknown>(list)
          .map(normalizeCard)
          .map(c => (c.id === id ? noteTool(c, { tool: e.tool, text, isError: hasFailed || ran.deny !== undefined }) : c)),
      )
    }
    // The log keeps what is worth a glance: refusals, errors and edits; the rest is on the cards.
    if (ran.deny !== undefined) await say($, await whoIs($, e.agentId), `${text}  denied`, 'error', e.agentId ?? null)
    else if (hasFailed) await say($, await whoIs($, e.agentId), `✗ ${text}`, 'error', e.agentId ?? null)
    else if (isEdit) await say($, await whoIs($, e.agentId), text, 'info', e.agentId ?? null)
    if (isSettled || !didRun) await refreshStatus($, cfg)
    return ran
  }).catch(($, e, next) => next(e)) // devFSD: 관제판은 관찰만 한다 — 처리기가 던져도 도구 호출·프롬프트는 통과한다

  // A server-side review tool never reaches tool.call: it shows only in the assistant's rows.
  // Only response rows carry them. A managed plugin may pass user plugins over on other doors.
  on('session.append', { door: 'response' }, async ($, e, next) => {
    if (!e.agentId && e.message.type === 'assistant') {
      const a = await getArchitect($)
      // Consults this row opened: their result may be in the same row, after the stale read above.
      const opened = new Set<string>()
      for (const block of e.message.content as unknown as readonly ServerBlock[]) {
        if (block.type === 'server_tool_use' && block.name && block.id && cfg.architect.test(block.name)) {
          if (a.seen.includes(block.id)) continue
          const id = block.id
          await update($, architect, x => {
            const y = normalize(DEFAULT_ARCHITECT, x)
            return { ...y, seen: [...listOf<string>(y.seen), id].slice(-60) }
          })
          opened.add(id)
          await consultStarted($, cfg, id, `${block.name} tool`)
        } else if (block.type.endsWith('_tool_result') && block.tool_use_id) {
          const id = block.tool_use_id
          const isOpen = opened.has(id) || (await getArchitect($)).consults.some(c => c.id === id && c.endAt === null)
          if (isOpen) await consultEnded($, cfg, null, id)
        }
      }
    }
    return next(e)
  }).catch(($, e, next) => next(e)) // devFSD: 관제판은 관찰만 한다 — 처리기가 던져도 도구 호출·프롬프트는 통과한다

  // devFSD: 백그라운드 작업 종료 알림 → 로그 한 줄. 종료 처리는 progress-pane 이 하고, 여기서는 board 를 읽어 기록만 한다.
  // 처리기 순서와 무관하게 running·recent 둘 다 본다. 같은 id 는 한 번만 — 실패해도 원 호출은 그대로 통과한다.
  // 종료 알림은 delivery 문으로 들어온다(progress-pane 의 처리기와 같은 행) — 엔진이 matcher 없는 같은 이벤트 둘째 등록을 막으므로 문으로 좁힌다.
  const endLogged = new Set<string>()
  on('session.append', { door: 'delivery' }, async ($, e, next) => {
    const stored = await next(e)
    if (e.agentId || e.message.type !== 'user') return stored
    const note = notificationOf(textOf(e.message.content))
    if (!note || endLogged.has(note.id)) return stored
    const b = await read($, board)
    const job = [...b.running, ...b.recent].find(j => j.id === note.id)
    if (!job) return stored
    const endedAt = job.endedAt ?? (await $.clock.now())
    endLogged.add(note.id)
    await say($, '↻ bg', `${note.isFailed ? '✗' : '✓'} ${job.label.trim() || job.id} · ${durationLabel(endedAt - job.startedAt, false)}`, note.isFailed ? 'error' : 'info')
    return stored
  }).catch(($, e, next) => next(e)) // devFSD: 관제판은 관찰만 한다 — 처리기가 던져도 도구 호출·프롬프트는 통과한다

  on('agent.spawn', async ($, e, next) => {
    await touch($)
    const started = await next(e)
    if (!e.parentAgentId) await noteMode($, e.permissionMode)
    if (started.deny !== undefined || !started.agentId) return started
    const id = started.agentId
    if (await isArchitectType($, cfg, e.subagentType)) {
      await update($, architect, a => {
        const x = normalize(DEFAULT_ARCHITECT, a)
        return { ...x, ids: [...listOf<string>(x.ids), id].slice(-40) }
      })
      await update($, loops, l => listOf<Loop>(l).filter(x => x.id !== id))
      await consultStarted($, cfg, id, e.subagentType.split(':').pop() ?? 'agent')
      return started
    }
    const card: AgentCard = {
      ...normalizeCard({}),
      id,
      type: e.name ?? e.subagentType,
      model: started.model,
      description: e.description,
      spawnedAt: await $.clock.now(),
    }
    // Decided in the write: a resume whose first step already put its card back to running is not logged again.
    let isNew = true
    let isResumed = false
    await update($, agents, list => {
      const cards = listOf<unknown>(list).map(normalizeCard)
      const known = cards.find(c => c.id === id)
      isNew = known === undefined
      isResumed = known !== undefined && known.status !== 'running'
      return addCard(cards, card)
    })
    await update($, loops, l => listOf<Loop>(l).filter(x => x.id !== id))
    if (isNew || isResumed) await say($, shorten(cardTitle(card), 12), isNew ? `spawned · ${card.type}` : 'resumed', 'info', id)
    await refreshStatus($, cfg)
    return started
  }).catch(($, e, next) => next(e)) // devFSD: 관제판은 관찰만 한다 — 처리기가 던져도 도구 호출·프롬프트는 통과한다

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    const id = e.agentId
    const now = await $.clock.now()
    if (!id) {
      const [t, cards, cost] = await Promise.all([getTurn($), getCards($), costNow($)])
      const r = receiptOf(t, {
        durationMs: e.durationMs,
        agentsSince: cards.filter(c => c.spawnedAt >= t.startedAt).length,
        costNow: cost,
        reason: e.reason,
      })
      await update($, receipt, () => r)
      await update($, main, m => ({ ...normalize(DEFAULT_MAIN, m), isRunning: false }))
      await touch($, false)
      await refreshStatus($, cfg)
      return done
    }
    if ((await getArchitect($)).ids.includes(id)) {
      await consultEnded($, cfg, e.answer, id)
      return done
    }
    const cards = await getCards($)
    if (cards.some(c => c.id === id)) {
      const status = e.reason === 'answer' ? 'done' : e.reason === 'aborted' ? 'stopped' : 'failed'
      await update($, agents, list =>
        listOf<unknown>(list)
          .map(normalizeCard)
          .map(c => (c.id === id ? { ...c, status, endedAt: now, answer: shorten(e.answer, 400) } : c)),
      )
      // This run's own length: a resumed agent's card clock also spans the idle time between runs.
      const took = fmtDuration(e.durationMs)
      await say($, await whoIs($, id), status === 'done' ? `done · ${took}` : status, status === 'done' ? 'done' : 'error', id)
    } else {
      await update($, loops, l => listOf<Loop>(l).map(x => (x.id === id ? { ...x, isDone: true, lastAt: now } : x)))
    }
    await refreshStatus($, cfg)
    return done
  })

  // ---------------------------------------------------------------- drawing

  // After a surface module faults on a surface, this load draws it there as plain text; the other
  // module, and other surfaces, keep theirs. Keyed by faultKey: `desktop:rail.tsx`.
  const faulted = new Set<string>()
  on('ui.fault', async ($, e, next) => {
    const key = faultKey(e.surface, e.module)
    if (e.requestId === PANE && !faulted.has(key)) {
      faulted.add(key)
      $.ui.log(`devfsd: ${e.module} faulted on ${e.surface} (${e.phase}: ${e.reason}); drawing it without animation`)
      $.ui.invalidate('ui.render')
    }
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const els = $.ui.resolve(e)
    const { Box, Text, Button } = els
    const hasClient = 'Client' in els
    const hasRail = hasClient && !faulted.has(faultKey(e.surface, 'rail.tsx'))
    const hasClock = hasClient && !faulted.has(faultKey(e.surface, 'elapsed.tsx'))
    const [m, u, a, g, cards, lp, lines, t, r, v, now, b] = await Promise.all([
      getMain($),
      getUsage($),
      getArchitect($),
      getGate($),
      getCards($),
      getLoops($),
      getLog($),
      getTurn($),
      read($, receipt),
      getView($),
      $.clock.now(),
      read($, board),
      read($, nowTick), // 구독만 — 값은 쓰지 않는다
    ])
    // The body's own width, down to the narrowest dock Claude Code seats (24): a wider drawing is cut off at the frame.
    const W = Math.max(24, e.props.bodyColumns)
    // 메인 턴은 쉬지만 백그라운드 작업(또는 CI 대기)이 도는 중 — 완전한 idle 과 구분해 보인다.
    const bgTotal = b.running.length + ciPending(b.ci)
    // 배지의 BG N 도 헤더·카드와 같은 개수(실행 중 작업 + CI 대기)를 센다.
    const badge = activityBadge({ jobs: bgTotal, isRunning: m.isRunning, activityAt: b.activityAt, now, compact: W < 60, since: oldestStart(b.running) })
    const isWaiting = !m.isRunning && bgTotal > 0
    // 끝난 지 1분 안의 백그라운드 명령(bash)만 — 에이전트 종료는 agents 패널의 몫이다.
    const endedJobs = b.recent.filter(j => j.kind === 'bash' && j.endedAt !== undefined && now - j.endedAt < 60_000).slice(0, 3)
    const badgeColor = badge?.stalled ? C.warn : C.dim
    const layout = v.layout ?? cfg.layout
    const modelName = prettyModel(m.model)
    const viewed = e.props.view?.agentId ?? null
    const advising = isAdvising(a)
    const running = cards.filter(c => c.status === 'running')
    const showArchitect = a.consults.length > 0 || a.ids.length > 0
    const motion = cfg.motion && hasRail
    // A panel with nothing to show yet takes no room: most sessions never spawn an agent.
    const isEmpty: Record<Panel, boolean> = {
      // FID 가 없어도 BG·CI 가 있으면 카드를 BG 구역만으로 그린다.
      fid: !b.fid && bgTotal === 0 && !ciLine(b.ci),
      main: false,
      architect: !showArchitect,
      // GATE 는 opt-in — 설정 panels 에 gate 를 넣은 사람만, 그 안에서도 기록이 있을 때만 그린다.
      gate: !cfg.panels.includes('gate') || (g.recent.length === 0 && gateSummary(g).total === 0),
      agents: cards.length === 0,
      // receipt·loops 는 별도 패널이 아니다 — receipt 는 main 넷째 줄로, loops 는 agents 패널로 흡수(설정에 적어도 그리지 않는다).
      loops: true,
      receipt: true,
      log: false,
    }
    // main 이 맨 위, GATE 는 session log 바로 위, log 가 맨 아래 — 나머지는 설정 순서.
    const order = [
      ...cfg.panels.filter(p => p === 'main'),
      ...cfg.panels.filter(p => p !== 'main' && p !== 'gate' && p !== 'log'),
      ...cfg.panels.filter(p => p === 'gate'),
      ...cfg.panels.filter(p => p === 'log'),
    ].filter(p => !isEmpty[p])
    const decider = m.mode === 'auto' ? 'classifier' : 'you'

    // A connector between panels: animated while its flow is live, a dim line otherwise.
    const rail = (key: string, active: boolean, color: string, width: number, marks: number[] = [], isMerge = false) =>
      motion ? (
        <els.Client
          key={key}
          module="./rail.tsx"
          width={width}
          height={1}
          props={{ active, width, color, dim: C.faint, marks, isMerge }}
        />
      ) : (
        <Text color={C.faint} mono>
          {'─'.repeat(Math.max(1, width))}
        </Text>
      )

    // A start time of 0 is unknown (state saved before it was recorded): no clock, not decades.
    const clock = (key: string, since: number, endAt: number | null, color: string) =>
      since <= 0 ? (
        <Text color={color}>—</Text>
      ) : hasClock ? (
        <els.Client key={key} module="./elapsed.tsx" props={{ since, now, endAt, color }} />
      ) : (
        <Text color={color}>{fmtTimer((endAt ?? now) - since)}</Text>
      )

    const isTerminal = e.surface === 'terminal'
    // A row of marks (gate checks, loop dots), sized by `marksIn`. Should a surface draw them wider
    // still, the row is cut at its box rather than running past it.
    const markRow = (marks: RenderChildren, lead = 0) => (
      <Box overflow="hidden" {...(lead ? { marginLeft: lead } : {})}>
        <Text wrap="truncate-start">{marks}</Text>
      </Box>
    )

    // A line of coloured pieces, drawn as a row of boxes the way the log draws its lines. A Text nesting
    // coloured Texts truncates as one line in a terminal, but the desktop app wraps each nested piece on its
    // own, lays truncating ones out as blocks of their own, and collapses runs of spaces. So pieces sit `gap`
    // cells apart (a piece's `lead` adds more), each keeps its width, and pieces that don't fit in `room` are
    // left out from the end; or a piece marked `fill` (one span) truncates to what the others leave.
    type Span = { text: string; color?: string; dim?: boolean; bold?: boolean }
    type Piece = { spans: Span[]; lead?: number; fill?: boolean }
    const styleOf = (s: Span) => ({ ...(s.color ? { color: s.color } : {}), ...(s.dim ? { dimColor: true } : {}), ...(s.bold ? { bold: true } : {}) })
    const widthOf = (p: Piece) => p.spans.reduce((n, s) => n + cellWidth(s.text), 0)
    const line = (pieces: (Piece | null)[], room: number, gap = 1, justify?: 'center') => {
      const all = pieces.filter((p): p is Piece => p !== null)
      const shown = all.some(p => p.fill) ? all : all.slice(0, piecesThatFit(all.map(p => ({ width: widthOf(p), lead: p.lead })), room, gap))
      return (
        <Box width={room} columnGap={gap} overflow="hidden" {...(justify ? { justifyContent: justify } : {})}>
          {shown.map(p => {
            const lead = p.lead ? { marginLeft: p.lead } : {}
            if (p.fill && p.spans[0]) {
              return (
                <Text {...styleOf(p.spans[0])} wrap="truncate">
                  {p.spans[0].text}
                </Text>
              )
            }
            return (
              <Box flexShrink={0} {...lead}>
                {p.spans.length === 1 && p.spans[0] ? <Text {...styleOf(p.spans[0])}>{p.spans[0].text}</Text> : <Text>{p.spans.map(s => <Text {...styleOf(s)}>{s.text}</Text>)}</Text>}
              </Box>
            )
          })}
        </Box>
      )
    }

    // ---- main: 네 줄 — 제목+상태 · ctx 게이지 | effort·mode · 비용 | 사용 한도 · 마지막 턴(receipt)
    const ctxFill = contextFill(u)
    const ctxGauge = ctxFill.pct !== null ? gauge(ctxFill.pct, 10) : null
    const ctxColor = ctxFill.pct !== null ? gaugeColor(ctxFill.pct, C) : C.main
    const waitSince = oldestStart(b.running)
    const mainRows = (w: number) => {
      // 비용 증분: 턴 진행 중이면 시작 이후 쌓인 값, 끝났으면 마지막 턴의 값.
      const delta = m.isRunning ? (u.costUsd !== null && t.costAtStart !== null && u.costUsd - t.costAtStart >= 0.005 ? u.costUsd - t.costAtStart : null) : (r?.costDelta ?? null)
      const state = m.isRunning ? '● working' : isWaiting ? `◌ 대기${waitSince !== undefined && waitSince > 0 ? ` ${fmtDuration(now - waitSince)}` : ''}` : '○ idle'
      return [
        <Box justifyContent="space-between">
          <Text color={C.main} bold wrap="truncate">
            {modelName} · main
          </Text>
          <Box flexShrink={0} columnGap={1}>
            <Text color={m.isRunning || isWaiting ? C.main : C.dim} bold={m.isRunning}>{state}</Text>
            {badge && W >= 40 ? <Text color={badgeColor}>{`· ${badge.text}`}</Text> : null}
          </Box>
        </Box>,
        line(
          [
            ctxGauge
              ? {
                  spans: [
                    { text: 'ctx ', dim: true },
                    { text: ctxGauge.on, color: ctxColor },
                    { text: ctxGauge.off, color: C.faint },
                    { text: ` ${Math.round(ctxFill.pct ?? 0)}%`, bold: true },
                  ],
                }
              : null,
            ctxGauge && u.tokens !== null ? { spans: [{ text: `${kTokens(u.tokens)}/${kTokens(ctxFill.window)}`, dim: true }] } : null,
            u.compactions > 0 ? { spans: [{ text: compactMark(u), color: C.amber }], lead: 1 } : null,
            // 오른쪽 — 좁으면 먼저 빠진다.
            { spans: [{ text: `effort ${m.effort || '—'}${m.mode ? ` · mode ${m.mode}` : ''}`, dim: true }], lead: 1 },
            // Left out first when the line is short; the ~ in the mark still says it.
            u.compactions > 0 && u.isCompactEstimate ? { spans: [{ text: '(estimated)', color: C.dim }] } : null,
          ],
          w - 4,
        ),
        u.costUsd !== null || u.limits.length > 0
          ? line(
              [
                u.costUsd !== null
                  ? { spans: [{ text: fmtUsd(u.costUsd), color: C.text }, ...(delta !== null ? [{ text: ` (+${fmtUsd(delta)})`, dim: true }] : [])] }
                  : null,
                ...u.limits.slice(0, 2).map((l, i): Piece => {
                  const lg = gauge(l.pct, 5)
                  // The time to each reset where the line has room for it: both windows fit from 56 columns,
                  // so a wide pane's half column (59 at 120) has them; a window that doesn't fit is left out.
                  const resetIn = w >= 56 ? fmtResetIn(l.resetsAt, now) : ''
                  return {
                    lead: i > 0 ? 1 : u.costUsd !== null ? 2 : 0,
                    spans: [
                      { text: `${limitLabel(l.kind)} `, dim: true },
                      { text: lg.on, color: gaugeColor(l.pct, C) },
                      { text: lg.off, color: C.faint },
                      { text: ` ${Math.round(l.pct)}%${resetIn ? ` resets ${resetIn}` : ''}`, dim: true },
                    ],
                  }
                }),
              ],
              w - 4,
            )
          : null,
        m.isRunning ? (
          <Box width={w - 4} columnGap={1} overflow="hidden">
            <Text color={C.main} wrap="truncate">● turn</Text>
            <Box flexShrink={0}>{clock('turn-clock', t.startedAt, null, C.main)}</Box>
            {w >= 60 ? <Text dimColor wrap="truncate">{`· ${plural(t.edits, 'edit')} · ${plural(t.errors, 'error')}`}</Text> : null}
          </Box>
        ) : r ? (
          line(
            [
              { spans: [{ text: r.reason === 'answer' ? '✓' : '✗', color: r.reason === 'answer' ? C.gate : C.warn }] },
              {
                spans: [{ text: `last turn ${fmtDuration(r.durationMs)} · ${plural(r.agents, 'agent')} · ${plural(r.edits, 'edit')} · ${plural(r.errors, 'error')}` }],
                fill: true,
              },
              r.costDelta !== null ? { spans: [{ text: `· +${fmtUsd(r.costDelta)}`, color: C.main }] } : null,
            ],
            w - 4,
          )
        ) : null,
      ].filter(row => row !== null)
    }
    const mainPanel = (w: number) => (
      <Box flexDirection="column" borderStyle="round" borderColor={C.main} paddingX={1} width={w}>
        {mainRows(w)}
      </Box>
    )

    // ---- architect
    const lastConsult = a.consults[a.consults.length - 1]
    const architectPanel = (w: number) => {
      // Both ends are anchors (the first consult, now): should it run past its box, it asks to lose the middle.
      const tl = consultTimeline(a, now, Math.max(8, w - 4))
      return (
        <Box flexDirection="column" borderStyle="round" borderColor={C.arch} paddingX={1} width={w}>
          <Box justifyContent="space-between">
            <Text color={C.arch} bold wrap="truncate">
              {cfg.architectLabel} · {advising ? 'advising' : 'on call'}
            </Text>
            <Box flexShrink={0}>
              <Text>
                <Text dimColor>consults </Text>
                <Text color={C.arch} bold>
                  {a.consults.length}
                </Text>
              </Text>
            </Box>
          </Box>
          <Text color={C.arch} wrap="truncate-middle">
            {tl}
          </Text>
          {lastConsult ? (
            <Text dimColor wrap="truncate">
              {advising
                ? `consulting since ${fmtClock(lastConsult.at)}`
                : `last ${fmtDuration(now - (lastConsult.endAt ?? lastConsult.at))} ago · took ${fmtDuration((lastConsult.endAt ?? now) - lastConsult.at)}`}
            </Text>
          ) : (
            <Text dimColor>not consulted yet</Text>
          )}
          {cfg.moments ? (
            <Box flexWrap="wrap" columnGap={2}>
              {(['before a plan', 'error repeats', 'before done'] as const).map(mo => {
                const isOn = lastConsult?.moment === mo
                return (
                  <Text color={isOn ? C.arch : C.dim} bold={isOn}>
                    {isOn ? '◆' : '◇'} {mo}
                  </Text>
                )
              })}
              <Text color={C.dim}>(inferred)</Text>
            </Box>
          ) : null}
          {a.lastAdvice ? (
            <Text color={C.arch} wrap="truncate">
              » {a.lastAdvice}
            </Text>
          ) : null}
        </Box>
      )
    }

    // ---- gate
    const s = gateSummary(g)
    const verdictColor = (c: Check) =>
      c.verdict === 'rule' ? C.gate : c.verdict === 'cleared' ? C.cleared : c.verdict === 'ask' ? C.amber : C.warn
    const checkMark = (c: Check) => (
      <Text color={verdictColor(c)} dimColor={c.inSubagent}>
        {c.verdict === 'deny' ? '✗' : '■'}
      </Text>
    )
    const gatePanel = (w: number) => {
      const strip = g.recent.slice(-Math.max(8, marksIn(w - 4, isTerminal)))
      const open = v.gateOpen
      // The totals in words where they all fit, in numbers alone where they don't: the colours say which is which.
      const totalsOf = (isShort: boolean): Piece[] => [
        { spans: [{ text: '■', color: C.gate }, { text: isShort ? ` ${s.rule}` : ` ${s.rule} allowed`, dim: true }] },
        { spans: [{ text: '■', color: C.cleared }, { text: isShort ? ` ${s.cleared}` : ` ${s.cleared} ${decider}`, dim: true }] },
        ...(s.ask > 0 ? [{ spans: [{ text: isShort ? `■ ${s.ask}` : `■ ${s.ask} pending`, color: C.amber }] }] : []),
        { spans: [{ text: isShort ? `✗ ${s.deny}` : `✗ ${s.deny} denied`, color: s.deny > 0 ? C.warn : C.dim }] },
      ]
      const words = totalsOf(false)
      const isShort = piecesThatFit(words.map(p => ({ width: widthOf(p) })), w - 4, 2) < words.length
      const totals = isShort ? totalsOf(true) : words
      return (
        <Box flexDirection="column" borderStyle="round" borderColor={C.gate} paddingX={1} width={w}>
          <Box justifyContent="space-between">
            <Text color={C.gate} bold wrap="truncate">
              {cfg.gateLabel} · permissions
            </Text>
            <Box flexShrink={0}>
              <Text dimColor>{`${s.total} checks`}</Text>
            </Box>
          </Box>
          {strip.length === 0 ? <Text color={C.dim}>no checks yet</Text> : markRow(strip.map(checkMark))}
          {line([...totals, !isShort && w >= 80 && g.recent.some(c => c.inSubagent) ? { spans: [{ text: 'dim: in subagents', color: C.dim }] } : null], w - 4, 2)}
          {/* Below about 44 columns the three rows' buttons take two lines rather than run past the box. */}
          <Box columnGap={2} flexWrap="wrap">
            {(['file', 'shell', 'other'] as const).map((b: Bucket) => {
              const tl = g.totals[b]
              const n = tl.rule + tl.ask + tl.cleared + tl.deny
              return (
                <Button
                  key={`gate-${b}`}
                  plain
                  hotkey={b[0]}
                  label={`${b} ${n}${open === b ? ' ▾' : ''}`}
                  dimColor={n === 0}
                  onPress={() => update($, view, x => ({ ...normalize(DEFAULT_VIEW, x), gateOpen: normalize(DEFAULT_VIEW, x).gateOpen === b ? null : b }))}
                />
              )
            })}
          </Box>
          {open
            ? g.recent
                .filter(c => c.bucket === open)
                .slice(-5)
                .map(c => (
                  // The verdict sits in a box of its own width, not padded with spaces, which a graphical surface collapses.
                  <Box width={w - 4} columnGap={1} overflow="hidden">
                    <Box width={12} flexShrink={0}>
                      <Text>
                        <Text color={verdictColor(c)}>{c.verdict === 'deny' ? '✗ ' : '■ '}</Text>
                        <Text color={C.dim}>{c.verdict === 'rule' ? 'allowed' : c.verdict === 'cleared' ? decider : c.verdict === 'ask' ? 'pending' : 'denied'}</Text>
                      </Text>
                    </Box>
                    <Text dimColor={c.inSubagent} wrap="truncate">
                      {shorten(c.detail, Math.max(10, w - 18))}
                    </Text>
                  </Box>
                ))
            : null}
        </Box>
      )
    }

    // ---- agents: cards up to the limit, swimlanes beyond it
    const statusColor = (c: AgentCard) => (c.status === 'failed' ? C.warn : c.status === 'done' ? C.gate : C.agent)
    const glyph = (c: AgentCard) => (c.status === 'running' ? '●' : c.status === 'done' ? '✓' : c.status === 'failed' ? '✗' : '■')
    const expandOnPress = (id: string) => () =>
      update($, view, x => ({ ...normalize(DEFAULT_VIEW, x), expanded: normalize(DEFAULT_VIEW, x).expanded === id ? null : id }))

    // 활성 loop 가 있을 때만 agents 패널 맨 아래에 한 줄 (별도 패널이 아니다).
    const activeLoops = lp.filter(l => isLoopActive(l, now)).length
    const loopsLine = (w: number) =>
      activeLoops > 0 ? (
        <Text key="other-loops" dimColor wrap="truncate">{`other loops ${lp.length} · ${activeLoops} active`}</Text>
      ) : null
    const hasFanRails = running.length >= 2

    const agentsPanel = (w: number) => {
      // Cards need 20 columns each; when the pane can't hold the limit, lanes take over.
      const fit = Math.max(1, Math.min(cfg.maxCards, Math.floor((w + 1) / 21)))
      const useLanes = cards.length > fit
      const isNarrow = w < 40
      const header = (
        <Box justifyContent="space-between" width={w}>
          <Text bold wrap="truncate">
            {isNarrow ? `agents · ${running.length}/${cards.length}` : `agents · ${running.length} running · ${cards.length} total`}
          </Text>
          {cards.length > 0 ? (
            <Box flexShrink={0}>
              <Text color={C.dim}>{`1-${Math.min(cards.length, useLanes ? 6 : fit)}${isNarrow ? '' : ' expand'}`}</Text>
            </Box>
          ) : null}
        </Box>
      )
      if (cards.length === 0) {
        return (
          <Box flexDirection="column" width={w}>
            {header}
            <Text color={C.dim}>no subagents yet</Text>
          </Box>
        )
      }
      if (useLanes) {
        const shown = cards.slice(-6)
        // A lane is its glyph, a label, the bar and a clock: below 34 columns the label narrows, below
        // 36 the bar, so a 24-column pane still holds it. From 40 they are as they always were.
        const labelW = Math.min(17, Math.max(7, w - 17))
        const barW = Math.max(4, w - 11 - labelW)
        const geo = lanes(shown, now, barW)
        return (
          <Box flexDirection="column" width={w}>
            {header}
            {cards.length > shown.length ? <Text color={C.dim}>{`+${cards.length - shown.length} earlier`}</Text> : null}
            {shown.map((c, i) => {
              const gm = geo[i]
              const isViewed = viewed === c.id
              return (
                <Box columnGap={1}>
                  <Text color={statusColor(c)} bold={isViewed}>
                    {isViewed ? '▶' : glyph(c)}
                  </Text>
                  <Box width={labelW} flexShrink={0}>
                    <Button key={`card-${c.id}`} plain hotkey={String(i + 1)} label={shorten(cardTitle(c), labelW - 3)} onPress={expandOnPress(c.id)} />
                  </Box>
                  <Box flexShrink={0}>
                    <Text>
                      <Text color={C.faint}>{'·'.repeat(gm?.before ?? 0)}</Text>
                      <Text color={statusColor(c)}>{'━'.repeat(gm?.bar ?? 1)}</Text>
                      <Text color={C.faint}>{'·'.repeat(gm?.after ?? 0)}</Text>
                    </Text>
                  </Box>
                  {clock(`lane-clock-${c.id}`, c.spawnedAt, c.endedAt, C.dim)}
                </Box>
              )
            })}
            {loopsLine(w)}
          </Box>
        )
      }
      const shown = cards.slice(-fit)
      const cardW = Math.max(20, Math.floor((w - (shown.length - 1)) / shown.length))
      const centers = shown.map((_, i) => i * (cardW + 1) + Math.floor(cardW / 2))
      return (
        <Box flexDirection="column" width={w}>
          {header}
          {hasFanRails ? rail('fan-out', true, C.agent, w, centers) : null}
          <Box columnGap={1}>
            {shown.map((c, i) => {
              const isViewed = viewed === c.id
              const sameModel = !c.model || prettyModel(c.model) === modelName
              return (
                <Box
                  flexDirection="column"
                  borderStyle={isViewed ? 'double' : 'round'}
                  borderColor={c.lastStop === 'max_tokens' ? C.warn : C.agent}
                  borderDimColor={c.status !== 'running' && !isViewed}
                  width={cardW}
                  paddingX={1}
                >
                  <Button key={`card-${c.id}`} plain hotkey={String(i + 1)} label={titleLines(cardTitle(c), cardW - 7, cardW - 4)[0]} onPress={expandOnPress(c.id)} />
                  {titleLines(cardTitle(c), cardW - 7, cardW - 4)[1] ? (
                    <Text bold wrap="truncate">
                      {titleLines(cardTitle(c), cardW - 7, cardW - 4)[1]}
                    </Text>
                  ) : null}
                  <Text color={C.dim} wrap="truncate">
                    {sameModel ? c.type : `${c.type} · ${prettyModel(c.model)}`}
                  </Text>
                  <Text dimColor wrap="truncate">
                    {c.steps > 0 ? `ctx ${kTokens(c.ctx)} · out ${kTokens(c.out)} · ${c.steps} st` : 'starting…'}
                  </Text>
                  <Box columnGap={1}>
                    <Text color={c.lastStop === 'max_tokens' ? C.warn : statusColor(c)}>
                      {cardW >= 26 ? `${glyph(c)} ${c.lastStop === 'max_tokens' ? 'max_tokens' : c.status}` : glyph(c)}
                    </Text>
                    <Box flexShrink={0}>{clock(`card-clock-${c.id}`, c.spawnedAt, c.endedAt, C.dim)}</Box>
                  </Box>
                </Box>
              )
            })}
          </Box>
          {hasFanRails ? rail('merge', true, C.agent, w, centers, true) : null}
          {loopsLine(w)}
        </Box>
      )
    }

    const expandedCard = cards.find(c => c.id === v.expanded)
    const expandedPanel = (w: number) =>
      expandedCard ? (
        <Box flexDirection="column" borderStyle="single" borderColor={C.agent} paddingX={1} width={w}>
          <Text bold wrap="wrap">
            {expandedCard.description || expandedCard.type}
          </Text>
          <Text dimColor wrap="truncate">{`${expandedCard.type} · ${prettyModel(expandedCard.model)} · ${expandedCard.status} · ${expandedCard.steps} steps`}</Text>
          {expandedCard.tools.length === 0 ? <Text color={C.dim}>no tool calls yet</Text> : null}
          {expandedCard.tools.map(n => (
            <Text color={n.isError ? C.warn : C.text} wrap="truncate">
              {`${n.isError ? '✗' : '·'} ${n.text}`}
            </Text>
          ))}
          {expandedCard.answer ? (
            <Text dimColor wrap="wrap">
              {`» ${shorten(expandedCard.answer, 240)}`}
            </Text>
          ) : null}
        </Box>
      ) : null

    // ---- log: whatever rows the other panels leave, 4 to 8
    // 고정 행 수 = 헤더 1 + 오로라 1 + 로그를 뺀 패널마다 (테두리 2 + 본문 행) + 패널 사이 빈 줄 `order.length - 1`.
    // 본문 행은 각 패널이 그리는 줄을 센 값이다(줄바꿈이 생기는 좁은 폭에서는 가장 긴 경우를 잡지 않는다 — 로그가 하한 4줄을 지킨다).
    const fitCards = Math.max(1, Math.min(cfg.maxCards, Math.floor((W + 1) / 21)))
    const expandedRows = expandedCard ? 2 + 2 + Math.max(1, expandedCard.tools.length) + (expandedCard.answer ? 1 : 0) : 0
    const heightOf: Record<Panel, number> = {
      main: 2 + mainRows(W).length,
      // 테두리 2 + (FID 가 있으면 제목 1 + 단계가 있으면 진행 줄·단계 막대 2) + BG 줄 + 작업 줄 + 끝난 작업 줄
      fid: 2 + (b.fid ? 1 + (b.stages && b.stages.length > 0 ? 2 : 0) : 0) + (bgTotal > 0 || ciLine(b.ci) ? 1 : 0) + Math.min(3, b.running.length) + (b.running.length > 3 ? 1 : 0) + endedJobs.length,
      architect: 2 + 3 + (cfg.moments ? 1 : 0) + (a.lastAdvice ? 1 : 0),
      gate: 2 + 4 + (v.gateOpen ? Math.min(5, g.recent.filter(c => c.bucket === v.gateOpen).length) : 0),
      // 테두리 없음: 머리 1 + (줄 모드: 이전 표시 1 + 줄 · 카드 모드: 카드 7줄 + 위아래 rail)
      agents: (cards.length > fitCards ? 1 + (cards.length > 6 ? 1 : 0) + Math.min(6, cards.length) : 1 + (hasFanRails ? 2 : 0) + 7) + (activeLoops > 0 ? 1 : 0),
      loops: 0,
      receipt: 0,
      log: 0,
    }
    const used = 2 + order.filter(p => p !== 'log').reduce((n, p) => n + heightOf[p] + (p === 'agents' ? expandedRows : 0), 0) + Math.max(0, order.length - 1)
    const bodyRows = e.props.scroll?.bodyRows ?? e.viewport?.rows ?? 40
    const nLog = logRows(bodyRows, used)
    const shownLines = (viewed ? lines.filter(l => l.agentId === viewed) : lines).slice(-nLog)
    const colorOf = (l: LogLine) =>
      l.kind === 'error' ? C.warn : l.kind === 'consult' ? C.arch : l.who === 'main' || l.who === '↻ bg' ? C.main : l.who === 'gate' ? C.gate : l.who === 'you' ? C.text : C.agent
    // Below 40 columns a line keeps its minute, not its second, and a shorter name.
    const logPanel = (w: number) => (
      <Box flexDirection="column" borderStyle="round" borderColor={C.faint} paddingX={1} width={w}>
        <Text dimColor wrap="truncate">
          {viewed ? 'session log · this agent' : 'session log'}
        </Text>
        {shownLines.length === 0 ? <Text color={C.dim}>nothing yet</Text> : null}
        {shownLines.map(l => (
          <Box>
            <Box width={w < 40 ? 6 : 9} flexShrink={0}>
              <Text color={C.dim}>{w < 40 ? fmtClock(l.at).slice(0, 5) : fmtClock(l.at)}</Text>
            </Box>
            <Box width={w < 40 ? 9 : 13} flexShrink={0}>
              <Text color={colorOf(l)} bold wrap="truncate">
                {l.who}
              </Text>
            </Box>
            <Text color={l.kind === 'error' ? C.warn : C.text} wrap="truncate">
              {l.text}
            </Text>
          </Box>
        ))}
      </Box>
    )

    // devFSD: 제목·검증 배지 · 진행 줄 · 단계 막대(현재 단계 강조) · BG/CI 줄 · 작업 줄 · 방금 끝난 작업. FID 가 없으면 BG 구역만.
    const fidPanel = (w: number) => {
      const sp = stageProgress(b.stages ?? [])
      const hasStages = !!b.fid && sp.total > 0
      const isGreen = b.verify === '완료' || b.verify === '검증 PASS'
      const verifyColor = isGreen ? C.gate : b.verify === '검증 FAIL' ? C.warn : C.amber
      const ci = b.ci ?? []
      const ciPass = ci.filter(c => c.bucket === 'pass').length
      const ciFail = ci.filter(c => c.bucket === 'fail').length
      const ciPend = ciPending(b.ci)
      const gaugeW = Math.max(0, Math.min(12, w - 24))
      const prog = gauge(sp.total > 0 ? (sp.step / sp.total) * 100 : 0, gaugeW)
      const markColor = (s: StageMark) => (s.mark === '✓' ? C.gate : s.mark === '!' ? C.amber : s.mark === '✗' ? C.warn : C.dim)

      return (
        <Box flexDirection="column" borderStyle="round" borderColor={C.gate} paddingX={1} width={w}>
          {b.fid ? (
            <Box justifyContent="space-between">
              <Text color={C.gate} bold wrap="truncate">
                {`devFSD · ${b.fid}`}
              </Text>
              {b.verify ? (
                <Box flexShrink={0}>
                  <Text color={verifyColor} bold={!isGreen}>{b.verify}</Text>
                </Box>
              ) : null}
            </Box>
          ) : null}
          {hasStages
            ? line(
                [
                  gaugeW > 0 ? { spans: [{ text: prog.on, color: C.gate }, { text: prog.off, color: C.faint }] } : null,
                  { spans: [{ text: `${sp.step}/${sp.total} ${sp.current ?? (sp.isDone ? '완료' : '')}`.trimEnd() + (sp.next ? ` · 다음 ${sp.next}` : '') }], fill: true },
                ],
                w - 4,
              )
            : null}
          {hasStages ? (
            <Box key="stage-bar" flexWrap="wrap" columnGap={1}>
              {(b.stages ?? []).map(s => {
                const failed = s.mark === '✗'
                return (
                  <Box flexShrink={0}>
                    {s.isCurrent ? (
                      <Text backgroundColor={failed ? C.warn : C.cleared} color={C.text} bold>{`▶ ${s.label}${failed ? '✗' : '●'}`}</Text>
                    ) : (
                      <Text color={markColor(s)} bold={s.mark === '!'}>{`${s.label}${s.mark}`}</Text>
                    )}
                  </Box>
                )
              })}
            </Box>
          ) : null}
          {bgTotal > 0 || ciLine(b.ci)
            ? line(
                [
                  bgTotal > 0 ? { spans: [{ text: `BG ${bgTotal}`, bold: true }] } : null,
                  ciLine(b.ci)
                    ? {
                        spans: [
                          { text: 'CI ', dim: true },
                          { text: `✓${ciPass}`, color: C.gate },
                          ...(ciPend > 0 ? [{ text: ` ⋯${ciPend}`, color: C.amber }] : []),
                          ...(ciFail > 0 ? [{ text: ` ✗${ciFail}`, color: C.warn }] : []),
                        ],
                      }
                    : null,
                ],
                w - 4,
              )
            : null}
          {/* 작업별 한 줄 — 먼저 시작한 순으로 3개까지, 나머지는 개수로 */}
          {b.running.slice(0, 3).map(j => (
            <Text key={j.id} color={C.text} wrap="truncate">
              {jobRow(j, now, w < 60)}
            </Text>
          ))}
          {b.running.length > 3 ? (
            <Text dimColor wrap="truncate">{`… 외 ${b.running.length - 3}개`}</Text>
          ) : null}
          {endedJobs.map(j => (
            <Text key={j.id} color={j.isFailed ? C.warn : C.gate} wrap="truncate">
              {j.isFailed ? `✗ ${j.label.trim() || j.id} · 방금 끝남` : `✓ ${j.label.trim() || j.id}`}
            </Text>
          ))}
        </Box>
      )
    }

    const draw =(p: Panel, w: number) =>
      p === 'fid'
        ? fidPanel(w)
        : p === 'main'
        ? mainPanel(w)
        : p === 'architect'
          ? architectPanel(w)
          : p === 'gate'
            ? gatePanel(w)
            : p === 'agents'
              ? agentsPanel(w)
              : logPanel(w)

    // Desktop draws the agents' time axis as SVG under the panels.
    const svgLanes =
      e.surface !== 'terminal' && cards.length >= 2
        ? (() => {
            const { Svg } = $.ui.resolve(e)
            const rowH = 18
            const pxW = 520
            const barMax = pxW - 160 - 44 // 막대 끝 옆에 실행 시간 글자가 들어갈 자리
            const geo = lanes(cards.slice(-10), now, 100)
            const rects = cards
              .slice(-10)
              .map((c, i) => {
                const gm = geo[i]
                const x = 150 + ((gm?.before ?? 0) / 100) * barMax
                const wpx = Math.max(3, ((gm?.bar ?? 1) / 100) * barMax)
                const fill = c.status === 'running' ? SVG_COLORS.running : c.status === 'done' ? SVG_COLORS.done : c.status === 'failed' ? SVG_COLORS.failed : SVG_COLORS.other
                const label = shorten(cardTitle(c), 22).replace(/[<&>]/g, '')
                const took = fmtDuration((c.endedAt ?? now) - c.spawnedAt)
                return `<text x="4" y="${i * rowH + 13}" font-size="11" fill="${SVG_LABEL}">${label}</text><rect x="${x}" y="${i * rowH + 4}" width="${wpx}" height="10" rx="3" fill="${fill}"/><text x="${x + wpx + 4}" y="${i * rowH + 13}" font-size="10" fill="${SVG_LABEL}">${took}</text>`
              })
              .join('')
            const svgH = Math.min(10, cards.length) * rowH + 4
            // No width or height on the element: it takes the markup's own width up to the pane's and
            // scales down to fit a narrow one, rather than running past it at 520 pixels.
            return (
              <Svg
                source={`<svg xmlns="http://www.w3.org/2000/svg" width="${pxW}" height="${svgH}" viewBox="0 0 ${pxW} ${svgH}">${rects}</svg>`}
                alt={`${cards.length} agents on a time axis`}
              />
            )
          })()
        : null

    // 패널은 한 칸으로 쌓고 첫 패널 외에는 위에 빈 줄 1칸을 둔다. 패널 사이 rail 은 없다(agents 패널이 자기 rail 을 그린다).
    const column = (ps: Panel[], w: number) => (
      <Box flexDirection="column" width={w}>
        {ps.map((p, i) => (
          <Box key={`panel-${p}`} flexDirection="column" marginTop={i === 0 ? 0 : 1}>
            {draw(p, w)}
            {p === 'agents' ? expandedPanel(w) : null}
            {p === 'agents' ? svgLanes : null}
          </Box>
        ))}
      </Box>
    )

    // Inline above the prompt (the terminal's main screen), the pane is a summary of at most 8 rows.
    const isMini = layout === 'mini' || (layout === 'auto' && e.props.placement === 'inline')
    if (isMini) {
      const live = [...cards.filter(c => c.status === 'running'), ...cards.filter(c => c.status !== 'running').reverse()].slice(0, 3)
      const counts = `${s.rule} allowed · ${s.cleared} ${decider}${s.ask > 0 ? ` · ${s.ask} pending` : ''} · ${s.deny} denied`
      const strip = g.recent.slice(-Math.max(4, marksIn(W - cfg.gateLabel.length - 2 - counts.length, isTerminal)))
      const mg = ctxFill.pct !== null ? gauge(ctxFill.pct, 6) : null
      return (
        <Box flexDirection="column" width={W}>
          {line(
            [
              {
                spans: [
                  { text: modelName, color: C.main, bold: true },
                  { text: m.isRunning ? ' ● working' : isWaiting ? ' ◌ 대기' : ' ○ idle', color: m.isRunning || isWaiting ? C.main : C.dim },
                ],
              },
              mg
                ? {
                    spans: [
                      { text: '· ctx ', dim: true },
                      { text: mg.on, color: ctxColor },
                      { text: mg.off, color: C.faint },
                      { text: ` ${Math.round(ctxFill.pct ?? 0)}%` },
                      ...(u.compactions > 0 ? [{ text: ` ${compactMark(u)}`, color: C.amber }] : []),
                    ],
                  }
                : u.compactions > 0
                  ? { spans: [{ text: compactMark(u), color: C.amber }] }
                  : null,
              u.costUsd !== null ? { spans: [{ text: `· ${fmtUsd(u.costUsd)}`, dim: true }] } : null,
              showArchitect ? { spans: [{ text: `· ${cfg.architectLabel.toLowerCase()} ${advising ? 'advising' : a.consults.length}`, color: C.arch }] } : null,
            ],
            W,
          )}
          {badge ? <Text color={badgeColor} wrap="truncate">{badge.text}</Text> : null}
          {strip.length > 0 && cfg.panels.includes('gate') ? (
            <Box columnGap={1}>
              <Text dimColor>{cfg.gateLabel.toLowerCase()}</Text>
              {markRow(strip.map(checkMark))}
              <Text color={s.deny > 0 ? C.warn : s.ask > 0 ? C.amber : C.dim} wrap="truncate">
                {counts}
              </Text>
            </Box>
          ) : null}
          {live.map(c => (
            <Box columnGap={1}>
              <Text color={statusColor(c)}>{glyph(c)}</Text>
              <Box width={Math.max(6, W - 30)} flexShrink={0}>
                <Text wrap="truncate">{cardTitle(c)}</Text>
              </Box>
              {c.steps > 0 ? <Text dimColor>{`ctx ${kTokens(c.ctx)}`}</Text> : null}
              {clock(`mini-clock-${c.id}`, c.spawnedAt, c.endedAt, C.dim)}
            </Box>
          ))}
          {cards.length > live.length ? (
            <Text color={C.dim} wrap="truncate">{`+${cards.length - live.length} more agents · /devfsd layout compact for all`}</Text>
          ) : null}
          {loopsLine(W)}
          {!m.isRunning && r ? (
            <Text dimColor wrap="truncate">
              {`last turn ${fmtDuration(r.durationMs)} · ${plural(r.agents, 'agent')} · ${plural(r.edits, 'edit')} · ${plural(r.errors, 'error')}${r.costDelta !== null ? ` · +${fmtUsd(r.costDelta)}` : ''}`}
            </Text>
          ) : null}
        </Box>
      )
    }

    // ---- 헤더: 한 줄 요약 `DEVFSD · 상태 · 단계 · 검증 · BG N` (좁으면 뒤 조각부터 빠진다)
    const status = m.isRunning ? 'WORKS' : isWaiting ? '◌ 대기' : 'IDLE'
    const sp = stageProgress(b.stages ?? [])
    const stageWord = b.fid ? sp.current ?? (sp.isDone ? '완료' : null) : null
    const verifyWord = b.fid && b.verify ? b.verify.replace(/^검증 /, '') : null
    const verifyColor = verifyWord === 'PASS' || verifyWord === '완료' ? C.gate : verifyWord === 'FAIL' ? C.warn : C.amber
    const mode = cfg.motion ? (m.isRunning ? 'working' : isWaiting ? 'waiting' : 'idle') : 'idle'

    return (
      <Box flexDirection="column" width={W}>
        {/* Below 40 columns the frame's own title names the pane, so the header starts at the status. */}
        <Box key="header" flexDirection="column">
          {line(
            [
              W >= 40 ? { spans: [{ text: 'DEVFSD', bold: true }, { text: ' ·', color: C.dim, bold: true }] } : null,
              { spans: [{ text: status, color: C.main, bold: true }] },
              stageWord ? { spans: [{ text: '· ', color: C.dim, bold: true }, { text: stageWord, color: C.text, bold: true }] } : null,
              // 단계가 이미 `완료` 면 같은 낱말을 두 번 쓰지 않는다.
              verifyWord && !(stageWord === '완료' && verifyWord === '완료')
                ? { spans: [{ text: '· ', color: C.dim, bold: true }, { text: verifyWord, color: verifyColor, bold: verifyColor !== C.gate }] }
                : null,
              // 맨 뒤 — 좁은 폭에서는 다른 조각을 밀어내지 않고 이 조각이 먼저 빠진다.
              bgTotal > 0 ? { spans: [{ text: `· BG ${bgTotal}`, color: C.main, bold: true }] } : null,
            ],
            W,
            1,
            'center',
          )}
        </Box>
        {hasRail ? (
          <els.Client
            key="aurora"
            module="./rail.tsx"
            width={W}
            height={1}
            props={{ variant: 'aurora', mode, active: mode !== 'idle', width: W, color: C.main, dim: C.faint, marks: [], isMerge: false }}
          />
        ) : (
          <Text color={C.faint} mono>
            {'─'.repeat(W)}
          </Text>
        )}
        {column(order, W)}
      </Box>
    )
  }).catch(($, e, next) => {
    // Without this a failed draw leaves the engine's empty pane.
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="column" width={Math.max(20, e.props.bodyColumns)}>
        <Text bold>DEVFSD</Text>
        <Text color={C.warn} wrap="wrap">{`draw failed (${next.error.kind}): ${next.error.message ?? 'no message'}`}</Text>
      </Box>
    )
  })
}
