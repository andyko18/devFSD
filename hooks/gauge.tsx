// devFSD 계기판 — 입력창 바로 위 띠. 자료 수집(progress-pane.tsx)이 채운 상태를 읽어 그리기만 한다(차단·수정 없음).
//   그림을 그리는 화면(데스크톱 앱 등): 왼쪽에 이름(모델) · 명령·작업·누구 차례 · 버튼, 오른쪽에 그림 — 모드 둘을 버튼으로 바꾼다:
//     전기차 모드(기본) = 도로 보기(gauge-road.ts — 경로 띠 · 남은 단계 · 톨게이트) + 한도 글자 · 내연기관 모드 = 둥근 계기 셋(gauge-dial.ts).
//   터미널: 그림 요소가 없어 글자 세 줄로 그린다(상태+버튼 · 단계 점 · 모델·한도·비용).
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Board, CmdBoard, CmdStep, GaugeMode, GaugeView, Main, StageMark, Usage } from '../types'
import { DEFAULT_MAIN, DEFAULT_USAGE, fmtResetIn, fmtUsd, limitLabel, prettyModel } from './core'
import { DIAL_H, DIAL_SCALE, dialAlt, dialSvg, dialWidth } from './gauge-dial'
import type { DialModel, DialTick, DialTickState } from './gauge-dial'
import { ROAD_H, ROAD_SCALE, ROAD_W, roadAlt, roadSvg } from './gauge-road'
import { HELP_SECTIONS } from './gauge-help'
import { isGoverned } from './progress-pane'

const HELP_PANE = 'devfsd-help'
const HELP_TITLE = 'devFSD 도움말'
const CONSOLE_PANE = 'devfsd-console'
const CONSOLE_TITLE = 'devFSD 관제판'
const COMMAND = 'devfsd-gauge'
const MODE_KEY = 'gaugeMode' // $.store — 세션을 넘겨 기억한다
const MODE_NAMES: Record<GaugeMode, string> = { ev: '전기차 모드', ice: '내연기관 모드' }

/** 저장된 값 → 모드. 모르는 값·없음은 기본(전기차). */
export function modeOf(stored: unknown): GaugeMode {
  return stored === 'ice' ? 'ice' : 'ev'
}
// 강조색 하나 — 이름 · 지금 단계 · 버튼 기호에만 쓴다. 초록은 '달리는 중' 상태 점의 뜻이라 이름에는 쓰지 않는다.
const ACCENT = 'suggestion'
const BAR_WIDTH = 5
const HOT_PCT = 80 // 이 아래로는 막대에 색을 쓰지 않는다 — 평소엔 무채색
const LIMITS_SHOWN = 2
// 글자 한 칸의 픽셀 폭 어림(좁게 잡는다) — 띠가 계기 그림보다 좁을 때 그림을 줄이는 데만 쓴다.
const CELL_PX = 7
// 보안·통합·성능·데모는 계기판에서 한 점(게이트)으로 묶는다 — 상세는 관제판이 보여 준다.
const GATE_KEYS: readonly string[] = ['security', 'integration', 'performance', 'demo']
// 승인은 기록에 단계로 남지 않는다 — 이 단계 바로 뒤에 끼워 앞뒤 단계로 상태를 추정한다.
const APPROVAL_AFTER: readonly string[] = ['clarify', 'specify']

const board = atom({ plugin: 'devfsd', key: 'board' } as const, { running: [], recent: [] } as Board, { shape: 'board-3' })
const nowTick = atom({ plugin: 'devfsd', key: 'now' } as const, 0, { shape: 'now-1' })
const main = atom({ plugin: 'devfsd', key: 'main' } as const, DEFAULT_MAIN)
const usage = atom({ plugin: 'devfsd', key: 'usage' } as const, DEFAULT_USAGE)
const DEFAULT_GAUGE: GaugeView = { isGoverned: false, isHidden: false }
// Change the tag when the value's fields change: it declines what an earlier version stored.
const gaugeView = atom({ plugin: 'devfsd', key: 'gauge' } as const, DEFAULT_GAUGE, { shape: 'gauge-1' })

