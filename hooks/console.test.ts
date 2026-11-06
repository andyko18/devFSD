// Ported from Claude Flightdeck (https://github.com/scasella/claude-flightdeck, v0.6.0)
// Copyright (c) 2026 Stephen Casella — MIT License. See NOTICE. Modified for devFSD.
import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

import {
  DEFAULT_ARCHITECT,
  DEFAULT_GATE,
  DEFAULT_TURN,
  DEFAULT_USAGE,
  COMPACT_TRIES,
  addCard,
  cellWidth,
  piecesThatFit,
  afterCompactRead,
  claimCompactRead,
  faultKey,
  forgetCompactRead,
  resumeCard,
  afterCall,
  applyStep,
  compactWindowOf,
  consultTimeline,
  contextFill,
  describeInput,
  endConsult,
  fitLegend,
  fmtResetIn,
  fmtSpeed,
  gateSummary,
  lanes,
  limitLabel,
  limitOf,
  logRows,
  marksIn,
  momentOf,
  normalizeCard,
  normalizeGate,
  normalizeLog,
  titleLines,
  parseConfig,
  prettyModel,
  promptLine,
  handbackOf,
  adviceLine,
  receiptOf,
  recordCheck,
  redact,
  settleCheck,
  trimRecent,
  startConsult,
  stepSpeed,
  STALL_MS,
  activityBadge,
  agoLabel,
  durationLabel,
  jobRow,
  oldestStart,
  latestMtimeMs,
  outputPathOf,
  withActivity,
  gauge,
  gaugeColor,
  stageProgress,
  PALETTES,
} from './core'
import { auroraCells } from './rail'
import type { Check, StageMark } from '../types'

// ---------------------------------------------------------------- pure behaviour

test('redaction masks credentials before anything is stored', () => {
  // devFSD: 가짜 비밀을 조각으로 이어 만든다 — 비밀 검사기(gitleaks)가 테스트 값을 진짜 비밀로 읽는 오탐을 피한다
  expect(redact('curl -H "Authorization: Bearer ' + 'abc.def.ghi123' + '" x')).not.toContain('abc.def')
  expect(redact('export OPENAI_API_KEY=' + 'sk-proj-' + '1234567890abcdef')).not.toContain('1234567890')
  expect(redact('gh auth --token ghp_abcdefghijklmnop')).not.toContain('abcdefghijklmnop')
  expect(redact('psql postgres://bob:hunter2@db/x')).not.toContain('hunter2')
  expect(redact('password=hunter2 ls')).not.toContain('hunter2')
  expect(redact('ls -la src/')).toBe('ls -la src/')
  expect(describeInput('Read', { file_path: 'C:\\Users\\me\\proj\\src\\main.ts' })).toBe('Read → src/main.ts')
})

const check = (id: string, verdict: Check['verdict'], bucket: Check['bucket'] = 'shell'): Check => ({
  id,
  tool: 'Bash',
  bucket,
  verdict,
  inSubagent: false,
  detail: 'Bash → ls',
  at: 1,
})

test('an ask is settled by the call that follows: cleared if it ran, deny if refused', () => {
  let g = recordCheck(DEFAULT_GATE, check('a', 'ask'))
  g = recordCheck(g, check('b', 'ask'))
  g = recordCheck(g, check('c', 'rule', 'file'))
  g = settleCheck(g, 'a', true)
  g = settleCheck(g, 'b', false)
  g = settleCheck(g, 'zzz', true) // not an ask: unchanged
  const s = gateSummary(g)
  expect([s.rule, s.ask, s.cleared, s.deny, s.total]).toEqual([1, 0, 1, 1, 3])
  expect(g.recent.map(c => c.verdict)).toEqual(['cleared', 'deny', 'rule'])
})

test('the gate tallies a mixed run of verdicts per family', () => {
  let g = DEFAULT_GATE
  g = recordCheck(g, check('r1', 'rule', 'file'))
  g = recordCheck(g, check('a1', 'ask', 'shell'))
  g = recordCheck(g, check('a2', 'ask', 'shell'))
  g = recordCheck(g, check('d1', 'deny', 'other'))
  g = settleCheck(g, 'a1', true)
  g = settleCheck(g, 'a2', false)
  expect(g.totals.file).toEqual({ rule: 1, ask: 0, cleared: 0, deny: 0 })
  expect(g.totals.shell).toEqual({ rule: 0, ask: 0, cleared: 1, deny: 1 })
  expect(g.totals.other.deny).toBe(1)
  expect(gateSummary(g)).toEqual({ rule: 1, ask: 0, cleared: 1, deny: 2, total: 4 })
  expect(gateSummary(DEFAULT_GATE).total).toBe(0)
})

test('a v1-shaped gate reads as empty, then records normally', () => {
  const g = normalizeGate({ file: { allow: 3, ask: 1, deny: 0, cleared: 2 }, shell: null })
  expect(gateSummary(g).total).toBe(0)
  const next = recordCheck(g, check('n1', 'rule', 'file'))
  expect(next.totals.file.rule).toBe(1)
  expect(next.recent.length).toBe(1)
})

test('a pending ask is never trimmed out before it settles', () => {
  let g = recordCheck(DEFAULT_GATE, check('old-ask', 'ask'))
  for (let i = 0; i < 120; i += 1) g = recordCheck(g, check(`r${i}`, 'rule', 'file'))
  expect(g.recent.length).toBe(80)
  expect(g.recent.some(c => c.id === 'old-ask')).toBe(true)
  g = settleCheck(g, 'old-ask', true)
  expect(gateSummary(g).ask).toBe(0)
  expect(trimRecent([check('a', 'rule'), check('b', 'rule')], 5).length).toBe(2)
})

test('edits count from every loop; errors only from the main loop', () => {
  const t = { ...DEFAULT_TURN, errorStreak: 1 }
  expect(afterCall(t, { inSubagent: true, hasFailed: false, isEdit: true }).edits).toBe(1)
  expect(afterCall(t, { inSubagent: true, hasFailed: true, isEdit: false }).errorStreak).toBe(1)
  expect(afterCall(t, { inSubagent: false, hasFailed: true, isEdit: false })).toEqual({ ...t, errorStreak: 2, errors: 1 })
  expect(momentOf(afterCall(DEFAULT_TURN, { inSubagent: true, hasFailed: false, isEdit: true }))).toBe('before done')
  expect(momentOf({ edits: 0, errorStreak: 2 })).toBe('error repeats')
})

test("a card's context is its latest step's whole input; output adds up", () => {
  let c = normalizeCard({ id: 'x' })
  c = applyStep(c, { model: 'claude-sonnet-5-5', usage: { input_tokens: 10, cache_read_input_tokens: 30_000, cache_creation_input_tokens: 2_000, output_tokens: 500 }, stopReason: 'tool_use' })
  c = applyStep(c, { model: 'claude-sonnet-5-5', usage: { input_tokens: 5, cache_read_input_tokens: 40_000, output_tokens: 700 }, stopReason: 'max_tokens' })
  expect([c.ctx, c.out, c.steps, c.lastStop, c.model]).toEqual([40_005, 1200, 2, 'max_tokens', 'claude-sonnet-5-5'])
})

test('a resumed agent runs again on its own card instead of adding a second', () => {
  const a = { ...normalizeCard({ id: 'a', description: 'first', spawnedAt: 5, model: 'claude-sonnet-5-5' }), status: 'done' as const, endedAt: 100, steps: 4, out: 900 }
  const b = normalizeCard({ id: 'b' })
  const cards = addCard(addCard(addCard([], a), b), { ...normalizeCard({ id: 'a', description: 'again', spawnedAt: 200 }) })
  expect(cards.map(c => `${c.id}:${c.description}`)).toEqual(['a:again', 'b:'])
  expect(cards[0] && [cards[0].status, cards[0].endedAt, cards[0].steps, cards[0].out, cards[0].spawnedAt]).toEqual(['running', null, 4, 900, 5])
  expect([resumeCard(a).status, resumeCard(a).endedAt]).toEqual(['running', null])
  // Spawned again on another model, the card names it; a spawn that names none keeps the card's.
  expect(addCard([a], normalizeCard({ id: 'a', model: 'claude-opus-5-5' }))[0]?.model).toBe('claude-opus-5-5')
  expect(addCard([a], normalizeCard({ id: 'a' }))[0]?.model).toBe('claude-sonnet-5-5')
})

test('consults open, close by id, and draw on a shared timeline', () => {
  let a = startConsult(DEFAULT_ARCHITECT, { id: 's1', at: 0, moment: 'before a plan', via: 'advisor tool' })
  a = startConsult(a, { id: 's1', at: 5, moment: 'before a plan', via: 'again' }) // same id: ignored
  a = endConsult(a, 10, null, 's1')
  a = startConsult(a, { id: 's2', at: 90, moment: 'before done', via: 'advisor tool' })
  expect(a.consults.length).toBe(2)
  expect(a.consults[0]?.endAt).toBe(10)
  const tl = consultTimeline(a, 100, 11)
  expect(tl.length).toBe(11)
  expect(tl.startsWith('◆━')).toBe(true)
  expect(tl.split('◆').length - 1).toBe(2)
})

test('config is read leniently: bad values fall back to defaults', () => {
  const d = parseConfig({})
  expect([d.maxCards, d.paneColumns, d.layout, d.motion, d.moments, d.panels.length]).toEqual([3, 66, 'auto', true, true, 5])
  expect(d.architect.test('fable-advisor:fable-advisor')).toBe(true)
  const c = parseConfig({ architectPattern: '([', maxCards: 99, layout: 'diagonal', panels: 'log, gate ,nope,gate', motion: 'off' })
  expect(c.architect.test('advisor')).toBe(true) // invalid regex → default
  expect([c.maxCards, c.layout, c.motion]).toEqual([6, 'auto', false])
  expect([46.4, 12, Number.NaN, '90'].map(n => parseConfig({ paneColumns: n }).paneColumns)).toEqual([46, 40, 66, 66])
  expect(c.panels).toEqual(['log', 'gate'])
})

test('devFSD: gauge fills in eighths of a cell and keeps its width', () => {
  const g2 = (p: number, w: number) => { const x = gauge(p, w); return x.on + x.off }
  // 손 계산 표 — 팔분 = floor(pct*width*8/100), 내림(100% 전에 꽉 차지 않음)
  const table: [number, string, string][] = [
    [0, '', '░'.repeat(10)], [5, '▌', '░'.repeat(9)], [59, '█████▉', '░'.repeat(4)], [60, '██████', '░'.repeat(4)],
    [72, '███████▏', '░░'], [79, '███████▉', '░░'], [80, '████████', '░░'], [100, '█'.repeat(10), ''],
  ]
  for (const [p, on, off] of table) expect(gauge(p, 10)).toEqual({ on, off })
  for (const w of [5, 6, 10]) for (const p of [-5, 0, 33, 99.99, 100, 150]) expect([...g2(p, w)].length).toBe(w)
  expect(gauge(99.99, 10).on).not.toBe('█'.repeat(10))
})

test('devFSD: the advisor panel is named Advisor unless the person saved another label', () => {
  expect(parseConfig({}).architectLabel).toBe('Advisor')
  expect(parseConfig({ architectLabel: 'ARCHITECT' }).architectLabel).toBe('ARCHITECT') // 저장값 보존
})

test('devFSD: panels default to main, fid, architect, agents, log and old saved values still read', () => {
  expect(parseConfig({}).panels).toEqual(['main', 'fid', 'architect', 'agents', 'log'])
  expect(parseConfig({ panels: 'fid,main,architect,gate,agents,loops,receipt,log' }).panels).toEqual(['fid', 'main', 'architect', 'gate', 'agents', 'loops', 'receipt', 'log'])
  expect(parseConfig({ panels: 'main,bogus,log' }).panels).toEqual(['main', 'log'])
  expect(parseConfig({ panels: 'bogus' }).panels).toEqual(['main', 'fid', 'architect', 'agents', 'log']) // 새 기본값으로 폴백
})

test('state saved under an older shape still reads', () => {
  expect(normalizeLog([{ at: '08:00:00', who: 'jev', text: 'x' }])[0]).toEqual({ at: 0, who: 'jev', text: 'x', agentId: null, kind: 'info' })
  const g = normalizeGate({ file: { allow: 1 } }) // v1 gate shape
  expect(g.recent).toEqual([])
  expect(g.totals.shell.rule).toBe(0)
  expect(normalizeCard({ id: 'a', status: 'done' }).tools).toEqual([])
})

