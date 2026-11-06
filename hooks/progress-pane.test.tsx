import { expect, mock, test } from 'claude-code/testing'

import {
  activeFid,
  elapsed,
  fidOf,
  isLifecycleDone,
  notificationOf,
  projectRoot,
  stageOf,
  stagesOf,
  verifyWord,
} from './progress-pane'

const PANE = {
  plugin: 'devfsd',
  component: 'Pane',
  requestId: 'devfsd-progress',
  props: {
    title: 'devFSD 진행',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

const SURFACES = ['terminal', 'desktop'] as const

test('helpers read stage, FID, notification and elapsed time', () => {
  expect(stageOf('devfsd:planning-ko')).toBe('설계 (planning-ko)')
  expect(stageOf('specops-ko:verifying-evidence-ko')).toBe('검증 (verifying-evidence-ko)')
  expect(stageOf('simplify')).toBe(undefined)
  expect(fidOf('# x\n\n## 20261030-foo · 설명\n- a')).toBe('20261030-foo')
  expect(notificationOf('<tool-use-id>toolu_1</tool-use-id><status>completed</status>')).toEqual({
    id: 'toolu_1',
    isFailed: false,
  })
  expect(notificationOf('<tool-use-id>toolu_2</tool-use-id><status>failed</status>')?.isFailed).toBe(true)
  expect(notificationOf('plain text')).toBe(undefined)
  expect(elapsed(192_000)).toBe('3m12s')
  expect(elapsed(9_000)).toBe('9s')
  expect(projectRoot('/repo/.worktrees/20261030-x')).toBe('/repo')
  expect(projectRoot('/repo/.claude/worktrees/wt')).toBe('/repo')
  expect(projectRoot('/repo')).toBe('/repo')
  expect(projectRoot('/a/.worktrees/x/.claude/worktrees/y')).toBe('/a')
  expect(projectRoot('/repo/.claude/worktrees')).toBe('/repo/.claude/worktrees')
})

test('the pane shows nothing running before any work', async ($, on) => {
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /실행 중/ }))?.text).toBe('▶ 실행 중 (0)')
    await ui.unmount()
  }
})

test('a foreground agent runs, then lands in recent', async ($, on) => {
  on('clock.now', () => ({ value: 1_000 }))
  let release: () => void = () => {}
  let entered: () => void = () => {}
  const gate = new Promise<void>(resolve => (release = resolve))
  const reached = new Promise<void>(resolve => (entered = resolve))
  on('tool.call', async () => {
    entered()
    await gate
    return { result: {}, text: 'review done' }
  })

  const call = $.tool.call({
    tool: 'Agent',
    tool_use_id: 'toolu_a',
    description: '리뷰 B',
    prompt: 'review',
    subagent_type: 'devfsd:spec-reviewer-ko',
  })
  await reached
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /리뷰 B/ }))?.text).toMatch(/리뷰 B · devfsd:spec-reviewer-ko/)
    await ui.unmount()
  }

  release()
  await call
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /실행 중/ }))?.text).toBe('▶ 실행 중 (0)')
    expect((await ui.find({ type: 'Text', text: /리뷰 B/ }))?.text).toMatch(/✓ 리뷰 B/)
    await ui.unmount()
  }
})

test('a background command stays running until its notification', async ($, on) => {
  on('clock.now', () => ({ value: 1_000 }))
  on('tool.call', () => ({ result: {}, text: 'Command running in background' }))

  await $.tool.call({
    tool: 'Bash',
    tool_use_id: 'toolu_b',
    command: 'bash scripts/tests/run-all.sh',
    description: 'run-all',
    run_in_background: true,
  })
  const running = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await running.find({ type: 'Text', text: /run-all/ }))?.text).toMatch(/run-all · 백그라운드/)
  await running.unmount()

  await $.session.append({
    door: 'delivery',
    origin: { kind: 'task-notification' },
    uuid: 'row-1',
    message: {
      type: 'user',
      content: [{ type: 'text', text: '<tool-use-id>toolu_b</tool-use-id><status>failed</status>' }],
    },
  })
  const done = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await done.find({ type: 'Text', text: /실행 중/ }))?.text).toBe('▶ 실행 중 (0)')
  expect((await done.find({ type: 'Text', text: /run-all/ }))?.text).toMatch(/✗ run-all/)
  await done.unmount()
})

test('a foreground command is not tracked', async ($, on) => {
  on('tool.call', () => ({ result: {}, text: 'ok' }))
  await $.tool.call({ tool: 'Bash', tool_use_id: 'toolu_c', command: 'ls' })

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /실행 중/ }))?.text).toBe('▶ 실행 중 (0)')
  expect(await ui.find({ type: 'Text', text: /ls/ })).toBe(undefined)
  await ui.unmount()
})

test('a devFSD skill call sets the stage', async ($, on) => {
  on('tool.call', () => ({ result: {}, text: 'loaded' }))
  await $.tool.call({ tool: 'Skill', tool_use_id: 'toolu_d', skill: 'devfsd:implementing-ko' })

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /^devFSD/ }))?.text).toMatch(/구현 \(implementing-ko\)/)
  await ui.unmount()
})

const opened = (on: Parameters<Parameters<typeof test>[1]>[1]) => {
  const calls: string[] = []
  on('command.register', () => ({ value: { command: 'devfsd-progress' } }))
  on('clock.every', () => ({ value: { cancel: () => {} } }))
  on('clock.now', () => ({ value: 1_000 }))
  on('fs.read', () => { throw new Error('ENOENT') })
  on('ui.open', (_, e) => { calls.push(e.id); return { value: { isPlaced: true } } })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  return calls
}

const START = { surface: 'desktop', isInteractive: true } as const

test('a governed repo opens the pane at session start', async ($, on) => {
  const calls = opened(on)
  on('fs.exists', (_, e) => ({ value: e.path === '/repo/.specops' }))
  await $.session.start({ cwd: '/repo', ...START })
  expect(calls).toEqual(['devfsd-console'])
})

test('a worktree of a governed repo opens the pane', async ($, on) => {
  const calls = opened(on)
  on('fs.exists', (_, e) => ({ value: e.path === '/repo/.specops' }))
  await $.session.start({ cwd: '/repo/.claude/worktrees/wt', ...START })
  expect(calls).toEqual(['devfsd-console'])
})

test('another repo does not open the pane, the command still does', async ($, on) => {
  const calls = opened(on)
  on('fs.exists', () => ({ value: false }))
  await $.session.start({ cwd: '/other', ...START })
  expect(calls).toEqual([])
  await $.command.run({ command: 'devfsd-progress', args: '' })
  expect(calls).toEqual(['devfsd-progress'])
})

