import { expect, test } from 'claude-code/testing'

import type { Board, CmdBoard, StageMark } from '../types'
import { alignCurrent, commandOf, dialModelOf, helpLead, limitParts, noteTint, shortFid, stopsOf, turnOf } from './gauge'
import { dialAlt, dialHue, dialNow, dialSvg, dialWidth } from './gauge-dial'
import type { DialTick } from './gauge-dial'
import { HELP_SECTIONS } from './gauge-help'
import { currentStageKey, stagesOf, withVerifyMark } from './progress-pane'

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

// 버튼 처리는 창 목록을 확인한 뒤 열고 닫는 비동기라 누름이 돌아온 뒤에야 끝난다 — 단언 전에 비운다.
const flush = async () => {
  for (let i = 0; i < 20; i++) await Promise.resolve()
}

const board = (over: Partial<Board>): Board => ({ running: [], recent: [], ...over })

const started = (on: Parameters<Parameters<typeof test>[1]>[1], governed: boolean) => {
  const opens: string[] = []
  const closes: string[] = []
  const up = new Set<string>()
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('clock.every', () => ({ value: { cancel: () => {} } }))
  on('clock.now', () => ({ value: 1_000 }))
  on('fs.read', () => {
    throw new Error('ENOENT')
  })
  on('fs.exists', (_, e) => ({ value: governed && e.path === '/repo/.specops' }))
  on('ui.open', (_, e) => {
    opens.push(e.id)
    up.add(e.id)

    return { value: { isPlaced: true } }
  })
  on('ui.close', (_, e) => {
    closes.push(e.id)
    up.delete(e.id)

    return { value: undefined }
  })
  on('ui.panes', () => ({ value: [...up].map(id => ({ id, title: id, isShown: true, isFocused: false, isPlaced: true })) }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  // 계기판이 그리지 않고 넘긴 띠는 엔진이 그린다 — 이 훅이 엔진 자리다.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })

  return { opens, closes }
}

test('full-lane stages fold the gates into one stop and add approval, ending at PR like the console', () => {
  const stops = stopsOf(FULL)
  expect(stops.map(s => s.label)).toEqual(['명세', '명확화', '승인', '설계', '분해', '구현', '검증', '게이트', 'PR'])
  expect(stops.find(s => s.key === 'approve')?.state).toBe('done')
  expect(stops.find(s => s.key === 'implement')?.state).toBe('now')
  expect(stops.find(s => s.key === 'gate')?.state).toBe('todo')
  expect(stops.some(s => s.key === 'merge')).toBe(false)
})

test('a stale or partial verify reads as re-verify in amber, not as a red failure like the console', () => {
  const stale = [stage('implement', '구현', '✓'), stage('verify', '검증', '!'), stage('pr', 'PR', '○')]
  const stops = stopsOf(stale)
  expect(stops.find(s => s.key === 'verify')?.state).toBe('warn')
  expect(stops.some(s => s.state === 'fail')).toBe(false)
  for (const verify of ['검증 STALE', '검증 PARTIAL']) {
    const note = turnOf(board({ fid: '20261123-x', stages: stale, verify, activityAt: 900 }), false, stops)
    expect(note).toEqual({ tone: 'hold', text: '재검증 필요' })
    expect(noteTint(note)).toBe('warning')
  }
  const failed = [stage('implement', '구현', '✓'), stage('verify', '검증', '✗'), stage('pr', 'PR', '○')]
  expect(turnOf(board({ fid: '20261123-x', stages: failed, verify: '검증 FAIL', activityAt: 900 }), false, stopsOf(failed)).tone).toBe('bad')
})

test('on the basic lane the spec stage holds the approval — approved means approval passed', () => {
  const lane = (spec: StageMark['mark']) => [stage('specify', '명세', spec), stage('implement', '구현', '○'), stage('review', '리뷰', '○'), stage('verify', '검증', '○'), stage('pr', 'PR', '○')]
  const approved = stopsOf(lane('✓'))
  expect(approved.find(s => s.key === 'approve')?.state).toBe('done')
  expect(turnOf(board({ fid: '20261123-x', stages: lane('✓'), activityAt: 900 }), false, approved).text).not.toBe('승인 대기')
  const waiting = stopsOf(lane('●'))
  expect(waiting.find(s => s.key === 'approve')?.state).toBe('now')
  expect(turnOf(board({ fid: '20261123-x', stages: lane('●'), activityAt: 900 }), false, waiting).text).toBe('승인 대기')
})

test('approval is the current stop once the stage before it is done and nothing after has begun', () => {
  const waiting = [stage('specify', '명세', '✓'), stage('clarify', '명확화', '✓'), stage('plan', '설계', '○')]
  expect(stopsOf(waiting).find(s => s.key === 'approve')?.state).toBe('now')
  const early = [stage('specify', '명세', '✓'), stage('clarify', '명확화', '●'), stage('plan', '설계', '○')]
  expect(stopsOf(early).find(s => s.key === 'approve')?.state).toBe('todo')
})

test('the gate stop takes the strongest state of the stages it folds', () => {
  const gates = (a: StageMark['mark'], b: StageMark['mark']) =>
    stopsOf([stage('verify', '검증', '✓'), stage('security', '보안', a), stage('integration', '통합', b)]).find(s => s.key === 'gate')?.state
  expect(gates('✗', '✓')).toBe('fail')
  expect(gates('✓', '○')).toBe('now')
  expect(gates('–', '✓')).toBe('done')
  expect(gates('–', '–')).toBe('skip')
  expect(gates('○', '○')).toBe('todo')
})

test('a basic lane has no approval stop without a specify stage and no stages draws none', () => {
  const basic = [stage('implement', '구현', '●'), stage('verify', '검증', '○'), stage('pr', 'PR', '○')]
  expect(stopsOf(basic).map(s => s.key)).toEqual(['implement', 'verify', 'pr'])
  expect(stopsOf(undefined)).toEqual([])
  expect(stopsOf([])).toEqual([])
})

test('the turn note tells whose turn it is', () => {
  const stops = stopsOf(FULL)
  const live = { fid: '20261120-x', stages: FULL, activityAt: 900 }
  expect(turnOf(board({}), false, []).tone).toBe('idle')
  expect(turnOf(board(live), true, stops)).toEqual({ tone: 'run', text: '진행 중' })
  expect(turnOf(board({ ...live, working: true }), false, stops).tone).toBe('run')
  expect(turnOf(board(live), false, stops)).toEqual({ tone: 'me', text: '답변 대기' })
  const waiting = stopsOf([stage('specify', '명세', '✓'), stage('plan', '설계', '○')])
  expect(turnOf(board(live), false, waiting).text).toBe('승인 대기')
  expect(turnOf(board({ ...live, verify: '검증 FAIL' }), false, stops)).toEqual({ tone: 'bad', text: '검증 실패' })
  const broken = stopsOf([stage('implement', '구현', '✗')])
  expect(turnOf(board(live), false, broken)).toEqual({ tone: 'bad', text: '구현 실패' })
  expect(turnOf(board({ ...live, verify: '완료' }), false, stops).tone).toBe('idle')
})

test('a past record raises no alarm: no stages, or untouched by this session', () => {
  const stops = stopsOf(FULL)
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
  expect(helpLead({ tone: 'run', text: '진행 중' })).toMatch(/할 일이 없다/)
  expect(helpLead({ tone: 'me', text: '승인 대기' })).toMatch(/승인/)
  expect(helpLead({ tone: 'me', text: '답변 대기' })).toMatch(/추천대로/)
  expect(helpLead({ tone: 'bad', text: '검증 실패' })).toMatch(/문제/)
  expect(helpLead({ tone: 'idle', text: '완료' })).toMatch(/병합/)
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

test('the buttons toggle the help pane and the console, and hide the gauge', async ($, on) => {
  const { opens, closes } = started(on, true)
  await $.session.start({ cwd: '/repo', ...START }) // 관제판은 세션 시작 때 자동으로 열린다
  opens.length = 0
  closes.length = 0
  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  await ui.press({ key: 'help' })
  await flush()
  expect([opens, closes]).toEqual([['devfsd-help'], []]) // 도움말은 없었으니 연다
  await ui.press({ key: 'console' })
  await flush()
  expect([opens, closes]).toEqual([['devfsd-help'], ['devfsd-console']]) // 관제판은 떠 있었으니 닫는다
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

const cmd = (kind: CmdBoard['kind'], steps: CmdBoard['steps'] = []): CmdBoard => ({ kind, title: '', steps, frs: [], rows: [] })
const LIMITS = [
  { kind: 'five_hour', pct: 42, resetsAt: 1_000 + 159 * 60_000 },
  { kind: 'seven_day', pct: 84, resetsAt: null },
]

test('the dial needle points at the live stage, the last when all are done, nowhere when idle', () => {
  const tick = (state: DialTick['state']): DialTick => ({ label: 'x', state })
  expect(dialNow([tick('done'), tick('now'), tick('todo')])).toBe(1)
  expect(dialNow([tick('done'), tick('fail'), tick('todo')])).toBe(1)
  expect(dialNow([tick('done'), tick('skip'), tick('done')])).toBe(2)
  expect(dialNow([tick('todo'), tick('todo')])).toBe(-1)
  expect(dialNow([])).toBe(-1)
})

test('the dial colour follows the stage group, and an alert or a failure is red', () => {
  const ticks: DialTick[] = ['specify', 'approve', 'implement', 'review', 'verify', 'pr'].map(key => ({ label: key, state: 'todo', key }))
  const hues = ticks.map((_, i) => dialHue(ticks, i, false))
  expect(hues[0]).toBe(hues[1]) // 정하는 단계
  expect(hues[2]).toBe(hues[3]) // 만드는 단계
  expect(hues[4]).toBe(hues[5]) // 확인하는 단계
  expect(new Set([hues[0], hues[2], hues[4]]).size).toBe(3)
  const red = dialHue(ticks, 2, true)
  expect(hues.includes(red)).toBe(false)
  expect(dialHue([{ label: 'x', state: 'fail', key: 'implement' }], 0, false)).toBe(red)
  // 묶음을 모르는 단계(명령이 준 흐름)는 자리 비율로 셋에 나눈다
  const plain: DialTick[] = Array.from({ length: 6 }, (_, i) => ({ label: `s${i}`, state: 'todo' }))
  expect(plain.map((_, i) => dialHue(plain, i, false))).toEqual([hues[0], hues[0], hues[2], hues[2], hues[4], hues[4]])
})

test('the dial shows the running command and that command\'s own steps', () => {
  const stops = stopsOf(FULL)
  const live = { fid: '20261120-x', stages: FULL, activityAt: 900 }
  const run = { tone: 'run', text: '진행 중' } as const
  // 명령이 자기 흐름을 주면 그것이 눈금이다
  const init = dialModelOf(board({ ...live, cmd: cmd('init', [{ label: '수집', mark: 'done' }, { label: '문서', mark: 'cur' }, { label: '검토', mark: 'todo' }]) }), stops, run, LIMITS, 1_000)
  expect(init.command).toBe('init-project')
  expect(init.ticks.map(t => `${t.label}:${t.state}`)).toEqual(['수집:done', '문서:now', '검토:todo'])
  // 흐름이 없으면 이 작업의 단계 점
  const start = dialModelOf(board({ ...live, cmd: cmd('start') }), stops, run, LIMITS, 1_000)
  expect(start.command).toBe('start')
  expect(start.ticks.map(t => t.label)).toEqual(stops.map(s => s.label))
  expect(start.ticks.find(t => t.key === 'implement')?.state).toBe('now')
  expect(start.isAlert).toBe(false)
  expect(start.limits).toEqual([
    { name: 'Claude 5h', pct: 42, reset: '2h39m 뒤 초기화' },
    { name: 'Claude 7d', pct: 84, reset: '' },
  ])
  for (const [kind, name] of [['maintain', 'maintain'], ['quick', 'quick-fix'], ['batch', 'start-all'], ['foundation', 'start-foundation']] as const) {
    expect(commandOf(board({ cmd: cmd(kind) }))).toBe(name)
  }
  expect(commandOf(board({}))).toBe(undefined)
  expect(dialModelOf(board(live), stops, { tone: 'me', text: '답변 대기' }, [], 1_000).isAlert).toBe(true)
  // 대기·완료는 눈금 없이 이름만
  const idle = dialModelOf(board({ fid: '20261116-x' }), [], { tone: 'idle', text: '대기' }, LIMITS, 1_000)
  expect([idle.command, idle.ticks.length]).toEqual(['대기', 0])
  expect(dialModelOf(board(live), stops, { tone: 'idle', text: '완료' }, [], 1_000).command).toBe('완료')
})

test('a running init keeps its dial while it waits for answers, and never turns red', () => {
  const steps = [{ label: '준비', mark: 'done' as const }, { label: '인터뷰', mark: 'cur' as const }, { label: '종결', mark: 'todo' as const }]
  expect(turnOf(board({ cmd: cmd('init', steps) }), true, []).tone).toBe('run')
  expect(turnOf(board({ cmd: cmd('init', steps), working: true }), false, []).tone).toBe('run')
  // 질문을 기다리는 동안 — 계기는 남고 빨강은 아니다(중단된 초기화 흔적이 남은 저장소도 같다: 5.14.1 거짓 경보 재발 방지)
  const hold = turnOf(board({ cmd: cmd('init', steps), activityAt: 900 }), false, [])
  expect(hold).toEqual({ tone: 'hold', text: '일시 멈춤' })
  const dial = dialModelOf(board({ cmd: cmd('init', steps) }), [], hold, [], 1_000)
  expect([dial.command, dial.ticks.length, dial.isAlert]).toEqual(['init-project', 3, false])
  expect(helpLead(hold)).toMatch(/추천대로/)
  // 앞선 작업이 남아 있어도 초기화가 돌면 초기화를 따른다
  expect(turnOf(board({ fid: '20261120-x', stages: FULL, activityAt: 900, cmd: cmd('init', steps) }), false, stopsOf(FULL)).tone).toBe('hold')
  // 다 끝난 초기화는 조용하다
  expect(turnOf(board({ cmd: cmd('init', [{ label: '종결', mark: 'done' }]) }), true, []).tone).toBe('idle')
  expect(turnOf(board({ fid: '20261120-init-project', cmd: cmd('init', [{ label: '종결', mark: 'done' }]), activityAt: 900 }), false, []).tone).toBe('idle')
})

test('only commands with their own flow replace the task stages on the dial', () => {
  const stops = stopsOf(FULL)
  const run = { tone: 'run', text: '진행 중' } as const
  const odd = [{ label: '초안', mark: 'cur' as const }]
  for (const kind of ['start', 'maintain', 'foundation'] as const) {
    const m = dialModelOf(board({ fid: '20261120-x', stages: FULL, cmd: cmd(kind, odd) }), stops, run, [], 1_000)
    expect(m.ticks.map(x => x.label)).toEqual(stops.map(x => x.label))
  }
  for (const kind of ['init', 'batch', 'quick'] as const) {
    expect(dialModelOf(board({ fid: '20261120-x', cmd: cmd(kind, odd) }), stops, run, [], 1_000).ticks.map(x => x.label)).toEqual(['초안'])
  }
})

test('the dial drawing is well formed, escapes its labels and sizes to its limits', () => {
  const model = dialModelOf(board({ fid: '20261120-x', stages: FULL, activityAt: 900, cmd: cmd('start') }), stopsOf(FULL), { tone: 'run', text: '진행 중' }, LIMITS, 1_000)
  const svg = dialSvg(model)
  expect(svg.startsWith('<svg xmlns="http://www.w3.org/2000/svg"')).toBe(true)
  expect(svg.endsWith('</svg>')).toBe(true)
  expect(/NaN|undefined|Infinity/.test(svg)).toBe(false)
  expect(svg.includes('>start</text>')).toBe(true)
  expect(svg.includes('Claude 5h') && svg.includes('Claude 7d') && svg.includes('2h39m 뒤 초기화')).toBe(true)
  expect((svg.match(/<svg/g) ?? []).length).toBe(1)
  expect((svg.match(/<text/g) ?? []).length).toBe((svg.match(/<\/text>/g) ?? []).length)
  expect(svg.length < 131_072).toBe(true) // 그림 요소의 상한
  // 이름표에 든 꺾쇠·앰퍼샌드는 글자로 나간다
  const odd = dialSvg({ command: 'a<b>&"c', ticks: [{ label: '<x>&', state: 'now' }], isAlert: false, limits: [] })
  expect(odd.includes('a&lt;b&gt;&amp;&quot;c') && odd.includes('&lt;x&gt;&amp;')).toBe(true)
  expect(odd.includes('<x>')).toBe(false)
  // 한도 수에 따라 가로가 줄어든다
  expect(dialWidth(2) > dialWidth(1) && dialWidth(1) > dialWidth(0)).toBe(true)
  expect(dialSvg({ ...model, limits: [] }).includes('Claude')).toBe(false)
  // 단계가 많으면 이름표는 지금 단계와 양 끝만
  const many: DialTick[] = Array.from({ length: 12 }, (_, i) => ({ label: `단계${i}`, state: i < 5 ? 'done' : i === 5 ? 'now' : 'todo' }))
  const crowded = dialSvg({ command: 'start-all', ticks: many, isAlert: false, limits: [] })
  expect(['단계0', '단계5', '단계11'].every(l => crowded.includes(`>${l}<`))).toBe(true)
  expect(crowded.includes('>단계3<') || crowded.includes('>단계8<')).toBe(false)
  expect(dialAlt(model)).toMatch(/start 단계는 \d+개 중 \d+번째 구현, Claude 5h 한도 42퍼센트, Claude 7d 한도 84퍼센트/)
  expect(dialAlt({ command: '대기', ticks: [], isAlert: false, limits: [] })).toMatch(/진행 중인 단계 없음/)
})

test('a surface that draws pictures gets the round dial, the terminal gets text', async ($, on) => {
  started(on, true)
  await $.session.start({ cwd: '/repo', ...START })
  const desk = await $.ui.mount({ ...BAND, surface: 'desktop' })
  expect(await desk.find({ type: 'Svg' })).toBeDefined()
  expect(await desk.find({ type: 'Button' })).toBeDefined()
  expect(await desk.find({ text: /■|□/ })).toBeUndefined() // 글자 막대는 터미널 것
  await desk.unmount()
  const term = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await term.find({ type: 'Svg' })).toBeUndefined()
  expect(await term.find({ type: 'Button' })).toBeDefined()
  expect(await term.find({ text: /devFSD/ })).toBeDefined()
  await term.unmount()
})

// ---- 관제판과 같은 기준: 바늘은 관제판이 ▶ 로 그리는 지금(isCurrent) 단계를 가리킨다 ----
// 관제판이 읽는 단계는 기록(session-progress)에서 stagesOf → currentStageKey → withVerifyMark 로 만든다. 앞 단계가 끝난 직후의 다음 단계는
//   기록이 없어 표식이 ○ 인데 isCurrent 만 켜진다 — 손으로 만든 단계 자료에는 이 모양이 없어서 바늘이 처음 자리에 머무는 결함이 시험을 빠져나갔다.
const FID = '20261123-auth-state'
const realStages = (lines: readonly string[]): StageMark[] => {
  const progress = [`## ${FID} · 시험`, ...lines].join('\n')

  return withVerifyMark(stagesOf(progress, FID), undefined, currentStageKey(progress, FID))
}
const needleAt = (b: Board): { label: string; ticks: readonly DialTick[] } => {
  const stops = stopsOf(b.stages)
  const ticks = dialModelOf(b, stops, { tone: 'run', text: '진행 중' }, [], 1_000).ticks

  return { label: ticks[dialNow(ticks)]?.label ?? '(없음)', ticks }
}

test('the needle points at the stage the console marks as current, even before that stage has a record', () => {
  const stages = realStages(['- 2026-11-23 08:57 /specify 완료 (명세)'])
  expect(stages.find(s => s.isCurrent)?.label).toBe('명확화')
  expect(stages.find(s => s.isCurrent)?.mark).toBe('○') // 기록이 없다 — 표식만으로는 지금을 알 수 없다
  expect(needleAt(board({ fid: FID, stages, activityAt: 900 })).label).toBe('명확화')
})

test('the needle follows the console while a stage is recorded as running, and when the next one has not begun', () => {
  const running = realStages(['- 2026-11-23 09:10 /clarify 진행 (질문)', '- 2026-11-23 08:57 /specify 완료 (명세)'])
  expect(needleAt(board({ fid: FID, stages: running, activityAt: 900 })).label).toBe('명확화')
  const gate = realStages([
    '- 2026-11-23 12:00 /verify 완료 (증거)',
    '- 2026-11-23 11:00 /implement 완료 (구현)',
    '- 2026-11-23 10:00 /tasks 완료 (분해)',
    '- 2026-11-23 09:40 /plan 완료 (설계)',
    '- 2026-11-23 09:20 /clarify 완료 (명확화)',
    '- 2026-11-23 08:57 /specify 완료 (명세)',
  ])
  expect(gate.find(s => s.isCurrent)?.key).toBe('security')
  expect(needleAt(board({ fid: FID, stages: gate, activityAt: 900 })).label).toBe('게이트') // 보안·통합·성능·데모는 한 점
})

test('while waiting for approval the needle stays on the console stage, and the note still asks for the approval', () => {
  const stages = realStages(['- 2026-11-23 09:20 /clarify 완료 (명확화)', '- 2026-11-23 08:57 /specify 완료 (명세)'])
  expect(stages.find(s => s.isCurrent)?.label).toBe('설계')
  const b = board({ fid: FID, stages, activityAt: 900 })
  expect(needleAt(b).label).toBe('설계') // 관제판의 ▶ 와 같다
  expect(needleAt(b).ticks.filter(t => t.state === 'now')).toHaveLength(1)
  expect(turnOf(b, false, stopsOf(stages)).text).toBe('승인 대기') // 문구는 그대로
})

test('aligning to the console leaves a failed current stage red and ignores a current stage the dial does not have', () => {
  const tick = (key: string, state: DialTick['state']): DialTick => ({ key, label: key, state })
  const failed = alignCurrent([tick('a', 'done'), tick('b', 'fail')], [{ key: 'b', label: 'b', mark: '✗', isCurrent: true }])
  expect(failed.map(t => t.state)).toEqual(['done', 'fail'])
  const same = [tick('a', 'done'), tick('b', 'now')]
  expect(alignCurrent(same, [{ key: 'zzz', label: 'z', mark: '○', isCurrent: true }])).toEqual(same)
  expect(alignCurrent(same, undefined)).toEqual(same)
  expect(alignCurrent(same, [{ key: 'a', label: 'a', mark: '✓' }])).toEqual(same) // 지금 표시가 없으면 그대로
})

test('each state has a short name and its own colour — green running, red for the user\'s turn or a failure, amber paused, blue done, dim waiting', () => {
  expect(noteTint({ tone: 'run', text: '진행 중' })).toBe('success')
  expect(noteTint({ tone: 'me', text: '승인 대기' })).toBe('error')
  expect(noteTint({ tone: 'me', text: '답변 대기' })).toBe('error')
  expect(noteTint({ tone: 'bad', text: '구현 실패' })).toBe('error')
  expect(noteTint({ tone: 'hold', text: '일시 멈춤' })).toBe('warning')
  expect(noteTint({ tone: 'idle', text: '완료' })).toBe('suggestion')
  expect(noteTint({ tone: 'idle', text: '대기' })).toBeUndefined()
  const live = { fid: '20261120-x', stages: FULL, activityAt: 900 }
  expect(turnOf(board(live), true, stopsOf(FULL)).text).toBe('진행 중')
  expect(turnOf(board({ ...live, verify: '검증 FAIL' }), false, stopsOf(FULL)).text).toBe('검증 실패')
})

test('each button opens its pane when it is not up and closes it when it is — the two panes are counted apart', async ($, on) => {
  const { opens, closes } = started(on, true)
  await $.session.start({ cwd: '/repo', ...START })
  opens.length = 0
  closes.length = 0
  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  const press = async (key: string) => {
    await ui.press({ key })
    await flush()
  }
  await press('help')
  await press('help')
  await press('help')
  expect([opens, closes]).toEqual([['devfsd-help', 'devfsd-help'], ['devfsd-help']]) // 열고 · 닫고 · 다시 연다
  await press('console') // 자동으로 열려 있던 관제판
  await press('console')
  expect(closes).toEqual(['devfsd-help', 'devfsd-console'])
  expect(opens).toEqual(['devfsd-help', 'devfsd-help', 'devfsd-console']) // 도움말 상태와 무관하다
  await ui.unmount()
})

// ── 20261127: 검증 STALE 보존 · 지난 작업 ─────────────────────────────

const STALE_AT_GATE: StageMark[] = [
  stage('specify', '명세', '✓'),
  stage('implement', '구현', '✓'),
  stage('verify', '검증', '!'),
  stage('security', '보안', '✓'),
  { key: 'demo', label: '데모', mark: '○', isCurrent: true },
  stage('pr', 'PR', '○'),
]

test('a stale verify stays a warning on the dial after the needle moves to the console stage', () => {
  const stops = stopsOf(STALE_AT_GATE)
  const model = dialModelOf(board({ fid: '20261127-x', stages: STALE_AT_GATE, verify: '검증 STALE', activityAt: 900 }), stops, { tone: 'run', text: '진행 중' }, [], 0)
  expect(model.ticks.find(t => t.label === '검증')?.state).toBe('warn')
  expect(model.ticks.find(t => t.label === '게이트')?.state).toBe('now')
  expect(model.ticks[dialNow(model.ticks)]?.label).toBe('게이트')
})

test('a warning tick is drawn amber with its name even when the dial is crowded', () => {
  const ticks: DialTick[] = ['가', '나', '다', '라', '마', '바', '사', '아', '자', '차'].map((label, i) => ({
    label,
    state: i === 2 ? 'warn' : i < 5 ? 'done' : i === 5 ? 'now' : 'todo',
  }))
  const svg = dialSvg({ command: 'start', ticks, isAlert: false, limits: [] })
  expect(svg).toContain('>다</text>')
  expect(svg).toContain('#E0A030')
  expect(dialAlt({ command: 'start', ticks, isAlert: false, limits: [] })).toContain('다 다시 필요')
})

test('a stale verify is announced while the session is busy too', () => {
  const note = turnOf(board({ fid: '20261127-x', stages: STALE_AT_GATE, verify: '검증 STALE', activityAt: 900 }), true, stopsOf(STALE_AT_GATE))
  expect(note).toEqual({ tone: 'run', text: '진행 중 · 재검증 필요' })
  expect(noteTint(note)).toBe('warning')
})

test('a past work reads as waiting even while the session is busy with something else', () => {
  const past = board({ fid: '20261026-old', isPast: true, activityAt: 900, working: true })
  expect(turnOf(past, true, [])).toEqual({ tone: 'idle', text: '대기' })
})

const OLD_RECORD = '# s\n\n## 20261026-old · 설명\n\n- 2026-10-26 11:19 /performance-test SKIP (x)\n- 2026-10-26 11:15 /implement DONE (x)\n'

const NOW = Date.parse('2026-11-27T10:00')

const withRecord = (on: Parameters<Parameters<typeof test>[1]>[1], text = OLD_RECORD) => {
  const file = { text }
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('clock.every', () => ({ value: { cancel: () => {} } }))
  on('clock.now', () => ({ value: NOW }))
  on('fs.read', () => ({ value: file.text }))
  // 관할 폴더와 그 안의 작업 폴더가 있다 — 작업 폴더가 있어야 검증 상태를 읽는다.
  on('fs.exists', (_, e) => ({ value: e.path === '/repo/.specops' || /^\/repo\/\.specops\/\d{8}-[a-z0-9-]+$/.test(e.path) }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('tool.call', () => ({ result: {}, text: 'ok' }))

  return file
}

const bandText = async ($: Parameters<Parameters<typeof test>[1]>[0]) => {
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const found = await ui.find({ type: 'Text', text: /devFSD/ })
  await ui.unmount()

  return found?.text ?? ''
}

// 상태 갱신은 도구 호출이 돌아온 뒤에 이어지는 비동기 작업이라 여러 번 비운다.
const settle = async () => {
  for (let i = 0; i < 100; i++) await flush()
}

const edit = ($: Parameters<Parameters<typeof test>[1]>[0], id: string) =>
  $.tool.call({ tool: 'Edit', tool_use_id: id, file_path: '/repo/a.txt', old_string: 'a', new_string: 'b' } as never)

test('work recorded before this session shows as recent until its record changes', async ($, on) => {
  const file = withRecord(on)
  await $.session.start({ cwd: '/repo', ...START })
  await settle()
  await edit($, 'toolu_e1')
  await settle()
  expect(await bandText($)).toMatch(/대기 · 최근 old/)

  file.text = OLD_RECORD.replace('- 2026-10-26 11:19', '- 2026-11-27 09:00 /demo DONE (x)\n- 2026-10-26 11:19')
  await edit($, 'toolu_e2')
  await settle()
  expect(await bandText($)).not.toMatch(/최근/)
  expect(await bandText($)).toMatch(/old/)
})

test('a devFSD skill call in this session brings past work back', async ($, on) => {
  withRecord(on)
  await $.session.start({ cwd: '/repo', ...START })
  await settle()
  expect(await bandText($)).toMatch(/최근 old/)
  await $.tool.call({ tool: 'Skill', tool_use_id: 'toolu_s', skill: 'devfsd:verifying-evidence-ko' } as never)
  await settle()
  expect(await bandText($)).not.toMatch(/최근/)
})

test('a work started in this session is live from its first record', async ($, on) => {
  const file = withRecord(on)
  await $.session.start({ cwd: '/repo', ...START })
  await settle()
  file.text = '# s\n\n## 20261127-new · 설명\n\n- 2026-11-27 09:00 /specify 완료 (x)\n\n' + OLD_RECORD.slice(4)
  await edit($, 'toolu_e1')
  await settle()
  const text = await bandText($)
  expect(text).toMatch(/new/)
  expect(text).not.toMatch(/최근/)
})

test('work recorded within three days stays live when the session is reopened', async ($, on) => {
  withRecord(on, OLD_RECORD.replace(/2026-10-26/g, '2026-11-25'))
  await $.session.start({ cwd: '/repo', ...START })
  await settle()
  await edit($, 'toolu_e1')
  await settle()
  expect(await bandText($)).not.toMatch(/최근/)
  expect(await bandText($)).toMatch(/old/)
})

// ── 두 화면이 같은 말을 한다 (지난 작업 · 낡은 검증) ──────────────────────

const CONSOLE = {
  plugin: 'devfsd',
  component: 'Pane',
  requestId: 'devfsd-console',
  props: { title: 'devFSD 관제판', isFocused: true, bodyColumns: 66, placement: 'dock', scroll: { offset: 0, bodyRows: 70 }, view: {} },
} as const

test('past work: the desktop gauge and the console say the same thing', async ($, on) => {
  on('ui.status', () => ({ value: undefined }))
  withRecord(on)
  await $.session.start({ cwd: '/repo', ...START })
  await settle()
  await edit($, 'toolu_e1')
  await settle()

  const desk = await $.ui.mount({ ...BAND, surface: 'desktop' })
  expect(await desk.find({ text: /최근 old/ })).toBeDefined()
  expect(await desk.find({ text: /진행 중|답변 대기|재검증/ })).toBeUndefined()
  expect(String((await desk.find({ type: 'Svg' }))?.props?.alt)).toContain('진행 중인 단계 없음')
  await desk.unmount()

  const pane = await $.ui.mount({ ...CONSOLE, surface: 'terminal' })
  expect(await pane.find({ text: /devFSD · 최근 20261026-old/ })).toBeDefined()
  expect(await pane.find({ text: /▶/ })).toBeUndefined()
  expect(await pane.find({ text: /구현|검증|STALE/ })).toBeUndefined()
  await pane.unmount()
})

test('stale verify: the desktop gauge warns and the console shows it too', async ($, on) => {
  on('ui.status', () => ({ value: undefined }))
  withRecord(on, '# s\n\n## 20261127-x · 설명\n\n- 2026-11-27 09:30 /integration-test DONE (x)\n- 2026-11-27 09:20 /security-review DONE (x)\n- 2026-11-27 09:10 /verify PASS (x)\n- 2026-11-27 09:00 /implement DONE (x)\n')
  on('process.run', (_, e) => {
    const argv = (e as unknown as { argv: string[] }).argv
    const isVerify = argv.some(a => a.endsWith('verification-state.sh'))

    return { value: { exitCode: isVerify ? 0 : 1, stdout: isVerify ? 'STALE\n' : '', stderr: '' } }
  })
  await $.session.start({ cwd: '/repo', ...START })
  await settle()
  await edit($, 'toolu_e1')
  await settle()

  const desk = await $.ui.mount({ ...BAND, surface: 'desktop' })
  expect((await desk.find({ text: /●/ }))?.text).toContain('재검증 필요')
  expect(String((await desk.find({ type: 'Svg' }))?.props?.alt)).toContain('검증 다시 필요')
  await desk.unmount()

  const pane = await $.ui.mount({ ...CONSOLE, surface: 'terminal' })
  expect(await pane.find({ text: /검증 STALE/ })).toBeDefined()
  expect(await pane.find({ text: /검증!/ })).toBeDefined()
  await pane.unmount()
})

test('a narrow band keeps the whole dial picture — it wraps below and shrinks, never cut off', async ($, on) => {
  started(on, true)
  on('session.measure', (_, e) => ({ changed: e.changed }))
  await $.session.start({ cwd: '/repo', ...START })
  await $.session.measure({
    context: { window: 200_000 },
    rateLimits: [{ kind: 'five_hour', percentUsed: 21 }, { kind: 'seven_day', percentUsed: 37 }],
    changed: ['rateLimits'],
  } as never)
  const sizeAt = async (bodyColumns: number) => {
    const ui = await $.ui.mount({ ...BAND, props: { ...BAND.props, bodyColumns }, surface: 'desktop' })
    const svg = await ui.find({ type: 'Svg' })
    const alt = String(svg?.props?.alt)
    const size = [Number(svg?.props?.width), Number(svg?.props?.height)]
    await ui.unmount()
    expect(alt).toContain('7d 한도 37퍼센트')

    return size
  }
  const [wide, tall] = await sizeAt(140)
  expect(wide).toBe(Math.round(dialWidth(2) * 1.3))
  for (const cols of [60, 40]) {
    const [w, h] = await sizeAt(cols)
    expect(w).toBe(cols * 7)
    expect(Math.abs((h ?? 0) - ((w ?? 0) * (tall ?? 0)) / (wide ?? 1))).toBeLessThan(2) // 비율 유지
  }
})