export type StopState = 'done' | 'now' | 'todo' | 'skip' | 'fail' | 'warn'
export type Stop = { key: string; label: string; state: StopState }
// hold: 명령은 진행 중인데 지금은 멈춰 있다(질문을 기다릴 수 있다) — 계기는 그대로 두되 빨강은 켜지 않는다.
export type TurnTone = 'idle' | 'run' | 'hold' | 'me' | 'bad'
export type TurnNote = { tone: TurnTone; text: string }

const STATE_OF: Record<StageMark['mark'], StopState> = {
  '✓': 'done',
  '–': 'skip',
  '✗': 'fail',
  // `!` 는 검증 STALE·PARTIAL 이다 — 실패가 아니라 코드가 바뀌어 다시 돌려야 한다는 뜻(관제판은 호박색). 따로 둔다:
  //   `지금` 으로 읽으면 바늘이 다른 단계로 갈 때 `지남` 으로 덮여 통과처럼 보였다.
  '!': 'warn',
  '●': 'now',
  '○': 'todo',
}

/** 묶인 단계들의 상태 하나 — 실패 > 진행 > 남음 > 완료 > 생략 순으로 센 쪽이 이긴다. */
function mergedState(states: readonly StopState[]): StopState {
  for (const s of ['fail', 'now', 'todo', 'done'] as const) {
    if (states.includes(s)) return s === 'todo' && states.includes('done') ? 'now' : s
  }

  return 'skip'
}

/**
 * 승인 점의 상태 — 뒤 단계가 시작됐으면 지남, 앞 단계가 끝났으면 지금, 아니면 남음.
 * 기본 경로(`/basic`)는 명세 단계가 승인까지 품는다 — `/basic 시작`(●)은 spec 을 쓰고 승인을 기다리는 동안이고
 * `/approve 완료`(✓)가 곧 승인이다. 그래서 명세가 끝났으면 승인도 지났다(구현 기록은 구현이 끝나야 남아, 그 사이를 승인 대기로 읽었다).
 */
function approvalState(before: Stop, after: readonly Stop[], isBasic: boolean): StopState {
  if (after.some(s => s.state === 'done' || s.state === 'now' || s.state === 'fail' || s.state === 'warn')) return 'done'
  if (isBasic) return before.state === 'done' ? 'done' : before.state === 'now' ? 'now' : 'todo'

  return before.state === 'done' ? 'now' : 'todo'
}

/** 자료 수집이 만든 단계 막대 → 계기판의 점 줄(게이트 묶음 · 승인 추가 — 끝은 관제판처럼 PR). 단계가 없으면 빈 배열. */
export function stopsOf(stages: readonly StageMark[] | undefined): Stop[] {
  if (!stages || stages.length === 0) return []
  const plain: Stop[] = []
  const gateStates: StopState[] = []
  for (const s of stages) {
    const state = STATE_OF[s.mark]
    if (GATE_KEYS.includes(s.key)) {
      if (gateStates.length === 0) plain.push({ key: 'gate', label: '게이트', state: 'todo' })
      gateStates.push(state)
    } else {
      plain.push({ key: s.key, label: s.label, state })
    }
  }
  const merged = plain.map(s => (s.key === 'gate' ? { ...s, state: mergedState(gateStates) } : s))
  const at = merged.reduce((found, s, i) => (APPROVAL_AFTER.includes(s.key) ? i : found), -1)
  const isBasic = stages.some(s => s.key === 'review')   // 리뷰 단계는 기본 경로에만 있다(progress-pane BASIC_STAGES)
  const before = merged[at]
  const withApproval =
    before === undefined
      ? merged
      : [
          ...merged.slice(0, at + 1),
          { key: 'approve', label: '승인', state: approvalState(before, merged.slice(at + 1), isBasic) },
          ...merged.slice(at + 1),
        ]

  // 앞 단계가 끝난 직후의 "다음 단계"는 기록이 아직 없어 표식이 ○ 이고 지금(isCurrent) 표시만 켜져 있다 — 관제판은 ▶ 로 그리는 그 단계를
  //   계기판도 지금으로 읽는다. 단 이미 진행·실패인 점(승인 대기 포함)이 있으면 그것이 지금이다 — 점 둘이 지금이 되지 않게.
  const currentKey = stages.find(s => s.isCurrent)?.key
  const current = currentKey !== undefined && GATE_KEYS.includes(currentKey) ? 'gate' : currentKey
  const isInFlight = withApproval.some(s => s.state === 'now' || s.state === 'fail')
  return isInFlight ? withApproval : withApproval.map(s => (s.key === current && s.state === 'todo' ? { ...s, state: 'now' as const } : s))
}