test('layout math: lanes share one axis, the log gets 4-8 rows, the legend never wraps', () => {
  const cards = [
    { ...normalizeCard({}), id: 'a', spawnedAt: 1000, endedAt: 1050 },
    { ...normalizeCard({}), id: 'b', spawnedAt: 1050, endedAt: null },
  ]
  const [a, b] = lanes(cards, 1100, 20)
  expect(a).toEqual({ id: 'a', before: 0, bar: 10, after: 10 })
  expect(b?.before).toBe(10)
  expect((b?.before ?? 0) + (b?.bar ?? 0) + (b?.after ?? 0)).toBe(20)
  expect([logRows(10, 40), logRows(50, 40), logRows(200, 40)]).toEqual([4, 7, 8])
  expect(fitLegend([{ label: 'main' }, { label: 'agents' }, { label: 'architect' }], 20).map(x => x.label)).toEqual(['main', 'agents'])
  expect([marksIn(64, true), marksIn(64, false), marksIn(6, false)]).toEqual([64, 42, 4])
  expect(limitLabel('five_hour')).toBe('5h')
  expect(prettyModel('claude-opus-5-5[1m]')).toBe('Opus 5.5 1M')
  expect(prettyModel('us.anthropic.claude-sonnet-4-5-20250929-v1:0')).toBe('Sonnet 4.5')
  expect(prettyModel('claude-3-5-haiku-20241022')).toBe('Haiku 3.5')
  expect(prettyModel('claude-opus-4-20250514')).toBe('Opus 4')
  expect(prettyModel('claude-3-opus-20240229')).toBe('Opus 3')
  expect(prettyModel('z-ai/glm-5.3-flash-with-a-long-name')).toBe('z-ai/glm-5.3-flash-wi…')
  expect(prettyModel('')).toBe('—')
  expect(promptLine('fix the parser')).toEqual({ who: 'you', text: 'fix the parser' })
  const hb = '<agent-message from="a1940a83d593229d5">\n[Subagent hand-back] The text below is the final report. The report follows:\n  Add gate tests: redaction edge cases.\n  - more\n</agent-message>'
  expect(handbackOf(hb)).toEqual({ from: 'a1940a83d593229d5', body: 'Add gate tests: redaction edge cases.' })
  expect(handbackOf('<agent-message from="x">\nPlain report line\n</agent-message>')).toEqual({ from: 'x', body: 'Plain report line' })
  expect(handbackOf('fix the parser')).toBe(null)
  expect(adviceLine('## Ship it after one more gate test.\n- details')).toBe('Ship it after one more gate test.')
  expect(adviceLine('[Subagent hand-back] header\n\n**Fix card overflow first**')).toBe('Fix card overflow first')
  expect(adviceLine('')).toBe('')
  expect(promptLine('<agent-message from="a1492260715f3be7b"> [Subagent hand-back]')).toEqual({ who: 'engine', text: 'agent message from a1492260' })
  expect(receiptOf({ ...DEFAULT_TURN, costAtStart: 5 }, { durationMs: 1, agentsSince: 0, costNow: 5, reason: 'answer' }).costDelta).toBe(null)
  expect(titleLines('Write tinyqueue test suite', 13, 16)).toEqual(['Write', 'tinyqueue test…'])
  expect(titleLines('Short', 13, 16)).toEqual(['Short', ''])
  expect(receiptOf({ ...DEFAULT_TURN, costAtStart: 1, edits: 2 }, { durationMs: 1000, agentsSince: 3, costNow: 1.5, reason: 'answer' }).costDelta).toBe(0.5)
})

test('a request\'s speed is its time to the first piece of response, and no output rate', () => {
  expect(stepSpeed(1000, 1800)).toEqual({ ttftMs: 800 })
  expect(stepSpeed(1000, null)).toBe(null) // no response arrived
  expect(fmtSpeed({ ttftMs: 1250 })).toBe('ttft 1.3s')
  // State saved by 0.5.0 still carries a rate: it is not drawn.
  expect(fmtSpeed({ ttftMs: 800, tokPerS: 9844 } as { ttftMs: number })).toBe('ttft 0.8s')
})

test('a window keeps its reset time, drawn as the time left', () => {
  expect(limitOf({ kind: 'five_hour', percentUsed: 19, resetsAt: '1970-01-01T03:10:00.000Z' })).toEqual({ kind: 'five_hour', pct: 19, resetsAt: 11_400_000 })
  expect(limitOf({ kind: 'seven_day', percentUsed: 3 }).resetsAt).toBe(null)
  expect(limitOf({ kind: 'spend_limit', percentUsed: 1, resetsAt: 'soon' }).resetsAt).toBe(null)
  expect([fmtResetIn(11_400_000, 0), fmtResetIn(25 * 60_000 + 5_000, 0), fmtResetIn(4 * 86_400_000 + 2 * 3_600_000, 0)]).toEqual(['3h10m', '25m', '4d2h'])
  expect([fmtResetIn(null, 0), fmtResetIn(undefined, 0), fmtResetIn(5, 10)]).toEqual(['', '', ''])
})

// ---------------------------------------------------------------- devFSD: 백그라운드 활동 배지
test('devFSD: STALL_MS is five minutes', () => {
  expect(STALL_MS).toBe(300_000)
})

test('devFSD: outputPathOf pulls the task output path out of a tool result', () => {
  const bash = 'Command running in background with ID: b1. Output is being written to: /private/tmp/claude-501/-p/s1/tasks/b1.output. You will be notified'
  expect(outputPathOf(bash)).toBe('/private/tmp/claude-501/-p/s1/tasks/b1.output')
  const agent = 'Async agent launched successfully.\noutput_file: /private/tmp/claude-501/-p/s1/tasks/a9c1.output\nDo NOT Read'
  expect(outputPathOf(agent)).toBe('/private/tmp/claude-501/-p/s1/tasks/a9c1.output')
  expect(outputPathOf('Command running in background')).toBeUndefined()
  expect(outputPathOf(undefined)).toBeUndefined()
  expect(outputPathOf('see /tmp/x/tasks/b1.txt')).toBeUndefined()
})

test('devFSD: latestMtimeMs takes the newest stat line and ignores junk', () => {
  expect(latestMtimeMs('1000\n1500\n1200\n')).toBe(1_500_000)
  expect(latestMtimeMs('')).toBeNull()
  expect(latestMtimeMs('stat: no such file\nabc\n')).toBeNull()
  expect(latestMtimeMs('abc\n2000\n')).toBe(2_000_000)
})

test('devFSD: agoLabel reads seconds, then minutes, at every boundary', () => {
  const cases: [number, boolean, string][] = [
    [0, false, '방금'], [4_999, false, '방금'], [5_000, false, '5초 전'], [59_999, false, '59초 전'],
    [60_000, false, '1분 전'], [119_999, false, '1분 전'], [150_000, false, '2분 전'],
    [4_999, true, '0s'], [5_000, true, '5s'], [150_000, true, '2m'],
  ]
  for (const [ms, compact, want] of cases) expect(agoLabel(ms, compact)).toBe(want)
})

test('devFSD: activityBadge shows jobs and age, and warns exactly at five minutes', () => {
  const at = 1_000_000
  const base = { jobs: 1, isRunning: false, activityAt: at, compact: false }
  expect(activityBadge({ ...base, now: at + 150_000 })).toEqual({ text: '작업 1 · 마지막 활동 2분 전', stalled: false })
  expect(activityBadge({ ...base, now: at + 299_999 })?.stalled).toBe(false)
  expect(activityBadge({ ...base, now: at + 300_000 })).toEqual({ text: '⚠ 정체 의심 · 작업 1 · 5분 전', stalled: true })
  expect(activityBadge({ ...base, now: at + 150_000, compact: true })).toEqual({ text: '작업 1 · 2m', stalled: false })
  expect(activityBadge({ ...base, now: at + 7 * 60_000, compact: true })).toEqual({ text: '⚠ 작업 1 · 7m', stalled: true })
  expect(activityBadge({ ...base, now: at + 5_000, activityAt: undefined })).toEqual({ text: '작업 1', stalled: false })
  expect(activityBadge({ ...base, jobs: 2, isRunning: true, now: at + 30_000 })).toEqual({ text: '작업 2 · 마지막 활동 30초 전', stalled: false })
  expect(activityBadge({ ...base, now: at - 60_000 })).toEqual({ text: '작업 1 · 마지막 활동 방금', stalled: false }) // 미래 시각은 0 으로
})

test('devFSD: durationLabel counts run length, not time since last activity', () => {
  const cases: [number, boolean, string][] = [
    [0, false, '0초'], [23_000, false, '23초'], [59_999, false, '59초'], [60_000, false, '1분'], [150_000, false, '2분'],
    [23_000, true, '23s'], [150_000, true, '2m'], [-5_000, true, '0s'],
  ]
  for (const [ms, compact, want] of cases) expect(durationLabel(ms, compact)).toBe(want)
})

test('devFSD: jobRow names the job and how long it has run', () => {
  expect(jobRow({ id: 'a', label: 'publish', startedAt: 1_000 }, 24_000, false)).toBe('↻ publish · 23초')
  expect(jobRow({ id: 'a', label: 'publish', startedAt: 1_000 }, 24_000, true)).toBe('↻ publish · 23s')
  expect(jobRow({ id: 'a', label: '  ', startedAt: 1_000 }, 61_000, false)).toBe('↻ a · 1분') // 이름이 비면 id
})

test('devFSD: oldestStart picks the earliest running job', () => {
  expect(oldestStart([])).toBeUndefined()
  expect(oldestStart([{ startedAt: 30 }, { startedAt: 10 }, { startedAt: 20 }])).toBe(10)
})

test('devFSD: activityBadge with since shows run length apart from last activity', () => {
  const start = 1_000_000
  const base = { jobs: 1, isRunning: false, activityAt: start + 20_000, compact: false, since: start }
  expect(activityBadge({ ...base, now: start + 23_000 })).toEqual({ text: '작업 1 · 23초 경과 · 마지막 활동 방금', stalled: false })
  expect(activityBadge({ ...base, now: start + 23_000, compact: true })).toEqual({ text: '작업 1 · 23s', stalled: false })
  // 작업은 7분째, 마지막 활동은 5분 전 — 두 값이 따로 보인다
  expect(activityBadge({ ...base, now: start + 20_000 + 300_000, compact: true })).toEqual({ text: '⚠ 작업 1 · 5m · 정체 5m', stalled: true })
  expect(activityBadge({ ...base, now: start + 20_000 + 300_000 })).toEqual({ text: '⚠ 정체 의심 · 작업 1 · 5분 경과 · 5분 전', stalled: true })
  // 작업이 없으면 since 가 있어도 경과를 보이지 않는다
  expect(activityBadge({ ...base, jobs: 0, now: start + 23_000 })).toBeNull()
})

test('devFSD: activityBadge is silent without jobs unless a running turn has gone quiet', () => {
  const at = 1_000_000
  const quiet = { jobs: 0, activityAt: at, compact: false }
  expect(activityBadge({ ...quiet, isRunning: false, now: at + 600_000 })).toBeNull()
  expect(activityBadge({ ...quiet, isRunning: true, now: at + 60_000 })).toBeNull()
  expect(activityBadge({ ...quiet, isRunning: true, now: at + 300_000 })).toEqual({ text: '⚠ 정체 의심 · 5분 전', stalled: true })
})

test('devFSD: withActivity keeps the newest time and skips sub-second repeats', () => {
  const first = withActivity({ running: [], recent: [] }, 5_000)
  expect(first.activityAt).toBe(5_000)
  expect(withActivity(first, 5_500)).toBe(first)
  expect(withActivity(first, 4_000)).toBe(first)
  expect(withActivity(first, 6_000).activityAt).toBe(6_000)
})

// ---------------------------------------------------------------- drawing

const engine = (on: On) => {
  const clock = mock.clock(on)
  on('ui.status', () => ({ value: undefined }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  return clock
}

const pane = (bodyColumns: number) => ({
  plugin: 'devfsd',
  component: 'Pane' as const,
  requestId: 'devfsd-console',
  props: {
    title: 'devFSD 관제판',
    isFocused: true,
    bodyColumns,
    placement: 'dock' as const,
    scroll: { offset: 0, bodyRows: 70 },
    view: {},
  },
})

let spawnN = 0
const spawn = (subagentType: string, description: string) => ({
  prompt: description,
  description,
  subagentType,
  tool_use_id: `tu${++spawnN}`,
  provider: { plugin: 'engine', tier: 'core' as const },
  parentModel: 'claude-opus-5-5',
  background: true,
  fork: false,
})

test('a fresh session draws on every surface and width, empty panels hidden', async ($, on) => {
  engine(on)
  for (const surface of ['terminal', 'desktop', 'vscode', 'mobile'] as const) {
    for (const cols of [40, 60, 86, 120]) {
      const ui = await $.ui.mount({ ...pane(cols), surface })
      expect(await ui.find({ text: /· main$/ })).toBeDefined()
      expect(await ui.find({ text: /session log/ })).toBeDefined()
      expect(await ui.find({ text: /agents ·/ })).toBeUndefined() // no subagents: no agents panel
      expect(await ui.find({ text: /permissions/ })).toBeUndefined() // no checks yet: no gate panel
      await ui.unmount()
    }
  }
})

test('inline above the prompt, the pane is a summary of at most 8 rows', async ($, on) => {
  engine(on)
  let n = 0
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: `m${++n}` }))
  on('tool.check', () => ({ decision: 'allow' }))
  await $.turn.start({ text: 'go', turnId: 'M1' })
  for (const d of ['one', 'two', 'three', 'four', 'five']) await $.agent.spawn(spawn('general-purpose', `task ${d}`))
  await $.tool.check({ tool: 'Read', input: { file_path: '/a' }, tool_use_id: 'm-k1' })
  for (const surface of ['terminal', 'vscode'] as const) {
    const ui = await $.ui.mount({ ...pane(80), props: { ...pane(80).props, placement: 'inline' as const }, surface })
    const root = (await ui.drawn()) as { children?: unknown[] }
    expect((root.children ?? []).filter(Boolean).length <= 8).toBe(true)
    expect(await ui.find({ text: /\+2 more agents/ })).toBeDefined()
    expect(await ui.find({ text: /1 allowed/ })).toBeDefined()
    expect(await ui.find({ text: /session log/ })).toBeUndefined()
    await ui.unmount()
  }
})