test('a worktree with its own .specops opens the pane', async ($, on) => {
  const calls = opened(on)
  on('fs.exists', (_, e) => ({ value: e.path === '/repo/.claude/worktrees/wt/.specops' }))
  await $.session.start({ cwd: '/repo/.claude/worktrees/wt', ...START })
  expect(calls).toEqual(['devfsd-console'])
})

test('a .worktrees worktree opens the pane, a look-alike folder does not', async ($, on) => {
  const calls = opened(on)
  on('fs.exists', (_, e) => ({ value: e.path === '/repo/.specops' }))
  await $.session.start({ cwd: '/repo/.worktrees/20261030-x', ...START })
  expect(calls).toEqual(['devfsd-console'])
  await $.session.start({ cwd: '/repo/.worktrees-old/x', ...START })
  expect(calls).toEqual(['devfsd-console'])
})

test('a failing existence check keeps the pane closed without rejecting', async ($, on) => {
  const calls = opened(on)
  on('fs.exists', () => { throw new Error('EACCES') })
  await $.session.start({ cwd: '/repo', ...START })
  expect(calls).toEqual([])
})

// --- T5: 추적 분기 · 관찰 격리 · 시간 ----------------------------------------

type Pane$ = Parameters<Parameters<typeof test>[1]>[0]
type PaneOn = Parameters<Parameters<typeof test>[1]>[1]

/** 한 번 마운트해 Text 줄을 모두 읽는다. */
const rowsOf = async ($: Pane$): Promise<string[]> => {
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  const rows = (await ui.findAll({ type: 'Text' })).map(one => one.text ?? '')
  await ui.unmount()

  return rows
}

const agentCall = (id: string, extra: Record<string, unknown> = {}) =>
  ({ tool: 'Agent', tool_use_id: id, description: `작업 ${id}`, prompt: 'p', subagent_type: 'general-purpose', ...extra }) as never

const bgBash = (id: string, extra: Record<string, unknown> = {}) =>
  ({ tool: 'Bash', tool_use_id: id, command: 'bash run.sh', description: `명령 ${id}`, run_in_background: true, ...extra }) as never

const notify = ($: Pane$, id: string, status: string, extra: Record<string, unknown> = {}) =>
  $.session.append({
    door: 'delivery',
    origin: { kind: 'task-notification' },
    uuid: `row-${id}-${status}`,
    message: { type: 'user', content: [{ type: 'text', text: `<tool-use-id>${id}</tool-use-id><status>${status}</status>` }] },
    ...extra,
  } as never)

const running = (rows: string[]) => rows.find(row => row.startsWith('▶ 실행 중'))

test('a background agent stays running after launch, then lands in recent on its notification', async ($, on) => {
  on('clock.now', () => ({ value: 1_000 }))
  on('tool.call', () => ({ result: {}, text: 'Async agent launched successfully' }))
  await $.tool.call(agentCall('toolu_bg'))

  const launched = await rowsOf($)
  expect(running(launched)).toBe('▶ 실행 중 (1)')
  expect(launched.some(row => row.includes('✓ 작업 toolu_bg'))).toBe(false)

  await notify($, 'toolu_bg', 'completed')
  const done = await rowsOf($)
  expect(running(done)).toBe('▶ 실행 중 (0)')
  expect(done.some(row => row.includes('✓ 작업 toolu_bg'))).toBe(true)
})

test('a foreground agent that errors or is denied lands as failed', async ($, on) => {
  on('clock.now', () => ({ value: 1_000 }))
  on('tool.call', (_, e) => (e.tool_use_id === 'toolu_deny' ? { deny: '막힘' } : { result: {}, isError: true, text: 'x' }))
  await $.tool.call(agentCall('toolu_err'))
  await $.tool.call(agentCall('toolu_deny'))

  const rows = await rowsOf($)
  expect(running(rows)).toBe('▶ 실행 중 (0)')
  expect(rows.some(row => row.includes('✗ 작업 toolu_err'))).toBe(true)
  expect(rows.some(row => row.includes('✗ 작업 toolu_deny'))).toBe(true)
})

test('a denied background command lands as failed', async ($, on) => {
  on('clock.now', () => ({ value: 1_000 }))
  on('tool.call', () => ({ deny: '막힘' }))
  await $.tool.call(bgBash('toolu_bd'))

  const rows = await rowsOf($)
  expect(running(rows)).toBe('▶ 실행 중 (0)')
  expect(rows.some(row => row.includes('✗ 명령 toolu_bd'))).toBe(true)
})

test('a background command notified as completed lands as done', async ($, on) => {
  on('clock.now', () => ({ value: 1_000 }))
  on('tool.call', () => ({ result: {}, text: 'Command running in background' }))
  await $.tool.call(bgBash('toolu_bok'))
  await notify($, 'toolu_bok', 'completed')

  const rows = await rowsOf($)
  expect(rows.some(row => row.includes('✓ 명령 toolu_bok'))).toBe(true)
  expect(rows.some(row => row.includes('✗ 명령 toolu_bok'))).toBe(false)
})

test('calls and notifications from inside a subagent are ignored', async ($, on) => {
  on('clock.now', () => ({ value: 1_000 }))
  on('tool.call', () => ({ result: {}, text: 'Async agent launched successfully' }))
  await $.tool.call(agentCall('toolu_sub', { agentId: 'sub1' }))
  await $.tool.call(bgBash('toolu_subb', { agentId: 'sub1' }))
  expect(running(await rowsOf($))).toBe('▶ 실행 중 (0)')

  await $.tool.call(agentCall('toolu_top'))
  await notify($, 'toolu_top', 'completed', { agentId: 'sub1' })
  expect(running(await rowsOf($))).toBe('▶ 실행 중 (1)')

  await notify($, 'toolu_top', 'completed')
  expect(running(await rowsOf($))).toBe('▶ 실행 중 (0)')
})

test('recent keeps the latest five, newest on top', async ($, on) => {
  let t = 0
  on('clock.now', () => ({ value: (t += 1_000) }))
  on('tool.call', () => ({ result: {}, text: 'done' }))
  for (const n of [1, 2, 3, 4, 5, 6]) await $.tool.call(agentCall(`a${n}`))

  const done = (await rowsOf($)).filter(row => row.includes('✓'))
  expect(done.length).toBe(5)
  expect(done.some(row => row.includes('작업 a1 '))).toBe(false)
  // 관제판 훅도 같은 시계를 읽으므로 소요 초는 고정하지 않고 순서만 본다.
  expect(done[0]).toMatch(/^  ✓ 작업 a6 · \d+s$/)
  expect(done[4]).toMatch(/^  ✓ 작업 a2 · \d+s$/)
})