/** `20261116-plan-reflect` → `plan-reflect` — 날짜 접두는 사람에게 소음이다. */
export function shortFid(fid: string): string {
  return fid.replace(/^\d{8}-/, '')
}

/**
 * 상태 줄 알림 — 지금 누구 차례인가. 빨강(me·bad)은 이 세션에서 실제로 움직인 lifecycle 작업에만 낸다:
 * 단계가 없는 작업(직접 수정 기록)이나 이 세션이 건드리지 않은 지난 작업은 `대기` 다 — 새 세션마다 경보가 켜지면 무시하게 된다.
 */
/** 상태 이름의 색 — 진행 중 초록 · 내 차례와 실패 빨강 · 일시 멈춤 호박 · 완료 파랑 · 대기는 색 없이 흐리게. */
export function noteTint(note: TurnNote): string | undefined {
  if (note.tone === 'run') return note.text.includes('재검증') ? 'warning' : 'success'
  if (note.tone === 'me' || note.tone === 'bad') return 'error'
  if (note.tone === 'hold') return 'warning'

  return note.text.startsWith('완료') ? ACCENT : undefined
}

export function turnOf(b: Board, isRunning: boolean, stops: readonly Stop[]): TurnNote {
  const isBusy = isRunning || b.working === true || b.running.length > 0
  // 초기화(/init-project)는 작업(FID) 없이도 돈다. 진행 중인 단계가 있으면 멈춰 있어도(질문을 기다리는 동안) 계기를 남기되,
  //   빨강은 켜지 않는다 — 중단된 초기화의 표시 파일이 남은 저장소에서 새 세션마다 경보가 뜨지 않게.
  const flowCur = b.cmd && (!b.fid || b.cmd.kind === 'init') ? b.cmd.steps.find(st => st.mark === 'cur') : undefined
  if (flowCur) return isBusy ? { tone: 'run', text: '진행 중' } : { tone: 'hold', text: '일시 멈춤' }
  if (!b.fid || b.isPast) return { tone: 'idle', text: '대기' }
  const isStale = b.verify !== undefined && /STALE|PARTIAL/.test(b.verify)
  if (isBusy) return { tone: 'run', text: isStale && stops.length > 0 ? '진행 중 · 재검증 필요' : '진행 중' }
  const isLive = stops.length > 0 && b.activityAt !== undefined
  if (!isLive) return { tone: 'idle', text: b.verify === '완료' ? '완료' : '대기' }
  const failed = stops.find(s => s.state === 'fail')
  if (failed) return { tone: 'bad', text: `${failed.label} 실패` }
  if (b.verify !== undefined && /FAIL/.test(b.verify)) return { tone: 'bad', text: '검증 실패' }
  if (isStale) return { tone: 'hold', text: '재검증 필요' }
  if (b.verify === '완료') return { tone: 'idle', text: '완료' }
  const isApproval = stops.some(s => s.key === 'approve' && s.state === 'now')

  return { tone: 'me', text: isApproval ? '승인 대기' : '답변 대기' }
}

/**
 * `five_hour 53% (1시간 54분 뒤 초기화)` → `5h ■■■□□ 53% · 1h54m` 의 조각들.
 * 칸은 꽉 찬 것과 빈 것 두 글자뿐이다 — 부분 블록(▌)과 음영(░)은 앱 글꼴에서 칸 크기가 서로 달라 막대가 울퉁불퉁해진다.
 */