test('/clear starts the pane fresh', async ($, on) => {
  engine(on)
  on('session.end', (_$, e) => ({ sessionId: e.sessionId }))
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'c1' }))
  await $.turn.start({ text: 'go', turnId: 'C1' })
  await $.agent.spawn(spawn('Explore', 'look around'))
  await $.session.end({ reason: 'clear', sessionId: 's' } as never)
  const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await ui.find({ text: /look around/ })).toBeUndefined()
  await ui.unmount()
})

test('colours come from the theme by default, raw hex only when asked', async ($, on) => {
  engine(on)
  const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  const title = await ui.find({ text: /· main$/ })
  expect(title?.props.color).toBe('claude')
  await ui.unmount()
})

test('pastel keeps the fixed dark-terminal colours', { options: { palette: 'pastel' } }, async ($, on) => {
  engine(on)
  const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect((await ui.find({ text: /· main$/ }))?.props.color).toBe('#7dd3fc')
  await ui.unmount()
})

test('subagents become cards, then swimlanes past the card limit; a card expands on its hotkey', async ($, on) => {
  engine(on)
  let n = 0
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: `ag${++n}` }))
  await $.turn.start({ text: 'fan out', turnId: 'T1' })
  await $.agent.spawn(spawn('general-purpose', 'Write the parser tests'))
  await $.agent.spawn(spawn('Explore', 'Map the call sites'))

  const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await ui.find({ text: /Write the parser/ })).toBeDefined()
  expect(await ui.find({ text: /Sonnet 5\.5/ })).toBeDefined() // differs from main: shown
  await ui.press({ key: 'card-ag1' })
  expect(await ui.find({ text: /^Write the parser tests$/ })).toBeDefined() // the expanded panel, full title
  await ui.unmount()

  await $.agent.spawn(spawn('general-purpose', 'Implement the parser'))
  await $.agent.spawn(spawn('general-purpose', 'Review the parser'))
  for (const surface of ['terminal', 'desktop'] as const) {
    const lanesUi = await $.ui.mount({ ...pane(64), surface })
    expect(await lanesUi.find({ text: /4 total/ })).toBeDefined()
    expect(await lanesUi.find({ text: /━/ })).toBeDefined()
    await lanesUi.unmount()
  }
})

test('the server-side advisor is read from assistant rows: consulting, then on call', async ($, on) => {
  engine(on)
  await $.turn.start({ text: 'plan it', turnId: 'T2' })
  const row = (content: unknown[]) =>
    $.session
      .append({
        message: { type: 'assistant', role: 'assistant', content: content as never },
        door: 'response',
        origin: { kind: 'model', model: 'claude-opus-5-5' } as never,
        uuid: `u${++spawnN}`,
      })
      .catch(() => undefined) // the test has no transcript to store rows in
  await row([{ type: 'server_tool_use', id: 'srv1', name: 'advisor', input: {} }])
  const mid = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await mid.find({ text: /Advisor · advising/ })).toBeDefined()
  expect(await mid.find({ text: /◆ before a plan/ })).toBeDefined()
  await mid.unmount()

  await row([{ type: 'advisor_tool_result', tool_use_id: 'srv1', content: { type: 'advisor_redacted_result' } }])
  const after = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await after.find({ text: /Advisor · on call/ })).toBeDefined()
  expect(await after.find({ text: /^1$/ })).toBeDefined()
  await after.unmount()
})

// The built-in guard passes user plugins over on the attachment, hook-context and compaction doors,
// so the hook subscribes to the response door alone, which is where the assistant's rows come in.
test('the server-side advisor is read only from rows that come in by the response door', async ($, on) => {
  engine(on)
  await $.turn.start({ text: 'plan it', turnId: 'T5' })
  const row = (door: 'response' | 'hook-context', id: string) =>
    $.session
      .append({
        message: { type: 'assistant', role: 'assistant', content: [{ type: 'server_tool_use', id, name: 'advisor', input: {} }] as never },
        door,
        origin: { kind: 'model', model: 'claude-opus-5-5' } as never,
        uuid: `u${++spawnN}`,
      })
      .catch(() => undefined) // the test has no transcript to store rows in
  await row('hook-context', 'srvH')
  const before = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await before.find({ text: /Advisor · advising/ })).toBeUndefined()
  await before.unmount()

  await row('response', 'srvR')
  const after = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await after.find({ text: /Advisor · advising/ })).toBeDefined()
  await after.unmount()
})

test('the gate strip fills from checks and a row opens its redacted drill-down', { options: { panels: 'main,fid,architect,gate,agents,log' } }, async ($, on) => {
  engine(on)
  on('tool.check', (_$, e) => ({ decision: e.tool === 'Read' ? 'allow' : 'ask' }))
  await $.tool.check({ tool: 'Read', input: { file_path: '/a/b.ts' }, tool_use_id: 'k1' })
  await $.tool.check({ tool: 'Bash', input: { command: 'curl -H "Authorization: Bearer ' + 'abcdefgh12345' + '" api' }, tool_use_id: 'k2' })
  const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await ui.find({ text: /2 checks/ })).toBeDefined()
  expect(await ui.find({ text: /1 pending/ })).toBeDefined()
  await ui.press({ key: 'gate-shell' })
  expect(await ui.find({ text: /Authorization: Bearer •••/ })).toBeDefined()
  expect(await ui.find({ text: /abcdefgh12345/ })).toBeUndefined()
  await ui.unmount()
})

test('config changes labels, hides panels and turns the moments off', { options: { architectLabel: 'REVIEWER', panels: 'main,architect,agents,log', moments: false } }, async ($, on) => {
  engine(on)
  let n = 0
  on('agent.spawn', () => ({ model: 'claude-fable-5-1', agentId: `r${++n}` }))
  await $.turn.start({ text: 'review it', turnId: 'T3' })
  await $.agent.spawn(spawn('fable-advisor:fable-advisor', 'final review'))
  const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await ui.find({ text: /REVIEWER · advising/ })).toBeDefined()
  expect(await ui.find({ text: /permissions/ })).toBeUndefined()
  expect(await ui.find({ text: /before a plan/ })).toBeUndefined()
  await ui.unmount()
})

test('a consult whose start and result share one row closes, and its review flag with it', async ($, on) => {
  engine(on)
  on('tool.call', () => ({ result: {}, text: 'ok' }))
  await $.turn.start({ text: 'go', turnId: 'T4' })
  // An edit first, so the consult is inferred as "before done" and sets the review flag.
  await $.tool.call({ tool: 'Edit', file_path: '/x.ts', old_string: 'a', new_string: 'b' } as never)
  await $.session
    .append({
      message: {
        type: 'assistant',
        role: 'assistant',
        content: [
          { type: 'server_tool_use', id: 'srv9', name: 'advisor', input: {} },
          { type: 'advisor_tool_result', tool_use_id: 'srv9', content: { type: 'advisor_redacted_result' } },
        ] as never,
      },
      door: 'response',
      origin: { kind: 'model', model: 'claude-opus-5-5' } as never,
      uuid: 'one-row',
    })
    .catch(() => undefined)
  const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await ui.find({ text: /Advisor · on call/ })).toBeDefined()
  expect(await ui.find({ text: /◆ before done/ })).toBeDefined()
  expect(await ui.find({ text: /reviewing before done/ })).toBeUndefined()
  await ui.unmount()
})

test('with no architect anywhere, the panel, legend entry and status field stay hidden', async ($, on) => {
  engine(on)
  const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await ui.find({ text: /Advisor/ })).toBeUndefined()
  expect(await ui.find({ text: /^ architect$/ })).toBeUndefined()
  await ui.unmount()
})

test('cards that cannot fit the pane fall back to lanes', async ($, on) => {
  engine(on)
  let n = 0
  on('agent.spawn', () => ({ model: 'claude-opus-5-5', agentId: `w${++n}` }))
  await $.turn.start({ text: 'go', turnId: 'W1' })
  for (const d of ['alpha', 'beta', 'gamma']) await $.agent.spawn(spawn('Explore', `task ${d}`))
  const narrow = await $.ui.mount({ ...pane(40), surface: 'terminal' })
  expect(await narrow.find({ text: /━/ })).toBeDefined() // lanes
  await narrow.unmount()
  const wide = await $.ui.mount({ ...pane(70), surface: 'terminal' })
  expect(await wide.find({ text: /━/ })).toBeUndefined() // three cards fit in 70
  expect(await wide.find({ text: /task gamma/ })).toBeDefined()
  await wide.unmount()
})

test("a background architect's advice is read from its hand-back", async ($, on) => {
  engine(on)
  on('agent.spawn', () => ({ model: 'claude-fable-5-1', agentId: 'fab1' }))
  await $.turn.start({ text: 'review it', turnId: 'H1' })
  await $.agent.spawn(spawn('fable-advisor:fable-advisor', 'final review'))
  await $.turn.complete({ answer: '', durationMs: 10, isAborted: false, turnId: 'H1', agentId: 'fab1', reason: 'answer' })
  await $.turn.start({
    text: '<agent-message from="fab1">\n[Subagent hand-back] The report follows:\n  Ship it after one more gate test.\n</agent-message>',
    turnId: 'H2',
  })
  const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await ui.find({ text: /» Ship it after one more gate test\./ })).toBeDefined()
  await ui.unmount()
})

test('each rate-limit window shows the time to its reset where the main panel has room', async ($, on) => {
  engine(on)
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  const at = (ms: number) => new Date(ms).toISOString()
  await $.session.measure({
    context: { window: 200_000 },
    rateLimits: [
      { kind: 'five_hour', percentUsed: 19, resetsAt: at(3 * 3_600_000 + 10 * 60_000) },
      { kind: 'seven_day', percentUsed: 3, resetsAt: at(4 * 86_400_000 + 2 * 3_600_000) },
    ],
    changed: ['rateLimits'],
  })
  for (const cols of [64, 120]) {
    const ui = await $.ui.mount({ ...pane(cols), surface: 'terminal' })
    expect(await ui.find({ text: /19% ↻3h10m/ })).toBeDefined()
    expect(await ui.find({ text: /3% ↻4d2h/ })).toBeDefined()
    await ui.unmount()
  }
  const narrow = await $.ui.mount({ ...pane(40), surface: 'terminal' })
  expect(await narrow.find({ text: /19%/ })).toBeDefined()
  expect(await narrow.find({ text: /↻/ })).toBeUndefined() // no room: the gauges stay whole
  await narrow.unmount()
})

test("the main box shows the last request's time to first token, and no tokens per second", async ($, on) => {
  const clock = engine(on)
  // The model beneath: 800 ms to its first words, then 2 s more to stop after 120 tokens.
  on('turn.step', async function* () {
    await clock.sleep(800)
    yield { kind: 'text' as const, index: 0, text: 'hello' }
    await clock.sleep(2000)
    const usage = { input_tokens: 10, output_tokens: 120, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, model: 'claude-opus-5-5' }
    yield { kind: 'stop' as const, stopReason: 'end_turn' as const, usage }
    return { turnId: 'S1', index: 0, answer: 'hello', toolUses: [], stopReason: 'end_turn' as const, usage }
  })
  const before = await $.ui.mount({ ...pane(40), surface: 'terminal' })
  expect(await before.find({ text: /ttft/ })).toBeUndefined() // nothing measured yet: no line
  await before.unmount()
  const s = $.turn.step({ turnId: 'S1', index: 0, model: 'claude-opus-5-5', messageCount: 1 })
  const first = s.next()
  await clock.advance(800)
  expect((await first).value).toEqual({ kind: 'text', index: 0, text: 'hello' })
  const stop = s.next()
  await clock.advance(2000)
  await stop
  for await (const _ of s) void _
  await s.result
  for (const cols of [40, 64, 120]) {
    const ui = await $.ui.mount({ ...pane(cols), surface: 'terminal' })
    expect(await ui.find({ text: /ttft 0\.8s$/ })).toBeDefined()
    expect(await ui.find({ text: /tok\/s/ })).toBeUndefined()
    await ui.unmount()
  }
})

