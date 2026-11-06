import { expect, test } from 'claude-code/testing'

import { ciLine, ciPending, parseChecks, pollCi } from './ci-watch'

const OUT = JSON.stringify([
  { name: 'run-all', state: 'SUCCESS', bucket: 'pass' },
  { name: 'mac', state: 'IN_PROGRESS', bucket: 'pending' },
  { name: 'lint', state: 'FAILURE', bucket: 'fail' },
  { name: 'doc', state: 'SKIPPED', bucket: 'skipping' },
])

test('AC-1 parseChecks keeps name and bucket, and rejects what is not a check list', () => {
  expect(parseChecks(OUT)).toEqual([
    { name: 'run-all', bucket: 'pass' },
    { name: 'mac', bucket: 'pending' },
    { name: 'lint', bucket: 'fail' },
    { name: 'doc', bucket: 'skipping' },
  ])
  expect(parseChecks('not json')).toBe(undefined)
  expect(parseChecks('{"a":1}')).toBe(undefined)
  expect(parseChecks('[]')).toEqual([])
  expect(parseChecks('[{"name":3}]')).toEqual([])
})

test('AC-2 ciLine says passed/total, failed names; empty for no checks', () => {
  expect(ciLine([{ name: 'a', bucket: 'pass' }, { name: 'b', bucket: 'pass' }, { name: 'c', bucket: 'pass' }, { name: 'd', bucket: 'pending' }])).toBe('CI 3/4 통과')
  expect(ciLine([{ name: 'run-all', bucket: 'fail' }, { name: 'x', bucket: 'pass' }])).toBe('CI ✗ run-all · 1/2 통과')
  expect(ciLine([{ name: 'a', bucket: 'fail' }, { name: 'b', bucket: 'fail' }])).toBe('CI ✗ a, b · 0/2 통과')
  expect(ciLine([{ name: 'a', bucket: 'skipping' }])).toBe('')
  expect(ciLine([])).toBe('')
  expect(ciLine(undefined)).toBe('')
})

test('ciPending counts only pending checks', () => {
  expect(ciPending(parseChecks(OUT))).toBe(1)
  expect(ciPending(undefined)).toBe(0)
})

const run = (result: () => unknown) => ({ process: { run: async () => result() } }) as never

test('AC-3 pollCi returns the checks, and undefined on every failure', async () => {
  const ok = { exitCode: 0, stdout: OUT, stderr: '' }
  expect((await pollCi(run(() => ok), '/repo'))?.length).toBe(4)
  expect(await pollCi(run(() => ({ ...ok, exitCode: 1 })), '/repo')).toBe(undefined)
  expect((await pollCi(run(() => ({ ...ok, exitCode: 8 })), '/repo'))?.length).toBe(4)
  expect(await pollCi(run(() => ({ ...ok, stdout: 'x' })), '/repo')).toBe(undefined)
  expect(await pollCi(run(() => { throw new Error('spawn') }), '/repo')).toBe(undefined)
})

test('pollCi asks gh read-only in the given folder with a timeout', async () => {
  let seen: { argv: string[]; init: Record<string, unknown> } | undefined
  const $ = { process: { run: async (argv: string[], init: Record<string, unknown>) => { seen = { argv, init }; return { exitCode: 0, stdout: '[]', stderr: '' } } } } as never
  await pollCi($, '/repo')
  expect(seen?.argv).toEqual(['gh', 'pr', 'checks', '--json', 'name,bucket'])
  expect(seen?.init.cwd).toBe('/repo')
  expect(typeof seen?.init.timeoutMs).toBe('number')
})
