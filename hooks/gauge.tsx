// devFSD 계기판 — 입력창 바로 위 띠. 관제판·진행 패널이 채운 상태를 읽어 그리기만 한다(차단·수정 없음).
//   1줄: 상태 · 명령 · 작업 · 내 차례 + 버튼(? 도움말 · ↗ 관제판 · × 계기판 숨기기 — 기호만 색을 입힌 글자)   2줄: 단계 점(작업 중에만)   3줄: 모델 · effort · 5h · 7d · 비용(참고 수치 — 흐리게)
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Board, GaugeView, Main, StageMark, Usage } from '../types'
import { DEFAULT_MAIN, DEFAULT_USAGE, fmtResetIn, fmtUsd, limitLabel, prettyModel } from './core'
import { HELP_SECTIONS } from './gauge-help'
import { isGoverned } from './progress-pane'

const HELP_PANE = 'devfsd-help'
const HELP_TITLE = 'devFSD 도움말'
const CONSOLE_PANE = 'devfsd-console'
const CONSOLE_TITLE = 'devFSD 관제판'
const COMMAND = 'devfsd-gauge'
// 강조색 하나 — 이름 · 지금 단계 · 버튼 기호에만 쓴다. 초록은 '달리는 중' 상태 점의 뜻이라 이름에는 쓰지 않는다.
const ACCENT = 'suggestion'
const BAR_WIDTH = 5
const HOT_PCT = 80 // 이 아래로는 막대에 색을 쓰지 않는다 — 평소엔 무채색
const LIMITS_SHOWN = 2
// 보안·통합·성능·데모는 계기판에서 한 점(게이트)으로 묶는다 — 상세는 진행 패널이 보여 준다.
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

export type StopState = 'done' | 'now' | 'todo' | 'skip' | 'fail' | 'gate'
export type Stop = { key: string; label: string; state: StopState }
export type TurnTone = 'idle' | 'run' | 'me' | 'bad'
export type TurnNote = { tone: TurnTone; text: string }