test('on a graphical surface, rows of marks hold fewer marks, keep the newest and clip at their box', { options: { panels: 'main,fid,architect,gate,agents,loops,log' } }, async ($, on) => {
  engine(on)
  // The newest check is the one refused: its ✗ must stay in sight.
  on('tool.check', (_$, e) => ({ decision: e.tool_use_id === 'g29' ? 'deny' : 'allow' }))
  const usage = { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, model: 'claude-opus-5-5' }
  on('turn.step', async function* () {
    return { turnId: 'G1', index: 0, answer: '', toolUses: [], stopReason: 'end_turn' as const, usage }
  })
  for (let i = 0; i < 30; i += 1) await $.tool.check({ tool: 'Read', input: { file_path: `/f${i}.ts` }, tool_use_id: `g${i}` })
  // A loop that is no card and no architect: a dot on the "other loops" row.
  const s = $.turn.step({ turnId: 'G1', index: 0, model: 'claude-opus-5-5', messageCount: 1, agentId: 'wf1' })
  for await (const _ of s) void _
  await s.result
  await $.session
    .append({
      message: { type: 'assistant', role: 'assistant', content: [{ type: 'server_tool_use', id: 'srvG', name: 'advisor', input: {} }] as never },
      door: 'response',
      origin: { kind: 'model', model: 'claude-opus-5-5' } as never,
      uuid: 'marks-row',
    })
    .catch(() => undefined)
  for (const surface of ['terminal', 'desktop', 'vscode', 'mobile'] as const) {
    for (const cols of [40, 64, 120]) {
      const ui = await $.ui.mount({ ...pane(cols), surface })
      // A terminal draws all 30 marks; a graphical surface draws fewer where 30 would not fit
      // (24 in the 36 cells of a 40-column pane), always ending on the newest.
      const strip = await ui.find({ type: 'Text', text: /^[■✗]{2,}$/ })
      expect(strip?.props.wrap).toBe('truncate-start')
      expect(strip?.text.length).toBe(surface !== 'terminal' && cols === 40 ? 24 : 30)
      expect(strip?.text.endsWith('✗')).toBe(true)
      expect((await ui.find({ type: 'Text', text: /^●$/ }))?.props.wrap).toBe('truncate-start')
      expect((await ui.find({ type: 'Text', text: /^[─━◆]+$/ }))?.props.wrap).toBe('truncate-middle')
      expect((await ui.find({ key: 'legend' }))?.props.marginBottom).toBe(surface === 'terminal' ? 0 : 1)
      await ui.unmount()
    }
  }
})

test("the inline summary's strip holds fewer marks on a graphical surface and keeps the newest", async ($, on) => {
  engine(on)
  on('tool.check', (_$, e) => ({ decision: e.tool_use_id === 'n59' ? 'deny' : 'allow' }))
  for (let i = 0; i < 60; i += 1) await $.tool.check({ tool: 'Bash', input: { command: `ls ${i}` }, tool_use_id: `n${i}` })
  for (const surface of ['terminal', 'vscode'] as const) {
    const ui = await $.ui.mount({ ...pane(80), props: { ...pane(80).props, placement: 'inline' as const }, surface })
    // 80 columns less "gate " and " 59 allowed · 0 you · 1 denied" leave 45: 45 marks in a terminal, 30 elsewhere.
    const strip = await ui.find({ type: 'Text', text: /^[■✗]{2,}$/ })
    expect(strip?.props.wrap).toBe('truncate-start')
    expect(strip?.text.length).toBe(surface === 'terminal' ? 45 : 30)
    expect(strip?.text.endsWith('✗')).toBe(true)
    expect(await ui.find({ text: /59 allowed/ })).toBeDefined()
    await ui.unmount()
  }
})

test('a draw that fails says why instead of leaving the pane empty', async ($, on) => {
  on('ui.status', () => ({ value: undefined }))
  on('clock.now', () => {
    throw new Error('boom')
  })
  for (const cols of [40, 64, 120]) {
    const ui = await $.ui.mount({ ...pane(cols), surface: 'terminal' })
    expect(await ui.find({ text: /^draw failed \(throw\)/ })).toBeDefined()
    await ui.unmount()
  }
})

test('a finished agent that takes another step (resumed by SendMessage) runs again, in the pane and the status line', async ($, on) => {
  // engine(on), with a status line that keeps what it was told
  mock.clock(on)
  const status: (string | undefined)[] = []
  on('ui.status', (_$, e) => (status.push(e.text), { value: undefined }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'r1' }))
  const usage = { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, model: 'claude-sonnet-5-5' }
  on('turn.step', async function* () {
    return { turnId: 'R1', index: 0, answer: '', toolUses: [], stopReason: 'end_turn' as const, usage }
  })
  const step = async () => {
    const s = $.turn.step({ turnId: 'R1', index: 0, model: 'claude-sonnet-5-5', messageCount: 1, agentId: 'r1' })
    for await (const _ of s) void _
    await s.result
  }
  await $.turn.start({ text: 'go', turnId: 'T1' })
  await $.agent.spawn(spawn('general-purpose', 'Audit the parser'))
  await step()
  await $.turn.complete({ answer: 'ok', durationMs: 10, isAborted: false, turnId: 'R1', agentId: 'r1', reason: 'answer' })
  expect(status[status.length - 1]).toMatch(/agents 0\/1/)
  await step()
  expect(status[status.length - 1]).toMatch(/agents 1\/1/)
  const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await ui.find({ text: /◐ running/ })).toBeDefined()
  expect(await ui.find({ text: /✓ done/ })).toBeUndefined()
  expect(await ui.find({ text: /^resumed$/ })).toBeDefined()
  expect(await ui.find({ text: /ctx 10 · out 10 · 2 st/ })).toBeDefined()
  await ui.unmount()
})

test('the docked pane asks for the width set in paneColumns', { options: { paneColumns: 46, openOnStart: true } }, async ($, on) => {
  engine(on)
  const asked: (number | undefined)[] = []
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('ui.open', (_$, e) => (asked.push(e.columns), { value: { isPlaced: true as const } }))
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  expect(asked).toEqual([46])
})

test('the context gauge measures against a compaction window set below the model window', () => {
  const u = { ...DEFAULT_USAGE, tokens: 200_000, window: 1_000_000, compactWindow: 400_000 }
  // From the real reading, not the model's percentage: 200k of 400k.
  expect(contextFill(u)).toEqual({ pct: 50, window: 400_000 })
  expect(contextFill({ ...u, tokens: 100_000 })).toEqual({ pct: 25, window: 400_000 })
  // None set, or not below the model's window: the model's window.
  expect(contextFill({ ...u, compactWindow: null })).toEqual({ pct: 20, window: 1_000_000 })
  expect(contextFill({ ...u, compactWindow: 1_000_000 })).toEqual({ pct: 20, window: 1_000_000 })
  expect(contextFill({ ...u, compactWindow: 1_500_000 })).toEqual({ pct: 20, window: 1_000_000 })
  expect(contextFill({ ...u, compactWindow: 0 })).toEqual({ pct: 20, window: 1_000_000 })
  // No reading yet, no gauge; and none from a window not yet known.
  expect(contextFill({ ...u, tokens: null })).toEqual({ pct: null, window: 400_000 })
  expect(contextFill(DEFAULT_USAGE)).toEqual({ pct: null, window: 0 })
  expect(contextFill({ ...DEFAULT_USAGE, tokens: 5 }).pct).toBeNull()
})

test('a breakdown names a compaction window only when auto-compaction is on and it is below the model window', () => {
  const on = { rawMaxTokens: 400_000, isAutoCompactEnabled: true }
  expect(compactWindowOf(on, 1_000_000)).toBe(400_000)
  expect(compactWindowOf({ ...on, isAutoCompactEnabled: false }, 1_000_000)).toBeNull()
  expect(compactWindowOf({ ...on, rawMaxTokens: 1_000_000 }, 1_000_000)).toBeNull() // the model's own limit
  expect(compactWindowOf(on, 200_000)).toBeNull() // a model switch to a smaller window
  expect(compactWindowOf({ ...on, rawMaxTokens: 0 }, 1_000_000)).toBeNull()
  expect(compactWindowOf(undefined, 1_000_000)).toBeNull() // no breakdown: unknown
  expect(compactWindowOf(null, 1_000_000)).toBeNull()
})

/** A session whose `session.usage` answers as a host does: the breakdown only to a call that asks for one. */
const compactHost = (on: On, o: { window: () => number; compact: number | null; isEnabled?: boolean; tokens?: number }) => {
  const asked: (string | undefined)[] = []
  on('session.usage', (_$, e) => {
    asked.push(e.breakdown)
    const window = o.window()
    const breakdown =
      e.breakdown && o.compact !== null
        ? { rawMaxTokens: o.compact, isAutoCompactEnabled: o.isEnabled ?? true, totalTokens: 123, percentage: 99 }
        : undefined
    return { value: { startedAt: 0, rateLimits: [], context: { window, ...(o.tokens !== undefined ? { tokens: o.tokens } : {}), ...(breakdown ? { breakdown: breakdown as never } : {}) } } }
  })
  return asked
}

test('the gauge, status and inline summary measure against the compaction window, read once per model window', async ($, on) => {
  mock.clock(on)
  let status: string | undefined
  on('ui.status', (_$, e) => {
    status = e.text
    return { value: undefined }
  })
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  let window = 1_000_000
  const asked = compactHost(on, { window: () => window, compact: 400_000 })
  const measure = (tokens: number) =>
    $.session.measure({ context: { window, tokens, percent: tokens / (window / 100) }, rateLimits: [], changed: ['context'] })
  await measure(100_000)
  await measure(150_000)
  await measure(200_000)
  // Three measurements, one summary breakdown: never `full`, which would send token-count requests.
  expect(asked.filter(Boolean)).toEqual(['summary'])
  expect(status).toBe('ctx 50%') // not the host's 20% of a million
  for (const cols of [40, 64, 120]) {
    const ui = await $.ui.mount({ ...pane(cols), surface: 'terminal' })
    expect(await ui.find({ text: /200k\/400k/ })).toBeDefined()
    expect(await ui.find({ text: / 50%/ })).toBeDefined()
    expect(await ui.find({ text: /1\.0M/ })).toBeUndefined()
    await ui.unmount()
    const mini = await $.ui.mount({ ...pane(cols), props: { ...pane(cols).props, placement: 'inline' as const }, surface: 'terminal' })
    expect(await mini.find({ text: / 50%/ })).toBeDefined()
    await mini.unmount()
  }
  // Past 80% of the compaction window the gauge warns, though the model's window has room.
  await measure(340_000)
  const warn = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect((await warn.find({ type: 'Text', text: /^[█▏▎▍▌▋▊▉]+$/ }))?.props.color).toBe('error')
  expect(await warn.find({ text: / 85%/ })).toBeDefined()
  await warn.unmount()
  // A model with a smaller window: read again, and a compaction window above it no longer counts.
  window = 200_000
  await measure(100_000)
  expect(asked.filter(Boolean)).toEqual(['summary', 'summary'])
  const small = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await small.find({ text: /100k\/200k/ })).toBeDefined()
  await small.unmount()
})

const keepsModelWindow = (name: string, host: { compact: number | null; isEnabled?: boolean }, asks: number) =>
  test(name, async ($, on) => {
    mock.clock(on)
    on('ui.status', () => ({ value: undefined }))
    on('session.measure', (_$, e) => ({ changed: e.changed }))
    const asked = compactHost(on, { window: () => 1_000_000, ...host })
    for (const tokens of [50_000, 100_000, 200_000, 250_000, 300_000]) {
      await $.session.measure({ context: { window: 1_000_000, tokens, percent: tokens / 10_000 }, rateLimits: [], changed: ['context'] })
    }
    // An answer is asked for once; no breakdown (no session bound yet) is asked again, COMPACT_TRIES in all.
    expect(asked.filter(Boolean).length).toBe(asks)
    for (const cols of [40, 64, 120]) {
      const ui = await $.ui.mount({ ...pane(cols), surface: 'terminal' })
      expect(await ui.find({ text: /300k\/1\.0M/ })).toBeDefined()
      expect(await ui.find({ text: / 30%/ })).toBeDefined()
      await ui.unmount()
    }
  })

keepsModelWindow('a host that gives no breakdown keeps the model window and stops asking after 3 tries', { compact: null }, 3)
keepsModelWindow('with auto-compaction off the gauge keeps the model window and is asked once', { compact: 400_000, isEnabled: false }, 1)

test('a resumed session reads its compaction window at start, and /clear leaves the reading alone', async ($, on) => {
  mock.clock(on)
  on('ui.status', () => ({ value: undefined }))
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('session.end', (_$, e) => ({ sessionId: e.sessionId }))
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('command.register', () => ({ value: { command: 'devfsd' } }))
  on('ui.open', () => ({ value: { isPlaced: true as const } }))
  // Resumed with 200k already in context.
  const asked = compactHost(on, { window: () => 1_000_000, compact: 400_000, tokens: 200_000 })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  expect(asked).toEqual([undefined, 'summary'])
  const resumed = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await resumed.find({ text: /200k\/400k/ })).toBeDefined()
  expect(await resumed.find({ text: / 50%/ })).toBeDefined()
  await resumed.unmount()
  // The gauge waits for the next measurement after a /clear; the compaction window is not asked again.
  await $.session.end({ reason: 'clear', sessionId: 's' } as never)
  await $.session.measure({ context: { window: 1_000_000, tokens: 100_000, percent: 10 }, rateLimits: [], changed: ['context'] })
  expect(asked).toEqual([undefined, 'summary'])
  const cleared = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await cleared.find({ text: /100k\/400k/ })).toBeDefined()
  expect(await cleared.find({ text: / 25%/ })).toBeDefined()
  await cleared.unmount()
})