export function limitParts(l: Usage['limits'][number], now: number): { label: string; on: string; off: string; tail: string; isHot: boolean } {
  const filled = Math.max(0, Math.min(BAR_WIDTH, Math.round((l.pct * BAR_WIDTH) / 100)))
  const resetIn = fmtResetIn(l.resetsAt, now)

  return {
    label: limitLabel(l.kind),
    on: '■'.repeat(filled),
    off: '□'.repeat(BAR_WIDTH - filled),
    tail: `${Math.round(l.pct)}%${resetIn ? ` · ${resetIn}` : ''}`,
    isHot: l.pct >= HOT_PCT,
  }
}

const CMD_NAMES: Record<CmdBoard['kind'], string> = {
  init: 'init-project',
  foundation: 'start-foundation',
  batch: 'start-all',
  start: 'start',
  maintain: 'maintain',
  quick: 'quick-fix',
}
const TICK_OF_STEP: Record<CmdStep['mark'], DialTickState> = { done: 'done', cur: 'now', todo: 'todo', skip: 'skip', fail: 'fail', warn: 'now' }
const TICK_OF_STOP: Record<StopState, DialTickState> = { done: 'done', now: 'now', todo: 'todo', skip: 'skip', fail: 'fail', warn: 'warn' }

/** 지금 도는 명령의 이름(`/` 없이) — 판정할 수 없으면 undefined. */
export function commandOf(b: Board): string | undefined {
  return b.cmd ? CMD_NAMES[b.cmd.kind] : undefined
}

// 자기 흐름(STEP 줄)을 주는 명령 — board-mode.sh 가 STEP 을 내는 셋뿐이다. 나머지(start·maintain·foundation)는 작업의 단계 점을 쓴다.
const OWN_FLOW: readonly CmdBoard['kind'][] = ['init', 'batch', 'quick']

/**
 * 둥근 계기에 넘길 값 — 눈금은 **지금 도는 명령의 단계**다: 자기 흐름을 주는 명령(초기화·일괄·몇 줄 수정)은 그것을, 아니면 이 작업의 단계 점을 쓴다.
 * 대기일 때는 눈금 없이 빈 호만 그린다.
 */
/**
 * 바늘은 관제판과 같은 단계를 가리킨다 — 관제판이 ▶ 로 그리는 지금(isCurrent) 단계. 승인 대기 점이 먼저 지금이어도
 * (설계를 읽고 승인하는 동안) 관제판은 ▶설계 이므로 계기판도 그쪽이다. 지금 단계가 눈금에 없으면 그대로 둔다.
 */
export function alignCurrent(ticks: readonly DialTick[], stages: readonly StageMark[] | undefined): DialTick[] {
  const key = stages?.find(s => s.isCurrent)?.key
  const target = key !== undefined && GATE_KEYS.includes(key) ? 'gate' : key
  const at = target === undefined ? -1 : ticks.findIndex(t => t.key === target)
  if (at < 0) return [...ticks]

  return ticks.map((t, i) => (i === at ? { ...t, state: t.state === 'fail' ? 'fail' : 'now' } : t.state === 'now' ? { ...t, state: 'done' } : t))
}

export function dialModelOf(b: Board, stops: readonly Stop[], note: TurnNote, limits: Usage['limits'], now: number): DialModel {
  const steps = b.cmd && OWN_FLOW.includes(b.cmd.kind) ? b.cmd.steps : []
  const isIdle = note.tone === 'idle'
  const ticks: DialTick[] = isIdle
    ? []
    : steps.length > 0
      ? steps.map(st => ({ label: st.label, state: TICK_OF_STEP[st.mark] }))
      : alignCurrent(
          stops.map(st => ({ label: st.label, state: TICK_OF_STOP[st.state], key: st.key })),
          b.stages,
        )

  return {
    command: isIdle ? (note.text.startsWith('완료') ? '완료' : '대기') : (commandOf(b) ?? 'devFSD'),
    ticks,
    isAlert: note.tone === 'me' || note.tone === 'bad',
    limits: limits.slice(0, LIMITS_SHOWN).map(l => {
      const reset = fmtResetIn(l.resetsAt, now)

      return { name: `Claude ${limitLabel(l.kind)}`, pct: l.pct, reset: reset ? `${reset} 뒤 초기화` : '' }
    }),
  }
}

