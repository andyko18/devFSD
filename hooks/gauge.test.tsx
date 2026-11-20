import { expect, test } from 'claude-code/testing'

import type { Board, StageMark } from '../types'
import { helpLead, limitParts, shortFid, stopsOf, turnOf } from './gauge'
import { HELP_SECTIONS } from './gauge-help'

const BAND = {
  plugin: 'devfsd',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isCollapsed: false,
    isWorking: false,
    maxRows: 20,
    bodyColumns: 100,
    scroll: { offset: 0, bodyRows: 20 },
    view: {},
  },
} as const

const HELP = {
  plugin: 'devfsd',
  component: 'Pane',
  requestId: 'devfsd-help',
  props: {
    title: 'devFSD 도움말',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

const START = { surface: 'desktop', isInteractive: true } as const

const stage = (key: string, label: string, mark: StageMark['mark']): StageMark => ({ key, label, mark })

const FULL: StageMark[] = [
  stage('specify', '명세', '✓'),
  stage('clarify', '명확화', '✓'),
  stage('plan', '설계', '✓'),
  stage('tasks', '분해', '✓'),
  stage('implement', '구현', '●'),
  stage('verify', '검증', '○'),
  stage('security', '보안', '○'),
  stage('integration', '통합', '○'),
  stage('performance', '성능', '○'),
  stage('demo', '데모', '○'),
  stage('pr', 'PR', '○'),
]

const board = (over: Partial<Board>): Board => ({ running: [], recent: [], ...over })

const started = (on: Parameters<Parameters<typeof test>[1]>[1], governed: boolean) => {
  const opens: string[] = []
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('clock.every', () => ({ value: { cancel: () => {} } }))
  on('clock.now', () => ({ value: 1_000 }))
  on('fs.read', () => {
    throw new Error('ENOENT')
  })
  on('fs.exists', (_, e) => ({ value: governed && e.path === '/repo/.specops' }))
  on('ui.open', (_, e) => {
    opens.push(e.id)

    return { value: { isPlaced: true } }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  // 계기판이 그리지 않고 넘긴 띠는 엔진이 그린다 — 이 훅이 엔진 자리다.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })

  return { opens }
}

test('full-lane stages fold the gates into one stop and add approval and merge', () => {
  const stops = stopsOf(FULL, false)
  expect(stops.map(s => s.label)).toEqual(['명세', '명확화', '승인', '설계', '분해', '구현', '검증', '게이트', 'PR', '머지'])
  expect(stops.find(s => s.key === 'approve')?.state).toBe('done')
  expect(stops.find(s => s.key === 'implement')?.state).toBe('now')
  expect(stops.find(s => s.key === 'gate')?.state).toBe('todo')
  expect(stops.find(s => s.key === 'merge')?.state).toBe('gate')
})

test('approval is the current stop once the stage before it is done and nothing after has begun', () => {
  const waiting = [stage('specify', '명세', '✓'), stage('clarify', '명확화', '✓'), stage('plan', '설계', '○')]
  expect(stopsOf(waiting, false).find(s => s.key === 'approve')?.state).toBe('now')
  const early = [stage('specify', '명세', '✓'), stage('clarify', '명확화', '●'), stage('plan', '설계', '○')]
  expect(stopsOf(early, false).find(s => s.key === 'approve')?.state).toBe('todo')
})

test('the gate stop takes the strongest state of the stages it folds', () => {
  const gates = (a: StageMark['mark'], b: StageMark['mark']) =>
    stopsOf([stage('verify', '검증', '✓'), stage('security', '보안', a), stage('integration', '통합', b)], false).find(s => s.key === 'gate')?.state
  expect(gates('✗', '✓')).toBe('fail')
  expect(gates('✓', '○')).toBe('now')
  expect(gates('–', '✓')).toBe('done')
  expect(gates('–', '–')).toBe('skip')
  expect(gates('○', '○')).toBe('todo')
})

test('a basic lane has no approval stop without a specify stage and no stages draws none', () => {
  const basic = [stage('implement', '구현', '●'), stage('verify', '검증', '○'), stage('pr', 'PR', '○')]
  expect(stopsOf(basic, false).map(s => s.key)).toEqual(['implement', 'verify', 'pr', 'merge'])
  expect(stopsOf(undefined, false)).toEqual([])
  expect(stopsOf([], false)).toEqual([])
  expect(stopsOf(basic, true).find(s => s.key === 'merge')?.state).toBe('now')
})

test('the turn note tells whose turn it is', () => {
  const stops = stopsOf(FULL, false)
  const live = { fid: '20261120-x', stages: FULL, activityAt: 900 }
  expect(turnOf(board({}), false, []).tone).toBe('idle')
  expect(turnOf(board(live), true, stops)).toEqual({ tone: 'run', text: '기다리면 된다' })
  expect(turnOf(board({ ...live, working: true }), false, stops).tone).toBe('run')
  expect(turnOf(board(live), false, stops)).toEqual({ tone: 'me', text: '내 차례 — 답을 기다린다' })
  const waiting = stopsOf([stage('specify', '명세', '✓'), stage('plan', '설계', '○')], false)
  expect(turnOf(board(live), false, waiting).text).toBe('내 차례 — 설계를 읽고 승인')
  expect(turnOf(board({ ...live, verify: '검증 FAIL' }), false, stops)).toEqual({ tone: 'bad', text: '검증 실패' })
  const broken = stopsOf([stage('implement', '구현', '✗')], false)
  expect(turnOf(board(live), false, broken)).toEqual({ tone: 'bad', text: '구현 실패' })
  expect(turnOf(board({ ...live, verify: '완료' }), false, stops).tone).toBe('idle')
})

test('a past record raises no alarm: no stages, or untouched by this session', () => {
  const stops = stopsOf(FULL, false)
  // 직접 수정 기록 — 단계가 없다(20261120 실화면: 나흘 전 끝난 작업이 새 세션마다 빨강이었다)
  expect(turnOf(board({ fid: '20261116-plan-reflect', lane: '직접 수정', verify: '검증 PASS', activityAt: 900 }), false, [])).toEqual({ tone: 'idle', text: '대기' })
  // 단계는 있지만 이 세션이 건드리지 않은 작업
  expect(turnOf(board({ fid: '20261120-x', stages: FULL }), false, stops)).toEqual({ tone: 'idle', text: '대기' })
  expect(turnOf(board({ fid: '20261120-x', stages: FULL, verify: '검증 FAIL' }), false, stops).tone).toBe('idle')
  expect(turnOf(board({ fid: '20261120-x', verify: '완료' }), false, []).text).toMatch(/^완료/)
  expect(shortFid('20261116-plan-reflect')).toBe('plan-reflect')
  expect(shortFid('no-date')).toBe('no-date')
})

test('a limit bar uses two glyphs only and colours from 80 percent', () => {
  const p = limitParts({ kind: 'five_hour', pct: 53, resetsAt: 1_000 + 114 * 60_000 }, 1_000)
  expect(p.label).toBe('5h')
  expect(p.on + p.off).toBe('■■■□□')
  expect(p.tail).toBe('53% · 1h54m')
  expect(p.isHot).toBe(false)
  for (const pct of [0, 9, 10, 37, 64, 79, 80, 99, 100, 140]) {
    const bar = limitParts({ kind: 'seven_day', pct, resetsAt: null }, 1_000)
    expect(/^■*□*$/.test(bar.on + bar.off)).toBe(true)
    expect([...(bar.on + bar.off)].length).toBe(5)
    expect(bar.isHot).toBe(pct >= 80)
  }
  expect(limitParts({ kind: 'seven_day', pct: 61.6, resetsAt: null }, 1_000).tail).toBe('62%')
})

test('the help lead follows the state and every section has lines', () => {
  expect(helpLead({ tone: 'run', text: '기다리면 된다' })).toMatch(/할 일이 없다/)
  expect(helpLead({ tone: 'me', text: '내 차례 — 설계를 읽고 승인' })).toMatch(/승인/)
  expect(helpLead({ tone: 'me', text: '내 차례 — 답을 기다린다' })).toMatch(/추천대로/)
  expect(helpLead({ tone: 'bad', text: '검증 실패' })).toMatch(/문제/)
  expect(helpLead({ tone: 'idle', text: '완료 — PR 확인·병합은 직접' })).toMatch(/병합/)
  expect(helpLead({ tone: 'idle', text: '대기' })).toMatch(/\/start/)
  expect(HELP_SECTIONS.every(s => s.title.length > 0 && s.lines.length > 0)).toBe(true)
  const all = HELP_SECTIONS.flatMap(s => [s.title, ...s.lines]).join('\n')
  // 명령어 사용법 — 진입 명령마다 구획이 있고, 화면 명령(다시 켜는 법)과 자주 묻는 것이 있다
  for (const cmd of ['/start', '/maintain', '/quick-fix', '/status', '/init-project', '/start-foundation', '/start-all']) {
    expect(HELP_SECTIONS.some(s => s.title.startsWith(`${cmd} — `) && s.lines.some(l => l.startsWith('입력')) && s.lines.some(l => l.startsWith('그러면')))).toBe(true)
  }
  for (const need of ['커밋이 막혔다', 'doctor', '병합', '/devfsd-gauge', '/devfsd ']) {
    expect(all.includes(need)).toBe(true)
  }
  // 옆 패널 폭에 맞게 — 한글은 2칸으로 센다
  const cells = (line: string) => [...line].reduce((n, ch) => n + (ch.charCodeAt(0) > 0x2e7f ? 2 : 1), 0)
  expect(HELP_SECTIONS.flatMap(s => s.lines).filter(l => cells(l) > 76)).toEqual([])
})

test('a governed repo shows the gauge at session start with its three buttons', async ($, on) => {
  started(on, true)
  await $.session.start({ cwd: '/repo', ...START })
  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  expect(await ui.find({ text: /대기/ })).toBeDefined()
  expect(await ui.find({ type: 'Button' })).toBeDefined()
  expect(await ui.find({ text: /engine/ })).toBeUndefined()
  await ui.unmount()
})

test('another repo shows no gauge', async ($, on) => {
  started(on, false)
  await $.session.start({ cwd: '/other', ...START })
  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  expect(await ui.find({ type: 'Button' })).toBeUndefined()
  expect(await ui.find({ text: /engine/ })).toBeDefined()
  await ui.unmount()
})

test('the buttons open the help pane and the console and hide the gauge', async ($, on) => {
  const { opens } = started(on, true)
  await $.session.start({ cwd: '/repo', ...START })
  opens.length = 0
  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  await ui.press({ key: 'help' })
  await ui.press({ key: 'console' })
  expect(opens).toEqual(['devfsd-help', 'devfsd-console'])
  await ui.press({ key: 'hide' })
  await ui.unmount()
  const hidden = await $.ui.mount({ ...BAND, surface: 'desktop' })
  expect(await hidden.find({ type: 'Button' })).toBeUndefined()
  await hidden.unmount()
})

test('the command brings a hidden gauge back and a new session shows it again', async ($, on) => {
  started(on, true)
  await $.session.start({ cwd: '/repo', ...START })
  expect((await $.command.run({ command: 'devfsd-gauge', args: '' })).text).toMatch(/숨겼습니다/)
  expect((await $.command.run({ command: 'devfsd-gauge', args: '' })).text).toMatch(/켰습니다/)
  await $.command.run({ command: 'devfsd-gauge', args: '' })
  await $.session.start({ cwd: '/repo', ...START })
  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  expect(await ui.find({ type: 'Button' })).toBeDefined()
  await ui.unmount()
})

test('a survey takes the band and the gauge yields', async ($, on) => {
  started(on, true)
  await $.session.start({ cwd: '/repo', ...START })
  const ui = await $.ui.mount({ ...BAND, props: { ...BAND.props, hasSurvey: true }, surface: 'desktop' })
  expect(await ui.find({ type: 'Button' })).toBeUndefined()
  expect(await ui.find({ text: /engine/ })).toBeDefined()
  await ui.unmount()
})

test('the help pane leads with what to do now and lists every section', async ($, on) => {
  started(on, true)
  await $.session.start({ cwd: '/repo', ...START })
  const ui = await $.ui.mount({ ...HELP, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /^지금/ }))?.text).toMatch(/\/start/)
  for (const sec of HELP_SECTIONS) {
    expect(await ui.find({ type: 'Text', text: sec.title })).toBeDefined()
  }
  await ui.unmount()
})