test('a compaction-window read that fails is asked again at the next measurement', async ($, on) => {
  mock.clock(on)
  on('ui.status', () => ({ value: undefined }))
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  let reads = 0
  on('session.usage', (_$, e) => {
    if (e.breakdown && ++reads === 1) return { deny: 'not bound yet' }
    const breakdown = e.breakdown ? { rawMaxTokens: 400_000, isAutoCompactEnabled: true } : undefined
    return { value: { startedAt: 0, rateLimits: [], context: { window: 1_000_000, ...(breakdown ? { breakdown: breakdown as never } : {}) } } }
  })
  const measure = (tokens: number) =>
    $.session.measure({ context: { window: 1_000_000, tokens, percent: tokens / 10_000 }, rateLimits: [], changed: ['context'] })
  await measure(100_000)
  const failed = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await failed.find({ text: /100k\/1\.0M/ })).toBeDefined()
  await failed.unmount()
  await measure(200_000)
  await measure(300_000)
  expect(reads).toBe(2) // the failed read once more, then not again
  const read = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await read.find({ text: /300k\/400k/ })).toBeDefined()
  expect(await read.find({ text: / 75%/ })).toBeDefined()
  await read.unmount()
})

test('a compaction-window read is claimed once per model window, missed reads retried up to a cap, stale ones dropped', () => {
  const b = { rawMaxTokens: 400_000, isAutoCompactEnabled: true }
  const fresh = { ...DEFAULT_USAGE, window: 1_000_000 }
  const first = claimCompactRead(fresh, 1_000_000)
  expect([first.isClaimed, first.usage.compactFor]).toEqual([true, 1_000_000])
  expect(claimCompactRead(first.usage, 1_000_000).isClaimed).toBe(false) // already claimed
  expect(afterCompactRead(first.usage, 1_000_000, b).compactWindow).toBe(400_000)
  // A read for a window no longer claimed (the model switched while it ran) changes nothing.
  const switched = claimCompactRead({ ...first.usage, window: 1_000_000 }, 200_000).usage
  expect(afterCompactRead(switched, 1_000_000, b)).toBe(switched)
  // A miss (no breakdown, or a failed call) gives the claim back and counts; COMPACT_TRIES misses stop asking.
  let u = first.usage
  for (let i = 0; i < COMPACT_TRIES; i += 1) {
    const c = claimCompactRead(u, 1_000_000)
    expect(c.isClaimed || i === 0).toBe(true)
    u = afterCompactRead(c.isClaimed ? c.usage : u, 1_000_000, i % 2 ? null : undefined)
  }
  expect([u.compactFor, u.compactMisses, u.compactWindow]).toEqual([0, COMPACT_TRIES, null])
  expect(claimCompactRead(u, 1_000_000).isClaimed).toBe(false)
  // Another model window, or another model, starts afresh.
  expect(claimCompactRead(u, 200_000).isClaimed).toBe(true)
  expect(claimCompactRead(forgetCompactRead({ ...u, compactWindow: 400_000 }), 1_000_000).isClaimed).toBe(true)
  expect(forgetCompactRead({ ...u, compactWindow: 400_000 }).compactWindow).toBe(null)
})

// Claude Code's built-in guard keeps session.compact from user plugins. Claude Code reports no fill
// until the first response after a new session, a /clear or a compaction, so a main-loop request that
// finds none after a response came back follows a compaction: counted, marked as an estimate.
const fillHost = ($: Parameters<TestBody>[0], on: On) => {
  engine(on)
  on('session.end', (_$, e) => ({ sessionId: e.sessionId }))
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  let veto: string | undefined
  on('session.compact', (_$, e) => (veto ? { skip: veto } : { messages: e.messages }))
  let fill: number | undefined
  on('session.usage', () => ({ value: { startedAt: 0, rateLimits: [], context: { window: 1_000_000, ...(fill !== undefined ? { tokens: fill } : {}) } } }))
  const usage = { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 60_000, cache_creation_input_tokens: 0, model: 'x' }
  on('turn.step', async function* () {
    return { turnId: 'C1', index: 0, answer: '', toolUses: [], stopReason: 'end_turn' as const, usage }
  })
  return {
    /** One model request: the fill Claude Code reports as it goes out, then its response. */
    request: async (tokens: number | undefined, agentId?: string) => {
      fill = tokens
      const s = $.turn.step({ turnId: 'C1', index: 0, model: 'claude-opus-5-5', messageCount: 1, ...(agentId ? { agentId } : {}) })
      for await (const _ of s) void _
      await s.result
    },
    measure: (tokens: number) => $.session.measure({ context: { window: 1_000_000, tokens, percent: tokens / 10_000 }, rateLimits: [], changed: ['context'] }),
    /** Compactions from here on come back skipped with this reason, as a blocking PreCompact hook's do; undefined lets them run. */
    vetoCompactions: (why: string | undefined) => {
      veto = why
    },
    /** The compaction mark the main box shows, whether it says `(estimated)`, and how many log lines say compacted. */
    shown: async () => {
      const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
      const mark = (await ui.find({ type: 'Text', text: /^⟲/ }))?.text ?? null
      const isEstimated = (await ui.find({ type: 'Text', text: /^\(estimated\)$/ })) !== undefined
      const logged = (await ui.findAll({ type: 'Text', text: /^context compacted/ })).map(n => n.text)
      await ui.unmount()
      return { mark, isEstimated, logged }
    },
  }
}

test('under the built-in guard a request that finds the context emptied counts an estimated compaction', async ($, on) => {
  const h = fillHost($, on)
  await h.measure(60_000)
  await h.request(undefined) // a new session's first request: nothing to have emptied
  await h.request(60_000)
  expect(await h.shown()).toEqual({ mark: null, isEstimated: false, logged: [] })
  await h.request(undefined)
  expect(await h.shown()).toEqual({ mark: '⟲~1', isEstimated: true, logged: ['context compacted (estimated)'] })
  // Compacted again after one response, as auto-compaction can within a turn; a subagent's own window is not the main one.
  await h.request(undefined)
  await h.request(undefined, 'sub1')
  expect((await h.shown()).mark).toBe('⟲~2')
  // The label is left out where the line is short; nothing spills.
  const spills: string[] = []
  for (const surface of ['terminal', 'desktop'] as const) {
    for (const cols of [24, 28, 32, 36, 40, 64, 120]) {
      for (const placement of ['dock', 'inline'] as const) {
        const ui = await $.ui.mount({ ...pane(cols), props: { ...pane(cols).props, placement }, surface })
        for (const s of spillsOf(await ui.drawn(), cols)) spills.push(`${surface} ${placement} ${cols}: ${s}`)
        await ui.unmount()
      }
    }
  }
  expect(spills).toEqual([])
  // A /clear empties the context too, and isn't a compaction.
  await $.session.end({ reason: 'clear', sessionId: 's' } as never)
  await h.request(undefined)
  await h.measure(30_000)
  expect((await h.shown()).mark).toBe('⟲~2')
  // So can a /resume into another conversation, before its first response.
  await $.session.end({ reason: 'resume', sessionId: 's' } as never)
  await h.request(undefined)
  expect((await h.shown()).mark).toBe('⟲~2')
})

test('once session.compact reaches Flightdeck its count is the real one: estimates before it are dropped, none after', async ($, on) => {
  const h = fillHost($, on)
  await h.measure(60_000)
  await h.request(60_000)
  await h.request(undefined) // a rewind to the first prompt reads like a compaction
  expect((await h.shown()).mark).toBe('⟲~1')
  await $.session.compact({ trigger: 'auto', messages: [{ role: 'user', text: 'the summary', toolUses: [] }] })
  await h.request(undefined)
  await h.request(60_000)
  await h.request(undefined)
  expect(await h.shown()).toEqual({ mark: '⟲1', isEstimated: false, logged: ['context compacted (estimated)', 'context compacted (auto)'] })
})

test('a compaction that comes back skipped is neither counted nor logged', async ($, on) => {
  const h = fillHost($, on)
  await h.measure(60_000)
  const compact = () => $.session.compact({ trigger: 'manual', messages: [{ role: 'user', text: 'the summary', toolUses: [] }] })
  h.vetoCompactions('a PreCompact hook blocked it')
  await compact()
  expect(await h.shown()).toEqual({ mark: null, isEstimated: false, logged: [] })
  h.vetoCompactions(undefined)
  await compact()
  expect(await h.shown()).toEqual({ mark: '⟲1', isEstimated: false, logged: ['context compacted (manual)'] })
})

test("a surface module's fault key is the same for the hook's path, either separator, and the drawing's name", () => {
  expect(faultKey('desktop', 'hooks/rail.tsx')).toBe('desktop:rail.tsx')
  expect(faultKey('desktop', 'hooks\\rail.tsx')).toBe(faultKey('desktop', 'rail.tsx'))
  expect(faultKey('terminal', 'hooks/elapsed.tsx')).not.toBe(faultKey('desktop', 'hooks/elapsed.tsx'))
})

test('switching to another model with the same window reads its compaction window afresh', async ($, on) => {
  mock.clock(on)
  on('ui.status', () => ({ value: undefined }))
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  let compact = 400_000
  let reads = 0
  on('session.usage', (_$, e) => {
    if (e.breakdown) reads += 1
    const breakdown = e.breakdown ? { rawMaxTokens: compact, isAutoCompactEnabled: true } : undefined
    return { value: { startedAt: 0, rateLimits: [], context: { window: 1_000_000, ...(breakdown ? { breakdown: breakdown as never } : {}) } } }
  })
  const usage = { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, model: 'x' }
  on('turn.step', async function* () {
    return { turnId: 'M1', index: 0, answer: '', toolUses: [], stopReason: 'end_turn' as const, usage }
  })
  const step = async (model: string) => {
    const s = $.turn.step({ turnId: 'M1', index: 0, model, messageCount: 1 })
    for await (const _ of s) void _
    await s.result
  }
  const measure = (tokens: number) =>
    $.session.measure({ context: { window: 1_000_000, tokens, percent: tokens / 10_000 }, rateLimits: [], changed: ['context'] })
  await step('claude-opus-5-5[1m]')
  await measure(300_000)
  await step('claude-opus-5-5[1m]')
  await measure(360_000)
  expect(reads).toBe(1) // the same model: not asked again
  // Another 1M model whose own autoCompactWindow (modelSettings) is 700k.
  compact = 700_000
  await step('claude-sonnet-5-5[1m]')
  await measure(360_000)
  expect(reads).toBe(2)
  const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await ui.find({ text: /360k\/700k/ })).toBeDefined()
  expect(await ui.find({ text: / 51%/ })).toBeDefined()
  await ui.unmount()
})