test('the hooks hand back exactly what the tool returned', async ($, on) => {
  on('clock.now', () => ({ value: 1_000 }))
  let calls = 0
  const answer = { result: {}, text: 'review done' }
  on('tool.call', () => { calls += 1; return answer })

  expect(await $.tool.call(agentCall('toolu_r1'))).toEqual(answer)
  expect(await $.tool.call(bgBash('toolu_r2'))).toEqual(answer)
  expect(await $.tool.call({ tool: 'Skill', tool_use_id: 'toolu_r3', skill: 'devfsd:implementing-ko' } as never)).toEqual(answer)
  expect(calls).toBe(3)
})

test('a clock that fails after the call ran never runs the call twice', async ($, on) => {
  let clockCalls = 0
  on('clock.now', () => {
    clockCalls += 1
    if (clockCalls >= 2) throw new Error('boom')

    return { value: 1_000 }
  })
  let calls = 0
  const answer = { result: {}, text: 'review done' }
  on('tool.call', () => { calls += 1; return answer })

  expect(await $.tool.call(agentCall('toolu_f1'))).toEqual(answer)
  expect(calls).toBe(1)
})

test('a clock that fails after a denied background command never runs it twice', async ($, on) => {
  let clockCalls = 0
  on('clock.now', () => {
    clockCalls += 1
    if (clockCalls >= 2) throw new Error('boom')

    return { value: 1_000 }
  })
  let calls = 0
  const answer = { deny: '막힘' }
  on('tool.call', () => { calls += 1; return answer })

  expect(await $.tool.call(bgBash('toolu_f2'))).toEqual(answer)
  expect(calls).toBe(1)
})

test('a failing clock does not break any observed call', async ($, on) => {
  on('clock.now', () => { throw new Error('boom') })
  let calls = 0
  const answer = { result: {}, text: 'review done' }
  on('tool.call', () => { calls += 1; return answer })

  expect(await $.tool.call(agentCall('toolu_g1'))).toEqual(answer)
  expect(await $.tool.call(bgBash('toolu_g2'))).toEqual(answer)
  expect(await $.tool.call({ tool: 'Skill', tool_use_id: 'toolu_g3', skill: 'devfsd:implementing-ko' } as never)).toEqual(answer)
  expect(calls).toBe(3)

  const stored = await notify($, 'toolu_g1', 'completed')
  expect(stored).toEqual({
    uuid: 'row-toolu_g1-completed',
    message: {
      type: 'user',
      content: [{ type: 'text', text: '<tool-use-id>toolu_g1</tool-use-id><status>completed</status>' }],
    },
  })
})

test('a skill call puts the FID and stage on the head line; others leave it alone', async ($, on) => {
  on('fs.read', () => ({ value: '# s\n\n## 20261030-x · 설명\n' }))
  on('tool.call', () => ({ result: {}, text: 'loaded' }))
  const head = async () => (await rowsOf($)).find(row => row.startsWith('devFSD'))

  expect(await head()).toBe('devFSD')
  await $.tool.call({ tool: 'Skill', tool_use_id: 'toolu_s0', skill: 'simplify' } as never)
  await $.tool.call({ tool: 'Skill', tool_use_id: 'toolu_s1', skill: 'devfsd:planning-ko', agentId: 'sub1' } as never)
  expect(await head()).toBe('devFSD')

  await $.tool.call({ tool: 'Skill', tool_use_id: 'toolu_s2', skill: 'devfsd:implementing-ko' } as never)
  expect(await head()).toBe('devFSD · 20261030-x · 구현 (implementing-ko)')
})

type ToolHandler = Parameters<PaneOn>[1]

const startedClock = async ($: Pane$, clock: ReturnType<typeof mock.clock>) => {
  await $.session.start({ cwd: '/other', ...START })

  return clock
}