const STATE_OF: Record<StageMark['mark'], StopState> = {
  '✓': 'done',
  '–': 'skip',
  '✗': 'fail',
  '!': 'fail',
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

/** 승인 점의 상태 — 뒤 단계가 시작됐으면 지남, 앞 단계가 끝났으면 지금, 아니면 남음. */
function approvalState(before: Stop, after: readonly Stop[]): StopState {
  if (after.some(s => s.state === 'done' || s.state === 'now' || s.state === 'fail')) return 'done'

  return before.state === 'done' ? 'now' : 'todo'
}

/** 진행 패널의 단계 막대 → 계기판의 점 줄(게이트 묶음 · 승인 · 머지 추가). 단계가 없으면 빈 배열. */
export function stopsOf(stages: readonly StageMark[] | undefined, isDone: boolean): Stop[] {
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
  const before = merged[at]
  const withApproval =
    before === undefined
      ? merged
      : [
          ...merged.slice(0, at + 1),
          { key: 'approve', label: '승인', state: approvalState(before, merged.slice(at + 1)) },
          ...merged.slice(at + 1),
        ]

  return [...withApproval, { key: 'merge', label: '머지', state: isDone ? 'now' : 'gate' }]
}

/** `20261116-plan-reflect` → `plan-reflect` — 날짜 접두는 사람에게 소음이다. */
export function shortFid(fid: string): string {
  return fid.replace(/^\d{8}-/, '')
}

/**
 * 상태 줄 알림 — 지금 누구 차례인가. 빨강(me·bad)은 이 세션에서 실제로 움직인 lifecycle 작업에만 낸다:
 * 단계가 없는 작업(직접 수정 기록)이나 이 세션이 건드리지 않은 지난 작업은 `대기` 다 — 새 세션마다 경보가 켜지면 무시하게 된다.
 */
export function turnOf(b: Board, isRunning: boolean, stops: readonly Stop[]): TurnNote {
  if (!b.fid) return { tone: 'idle', text: '대기 — /start 또는 /maintain 으로 출발' }
  if (isRunning || b.working === true || b.running.length > 0) return { tone: 'run', text: '기다리면 된다' }
  const isLive = stops.length > 0 && b.activityAt !== undefined
  if (!isLive) return { tone: 'idle', text: b.verify === '완료' ? '완료 — PR 확인·병합은 직접' : '대기' }
  const failed = stops.find(s => s.state === 'fail')
  if (failed) return { tone: 'bad', text: `${failed.label} 실패` }
  if (b.verify !== undefined && /FAIL/.test(b.verify)) return { tone: 'bad', text: '검증 실패' }
  if (b.verify === '완료') return { tone: 'idle', text: '완료 — PR 확인·병합은 직접' }
  const isApproval = stops.some(s => s.key === 'approve' && s.state === 'now')

  return { tone: 'me', text: isApproval ? '내 차례 — 설계를 읽고 승인' : '내 차례 — 답을 기다린다' }
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

/** 도움말 맨 위 한 줄 — 지금 상태에 맞는 안내. */
export function helpLead(note: TurnNote): string {
  if (note.tone === 'run') return '지금은 할 일이 없다. 끝나면 결과와 PR 을 보여 준다.'
  if (note.tone === 'bad') return '문제가 생겼다. 대화창의 설명을 읽고, 모르겠으면 "어떻게 하면 돼?" 라고 묻는다.'
  if (note.tone === 'me') return note.text.includes('승인') ? '명세를 읽고 "승인" 이라고 답한다. 고칠 곳은 말로 고쳐 달라고 한다.' : '질문에 답한다. 모르겠으면 "추천대로" 라고 답한다.'

  return note.text.startsWith('완료') ? 'PR 을 읽고 직접 병합한다. 병합은 자동으로 하지 않는다.' : '만들 것을 /start 뒤에 한 줄로 적으면 출발한다.'
}

const DOT: Record<StopState, string> = { done: '●', now: '◉', todo: '○', skip: '–', fail: '✗', gate: '○' }

/** 세션 시작 때 한 번(관제판의 session.start 가 부른다 — 그 이벤트는 한 곳에서만 등록한다) — 관할 저장소인지 적어 두고, 숨김은 세션마다 풀어 준다(바로 보이게). */
export async function gaugeStart($: EngineInterface, cwd: string): Promise<void> {
  try {
    await $.command.register({ name: COMMAND, description: 'devFSD 계기판 보이기/숨기기' })
    const governed = await isGoverned($, cwd)
    await update($, gaugeView, () => ({ isGoverned: governed, isHidden: false }))
  } catch {
    // 관찰만 — 계기판이 안 뜨는 것으로 충분하다.
  }
}

export function registerGauge(on: Parameters<Register>[0]): void {
  on('command.run', { command: COMMAND }, async $ => {
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
    const stops = stopsOf(b.stages, b.verify === '완료')
    const note = turnOf(b, m.isRunning, stops)
    const isAlert = note.tone === 'me' || note.tone === 'bad'
    const model = prettyModel(m.model || m.startModel || '')
    const lead = isAlert ? 'error' : note.tone === 'run' ? 'success' : 'inactive'

    const work = [b.cmd?.title, b.fid && note.tone !== 'idle' ? shortFid(b.fid) : undefined].filter(Boolean).join(' · ')
    const recent = b.fid && note.tone === 'idle' ? ` · 최근 ${shortFid(b.fid)}` : ''

    return (
      <Box flexDirection="column">
        <Box flexDirection="row" justifyContent="space-between" gap={2}>
          <Text>
            <Text color={lead}>●</Text>{' '}
            <Text bold color={ACCENT}>
              devFSD
            </Text>
            {work ? ` ${work}` : ''}
            {isAlert ? (
              <Text bold color="error">
                {' '}
                · {note.text}
              </Text>
            ) : (
              <Text dimColor>
                {' '}
                · {note.text}
                {recent}
              </Text>
            )}
          </Text>
          <Box flexDirection="row" gap={2}>
            <Button key="help" plain onPress={() => void $.ui.open({ id: HELP_PANE, title: HELP_TITLE })}>
              <Text color={ACCENT}>?</Text> 도움말
            </Button>
            <Button key="console" plain onPress={() => void $.ui.open({ id: CONSOLE_PANE, title: CONSOLE_TITLE, columns: 66, rows: 8 })}>
              <Text color={ACCENT}>↗</Text> 관제판
            </Button>
            <Button key="hide" plain onPress={() => update($, gaugeView, x => ({ ...x, isHidden: true }))}>
              <Text color={ACCENT}>×</Text> 계기판 숨기기
            </Button>
          </Box>
        </Box>
        {stops.length > 0 && note.tone !== 'idle' && (
          <Text>
            {stops.map((s, i) => (
              <Text>
                {i > 0 ? <Text dimColor>{s.state === 'done' || s.state === 'now' || s.state === 'fail' ? ' ━ ' : ' ┄ '}</Text> : ''}
                <Text
                  bold={s.state === 'now'}
                  color={s.state === 'fail' ? 'error' : s.state === 'now' ? (isAlert ? 'error' : ACCENT) : undefined}
                  dimColor={s.state === 'todo' || s.state === 'skip' || s.state === 'gate'}
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
    const note = turnOf(b, m.isRunning, stopsOf(b.stages, b.verify === '완료'))

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