test('a resume through agent.spawn logs once, whether its spawn or its first step lands first; "done" times the run', async ($, on) => {
  const clock = mock.clock(on)
  on('ui.status', () => ({ value: undefined }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  const usage = { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, model: 'claude-sonnet-5-5' }
  on('turn.step', async function* () {
    return { turnId: 'R1', index: 0, answer: '', toolUses: [], stopReason: 'end_turn' as const, usage }
  })
  const step = async () => {
    const s = $.turn.step({ turnId: 'R1', index: 0, model: 'claude-sonnet-5-5', messageCount: 1, agentId: 'r1' })
    for await (const _ of s) void _
    await s.result
  }
  // A resumed agent may take its first step before its spawn's own hooks have finished.
  let isStepFirst = false
  on('agent.spawn', async (_$, e) => {
    if (e.resume && isStepFirst) await step()
    return { model: 'claude-sonnet-5-5', agentId: e.resume?.agentId ?? 'r1' }
  })
  const complete = (durationMs: number) =>
    $.turn.complete({ answer: 'ok', durationMs, isAborted: false, turnId: 'R1', agentId: 'r1', reason: 'answer' })
  const lines = async (re: RegExp) => {
    const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
    const n = (await ui.findAll({ text: re })).length
    await ui.unmount()
    return n
  }
  await $.turn.start({ text: 'go', turnId: 'T1' })
  await $.agent.spawn(spawn('general-purpose', 'Audit the parser'))
  await step()
  await clock.advance(60_000)
  await complete(60_000)
  // Idle half an hour, then resumed: the spawn first, then its step.
  await clock.advance(30 * 60_000)
  await $.agent.spawn({ ...spawn('general-purpose', 'Audit it again'), resume: { agentId: 'r1' } })
  await step()
  expect(await lines(/^resumed$/)).toBe(1)
  await clock.advance(90_000)
  await complete(90_000)
  // Resumed again, its first step landing inside the spawn.
  isStepFirst = true
  await $.agent.spawn({ ...spawn('general-purpose', 'And once more'), resume: { agentId: 'r1' } })
  expect(await lines(/^resumed$/)).toBe(2)
  expect(await lines(/^Audit the parser$/)).toBe(0) // one card, the latest task
  // Each run timed on its own, not from the first spawn.
  expect(await lines(/^done · 1m00s$/)).toBe(1)
  expect(await lines(/^done · 1m30s$/)).toBe(1)
})

test("a subagent's turn start is its own: no prompt line, and the main turn keeps its count", { options: { panels: 'main,fid,architect,gate,agents,receipt,log' } }, async ($, on) => {
  engine(on)
  on('tool.call', () => ({ result: {}, text: 'ok' }))
  await $.turn.start({ text: 'refactor it', turnId: 'T1' })
  await $.tool.call({ tool: 'Edit', file_path: '/x.ts', old_string: 'a', new_string: 'b' } as never)
  await $.turn.start({ text: 'Look at the parser again', turnId: 'A1', agentId: 'sub1' })
  await $.turn.complete({ answer: '', durationMs: 1000, isAborted: false, turnId: 'T1', reason: 'answer' })
  const ui = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  expect(await ui.find({ text: /Look at the parser again/ })).toBeUndefined()
  expect(await ui.find({ text: /refactor it/ })).toBeDefined()
  expect(await ui.find({ text: /· 1 edit ·/ })).toBeDefined()
  await ui.unmount()
})

test('a line keeps the pieces that fit, in order, counting each lead and the gaps between them', () => {
  const pieces = [{ width: 5 }, { width: 5, lead: 2 }, { width: 3 }]
  expect([piecesThatFit(pieces, 13, 1), piecesThatFit(pieces, 12, 1), piecesThatFit(pieces, 17, 1), piecesThatFit(pieces, 4, 1)]).toEqual([2, 1, 3, 0])
  expect([cellWidth('■ ▰▱ 48%'), cellWidth('')]).toEqual([8, 0])
})

// ---------------------------------------------------------------- width check

// The kit lays nothing out, so this measures the drawn tree as a row layout would: the fewest cells
// each element needs without spilling (a truncating Text or a clipping Box needs none, a Text that
// asks to wrap its longest word, any other Text its whole length, a plain Button with a hotkey `1: `
// more than its label), and checks that every Box given a width holds what it contains.
type Drawn = { type: string; props?: Record<string, unknown>; children?: unknown[] }
const isDrawn = (n: unknown): n is Drawn => typeof n === 'object' && n !== null && typeof (n as Drawn).type === 'string'
const cellsOf = (s: string) => [...s].length
const textOf = (n: unknown): string =>
  typeof n === 'string' || typeof n === 'number' ? String(n) : isDrawn(n) ? (n.children ?? []).map(textOf).join('') : ''
const spaceOf = (v: unknown) => (typeof v === 'number' ? v : v === undefined ? 0 : 1)
const longestWord = (s: string) => Math.max(0, ...s.split(/\s+/).map(cellsOf))
const needs = (n: unknown, out: string[], path: string): number => {
  if (typeof n === 'string') return longestWord(n)
  if (!isDrawn(n)) return 0
  const p = n.props ?? {}
  const here = `${path}/${String(p.key ?? n.type)}`
  if (n.type === 'Text') return p.wrap === undefined ? cellsOf(textOf(n)) : p.wrap === 'wrap' ? longestWord(textOf(n)) : 1
  if (n.type === 'Button') return cellsOf(String(p.label ?? '')) + (p.plain ? (p.hotkey ? 3 : 0) : 4)
  if (n.type === 'Client') return typeof p.width === 'number' ? p.width : 5
  if (n.type !== 'Box') return 0
  const kids = (n.children ?? []).filter(c => c !== null && c !== undefined && c !== false && c !== '')
  const inner = kids.map((c, i) => needs(c, out, `${here}[${i}]`))
  const isColumn = p.flexDirection === 'column' || p.flexDirection === 'column-reverse'
  const content =
    isColumn || p.flexWrap === 'wrap'
      ? Math.max(0, ...inner)
      : inner.reduce((a, b) => a + b, 0) + spaceOf(p.columnGap ?? p.gap) * Math.max(0, inner.length - 1)
  const need = content + (p.borderStyle ? 2 : 0) + 2 * spaceOf(p.paddingX ?? p.padding)
  const margin = spaceOf(p.marginLeft) + spaceOf(p.marginRight) + 2 * spaceOf(p.marginX)
  // A Box with a width must hold its contents, clipping or not; one without clips to nothing if it may.
  if (typeof p.width === 'number') {
    if (need > p.width) out.push(`${here}: needs ${need} in ${p.width}`)
    return p.width + margin
  }
  return (p.overflow === 'hidden' ? 0 : need) + margin
}

/**
 * What a graphical surface needs of a line of text: no `truncate` Text nests Texts (the desktop app wraps the
 * nested pieces, or lays truncating ones out as blocks of their own), and no Text placed in a Box starts or
 * ends with a space (it collapses spaces, so a gap between pieces is the Box's, not the text's).
 */
const desktopFaults = (n: unknown, out: string[], path = '', parent = ''): string[] => {
  if (!isDrawn(n)) return out
  const p = n.props ?? {}
  const here = `${path}/${String(p.key ?? n.type)}`
  const kids = (n.children ?? []).filter(isDrawn)
  if (n.type === 'Text') {
    const text = textOf(n)
    if (p.wrap === 'truncate' && kids.some(k => k.type === 'Text')) out.push(`${here}: truncates nested Texts "${text}"`)
    if (parent === 'Box' && text !== text.trim()) out.push(`${here}: edge spaces "${text}"`)
    return out
  }
  kids.forEach((k, i) => desktopFaults(k, out, `${here}[${i}]`, n.type))
  return out
}
const spillsOf = (tree: unknown, columns: number) => {
  const out: string[] = []
  const need = needs(tree, out, '')
  if (need > columns) out.push(`root: needs ${need} in ${columns}`)
  return out
}

/** A session with every panel busy: a compaction window, limits, consults with advice, checks of every kind, agents, a loop. */
const busySession = async ($: Parameters<TestBody>[0], on: On) => {
  const clock = engine(on)
  await clock.advance(3_600_000) // clocks draw as m:ss, as in a session, not as the '—' of an unknown start
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('tool.check', (_$, e) => ({ decision: (e.tool_use_id ?? '').endsWith('7') ? 'deny' : 'allow' }))
  on('tool.call', () => ({ result: {}, text: 'ok' }))
  let n = 0
  on('agent.spawn', (_$, e) => ({ model: 'claude-sonnet-5-5', agentId: e.subagentType.includes('advisor') ? 'adv1' : `b${++n}` }))
  const usage = { input_tokens: 4000, output_tokens: 900, cache_read_input_tokens: 120_000, cache_creation_input_tokens: 0, model: 'claude-opus-5-5' }
  on('turn.step', async function* () {
    yield { kind: 'text' as const, index: 0, text: 'ok' }
    yield { kind: 'stop' as const, stopReason: 'end_turn' as const, usage }
    return { turnId: 'B1', index: 0, answer: 'ok', toolUses: [], stopReason: 'end_turn' as const, usage }
  })
  const step = async (agentId?: string) => {
    const s = $.turn.step({ turnId: 'B1', index: 0, model: 'claude-opus-5-5[1m]', messageCount: 1, ...(agentId ? { agentId } : {}) })
    for await (const _ of s) void _
    await s.result
  }
  await $.session.measure({
    context: { window: 1_000_000, tokens: 360_000, percent: 36 },
    rateLimits: [
      { kind: 'five_hour', percentUsed: 82, resetsAt: new Date(3 * 3_600_000).toISOString() },
      { kind: 'seven_day_opus', percentUsed: 40, resetsAt: new Date(4 * 86_400_000).toISOString() },
    ],
    cost: { usd: 123.45 },
    changed: ['context', 'rateLimits', 'cost'],
  } as never)
  await $.turn.start({ text: 'Refactor the configuration loader and keep every public name stable please', turnId: 'B1' })
  await step()
  const tools = [
    { tool: 'Bash', input: { command: 'npm run test -- --reporter=verbose --coverage packages/configuration-loader' } },
    { tool: 'Read', input: { file_path: '/Users/someone/projects/a-very-long-repository-name/src/configuration/loader.ts' } },
    { tool: 'WebFetch', input: { url: 'https://example.com/a/very/long/documentation/path/for/the/loader' } },
  ]
  for (let i = 0; i < 60; i += 1) await $.tool.check({ ...tools[i % 3]!, tool_use_id: `k${i}` })
  await $.tool.call({ tool: 'Edit', file_path: '/x/loader.ts', old_string: 'a', new_string: 'b', tool_use_id: 'edit1' } as never)
  await $.agent.spawn(spawn('fable-advisor:fable-advisor', 'final review of the loader'))
  await $.turn.complete({
    answer: 'Ship it once the configuration loader keeps its public names and the migration test covers the old shape',
    durationMs: 9000, isAborted: false, turnId: 'A1', agentId: 'adv1', reason: 'answer',
  })
  for (const d of ['Write the configuration loader regression tests', 'Map every call site of the old loader', 'Review the migration path for saved state']) {
    await $.agent.spawn(spawn('general-purpose', d))
  }
  await step('b1')
  await step('wf-unclaimed-loop')
  await clock.advance(95_000)
  await $.turn.complete({ answer: '', durationMs: 95_000, isAborted: false, turnId: 'B1', reason: 'answer' })
  return clock
}

test('every panel fits the pane at every width from 24 columns, on every surface and placement, in lines a graphical surface keeps whole', { timeoutMs: 60_000, options: { panels: 'main,fid,architect,gate,agents,log' } }, async ($, on) => {
  await busySession($, on)
  const failures: string[] = []
  const check = async (label: string) => {
    for (const surface of ['terminal', 'desktop', 'vscode', 'mobile'] as const) {
      for (let cols = 24; cols <= 40; cols += 1) {
        for (const placement of ['dock', 'inline'] as const) {
          const ui = await $.ui.mount({ ...pane(cols), props: { ...pane(cols).props, placement }, surface })
          for (const s of spillsOf(await ui.drawn(), cols)) failures.push(`${label} ${surface} ${placement} ${cols}: ${s}`)
          await ui.unmount()
        }
      }
      for (const cols of [64, 120]) {
        const ui = await $.ui.mount({ ...pane(cols), surface })
        for (const s of spillsOf(await ui.drawn(), cols)) failures.push(`${label} ${surface} dock ${cols}: ${s}`)
        await ui.unmount()
      }
    }
  }
  await check('lanes, finished')
  // The gate drill-down and an expanded card open, and a turn running.
  const opener = await $.ui.mount({ ...pane(64), surface: 'terminal' })
  await opener.press({ key: 'gate-shell' })
  await opener.press({ key: 'card-b1' })
  await opener.unmount()
  await $.turn.start({ text: 'and once more', turnId: 'B2' })
  await check('drill-down, expanded, running')
  for (const surface of ['terminal', 'desktop'] as const) {
    for (const cols of [24, 32, 40, 64, 120]) {
      for (const placement of ['dock', 'inline'] as const) {
        const ui = await $.ui.mount({ ...pane(cols), props: { ...pane(cols).props, placement }, surface })
        for (const f of desktopFaults(await ui.drawn(), [])) failures.push(`${surface} ${placement} ${cols}: ${f}`)
        await ui.unmount()
      }
    }
  }
  // One line per panel and width that spills, the surface left out (they draw the same boxes).
  expect([...new Set(failures.map(f => f.replace(/ (terminal|desktop|vscode|mobile) /, ' ')))]).toEqual([])
})

test('a single agent card fits from 24 columns, and the time axis scales to the pane', async ($, on) => {
  const clock = engine(on)
  await clock.advance(3_600_000)
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'one' }))
  await $.turn.start({ text: 'go', turnId: 'O1' })
  await $.agent.spawn(spawn('general-purpose', 'Write the configuration loader regression tests'))
  const failures: string[] = []
  for (const surface of ['terminal', 'desktop', 'vscode', 'mobile'] as const) {
    for (let cols = 24; cols <= 40; cols += 1) {
      const ui = await $.ui.mount({ ...pane(cols), surface })
      for (const s of spillsOf(await ui.drawn(), cols)) failures.push(`${surface} ${cols}: ${s}`)
      if (surface !== 'terminal') {
        // No pixel width of its own: the surface draws it at the markup's width, down to the pane's.
        const svg = await ui.find({ type: 'Svg' })
        expect([svg !== undefined, svg?.props.width, svg?.props.height]).toEqual([true, undefined, undefined])
      }
      await ui.unmount()
    }
  }
  expect(failures).toEqual([])
})

