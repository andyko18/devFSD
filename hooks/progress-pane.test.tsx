import { expect, test } from 'claude-code/testing'

import { elapsed, fidOf, notificationOf, projectRoot, stageOf } from './progress-pane'

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