type PaneArgs = { id: string; title: string; columns?: number; rows?: number }

/** 버튼 하나로 여닫는다 — 창이 떠 있으면 닫고, 없으면 연다(도움말·관제판 공통). 창이 안 열리는 환경이어도 계기판은 그대로 둔다. */
export async function togglePane($: EngineInterface, args: PaneArgs): Promise<void> {
  try {
    const isUp = (await $.ui.panes()).some(p => p.id === args.id)
    if (isUp) await $.ui.close({ id: args.id })
    else await $.ui.open(args)
  } catch {
    // 보이는 일이라 실패해도 알릴 곳이 없다 — 다시 누르면 된다.
  }
}

/** 도움말 맨 위 한 줄 — 지금 상태에 맞는 안내. */
export function helpLead(note: TurnNote): string {
  if (note.tone === 'run') return '지금은 할 일이 없다. 끝나면 결과와 PR 을 보여 준다.'
  if (note.tone === 'hold') return '대화창에 질문이 있으면 답한다. 모르겠으면 "추천대로" 라고 답한다.'
  if (note.tone === 'bad') return '문제가 생겼다. 대화창의 설명을 읽고, 모르겠으면 "어떻게 하면 돼?" 라고 묻는다.'
  if (note.tone === 'me') return note.text.includes('승인') ? '명세를 읽고 "승인" 이라고 답한다. 고칠 곳은 말로 고쳐 달라고 한다.' : '질문에 답한다. 모르겠으면 "추천대로" 라고 답한다.'

  return note.text.startsWith('완료') ? 'PR 을 읽고 직접 병합한다. 병합은 자동으로 하지 않는다.' : '만들 것을 /start 뒤에 한 줄로 적으면 출발한다.'
}

const DOT: Record<StopState, string> = { done: '●', now: '◉', todo: '○', skip: '–', fail: '✗', warn: '!' }

/** 세션 시작 때 한 번(관제판의 session.start 가 부른다 — 그 이벤트는 한 곳에서만 등록한다) — 관할 저장소인지 적어 두고, 숨김은 세션마다 풀어 준다(바로 보이게). */
export async function gaugeStart($: EngineInterface, cwd: string): Promise<void> {
  try {
    await $.command.register({ name: COMMAND, description: 'devFSD 계기판 보이기/숨기기' })
    const governed = await isGoverned($, cwd)
    const mode = modeOf(await $.store.get(MODE_KEY).catch(() => undefined))
    await update($, gaugeView, () => ({ isGoverned: governed, isHidden: false, mode }))
  } catch {
    // 관찰만 — 계기판이 안 뜨는 것으로 충분하다.
  }
}

/** 모드를 바꾸고 다음 세션을 위해 기억한다. 기억에 실패해도 이 세션은 바뀐다. */
export async function setMode($: EngineInterface, mode: GaugeMode): Promise<void> {
  await update($, gaugeView, v => ({ ...v, mode, isHidden: false }))
  await $.store.set(MODE_KEY, mode).catch(() => undefined)
}

