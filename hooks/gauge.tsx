// devFSD 계기판 — 입력창 바로 위 띠. 관제판·진행 패널이 채운 상태를 읽어 그리기만 한다(차단·수정 없음).
//   1줄: 모델 · effort · 5h · 7d   2줄: 상태 · 명령 · 작업 · 내 차례   3줄: 단계 점   4줄: 버튼
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Board, GaugeView, Main, StageMark, Usage } from '../types'
import { DEFAULT_MAIN, DEFAULT_USAGE, fmtResetIn, fmtUsd, gauge, limitLabel, prettyModel } from './core'
import { isGoverned } from './progress-pane'

const HELP_PANE = 'devfsd-help'
const HELP_TITLE = 'devFSD 도움말'
const CONSOLE_PANE = 'devfsd-console'
const CONSOLE_TITLE = 'devFSD 관제판'
const COMMAND = 'devfsd-gauge'
const STATUS_PROMPT = 'devFSD 현황을 보여줘 (devfsd:status)'
const BAR_WIDTH = 5
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

/** 오른쪽 위 알림 — 지금 누구 차례인가. 정확히 읽을 수 있는 상태만 빨강(me·bad)으로 낸다. */
export function turnOf(b: Board, isRunning: boolean, stops: readonly Stop[]): TurnNote {
  if (!b.fid) return { tone: 'idle', text: '대기 — /start 또는 /maintain 으로 출발' }
  const failed = stops.find(s => s.state === 'fail')
  if (failed) return { tone: 'bad', text: `${failed.label} 실패` }
  if (b.verify !== undefined && /FAIL/.test(b.verify)) return { tone: 'bad', text: '검증 실패' }
  if (b.verify === '완료') return { tone: 'idle', text: '완료 — PR 확인·병합은 직접' }
  if (isRunning || b.working === true || b.running.length > 0) return { tone: 'run', text: '기다리면 된다' }
  const isApproval = stops.some(s => s.key === 'approve' && s.state === 'now')

  return { tone: 'me', text: isApproval ? '내 차례 — 설계를 읽고 승인' : '내 차례 — 답을 기다린다' }
}

/** `five_hour 42% (2시간 39분 뒤 초기화)` → `5h ██░░░ 42% · 2h39m` 의 조각들. */
export function limitParts(l: Usage['limits'][number], now: number): { label: string; on: string; off: string; tail: string } {
  const bar = gauge(l.pct, BAR_WIDTH)
  const resetIn = fmtResetIn(l.resetsAt, now)

  return { label: limitLabel(l.kind), on: bar.on, off: bar.off, tail: `${Math.round(l.pct)}%${resetIn ? ` · ${resetIn}` : ''}` }
}

/** 도움말 맨 위 한 줄 — 지금 상태에 맞는 안내. */
export function helpLead(note: TurnNote): string {
  if (note.tone === 'run') return '지금은 할 일이 없다. 끝나면 결과와 PR 을 보여 준다.'
  if (note.tone === 'bad') return '문제가 생겼다. 대화창의 설명을 읽고, 모르겠으면 "어떻게 하면 돼?" 라고 묻는다.'
  if (note.tone === 'me') return note.text.includes('승인') ? '명세를 읽고 "승인" 이라고 답한다. 고칠 곳은 말로 고쳐 달라고 한다.' : '질문에 답한다. 모르겠으면 "추천대로" 라고 답한다.'

  return note.text.startsWith('완료') ? 'PR 을 읽고 직접 병합한다. 병합은 자동으로 하지 않는다.' : '만들 것을 /start 뒤에 한 줄로 적으면 출발한다.'
}

export const HELP_SECTIONS: readonly { title: string; lines: readonly string[] }[] = [
  {
    title: '시작하기',
    lines: ['/start "만들 것 한 줄"      새 기능', '/maintain "고칠 것 한 줄"   있는 코드 수정', '/quick-fix "몇 줄 수정"      작은 수정'],
  },
  { title: '내가 할 일', lines: ['① 질문에 답 (최대 2번)', '② 승인 (1번)', '③ PR 병합'] },
  {
    title: '계기판 읽는 법',
    lines: ['● 지난 단계   ◉ 지금 단계   ○ 남은 단계   ✗ 실패', '5h · 7d  사용 한도와 초기화까지 남은 시간', '빨간 알림  내 차례이거나 문제가 생김'],
  },
  {
    title: '막혔을 때',
    lines: ['커밋이 막혔다 — 정상이다. 검증을 돌린 뒤 다시 한다', '질문이 어렵다 — "추천대로" 라고 답한다', '창을 닫았다 — 다시 열고 "현황" 을 누른다'],
  },
  { title: '더 보기', lines: ['진행 패널 /devfsd-progress · 관제판 /devfsd', '계기판 다시 켜기 /devfsd-gauge', '사용 설명서는 README 에 있다'] },
]

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

    return (
      <Box flexDirection="column">
        <Box flexDirection="row" gap={3}>
          <Text bold>
            {model}
            {m.effort ? ` · ${m.effort}` : ''}
          </Text>
          {u.limits.slice(0, LIMITS_SHOWN).map(l => {
            const p = limitParts(l, at)

            return (
              <Text>
                <Text dimColor>{p.label} </Text>
                <Text color={l.pct >= 80 ? 'error' : 'warning'}>{p.on}</Text>
                <Text dimColor>{p.off}</Text> {p.tail}
              </Text>
            )
          })}
        </Box>
        <Box flexDirection="row" gap={2}>
          <Text>
            <Text color={lead}>●</Text> <Text bold>devFSD</Text>
            {b.cmd ? ` ${b.cmd.title}` : ''}
            {b.fid ? <Text dimColor> {b.fid}</Text> : ''}
            {b.lane ? <Text dimColor> · {b.lane}</Text> : ''}
          </Text>
          <Text bold={isAlert} color={isAlert ? 'error' : undefined} dimColor={!isAlert}>
            {note.text}
            {u.costUsd !== null ? ` · ${fmtUsd(u.costUsd)}` : ''}
          </Text>
        </Box>
        {stops.length > 0 && (
          <Text>
            {stops.map((s, i) => (
              <Text>
                {i > 0 ? <Text dimColor>{s.state === 'todo' || s.state === 'gate' ? '┄' : '━'}</Text> : ''}
                <Text
                  bold={s.state === 'now'}
                  color={s.state === 'done' ? 'success' : s.state === 'now' ? 'warning' : s.state === 'fail' || s.state === 'gate' ? 'error' : undefined}
                  dimColor={s.state === 'todo' || s.state === 'skip'}
                >
                  {DOT[s.state]}
                  {s.label}
                </Text>
              </Text>
            ))}
          </Text>
        )}
        <Box flexDirection="row" gap={1}>
          <Button key="status" label="현황" onPress={() => void $.prompt.submit({ text: STATUS_PROMPT })} />
          <Button key="help" label="도움말" onPress={() => void $.ui.open({ id: HELP_PANE, title: HELP_TITLE })} />
          <Button key="console" label="관제판 보기" onPress={() => void $.ui.open({ id: CONSOLE_PANE, title: CONSOLE_TITLE, columns: 66, rows: 8 })} />
          <Button key="hide" label="계기판 숨기기" onPress={() => update($, gaugeView, x => ({ ...x, isHidden: true }))} />
        </Box>
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
