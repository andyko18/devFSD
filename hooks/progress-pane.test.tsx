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
  expect(calls).toEqual(['devfsd-progress'])
})

test('a worktree of a governed repo opens the pane', async ($, on) => {
  const calls = opened(on)
  on('fs.exists', (_, e) => ({ value: e.path === '/repo/.specops' }))
  await $.session.start({ cwd: '/repo/.claude/worktrees/wt', ...START })
  expect(calls).toEqual(['devfsd-progress'])
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
  expect(calls).toEqual(['devfsd-progress'])
})

test('a .worktrees worktree opens the pane, a look-alike folder does not', async ($, on) => {
  const calls = opened(on)
  on('fs.exists', (_, e) => ({ value: e.path === '/repo/.specops' }))
  await $.session.start({ cwd: '/repo/.worktrees/20261030-x', ...START })
  expect(calls).toEqual(['devfsd-progress'])
  await $.session.start({ cwd: '/repo/.worktrees-old/x', ...START })
  expect(calls).toEqual(['devfsd-progress'])
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
  expect(done[0]).toBe('  ✓ 작업 a6 · 1s')
  expect(done[4]).toBe('  ✓ 작업 a2 · 1s')
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
  expect(opens).toEqual(['devfsd-progress'])
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
  expect(line).toBe('분석✓ 명세✓ 명확화– 설계– 분해✓ 구현● 검증○ 보안○ 통합○ 성능○ PR○')
  const noAnalyze = PROG.replace('- 2026-11-04 10:00 /analyze 완료 (x)\n', '')
  expect(stagesOf(noAnalyze, '20261104-b')[0].label).toBe('명세')
  const failed = PROG.replace('/implement 진행 (T1)', '/verify FAIL (x)\n- 2026-11-04 10:05 /verify PASS (old)')
  expect(stagesOf(failed, '20261104-b').find(s => s.key === 'verify')?.mark).toBe('✗')
  const memo = PROG.replace('/tasks 완료 (tasks.md)', '/tasks 진행 (SKIP 아님)')
  expect(stagesOf(memo, '20261104-b').find(s => s.key === 'tasks')?.mark).toBe('●')
})

test('stagesOf maps all 11 stage commands and symbol words', () => {
  const full = [
    '## 20261104-f', '',
    '- d t /analyze 완료', '- d t /specify DONE', '- d t /clarify SKIP', '- d t /plan PASS',
    '- d t /tasks FAIL', '- d t /implement BLOCK', '- d t /verify PARTIAL', '- d t /security-review DONE',
    '- d t /integration-test SKIP', '- d t /performance-test 진행', '- d t /lifecycle DONE', '',
  ].join('\n')
  const line = stagesOf(full, '20261104-f').map(s => s.label + s.mark).join(' ')
  expect(line).toBe('분석✓ 명세✓ 명확화– 설계✓ 분해✗ 구현✗ 검증● 보안✓ 통합– 성능● PR✓')
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