export function registerGauge(on: Parameters<Register>[0]): void {
  on('command.run', { command: COMMAND }, async ($, e) => {
    const arg = String(e.args ?? '').trim()
    if (arg === 'ev' || arg === 'ice') {
      await setMode($, arg)

      return { text: `devFSD 계기판을 ${MODE_NAMES[arg]}로 바꿨습니다.` }
    }
    await update($, gaugeView, v => ({ ...v, isHidden: !v.isHidden }))
    const { isHidden } = await read($, gaugeView)

    return { text: isHidden ? 'devFSD 계기판을 숨겼습니다.' : 'devFSD 계기판을 켰습니다.' }
  }).catch(() => ({ text: 'devFSD 계기판 상태를 바꾸지 못했습니다.' }))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const v = await read($, gaugeView)
    if (e.props.hasSurvey || !v.isGoverned || v.isHidden) return next(e)
    const { Box, Button, Text } = $.ui.resolve(e)
    const b = await read($, board)
    const m: Main = await read($, main)
    const u: Usage = await read($, usage)
    const at = await read($, nowTick)
    const stops = stopsOf(b.stages)
    const note = turnOf(b, m.isRunning, stops)
    const isAlert = note.tone === 'me' || note.tone === 'bad'
    const model = prettyModel(m.model || m.startModel || '')
    const tint = noteTint(note)
    const lead = tint ?? 'inactive'

    const work = [b.cmd?.title, b.fid && note.tone !== 'idle' ? shortFid(b.fid) : undefined].filter(Boolean).join(' · ')
    const recent = b.fid && note.tone === 'idle' ? ` · 최근 ${shortFid(b.fid)}` : ''

    const buttons = (
      <Box flexDirection="row" gap={e.surface === 'terminal' ? 2 : 0}>
        <Button key="help" plain dimColor onPress={() => togglePane($, { id: HELP_PANE, title: HELP_TITLE })}>
          <Text color={ACCENT}>?</Text> 도움말
        </Button>
        <Button key="console" plain dimColor onPress={() => togglePane($, { id: CONSOLE_PANE, title: CONSOLE_TITLE, columns: 66, rows: 8 })}>
          <Text color={ACCENT}>↗</Text> 관제판
        </Button>
        <Button key="hide" plain dimColor onPress={() => update($, gaugeView, x => ({ ...x, isHidden: true }))}>
          <Text color={ACCENT}>×</Text> 계기판 숨기기
        </Button>
      </Box>
    )

    if (e.surface !== 'terminal') {
      const { Svg } = $.ui.resolve(e)
      const mode = v.mode ?? 'ev'
      // 모드 버튼 둘 — 지금 모드는 강조, 다른 쪽을 누르면 바뀐다.
      const modes = (
        <Box flexDirection="row" gap={0}>
          {(['ev', 'ice'] as const).map(k => (
            <Button key={`mode-${k}`} plain dimColor={k !== mode} onPress={() => (k === mode ? undefined : setMode($, k))}>
              <Text bold={k === mode} color={k === mode ? ACCENT : undefined}>
                {MODE_NAMES[k]}
              </Text>
            </Button>
          ))}
        </Box>
      )
      const dial = dialModelOf(b, stops, note, u.limits, at)
      const cmd = commandOf(b)
      const doing = note.tone === 'idle' ? '' : [cmd ? `/${cmd}` : undefined, b.cmd?.title || undefined, b.fid ? shortFid(b.fid) : undefined].filter(Boolean).join(' · ')
      const w = dialWidth(dial.limits.length)
      // 좁으면 계기 그림을 아랫줄로 내리고(flexWrap), 띠보다 넓으면 비율대로 줄인다 — 한 줄에 고정하면 오른쪽 7d 계기가 잘렸다.
      const dialPx = Math.min(Math.round(w * DIAL_SCALE), Math.round(e.props.bodyColumns * CELL_PX))
      // 도로는 달리는 중에만 움직인다 — 사람 차례·일시 멈춤·대기는 정지 화면(그림 문자열도 같아 다시 그리지 않는다).
      const road = { ticks: dial.ticks, isAlert: dial.isAlert, isMoving: note.tone === 'run' }
      const roadPx = Math.min(Math.round(ROAD_W * ROAD_SCALE), Math.round(e.props.bodyColumns * CELL_PX))

      return (
        <Box flexDirection="row" flexWrap="wrap" justifyContent="space-between" alignItems="stretch" columnGap={3} rowGap={1}>
          <Box flexDirection="column" justifyContent="space-between">
            <Box flexDirection="column" paddingLeft={1} gap="sm">
              <Text>
                <Text size="title" bold color={ACCENT}>
                  devFSD
                </Text>
                <Text dimColor>
                  {' '}
                  ({model}
                  {m.effort ? ` ${m.effort}` : ''})
                </Text>
              </Text>
              <Box flexDirection="column">
                <Text>
                  <Text bold={tint !== undefined} dimColor={tint === undefined} color={tint}>
                    ● {note.text}
                  </Text>
                  <Text dimColor>{recent}</Text>
                </Text>
                {doing ? (
                  <Text dimColor wrap="truncate-end">
                    {doing}
                  </Text>
                ) : ''}
              </Box>
            </Box>
            {buttons}
            {modes}
          </Box>
          {mode === 'ice' ? (
            <Svg source={dialSvg(dial)} width={dialPx} height={Math.round((dialPx * DIAL_H) / w)} alt={dialAlt(dial)} />
          ) : (
            <Box flexDirection="row" flexWrap="wrap" alignItems="flex-start" columnGap={2} rowGap={1}>
              <Svg source={roadSvg(road)} width={roadPx} height={Math.round((roadPx * ROAD_H) / ROAD_W)} alt={roadAlt(road)} isInteractive />
              <Box flexDirection="column">
                {dial.limits.map(l => (
                  <Text dimColor>
                    {l.name} <Text bold color={l.pct >= HOT_PCT ? 'warning' : undefined}>{Math.round(l.pct)}%</Text>
                    {l.reset ? ` · ${l.reset}` : ''}
                  </Text>
                ))}
              </Box>
            </Box>
          )}
        </Box>
      )
    }

    return (
      <Box flexDirection="column">
        <Box flexDirection="row" justifyContent="space-between" gap={2}>
          <Text>
            <Text color={lead}>●</Text>{' '}
            <Text bold color={ACCENT}>
              devFSD
            </Text>
            {work ? <Text dimColor> {work} ·</Text> : ''}{' '}
            <Text bold={tint !== undefined} dimColor={tint === undefined} color={tint}>
              {note.text}
            </Text>
            <Text dimColor>{recent}</Text>
          </Text>
          {buttons}
        </Box>
        {stops.length > 0 && note.tone !== 'idle' && (
          <Text>
            {stops.map((s, i) => (
              <Text>
                {i > 0 ? <Text dimColor>{s.state === 'done' || s.state === 'now' || s.state === 'fail' || s.state === 'warn' ? ' ━ ' : ' ┄ '}</Text> : ''}
                <Text
                  bold={s.state === 'now'}
                  color={s.state === 'fail' ? 'error' : s.state === 'warn' ? 'warning' : s.state === 'now' ? (isAlert ? 'error' : ACCENT) : undefined}
                  dimColor={s.state === 'todo' || s.state === 'skip'}
                >
                  {DOT[s.state]} {s.label}
                </Text>
              </Text>
            ))}
          </Text>
        )}
        <Text dimColor>
          {model}
          {m.effort ? ` · ${m.effort}` : ''}
          {u.limits.slice(0, LIMITS_SHOWN).map(l => {
            const p = limitParts(l, at)

            return (
              <Text>
                {'   '}
                {p.label} <Text color={p.isHot ? 'warning' : undefined}>{p.on}</Text>
                {p.off} {p.tail}
              </Text>
            )
          })}
          {u.costUsd !== null ? `   ${fmtUsd(u.costUsd)}` : ''}
        </Text>
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: HELP_PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const b = await read($, board)
    const m: Main = await read($, main)
    const note = turnOf(b, m.isRunning, stopsOf(b.stages))

    return (
      <Box flexDirection="column">
        <Text bold>지금 — {helpLead(note)}</Text>
        {HELP_SECTIONS.map(sec => (
          <Box flexDirection="column">
            <Text> </Text>
            <Text bold>{sec.title}</Text>
            {sec.lines.map(line => (
              <Text>
                {'  '}
                {line}
              </Text>
            ))}
          </Box>
        ))}
      </Box>
    )
  })
}