test('a running connector keeps its length every frame: one face, clipped at its width, the dot still moving', { options: { panels: 'main,fid,architect,gate,agents,log' } }, async ($, on) => {
  engine(on)
  on('tool.check', () => ({ decision: 'allow' }))
  await $.tool.check({ tool: 'Read', input: { file_path: '/a' }, tool_use_id: 'r1' })
  await $.turn.start({ text: 'go', turnId: 'R1' }) // a turn running: the connectors animate
  for (const surface of ['desktop', 'terminal'] as const) {
    const ui = await $.ui.mount({ ...pane(64), surface })
    expect((await ui.find({ key: 'link-gate' }))?.type).toBe('Client')
    const heads = new Set<number>()
    for (let frame = 0; frame < 30; frame += 1) {
      const tree = (await ui.drawn({ in: 'link-gate' })) as Drawn
      const texts: Drawn[] = []
      const walk = (n: unknown) => {
        if (!isDrawn(n)) return
        if (n.type === 'Text') texts.push(n)
        else (n.children ?? []).forEach(walk)
      }
      walk(tree)
      const line = texts.map(textOf).join('')
      // The box is the line's width and clips; its text is that width and four spare cells, every frame.
      expect([tree.type, tree.props?.width, tree.props?.overflow]).toEqual(['Box', 64, 'hidden'])
      expect(cellsOf(line)).toBe(64 + 4)
      expect(texts.every(t => t.props?.mono === true)).toBe(true)
      expect(/^[─●•┬┴]+$/.test(line)).toBe(true)
      const head = [...line].slice(0, 64).indexOf('●')
      if (head >= 0) heads.add(head)
      await ui.advance(110)
    }
    expect(heads.size > 5).toBe(true) // the dot travels along the line
    await ui.unmount()
  }
})

// ---------------------------------------------------------------- devFSD: 처리기 예외 격리 (AC-3)
// 관제판은 관찰만 한다 — 처리기 본문이 던져도 다음 단계(next)는 정확히 1회 실행되고 그 반환값이 그대로 돌아온다.
// next 를 이미 부른 뒤 던지는 처리기(tool.check·tool.call·agent.spawn)는 clock.now 를 던지게 해 만들고,
// next 전에 던지는 처리기(session.append·classic.UserPromptSubmit)는 clock.now / state.set 으로 만든다.
const boomClock = (on: On) =>
  on('clock.now', () => {
    throw new Error('boom: clock')
  })

test('devFSD: tool.check — a body that throws after next still returns next\'s verdict, next ran once', async ($, on) => {
  let ran = 0
  on('tool.check', () => (ran += 1, { decision: 'ask' as const }))
  boomClock(on)
  const verdict = await $.tool.check({ tool: 'Read', input: { file_path: '/a' }, tool_use_id: 'iso-check' })
  expect(verdict).toEqual({ decision: 'ask' })
  expect(ran).toBe(1)
})

test('devFSD: tool.call — a body that throws after next still returns next\'s answer, next ran once', async ($, on) => {
  let ran = 0
  const answer = { result: {}, text: 'sentinel-call' }
  on('tool.call', () => (ran += 1, answer))
  boomClock(on)
  const out = await $.tool.call({ tool: 'Edit', file_path: '/x.ts', old_string: 'a', new_string: 'b', tool_use_id: 'iso-call' } as never)
  expect(out).toEqual(answer)
  expect(ran).toBe(1)
})

test('devFSD: agent.spawn — a body that throws after next still returns next\'s answer, next ran once', async ($, on) => {
  let ran = 0
  const answer = { model: 'claude-sonnet-5-5', agentId: 'iso-agent' }
  on('agent.spawn', () => (ran += 1, answer))
  boomClock(on)
  const out = await $.agent.spawn(spawn('general-purpose', 'isolate me'))
  expect(out).toEqual(answer)
  expect(ran).toBe(1)
})

test('devFSD: session.append{response} — a body that throws before next still reaches next, once', async ($, on) => {
  let ran = 0
  on('session.append', { door: 'response' }, async (_$, e, next) => (ran += 1, next(e)))
  boomClock(on)
  const row = {
    message: { type: 'assistant', role: 'assistant', content: [{ type: 'server_tool_use', id: 'iso-srv', name: 'advisor', input: {} }] as never },
    door: 'response' as const,
    origin: { kind: 'model', model: 'claude-opus-5-5' } as never,
    uuid: 'iso-row',
  }
  const out = await $.session.append(row)
  expect(out.uuid).toBe('iso-row')
  expect(ran).toBe(1)
})

test('devFSD: classic.UserPromptSubmit — a body that throws before next still reaches next, once', async ($, on) => {
  let ran = 0
  const answer = { sentinel: 'classic-answer' }
  on('classic.UserPromptSubmit', () => (ran += 1, { value: answer as never }))
  // every write of the mode is refused (never "set"), so update() gives up and throws — before next
  on('state.set', () => ({ deny: 'refused' }) as never)
  const out = await $.classic.UserPromptSubmit({ prompt: 'hi', session_id: 's1', transcript_path: '/t', cwd: '/', hook_event_name: 'UserPromptSubmit', permission_mode: 'plan' } as never)
  expect(out).toEqual({ value: answer })
  expect(ran).toBe(1)
})

test('devFSD: a failure inside next itself is not swallowed — it reaches the caller and next is not retried', async ($, on) => {
  let ran = 0
  on('tool.call', () => {
    ran += 1
    throw new Error('downstream boom')
  })
  let caught: unknown
  try {
    await $.tool.call({ tool: 'Edit', file_path: '/x.ts', old_string: 'a', new_string: 'b', tool_use_id: 'iso-down' } as never)
  } catch (e) {
    caught = e
  }
  expect(caught).toBeDefined()
  expect(ran).toBe(1)
})


// ---------------------------------------------------------------- activity badge (baseline)

// 엔진이 next() 인자의 { answer } 를 검사하므로 turn.complete 는 완전한 모양으로 부른다(tasks.md 의 `{ turnId } as never` 대체).
const finished = (turnId: string, agentId?: string) => ({ answer: '', durationMs: 10, isAborted: false, turnId, reason: 'answer' as const, ...(agentId ? { agentId } : {}) })

const inline = (cols: number) => ({ ...pane(cols), props: { ...pane(cols).props, placement: 'inline' as const } })

test('devFSD: baseline — idle and working text on every width and placement', async ($, on) => {
  const clock = engine(on)
  for (const cols of [40, 86]) {
    for (const make of [pane, inline]) {
      const ui = await $.ui.mount({ ...make(cols), surface: 'terminal' })
      expect(await ui.findAll({ type: 'Text', text: /○ idle/ })).toHaveLength(make === pane ? 1 : 2) // 실측: 메인 패널 Text 1개 · 미니는 조각 Text 와 그 부모 Text 2개(중첩)
      await ui.unmount()
    }
  }
  await $.turn.start({ text: 'go', turnId: 'B1' })
  const ui = await $.ui.mount({ ...pane(86), surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /● working/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /WORKS/ })).toBeDefined()
  await ui.unmount()
  await $.turn.complete(finished('B1'))
  await clock.advance(600_000)
  const idle = await $.ui.mount({ ...pane(86), surface: 'terminal' })
  expect(await idle.find({ type: 'Text', text: /IDLE/ })).toBeDefined()
  expect(await idle.find({ type: 'Text', text: /작업 \d|정체 의심/ })).toBeUndefined() // 작업 0 이면 10분 뒤에도 배지 없음
  await idle.unmount()
})

// ---------------------------------------------------------------- activity badge

const bg = (id: string) => ({ tool: 'Bash', tool_use_id: id, command: 'x', description: 'publish', run_in_background: true }) as never
const shows = async ($: Parameters<TestBody>[0], cols: number, re: RegExp, make: typeof pane | typeof inline = pane) => {
  const ui = await $.ui.mount({ ...make(cols), surface: 'terminal' })
  const found = await ui.find({ type: 'Text', text: re }) // Text 만 — 조상 Box 의 합쳐진 글이 정규식에 걸리지 않게
  await ui.unmount()
  return found
}
/** progress-pane 의 `notify` 와 같은 session.append 인자 — 백그라운드 작업 종료 알림. */
const taskDone = (id: string) =>
  ({
    door: 'delivery',
    origin: { kind: 'task-notification' },
    uuid: `row-${id}-completed`,
    message: { type: 'user', content: [{ type: 'text', text: `<tool-use-id>${id}</tool-use-id><status>completed</status>` }] },
  }) as never

test('devFSD: jobs show as a count that follows the running list down to idle', async ($, on) => {
  const clock = engine(on)
  on('process.run', () => ({ value: { exitCode: 1, stdout: '', stderr: '' } }))
  on('tool.call', () => ({ result: {}, text: 'ok' }))
  await $.turn.start({ text: 'go', turnId: 'J1' })
  await $.tool.call(bg('j1')); await $.tool.call(bg('j2'))
  await clock.advance(30_000)
  expect(await shows($, 86, /● working/)).toBeDefined()
  expect((await shows($, 86, /작업 2/))?.text).toContain('작업 2 · 30초 경과 · 마지막 활동 30초 전')
  expect(await shows($, 86, /BG 2/)).toBeDefined() // 턴이 도는 중에도 헤더 BG 는 보인다
  await $.turn.complete(finished('J1'))
  // 턴은 끝났지만 작업이 도는 중 — 완전한 idle 이 아니라 대기, 헤더에 BG 개수
  expect(await shows($, 86, /◐ 대기/)).toBeDefined()
  expect(await shows($, 86, /○ idle/)).toBeUndefined()
  expect((await shows($, 86, /BG 2/))?.text).toContain('· BG 2')
  await $.session.append(taskDone('j1')); expect(await shows($, 86, /작업 1/)).toBeDefined()
  expect((await shows($, 86, /BG 1/))?.text).toContain('· BG 1')
  await $.session.append(taskDone('j2'))
  expect(await shows($, 86, /작업 \d/)).toBeUndefined()
  expect(await shows($, 86, /BG \d/)).toBeUndefined()
  expect(await shows($, 86, /◐ 대기/)).toBeUndefined()
  expect(await shows($, 86, /○ idle/)).toBeDefined()
})

test('every panel with a background job fits the pane and keeps its badge free of edge spaces, before and after a stall', { timeoutMs: 60_000 }, async ($, on) => {
  const clock = await busySession($, on)
  await $.tool.call(bg('fit1'))
  const failures: string[] = []
  const check = async (label: string) => {
    for (const surface of ['terminal', 'desktop'] as const) {
      for (const cols of [24, 32, 40, 45, 59, 60, 64, 80, 120]) {
        for (const placement of ['dock', 'inline'] as const) {
          const ui = await $.ui.mount({ ...pane(cols), props: { ...pane(cols).props, placement }, surface })
          const tree = await ui.drawn()
          for (const s of spillsOf(tree, cols)) failures.push(`${label} ${surface} ${placement} ${cols}: ${s}`)
          if (surface === 'desktop') for (const f of desktopFaults(tree, [])) failures.push(`${label} ${surface} ${placement} ${cols}: ${f}`)
          await ui.unmount()
        }
      }
    }
  }
  await check('job, fresh')
  await clock.advance(360_000)
  await check('job, stalled')
  expect(failures).toEqual([])
})

test('devFSD: five quiet minutes with a job turns the badge into a stall warning, clearing on new activity', async ($, on) => {
  const clock = engine(on)
  on('process.run', () => ({ value: { exitCode: 1, stdout: '', stderr: '' } }))
  on('tool.call', () => ({ result: {}, text: 'ok' }))
  await $.tool.call(bg('s1'))
  await clock.advance(299_000)
  expect(await shows($, 86, /정체 의심/)).toBeUndefined()
  await clock.advance(1_000)
  expect((await shows($, 86, /정체 의심/))?.text).toContain('⚠ 정체 의심 · 작업 1 · 5분 경과 · 5분 전')
  await $.tool.call({ tool: 'Read', tool_use_id: 'r1', file_path: '/x' } as never)
  expect(await shows($, 86, /정체 의심/)).toBeUndefined()
})

// 이벤트별: 290초 무활동 뒤 이벤트 X → 20초 뒤 `마지막 활동 20초 전` 이고 정체 아님 (X 가 없었다면 310초 = 정체)
const eventCases: [string, ($: Parameters<TestBody>[0]) => Promise<unknown>][] = [
  ['turn.start', $ => $.turn.start({ text: 'again', turnId: 'E1' })],
  ['main tool.call', $ => $.tool.call({ tool: 'Read', tool_use_id: 'e2', file_path: '/x' } as never)],
  ['subagent tool.call', $ => $.tool.call({ tool: 'Read', tool_use_id: 'e3', file_path: '/x', agentId: 'sub1' } as never)],
  ['agent.spawn', $ => $.agent.spawn(spawn('general-purpose', 'x'))],
  ['turn.step', async $ => {
    const s = $.turn.step({ turnId: 'E1', index: 0, model: 'claude-opus-5-5', messageCount: 1 }) // 스트림을 끝까지 소비해야 처리기 본문이 돈다
    for await (const _ of s) void _
    await s.result
  }],
]
for (const [name, fire] of eventCases) {
  test(`devFSD: ${name} counts as activity`, async ($, on) => {
    const clock = engine(on)
    on('process.run', () => ({ value: { exitCode: 1, stdout: '', stderr: '' } }))
    on('tool.call', () => ({ result: {}, text: 'ok' }))
    on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'c1' }))
    on('turn.step', async function* () {
      return { turnId: 'E1', index: 0, answer: '', toolUses: [], stopReason: 'end_turn' as const, usage: { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, model: 'claude-opus-5-5' } }
    })
    await $.tool.call(bg('ev'))
    await clock.advance(290_000)
    await fire($)
    await clock.advance(20_000)
    expect((await shows($, 86, /작업 1/))?.text).toContain('작업 1 · 5분 경과 · 마지막 활동 20초 전')
    expect(await shows($, 86, /정체 의심/)).toBeUndefined()
  })
}