/** `$` 를 처음 부르기 전에 깔 바닥 hook — mock 시계 + session.start 가 필요로 하는 것. */
const clockWorld = (on: PaneOn, tool: ToolHandler, now = 1_000, onNow: () => void = () => {}) => {
  // clock.now 읽기 횟수를 센다 — mock.clock 이 그 hook 을 쥐고 있어 따로 못 건다.
  const counting = ((event: string, ...rest: unknown[]) => {
    const last = rest.length - 1
    const hook = rest[last] as (...args: unknown[]) => unknown
    if (event === 'clock.now') rest[last] = (...args: unknown[]) => { onNow(); return hook(...args) }

    return (on as (...args: unknown[]) => unknown)(event, ...rest)
  }) as PaneOn
  const clock = mock.clock(counting, { now })
  on('command.register', () => ({ value: { command: 'devfsd-progress' } }))
  on('fs.read', () => { throw new Error('ENOENT') })
  on('fs.exists', () => ({ value: false }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('tool.call', tool)

  return clock
}

test('the tick moves elapsed time of a running job, and an ended job keeps its own span', async ($, on) => {
  let release: () => void = () => {}
  let entered: () => void = () => {}
  const gate = new Promise<void>(resolve => (release = resolve))
  const reached = new Promise<void>(resolve => (entered = resolve))
  const clock = clockWorld(on, async () => { entered(); await gate; return { result: {}, text: 'ok' } })
  await startedClock($, clock)

  const call = $.tool.call(agentCall('toolu_t'))
  await reached
  expect((await rowsOf($)).find(row => row.includes('작업 toolu_t'))).toBe('  작업 toolu_t · general-purpose · 0s')

  await clock.advance(3_000)
  release()
  await call
  expect((await rowsOf($)).find(row => row.includes('작업 toolu_t'))).toBe('  ✓ 작업 toolu_t · 3s')

  await clock.advance(190_000)
  expect((await rowsOf($)).find(row => row.includes('작업 toolu_t'))).toBe('  ✓ 작업 toolu_t · 3s')
})

test('the tick refreshes now while something runs', async ($, on) => {
  const clock = clockWorld(on, () => ({ result: {}, text: 'Async agent launched successfully' }))
  await startedClock($, clock)
  await $.tool.call(agentCall('toolu_u'))

  await clock.advance(190_000)
  expect((await rowsOf($)).find(row => row.includes('작업 toolu_u'))).toBe('  작업 toolu_u · general-purpose · 3m10s')
})

test('the tick leaves the clock alone while nothing runs', async ($, on) => {
  let nowCalls = 0
  const clock = clockWorld(on, () => ({ result: {}, text: 'ok' }), 1_000, () => { nowCalls += 1 })
  await startedClock($, clock)

  const before = nowCalls
  await clock.advance(60_000)
  expect(nowCalls).toBe(before)
})

test('a second session start leaves one live ticker', async ($, on) => {
  let nowCalls = 0
  const clock = clockWorld(on, () => ({ result: {}, text: 'Async agent launched successfully' }), 1_000, () => { nowCalls += 1 })
  await startedClock($, clock)
  await $.session.start({ cwd: '/other', ...START })
  await $.tool.call(agentCall('toolu_v'))

  const before = nowCalls
  await clock.advance(5_000)
  expect(nowCalls - before).toBe(1)
})

test('a second session start asks for a second timer', async ($, on) => {
  let every = 0
  on('command.register', () => ({ value: { command: 'devfsd-progress' } }))
  on('clock.every', () => { every += 1; return { value: undefined } })
  on('clock.now', () => ({ value: 1_000 }))
  on('fs.read', () => { throw new Error('ENOENT') })
  on('fs.exists', () => ({ value: false }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/other', ...START })
  await $.session.start({ cwd: '/other', ...START })
  expect(every).toBe(2)
})

test('a failing clock at session start still opens the pane of a governed repo', async ($, on) => {
  const opens: string[] = []
  on('command.register', () => ({ value: { command: 'devfsd-progress' } }))
  on('clock.every', () => ({ value: undefined }))
  on('clock.now', () => { throw new Error('boom') })
  on('fs.read', () => { throw new Error('ENOENT') })
  on('fs.exists', (_, e) => ({ value: e.path === '/repo/.specops' }))
  on('ui.open', (_, e) => { opens.push(e.id); return { value: { isPlaced: true } } })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/repo', ...START })
  expect(opens).toEqual(['devfsd-console'])
})

const PROG = [
  '# p', '<!-- active-fid: 20261104-b -->', '',
  '## 20261104-b · 설명', '',
  '- 2026-11-04 10:05 /implement 진행 (T1)',
  '- 2026-11-04 10:04 /tasks 완료 (tasks.md)',
  '- 2026-11-04 10:03 /plan SKIP (lite)',
  '- 2026-11-04 10:02 /clarify SKIP (lite)',
  '- 2026-11-04 10:01 /specify 완료 (spec.md)',
  '- 2026-11-04 10:00 /analyze 완료 (x)',
  '', '## 20261104-a · 옛', '', '- 2026-11-03 09:00 /lifecycle DONE (PR #1)', '',
].join('\n')

test('activeFid prefers the marker, then the first FID-shaped heading', () => {
  expect(activeFid(PROG)).toBe('20261104-b')
  expect(activeFid('# p\n\n## 활용 방법\n\n## 20261104-c · x\n')).toBe('20261104-c')
  expect(activeFid('# p\n\n## 활용 방법\n')).toBe(undefined)
})

test('activeFid marker beats an earlier heading and bad shapes fall back', () => {
  expect(activeFid('<!-- active-fid: 20261104-b -->\n## 20261104-a · x\n## 20261104-b · y\n')).toBe('20261104-b')
  expect(activeFid('<!-- active-fid: 활용방법 -->\n## 20261104-a\n')).toBe('20261104-a')
  expect(activeFid('## 20261104-A\n')).toBe(undefined)
  expect(activeFid('## 2026110-a\n')).toBe(undefined)
  expect(activeFid('### 20261104-a\n')).toBe(undefined)
})

test('stagesOf reads the newest record of each stage', () => {
  const line = stagesOf(PROG, '20261104-b').map(s => s.label + s.mark).join(' ')
  expect(line).toBe('분석✓ 명세✓ 명확화– 설계– 분해✓ 구현● 검증○ 보안○ 통합○ 성능○ 데모○ PR○')
  const noAnalyze = PROG.replace('- 2026-11-04 10:00 /analyze 완료 (x)\n', '')
  expect(stagesOf(noAnalyze, '20261104-b')[0].label).toBe('명세')
  const failed = PROG.replace('/implement 진행 (T1)', '/verify FAIL (x)\n- 2026-11-04 10:05 /verify PASS (old)')
  expect(stagesOf(failed, '20261104-b').find(s => s.key === 'verify')?.mark).toBe('✗')
  const memo = PROG.replace('/tasks 완료 (tasks.md)', '/tasks 진행 (SKIP 아님)')
  expect(stagesOf(memo, '20261104-b').find(s => s.key === 'tasks')?.mark).toBe('●')
})

test('stagesOf maps all 12 stage commands and symbol words', () => {
  const full = [
    '## 20261104-f', '',
    '- d t /analyze 완료', '- d t /specify DONE', '- d t /clarify SKIP', '- d t /plan PASS',
    '- d t /tasks FAIL', '- d t /implement BLOCK', '- d t /verify PARTIAL', '- d t /security-review DONE',
    '- d t /integration-test SKIP', '- d t /performance-test 진행', '- d t /lifecycle DONE', '',
  ].join('\n')
  const line = stagesOf(full, '20261104-f').map(s => s.label + s.mark).join(' ')
  expect(line).toBe('분석✓ 명세✓ 명확화– 설계✓ 분해✗ 구현✗ 검증● 보안✓ 통합– 성능● 데모○ PR✓')
  expect(stagesOf('## 20261104-f\n\n- d t /pr 완료\n', '20261104-f').find(s => s.key === 'pr')?.mark).toBe('○')
  const dir = '## 20261104-f\n\n- d t /verify PASS\n- d t /verify FAIL\n'
  expect(stagesOf(dir, '20261104-f').find(s => s.key === 'verify')?.mark).toBe('✓')
  const memos = '## 20261104-f\n\n- d t /implement 진행 (FAIL 아님 DONE)\n- d t /verify PASS (FAIL 0건)\n'
  const got = stagesOf(memos, '20261104-f')
  expect(got.find(s => s.key === 'implement')?.mark).toBe('●')
  expect(got.find(s => s.key === 'verify')?.mark).toBe('✓')
})

test('isLifecycleDone only when the newest record is /lifecycle DONE', () => {
  expect(isLifecycleDone(PROG, '20261104-a')).toBe(true)
  expect(isLifecycleDone(PROG, '20261104-b')).toBe(false)
  const after = PROG.replace('- 2026-11-03 09:00 /lifecycle DONE (PR #1)', '- 2026-11-03 09:10 /verify PASS (x)\n- 2026-11-03 09:00 /lifecycle DONE (PR #1)')
  expect(isLifecycleDone(after, '20261104-a')).toBe(false)
})

test('verifyWord accepts only a known single word on exit 0', () => {
  expect(verifyWord({ exitCode: 0, stdout: 'STALE\n' })).toBe('검증 STALE')
  expect(verifyWord({ exitCode: 1, stdout: 'STALE\n' })).toBe('검증 ?')
  expect(verifyWord({ exitCode: 0, stdout: '' })).toBe('검증 ?')
  expect(verifyWord({ exitCode: 0, stdout: 'PASS\nPASS\n' })).toBe('검증 ?')
  expect(verifyWord({ exitCode: 0, stdout: 'GREEN\n' })).toBe('검증 ?')
})

test('verifyWord covers all six words with and without newline, and rejects bad input', () => {
  for (const w of ['PASS', 'STALE', 'FAIL', 'PARTIAL', 'NOT_RUN', 'WAIVED']) {
    expect(verifyWord({ exitCode: 0, stdout: w })).toBe(`검증 ${w}`)
    expect(verifyWord({ exitCode: 0, stdout: `${w}\n` })).toBe(`검증 ${w}`)
  }
  for (const bad of ['stale', 'PASS extra', 'NOT_RUN: x', ' ']) {
    expect(verifyWord({ exitCode: 0, stdout: bad })).toBe('검증 ?')
  }
  expect(verifyWord({ exitCode: 124, stdout: 'PASS' })).toBe('검증 ?')
  expect(verifyWord({ exitCode: 1, stdout: 'PASS' })).toBe('검증 ?')
})

// --- T2: 단계·verify 갱신 · 트리거 --------------------------------------------

/** void 로 도는 계산이 끝까지 흐르게 마이크로태스크를 비운다 — 시계·타이머에 기대지 않는다. */
const drain = async () => { for (let i = 0; i < 300; i++) await Promise.resolve() }

const VERIFY_SH = '/scripts/_internal/verification-state.sh'
const STALE_OUT = { exitCode: 0, stdout: 'STALE\n', stderr: '' }
const PROG_C = PROG.replace('active-fid: 20261104-b', 'active-fid: 20261104-c').replace('## 20261104-b ·', '## 20261104-c ·')
const PROG_DONE = '# p\n\n## 20261104-b · x\n\n- 2026-11-04 10:09 /lifecycle DONE (PR #2)\n- 2026-11-04 10:00 /verify PASS (x)\n'

type Run = { argv: string[]; init?: Record<string, unknown> }

/** 관할 repo(`/repo`) 세계: progress 는 `/repo` 에만 있고, process.run 호출을 모두 기록한다. */
const verifyWorld = (on: PaneOn) => {
  const w = {
    progress: PROG,
    dirOk: true,
    readable: true,
    git: { exitCode: 0, stdout: '/repo/.git/worktrees/wt\n', stderr: '' },
    answer: STALE_OUT as typeof STALE_OUT | 'reject',
    gate: undefined as Promise<void> | undefined,
    reply: { result: {}, text: 'ok' } as Record<string, unknown>,
    toolDone: false,
    runs: [] as Run[],
    seen: [] as boolean[],
  }
  on('command.register', () => ({ value: { command: 'devfsd-progress' } }))
  on('clock.every', () => ({ value: undefined }))
  on('clock.now', () => ({ value: 1_000 }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('fs.read', (_, e) => {
    if (w.readable && e.path === '/repo/.specops/session-progress.md') return { value: w.progress }
    throw new Error('ENOENT')
  })
  on('fs.exists', (_, e) => ({ value: e.path === '/repo/.specops' || (e.path.startsWith('/repo/.specops/') && w.dirOk) }))
  on('tool.call', async () => { await drain(); w.toolDone = true; return w.reply as never })
  on('process.run', async (_, e) => {
    const run = e as unknown as Run
    w.runs.push({ argv: [...run.argv], init: run.init })
    if (run.argv[0] === 'git') return { value: w.git }
    w.seen.push(w.toolDone)
    if (w.gate) await w.gate
    if (w.answer === 'reject') throw new Error('spawn failed')

    return { value: w.answer }
  })

  return w
}

type World = ReturnType<typeof verifyWorld>
const bash = (w: World) => w.runs.filter(r => r.argv[0] === 'bash')
const begin = async ($: Pane$, w: World, cwd = '/repo') => {
  await $.session.start({ cwd, ...START })
  await drain()

  return bash(w).length
}
const editCall = (id: string, extra: Record<string, unknown> = {}) =>
  ({ tool: 'Edit', tool_use_id: id, file_path: '/repo/a.ts', old_string: 'a', new_string: 'b', ...extra }) as never
const fgBash = (id: string, extra: Record<string, unknown> = {}) =>
  ({ tool: 'Bash', tool_use_id: id, command: 'ls', ...extra }) as never
const headOf = async ($: Pane$) => (await rowsOf($)).find(row => row.startsWith('devFSD'))

test('an edit in a governed session recomputes verify once, after the tool finished', async ($, on) => {
  const w = verifyWorld(on)
  const base = await begin($, w)
  expect(base).toBe(1)

  const ran = await $.tool.call(editCall('toolu_e1'))
  await drain()
  expect(ran).toEqual(w.reply)
  expect(bash(w).length - base).toBe(1)
  const argv = bash(w)[base]?.argv ?? []
  expect([argv[0], argv[2], argv[3]]).toEqual(['bash', 'current', '20261104-b'])
  expect(argv[1]?.endsWith(VERIFY_SH)).toBe(true)
  expect(w.seen.slice(base)).toEqual([true])
})

test('a verification that never finishes does not hold the tool call', async ($, on) => {
  const w = verifyWorld(on)
  const base = await begin($, w)
  let release: () => void = () => {}
  w.gate = new Promise<void>(resolve => (release = resolve))
  try {
    const ran = await $.tool.call(editCall('toolu_n1'))
    await drain()
    expect(ran).toEqual(w.reply)
    expect(bash(w).length - base).toBe(1)
  } finally {
    release()
  }
  await drain()
})

test('subagent edits do not recompute, the main thread does', async ($, on) => {
  const w = verifyWorld(on)
  const base = await begin($, w)

  await $.tool.call(editCall('toolu_s1', { agentId: 'sub1' }))
  await drain()
  expect(bash(w).length - base).toBe(0)
  await $.tool.call(editCall('toolu_s2'))
  await drain()
  expect(bash(w).length - base).toBe(1)
})

test('overlapping triggers collapse into one extra run that re-reads progress', async ($, on) => {
  const w = verifyWorld(on)
  const base = await begin($, w)
  let release: () => void = () => {}
  w.gate = new Promise<void>(resolve => (release = resolve))
  try {
    await $.tool.call(fgBash('toolu_o1'))
    await drain()
    expect(bash(w).length - base).toBe(1)
    await $.tool.call(fgBash('toolu_o2'))
    await $.tool.call(fgBash('toolu_o3'))
    await drain()
    expect(bash(w).length - base).toBe(1)
    w.progress = PROG_C
  } finally {
    release()
  }
  await drain()
  expect(bash(w).slice(base).map(r => r.argv[3])).toEqual(['20261104-b', '20261104-c'])
})

test('a worktree session runs git for the project folder and verifies with its own GIT_DIR', async ($, on) => {
  const w = verifyWorld(on)
  const wt = '/repo/.claude/worktrees/wt'
  const base = await begin($, w, wt)
  expect(base).toBe(1)

  const git = w.runs.find(r => r.argv[0] === 'git')
  expect(git?.argv).toEqual(['git', '-C', wt, 'rev-parse', '--absolute-git-dir'])
  expect(git?.init).toEqual({ timeoutMs: 10000 })
  expect(bash(w)[0]?.init).toEqual({
    cwd: '/repo',
    env: { GIT_DIR: '/repo/.git/worktrees/wt', GIT_WORK_TREE: wt },
    timeoutMs: 10000,
  })
})

test('a plain repo skips git and passes an empty env', async ($, on) => {
  const w = verifyWorld(on)
  await begin($, w)

  expect(w.runs.filter(r => r.argv[0] === 'git').length).toBe(0)
  expect(bash(w)[0]?.init).toEqual({ cwd: '/repo', env: {}, timeoutMs: 10000 })
})

test('a failing git lookup in a worktree never starts the verifier', async ($, on) => {
  const w = verifyWorld(on)
  w.git = { exitCode: 128, stdout: '', stderr: 'fatal' }
  await begin($, w, '/repo/.claude/worktrees/wt')
  await $.tool.call(editCall('toolu_g1'))
  await drain()

  expect(w.runs.filter(r => r.argv[0] === 'git').length).toBe(2)
  expect(bash(w).length).toBe(0)
})

test('a rejected verifier leaves the call untouched and the next trigger recovers', async ($, on) => {
  const w = verifyWorld(on)
  const base = await begin($, w)

  w.answer = 'reject'
  const ran = await $.tool.call(editCall('toolu_r1'))
  await drain()
  expect(ran).toEqual(w.reply)
  expect(bash(w).length - base).toBe(1)

  w.answer = STALE_OUT
  await $.tool.call(editCall('toolu_r2'))
  await drain()
  expect(bash(w).length - base).toBe(2)
})

test('a finished lifecycle skips the verifier until progress says otherwise', async ($, on) => {
  const w = verifyWorld(on)
  w.progress = PROG_DONE
  const base = await begin($, w)
  expect(base).toBe(0)

  await $.tool.call(editCall('toolu_d1'))
  await drain()
  expect(bash(w).length).toBe(0)

  w.progress = PROG
  await $.tool.call(editCall('toolu_d2'))
  await drain()
  expect(bash(w).length).toBe(1)
})

test('no FID in progress means no verifier call and a bare head line', async ($, on) => {
  const w = verifyWorld(on)
  const base = await begin($, w)
  expect(await headOf($)).toBe('devFSD · 20261104-b')

  w.progress = '# p\n\n## 활용 방법\n'
  await $.tool.call(editCall('toolu_f1'))
  await drain()
  expect(bash(w).length - base).toBe(0)
  expect(await headOf($)).toBe('devFSD')

  w.progress = PROG
  await $.tool.call(editCall('toolu_f2'))
  await drain()
  expect(bash(w).length - base).toBe(1)
  expect(await headOf($)).toBe('devFSD · 20261104-b')
})

test('an unreadable progress file means no verifier call', async ($, on) => {
  const w = verifyWorld(on)
  w.progress = ''
  w.readable = false
  await begin($, w)
  await $.tool.call(editCall('toolu_u1'))
  await drain()

  expect(bash(w).length).toBe(0)
  expect(await headOf($)).toBe('devFSD')
})

test('the FID is re-read on every trigger', async ($, on) => {
  const w = verifyWorld(on)
  const base = await begin($, w)

  await $.tool.call(editCall('toolu_h1'))
  await drain()
  w.progress = PROG_C
  await $.tool.call(editCall('toolu_h2'))
  await drain()

  expect(bash(w).slice(base).map(r => r.argv[3])).toEqual(['20261104-b', '20261104-c'])
  expect(await headOf($)).toBe('devFSD · 20261104-c')
})

test('a marker FID without a section still verifies, a missing FID folder does not', async ($, on) => {
  const w = verifyWorld(on)
  w.progress = '<!-- active-fid: 20261104-z -->\n## 20261104-a · x\n'
  const base = await begin($, w)
  expect(bash(w).map(r => r.argv[3])).toEqual(['20261104-z'])

  w.dirOk = false
  await $.tool.call(editCall('toolu_m1'))
  await drain()
  expect(bash(w).length - base).toBe(0)

  w.dirOk = true
  await $.tool.call(editCall('toolu_m2'))
  await drain()
  expect(bash(w).length - base).toBe(1)
})

test('every state-changing tool recomputes, observation tools and subagents do not', async ($, on) => {
  const w = verifyWorld(on)
  await begin($, w)
  const cases: { label: string; call: Record<string, unknown>; text?: string; want: number }[] = [
    { label: 'Edit', call: { tool: 'Edit', file_path: '/repo/a', old_string: 'a', new_string: 'b' }, want: 1 },
    { label: 'Write', call: { tool: 'Write', file_path: '/repo/a', content: 'x' }, want: 1 },
    { label: 'NotebookEdit', call: { tool: 'NotebookEdit', notebook_path: '/repo/a.ipynb', new_source: 'x' }, want: 1 },
    { label: 'Agent fg', call: { tool: 'Agent', description: 'd', prompt: 'p', subagent_type: 'general-purpose' }, want: 1 },
    { label: 'Agent bg launch', call: { tool: 'Agent', description: 'd', prompt: 'p', subagent_type: 'general-purpose' }, text: 'Async agent launched successfully', want: 0 },
    { label: 'Bash fg', call: { tool: 'Bash', command: 'ls' }, want: 1 },
    { label: 'Bash bg', call: { tool: 'Bash', command: 'sleep 1', description: 'bg', run_in_background: true }, want: 1 },
    { label: 'Skill devfsd', call: { tool: 'Skill', skill: 'devfsd:implementing-ko' }, want: 1 },
    { label: 'Skill other', call: { tool: 'Skill', skill: 'simplify' }, want: 0 },
    { label: 'Read', call: { tool: 'Read', file_path: '/repo/a' }, want: 0 },
    { label: 'Grep', call: { tool: 'Grep', pattern: 'x' }, want: 0 },
    { label: 'Edit in subagent', call: { tool: 'Edit', file_path: '/repo/a', old_string: 'a', new_string: 'b', agentId: 's' }, want: 0 },
    { label: 'Bash in subagent', call: { tool: 'Bash', command: 'ls', agentId: 's' }, want: 0 },
    { label: 'Skill in subagent', call: { tool: 'Skill', skill: 'devfsd:planning-ko', agentId: 's' }, want: 0 },
    { label: 'Agent in subagent', call: { tool: 'Agent', description: 'd', prompt: 'p', agentId: 's' }, want: 0 },
  ]
  const got: [string, number][] = []
  let n = 0
  for (const c of cases) {
    w.reply = { result: {}, text: c.text ?? 'ok' }
    const before = bash(w).length
    n += 1
    await $.tool.call({ tool_use_id: `toolu_x${n}`, ...c.call } as never)
    await drain()
    got.push([c.label, bash(w).length - before])
  }
  expect(got).toEqual(cases.map(c => [c.label, c.want]))
})

test('session start and a background completion notice recompute, other messages do not', async ($, on) => {
  const w = verifyWorld(on)
  const base = await begin($, w)
  expect(base).toBe(1)
  w.reply = { result: {}, text: 'Async agent launched successfully' }
  await $.tool.call(agentCall('toolu_bgn'))
  await drain()
  expect(bash(w).length - base).toBe(0)

  await notify($, 'toolu_bgn', 'completed', { agentId: 'sub1' })
  await drain()
  expect(bash(w).length - base).toBe(0)
  await $.session.append({
    door: 'delivery',
    origin: { kind: 'task-notification' },
    uuid: 'row-plain',
    message: { type: 'user', content: [{ type: 'text', text: 'hello' }] },
  } as never)
  await drain()
  expect(bash(w).length - base).toBe(0)

  await notify($, 'toolu_bgn', 'completed')
  await drain()
  expect(bash(w).length - base).toBe(1)
})

test('every refreshing tool recomputes only after its own call returned', async ($, on) => {
  const w = verifyWorld(on)
  const base = await begin($, w)
  const calls = [
    { tool: 'Write', file_path: '/repo/a', content: 'x' },
    { tool: 'NotebookEdit', notebook_path: '/repo/a.ipynb', new_source: 'x' },
    { tool: 'Bash', command: 'ls' },
    { tool: 'Bash', command: 'sleep 1', description: 'bg', run_in_background: true },
    { tool: 'Agent', description: 'd', prompt: 'p', subagent_type: 'general-purpose' },
    { tool: 'Skill', skill: 'devfsd:implementing-ko' },
  ]
  let n = 0
  for (const c of calls) {
    w.toolDone = false
    n += 1
    await $.tool.call({ tool_use_id: `toolu_q${n}`, ...c } as never)
    await drain()
  }
  expect(bash(w).length - base).toBe(calls.length)
  expect(w.seen.slice(base)).toEqual(calls.map(() => true))
})

const BAR_B = '분석✓ 명세✓ 명확화– 설계– 분해✓ 구현● 검증○ 보안○ 통합○ 성능○ 데모○ PR○'
const BAR_NONE = '명세○ 명확화○ 설계○ 분해○ 구현○ 검증○ 보안○ 통합○ 성능○ 데모○ PR○'
const BAR_DONE = '명세○ 명확화○ 설계○ 분해○ 구현○ 검증✓ 보안○ 통합○ 성능○ 데모○ PR✓'

/** 한 surface 로 마운트해 비지 않은 Text 줄을 trim 해 읽는다. */
const rowsOn = async ($: Pane$, surface: (typeof SURFACES)[number]): Promise<string[]> => {
  const ui = await $.ui.mount({ ...PANE, surface })
  const rows = (await ui.findAll({ type: 'Text' })).map(one => (one.text ?? '').trim()).filter(Boolean)
  await ui.unmount()

  return rows
}
const badgeOn = async ($: Pane$, surface: (typeof SURFACES)[number]) =>
  (await rowsOn($, surface)).find(row => row.startsWith('검증 ') || row === '완료')

test('the pane lists head, stage bar, verify badge, running and recent in that order on both surfaces', async ($, on) => {
  const w = verifyWorld(on)
  await begin($, w)

  for (const surface of SURFACES) {
    expect(await rowsOn($, surface)).toEqual([
      'devFSD · 20261104-b', BAR_B, '검증 STALE', '▶ 실행 중 (0)', '없음', '최근 완료', '없음',
    ])
  }
})

test('every verifier word reaches the badge line on both surfaces', async ($, on) => {
  const w = verifyWorld(on)
  w.answer = { exitCode: 0, stdout: 'NOT_RUN\n', stderr: '' }
  await begin($, w)
  for (const surface of SURFACES) expect(await badgeOn($, surface)).toBe('검증 NOT_RUN')

  w.answer = { exitCode: 0, stdout: 'PASS\n', stderr: '' }
  await $.tool.call(editCall('toolu_w1'))
  await drain()
  for (const surface of SURFACES) expect(await badgeOn($, surface)).toBe('검증 PASS')
})

test('a rejected verifier shows a question mark and the next trigger restores the value', async ($, on) => {
  const w = verifyWorld(on)
  await begin($, w)

  w.answer = 'reject'
  await $.tool.call(editCall('toolu_q1'))
  await drain()
  for (const surface of SURFACES) expect(await badgeOn($, surface)).toBe('검증 ?')

  w.answer = { exitCode: 0, stdout: 'PASS\n', stderr: '' }
  await $.tool.call(editCall('toolu_q2'))
  await drain()
  for (const surface of SURFACES) expect(await badgeOn($, surface)).toBe('검증 PASS')
})

test('a finished lifecycle shows done on the badge line without calling the verifier', async ($, on) => {
  const w = verifyWorld(on)
  w.progress = PROG_DONE
  await begin($, w)

  expect(bash(w).length).toBe(0)
  for (const surface of SURFACES) {
    expect(await rowsOn($, surface)).toEqual([
      'devFSD · 20261104-b', BAR_DONE, '완료', '▶ 실행 중 (0)', '없음', '최근 완료', '없음',
    ])
  }
})

test('a missing FID folder shows a question mark', async ($, on) => {
  const w = verifyWorld(on)
  w.dirOk = false
  await begin($, w)

  expect(bash(w).length).toBe(0)
  for (const surface of SURFACES) expect(await badgeOn($, surface)).toBe('검증 ?')
})

test('without an active FID neither the stage bar nor the badge is drawn', async ($, on) => {
  const w = verifyWorld(on)
  w.progress = '# p\n\n## 활용 방법\n'
  await begin($, w)

  expect(bash(w).length).toBe(0)
  for (const surface of SURFACES) {
    expect(await rowsOn($, surface)).toEqual(['devFSD', '▶ 실행 중 (0)', '없음', '최근 완료', '없음'])
  }
})

test('a marker FID without a section draws an all-open bar with no analysis cell', async ($, on) => {
  const w = verifyWorld(on)
  w.progress = '<!-- active-fid: 20261104-z -->\n## 20261104-a · x\n'
  await begin($, w)

  for (const surface of SURFACES) {
    expect(await rowsOn($, surface)).toEqual([
      'devFSD · 20261104-z', BAR_NONE, '검증 STALE', '▶ 실행 중 (0)', '없음', '최근 완료', '없음',
    ])
  }
})

test('the badge is bold except for done and pass', async ($, on) => {
  const w = verifyWorld(on)
  await begin($, w)
  const boldOf = async (surface: (typeof SURFACES)[number], text: RegExp) => {
    const ui = await $.ui.mount({ ...PANE, surface })
    const node = (await ui.find({ type: 'Text', text })) as unknown as Record<string, any> | undefined
    await ui.unmount()

    return node?.bold ?? node?.props?.bold
  }

  // The head line is always bold: if the kit cannot show that, bold is not observable here.
  if ((await boldOf('terminal', /^devFSD/)) !== true) return

  for (const surface of SURFACES) expect(await boldOf(surface, /^검증 /)).toBe(true)
  w.answer = { exitCode: 0, stdout: 'PASS\n', stderr: '' }
  await $.tool.call(editCall('toolu_b1'))
  await drain()
  for (const surface of SURFACES) expect(await boldOf(surface, /^검증 /)).not.toBe(true)
})

test('devFSD: stagesOf puts 데모 between 성능 and PR, marked by its own /demo row only', () => {
  const prog = [
    '# p', '', '## 20261105-d · 데모', '',
    '- 2026-11-05 11:03 /demo DONE (screens)',
    '- 2026-11-05 11:02 /performance-test SKIP (x)',
    '- 2026-11-05 11:01 /verify PASS (x)', '',
  ].join('\n')
  const labels = stagesOf(prog, '20261105-d').map(s => s.label + s.mark)
  expect(labels.slice(-4)).toEqual(['통합○', '성능–', '데모✓', 'PR○'])
  // /demo 행이 없으면 ○ — 다른 단계 행(/lifecycle DONE 등)이 데모를 채우지 않는다
  const none = prog.replace('- 2026-11-05 11:03 /demo DONE (screens)\n', '')
  expect(stagesOf(none, '20261105-d').find(s => s.key === 'demo')).toEqual({ key: 'demo', label: '데모', mark: '○' })
  expect(stagesOf(none, '20261105-d').find(s => s.key === 'pr')?.mark).toBe('○')
})

test('devFSD: stageOf names the demo skill 데모 (demo-ko)', () => {
  expect(stageOf('devfsd:demo-ko')).toBe('데모 (demo-ko)')
  expect(stageOf('specops-ko:demo-ko')).toBe('데모 (demo-ko)')
  expect(stageOf('demolition-ko')).toBe(undefined) // 접두 일치로 번지지 않는다
})

const outOf = (id: string) => `/private/tmp/claude-501/-p/s1/tasks/${id}.output`
const launched = (id: string) => ({ result: {}, text: `Command running in background with ID: ${id}. Output is being written to: ${outOf(id)}.` })
/** 스캔 호출만 골라낸다 — verifyFor 의 `bash verification-state.sh …` 와 구별. */
const isScan = (argv: string[]) => argv[0] === 'bash' && argv[1] === '-c' && argv[3] === '_'

test('devFSD: each running background job gets its own output path, and an ended job leaves the scan', async ($, on) => {
  const scans: string[][] = []
  const clock = clockWorld(on, (_, e) => launched(String((e as { tool_use_id: string }).tool_use_id)))
  on('process.run', (_, e) => {
    const argv = (e as unknown as { argv: string[] }).argv
    if (isScan(argv)) scans.push(argv.slice(4))
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })
  await startedClock($, clock)
  await $.tool.call(bgBash('b1'))
  await $.tool.call(bgBash('b2'))
  await clock.advance(5_000)
  expect(scans.at(-1)).toEqual([outOf('b1'), outOf('b2')])
  await notify($, 'b1', 'completed')
  await clock.advance(5_000)
  expect(scans.at(-1)).toEqual([outOf('b2')])
})

test('devFSD: no output path in the result means no scan', async ($, on) => {
  const clock = clockWorld(on, () => ({ result: {}, text: 'Command running in background' }))
  let scans = 0
  on('process.run', (_, e) => {
    if (isScan((e as unknown as { argv: string[] }).argv)) scans += 1
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })
  await startedClock($, clock)
  await $.tool.call(bgBash('b3'))
  await clock.advance(10_000)
  expect(scans).toBe(0)
})

test('devFSD: a throwing scan is retried on the next tick and the job stays listed', async ($, on) => {
  const clock = clockWorld(on, (_, e) => launched(String((e as { tool_use_id: string }).tool_use_id)))
  let calls = 0
  on('process.run', (_, e) => {
    if (!isScan((e as unknown as { argv: string[] }).argv)) return { value: { exitCode: 0, stdout: '', stderr: '' } }
    calls += 1
    if (calls === 1) throw new Error('spawn failed')
    return { value: { exitCode: 0, stdout: '5\n', stderr: '' } }
  })
  await startedClock($, clock)
  await $.tool.call(bgBash('b1'))
  await clock.advance(5_000)
  expect(calls).toBeGreaterThanOrEqual(1) // 스캔이 시도됐다
  expect((await rowsOf($)).find(row => row.startsWith('▶ 실행 중'))).toBe('▶ 실행 중 (1)')
  await clock.advance(5_000)
  expect(calls).toBeGreaterThanOrEqual(2) // 던진 뒤에도 시계가 살아 있다
})
