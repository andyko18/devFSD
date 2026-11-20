import { expect, test } from 'claude-code/testing'

import type { Board, CmdBoard, StageMark } from '../types'
import { commandOf, dialModelOf, helpLead, limitParts, shortFid, stopsOf, turnOf } from './gauge'
import { dialAlt, dialHue, dialNow, dialSvg, dialWidth } from './gauge-dial'
import type { DialTick } from './gauge-dial'
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
  const ticks: DialTick[] = ['specify', 'approve', 'implement', 'review', 'verify', 'pr', 'merge'].map(key => ({ label: key, state: 'todo', key }))
  const hues = ticks.map((_, i) => dialHue(ticks, i, false))
  expect(hues[0]).toBe(hues[1]) // 정하는 단계
  expect(hues[2]).toBe(hues[3]) // 만드는 단계
  expect(hues[4]).toBe(hues[6]) // 확인하는 단계
  expect(new Set([hues[0], hues[2], hues[4]]).size).toBe(3)
  const red = dialHue(ticks, 2, true)
  expect(hues.includes(red)).toBe(false)
  expect(dialHue([{ label: 'x', state: 'fail', key: 'implement' }], 0, false)).toBe(red)
  // 묶음을 모르는 단계(명령이 준 흐름)는 자리 비율로 셋에 나눈다
  const plain: DialTick[] = Array.from({ length: 6 }, (_, i) => ({ label: `s${i}`, state: 'todo' }))
  expect(plain.map((_, i) => dialHue(plain, i, false))).toEqual([hues[0], hues[0], hues[2], hues[2], hues[4], hues[4]])
})

test('the dial shows the running command and that command\'s own steps', () => {
  const stops = stopsOf(FULL, false)
  const live = { fid: '20261120-x', stages: FULL, activityAt: 900 }
  const run = { tone: 'run', text: '기다리면 된다' } as const
  // 명령이 자기 흐름을 주면 그것이 눈금이다
  const init = dialModelOf(board({ ...live, cmd: cmd('init', [{ label: '수집', mark: 'done' }, { label: '문서', mark: 'cur' }, { label: '검토', mark: 'todo' }]) }), stops, run, LIMITS, 1_000)
  expect(init.command).toBe('init-project')
  expect(init.ticks.map(t => `${t.label}:${t.state}`)).toEqual(['수집:done', '문서:now', '검토:todo'])
  // 흐름이 없으면 이 작업의 단계 점
  const start = dialModelOf(board({ ...live, cmd: cmd('start') }), stops, run, LIMITS, 1_000)
  expect(start.command).toBe('start')
  expect(start.ticks.map(t => t.label)).toEqual(stops.map(s => s.label))
  expect(start.ticks.find(t => t.key === 'implement')?.state).toBe('now')
  expect(start.ticks.find(t => t.key === 'merge')?.state).toBe('todo')
  expect(start.isAlert).toBe(false)
  expect(start.limits).toEqual([
    { name: 'Claude 5h', pct: 42, reset: '2h39m 뒤 초기화' },
    { name: 'Claude 7d', pct: 84, reset: '' },
  ])
  for (const [kind, name] of [['maintain', 'maintain'], ['quick', 'quick-fix'], ['batch', 'start-all'], ['foundation', 'start-foundation']] as const) {
    expect(commandOf(board({ cmd: cmd(kind) }))).toBe(name)
  }
  expect(commandOf(board({}))).toBe(undefined)
  expect(dialModelOf(board(live), stops, { tone: 'me', text: '내 차례 — 답을 기다린다' }, [], 1_000).isAlert).toBe(true)
  // 대기·완료는 눈금 없이 이름만
  const idle = dialModelOf(board({ fid: '20261116-x' }), [], { tone: 'idle', text: '대기' }, LIMITS, 1_000)
  expect([idle.command, idle.ticks.length]).toEqual(['대기', 0])
  expect(dialModelOf(board(live), stops, { tone: 'idle', text: '완료 — PR 확인·병합은 직접' }, [], 1_000).command).toBe('완료')
})

test('a running init keeps its dial while it waits for answers, and never turns red', () => {
  const steps = [{ label: '준비', mark: 'done' as const }, { label: '인터뷰', mark: 'cur' as const }, { label: '종결', mark: 'todo' as const }]
  expect(turnOf(board({ cmd: cmd('init', steps) }), true, []).tone).toBe('run')
  expect(turnOf(board({ cmd: cmd('init', steps), working: true }), false, []).tone).toBe('run')
  // 질문을 기다리는 동안 — 계기는 남고 빨강은 아니다(중단된 초기화 흔적이 남은 저장소도 같다: 5.14.1 거짓 경보 재발 방지)
  const hold = turnOf(board({ cmd: cmd('init', steps), activityAt: 900 }), false, [])
  expect(hold).toEqual({ tone: 'hold', text: '인터뷰 중 — 질문이 있으면 답한다' })
  const dial = dialModelOf(board({ cmd: cmd('init', steps) }), [], hold, [], 1_000)
  expect([dial.command, dial.ticks.length, dial.isAlert]).toEqual(['init-project', 3, false])
  expect(helpLead(hold)).toMatch(/추천대로/)
  // 앞선 작업이 남아 있어도 초기화가 돌면 초기화를 따른다
  expect(turnOf(board({ fid: '20261120-x', stages: FULL, activityAt: 900, cmd: cmd('init', steps) }), false, stopsOf(FULL, false)).tone).toBe('hold')
  // 다 끝난 초기화는 조용하다
  expect(turnOf(board({ cmd: cmd('init', [{ label: '종결', mark: 'done' }]) }), true, []).tone).toBe('idle')
  expect(turnOf(board({ fid: '20261120-init-project', cmd: cmd('init', [{ label: '종결', mark: 'done' }]), activityAt: 900 }), false, []).tone).toBe('idle')
})

test('only commands with their own flow replace the task stages on the dial', () => {
  const stops = stopsOf(FULL, false)
  const run = { tone: 'run', text: '기다리면 된다' } as const
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
  const model = dialModelOf(board({ fid: '20261120-x', stages: FULL, activityAt: 900, cmd: cmd('start') }), stopsOf(FULL, false), { tone: 'run', text: '기다리면 된다' }, LIMITS, 1_000)
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