test('devFSD: a subagent turn.complete is not activity', async ($, on) => {
  const clock = engine(on)
  on('process.run', () => ({ value: { exitCode: 1, stdout: '', stderr: '' } }))
  on('tool.call', () => ({ result: {}, text: 'ok' }))
  await $.tool.call(bg('na'))
  await clock.advance(290_000)
  await $.turn.complete(finished('sub', 'sub1'))
  await clock.advance(20_000)
  expect(await shows($, 86, /⚠ 정체 의심/)).toBeDefined()
})

test('devFSD: the badge never takes pieces away from a narrow line (AC-R-1)', async ($, on) => {
  const clock = engine(on)
  on('process.run', () => ({ value: { exitCode: 1, stdout: '', stderr: '' } }))
  on('tool.call', () => ({ result: {}, text: 'ok' }))
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('agent.spawn', () => ({ model: 'claude-fable-5-1', agentId: 'fab1' }))
  // 기준선 행에 ctx·비용·architect 조각이 있어야 의미가 있다 — 세 조각이 나오게 시드한다.
  await $.session.measure({ context: { window: 200_000, tokens: 100_000, percent: 50 }, rateLimits: [], cost: { usd: 1.5 }, changed: ['context', 'cost'] } as never)
  await $.agent.spawn(spawn('fable-advisor:fable-advisor', 'review'))
  const rowsFor = async (cols: number, make: typeof pane) => {
    const ui = await $.ui.mount({ ...make(cols), surface: 'terminal' })
    const rows = (await ui.findAll({ type: 'Text' })).map(one => one.text ?? '')
    await ui.unmount()
    return rows
  }
  // 작업이 도는 동안 idle 조각은 대기 표시로 바뀐다(의도) — 그 밖의 조각은 그대로여야 한다.
  const whileWaiting = (piece: string) => piece.replace('○ idle', '◐ 대기')
  const widths = [24, 26, 27, 40, 59, 60, 86]
  const base: Record<string, string[]> = {}
  for (const cols of widths) for (const make of [pane, inline]) base[`${make === pane ? 'dock' : 'inline'}-${cols}`] = await rowsFor(cols, make)
  await clock.advance(1_000) // 시드(spawn)의 활동과 작업 호출 사이를 띄운다
  await $.tool.call(bg('nw'))
  let sawBadge = false
  for (const [stalled, ms] of [[false, 150_000], [true, 270_000]] as const) {
    await clock.advance(ms)
    for (const cols of widths) {
      for (const make of [pane, inline]) {
        const key = `${make === pane ? 'dock' : 'inline'}-${cols}`
        const rows = await rowsFor(cols, make)
        for (const piece of base[key].filter(r => /(Opus|Sonnet|idle|IDLE|ctx|\$|architect)/i.test(r))) expect(rows).toContain(whileWaiting(piece)) // 기준선 조각(모델·상태·ctx·비용·architect) 보존
        if (cols >= 40) expect(base[key].some(r => /ctx/.test(r))).toBe(true) // 양성 대조: 시드가 실제로 ctx 조각을 만들었다
        const badge = rows.find(r => /작업 1/.test(r))
        if (make === pane && cols < 40) expect(badge).toBeUndefined() // dock 은 40 미만에서 배지 없음
        if (make === inline) { // 미니(inline)는 어떤 폭에서도 배지 줄이 보여야 한다 — 부재가 아니라 존재를 요구
          expect(badge).toBeDefined()
          expect(badge).toBe(cols < 60 ? (stalled ? '⚠ 작업 1 · 7m · 정체 7m' : '작업 1 · 2m') : (stalled ? '⚠ 정체 의심 · 작업 1 · 7분 경과 · 7분 전' : '작업 1 · 2분 경과 · 마지막 활동 2분 전'))
        }
        if (badge) {
          sawBadge = true
          expect(badge).toMatch(cols < 60 ? (stalled ? /⚠ 작업 1 · \d+m/ : /작업 1 · \d+m/) : /작업 1 · /)
        }
      }
    }
  }
  expect(sawBadge).toBe(true) // 양성 대조: 배지가 한 번도 안 뜨면 위 보존 검사는 아무것도 보지 않은 것
})

test('devFSD: a clock that fails inside the activity write neither blocks nor repeats the tool call', async ($, on) => {
  let broken = false
  const flaky = ((event: string, ...rest: unknown[]) => {
    const last = rest.length - 1
    const hook = rest[last] as (...a: unknown[]) => unknown
    if (event === 'clock.now') rest[last] = (...a: unknown[]) => { if (broken) throw new Error('clock down'); return hook(...a) }
    return (on as (...a: unknown[]) => unknown)(event, ...rest)
  }) as On
  engine(flaky)
  let ran = 0
  on('tool.call', () => { ran += 1; return { result: {}, text: 'ok' } })
  broken = true
  const out = await $.tool.call({ tool: 'Read', tool_use_id: 'tr2', file_path: '/x' } as never)
  expect(out.text).toBe('ok')
  expect(ran).toBe(1)
  broken = false
  await $.tool.call({ tool: 'Read', tool_use_id: 'tr3', file_path: '/x' } as never)
  expect(ran).toBe(2) // 이후 호출도 정상
})

// ---------------------------------------------------------------- devFSD: CI 잡 합산 (FID 20261106-console-ci-jobs)

const CI_OUT = JSON.stringify([
  { name: 'run-all', bucket: 'pass' },
  { name: 'mac', bucket: 'pending' },
  { name: 'lint', bucket: 'pending' },
])

/** 활성 FID 가 있는 /w 세계: gh 호출을 기록하고 answer 로 답한다. */
const ciWorld = (on: On, answer: () => unknown) => {
  const clock = engine(on)
  const gh: string[][] = []
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('ui.open', () => ({ value: { isPlaced: true as const } }))
  on('fs.exists', () => ({ value: true }))
  on('fs.read', () => ({ value: '# p\n<!-- active-fid: 20261106-x -->\n\n## 20261106-x · y\n\n- 2026-11-06 10:00 /analyze 완료 (x)\n' }))
  on('process.run', (_$, e) => {
    const argv = (e as unknown as { argv: string[] }).argv
    if (argv[0] !== 'gh') return { value: { exitCode: 1, stdout: '', stderr: '' } }
    gh.push(argv)

    return { value: answer() as never }
  })

  return Object.assign(gh, { clock })
}
const settle = async () => { for (let i = 0; i < 300; i++) await Promise.resolve() }
const fidLine = async ($: Parameters<TestBody>[0]) => {
  const ui = await $.ui.mount({ ...pane(80), surface: 'terminal' })
  const node = await ui.find({ text: /백그라운드 작업|CI / })
  await ui.unmount()

  return node?.props?.children ?? node?.text
}

test('AC-5 ciWatch on: pending CI jobs join the background count, with the CI line', { options: { ciWatch: true } }, async ($, on) => {
  const gh = ciWorld(on, () => ({ exitCode: 0, stdout: CI_OUT, stderr: '' }))
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  await settle()
  expect(gh.length).toBe(1)
  expect(String(await fidLine($))).toContain('백그라운드 작업 2개 실행 중 · CI 1/3 통과')
})

test('devFSD: the FID card lists each running job with its run length, up to three', async ($, on) => {
  const { clock } = ciWorld(on, () => ({ exitCode: 1, stdout: '', stderr: '' }))
  on('tool.call', () => ({ result: {}, text: 'ok' }))
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  await settle()
  const rows = async () => {
    const ui = await $.ui.mount({ ...pane(80), surface: 'terminal' })
    const found = (await ui.findAll({ type: 'Text' })).map(t => t.text ?? '').filter(r => /^↻ publish · |^… 외/.test(r))
    await ui.unmount()

    return found
  }
  expect(await rows()).toEqual([])
  await $.tool.call(bg('r1'))
  await clock.advance(30_000)
  await $.tool.call(bg('r2'))
  expect(await rows()).toEqual(['↻ publish · 30초', '↻ publish · 0초'])
  await $.tool.call(bg('r3')); await $.tool.call(bg('r4')); await $.tool.call(bg('r5'))
  expect(await rows()).toEqual(['↻ publish · 30초', '↻ publish · 0초', '↻ publish · 0초', '… 외 2개'])
  await $.session.append(taskDone('r1')); await $.session.append(taskDone('r2')); await $.session.append(taskDone('r3')); await $.session.append(taskDone('r4')); await $.session.append(taskDone('r5'))
  expect(await rows()).toEqual([])
})

test('AC-5 a lost PR (gh fails) clears the line, quietly', { options: { ciWatch: true } }, async ($, on) => {
  let ok = true
  const gh = ciWorld(on, () => (ok ? { exitCode: 0, stdout: CI_OUT, stderr: '' } : { exitCode: 1, stdout: '', stderr: 'no pull requests found' }))
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  await settle()
  ok = false
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  await settle()
  expect(gh.length).toBe(2)
  expect(await fidLine($)).toBeUndefined()
})

test('AC-4 ciWatch off (default): gh is never called and nothing is drawn', async ($, on) => {
  const gh = ciWorld(on, () => ({ exitCode: 0, stdout: CI_OUT, stderr: '' }))
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  await settle()
  expect(gh.length).toBe(0)
  expect(await fidLine($)).toBeUndefined()
})

test('AC-4 parseConfig: ciWatch defaults off, interval defaults 60 and never goes under 30', () => {
  expect(parseConfig({}).ciWatch).toBe(false)
  expect(parseConfig({}).ciIntervalSec).toBe(60)
  expect(parseConfig({ ciWatch: true, ciIntervalSec: 5 })).toMatchObject({ ciWatch: true, ciIntervalSec: 30 })
  expect(parseConfig({ ciIntervalSec: 120 }).ciIntervalSec).toBe(120)
  expect(parseConfig({ ciIntervalSec: 'x' }).ciIntervalSec).toBe(60)
})

test('devFSD: gaugeColor turns amber at 60 and warn at 80', () => {
  const C = PALETTES.theme
  expect([0, 59, 60, 79, 80, 100].map(p => gaugeColor(p, C))).toEqual([C.main, C.main, C.amber, C.amber, C.warn, C.warn])
})

test('devFSD: stageProgress counts done stages up to the current one and names the next', () => {
  const s = (key: string, mark: StageMark['mark'], isCurrent = false): StageMark => ({ key, label: key, mark, ...(isCurrent ? { isCurrent } : {}) })
  const stages = [s('a', '✓'), s('b', '✓'), s('c', '●', true), s('d', '○')]
  expect(stageProgress(stages)).toEqual({ done: 2, step: 3, total: 4, current: 'c', next: 'd', isDone: false })
  expect(stageProgress([s('a', '✓'), s('b', '✓')])).toEqual({ done: 2, step: 2, total: 2, current: null, next: null, isDone: true })
  expect(stageProgress([s('a', '✓'), s('b', '●', true)])).toEqual({ done: 1, step: 2, total: 2, current: 'b', next: null, isDone: false })
  expect(stageProgress([s('a', '✓'), s('b', '○')])).toEqual({ done: 1, step: 1, total: 2, current: null, next: null, isDone: false }) // 옛 보드: 현재 없음·미완
})

test('devFSD: aurora flows fast while working, slowly while waiting, and rests otherwise', () => {
  const lit = (cells: ReturnType<typeof auroraCells>) => cells.map((c, i) => (c.isLit ? i : -1)).filter(i => i >= 0)
  // 띠가 완전히 안에 들어오는 phase 만 (working len 12, waiting len 8, width 40)
  const W = [12, 18, 24].map(p => lit(auroraCells(p, 40, 'working')))
  expect(W.map(a => a.length)).toEqual([12, 12, 12]); expect(W.map(a => a[0])).toEqual([0, 6, 12])   // 1칸/프레임
  const S = [24, 30, 36].map(p => lit(auroraCells(p, 40, 'waiting')))
  expect(S.map(a => a.length)).toEqual([8, 8, 8]); expect(S.map(a => a[0])).toEqual([0, 2, 4])      // 1칸/3프레임
  const idle = [0, 1, 5, 52, 99].map(p => JSON.stringify(auroraCells(p, 40, 'idle')))
  expect(new Set(idle).size).toBe(1); expect(lit(auroraCells(5, 40, 'idle'))).toEqual([])
  for (const mode of ['working', 'waiting', 'idle'] as const) for (const w of [1, 8, 24, 40, 120]) for (const p of [0, 7, 99]) expect(auroraCells(p, w, mode)).toHaveLength(w)
  // 사양 hex 리터럴(구현 상수 import 금지) — 띠 12칸: 0~3 #D4537E, 4~7 #D85A30, 8~11 #EF9F27
  expect(auroraCells(12, 40, 'working').filter(c => c.isLit).map(c => c.color)).toEqual([...Array(4).fill('#D4537E'), ...Array(4).fill('#D85A30'), ...Array(4).fill('#EF9F27')])
})
