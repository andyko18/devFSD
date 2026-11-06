// devFSD 원작 — 현재 브랜치 PR 의 CI 잡을 읽어 관제판에 합산 표시한다. 관찰만 하고 던지지 않는다.
import type { EngineInterface } from 'claude-code'

import type { CiCheck } from '../types'

const GH_TIMEOUT_MS = 15_000
const BUCKETS: readonly string[] = ['pass', 'pending', 'fail', 'skipping', 'cancel']

/** `gh pr checks --json name,bucket` 출력 → 잡 목록. 목록이 아니면 undefined. */
export function parseChecks(stdout: string): CiCheck[] | undefined {
  let raw: unknown
  try {
    raw = JSON.parse(stdout)
  } catch {
    return undefined
  }
  if (!Array.isArray(raw)) return undefined

  return raw.flatMap((one): CiCheck[] => {
    const o = one as { name?: unknown; bucket?: unknown }

    return typeof o?.name === 'string' && typeof o.bucket === 'string' && BUCKETS.includes(o.bucket)
      ? [{ name: o.name, bucket: o.bucket as CiCheck['bucket'] }]
      : []
  })
}

/** 진행 중(pending) 잡 수 — 백그라운드 작업 수에 합산한다. */
export function ciPending(checks: readonly CiCheck[] | undefined): number {
  return (checks ?? []).filter(c => c.bucket === 'pending').length
}

/** `CI 3/4 통과` 또는 `CI ✗ run-all · 1/2 통과`. 셀 잡이 없으면 빈 문자열. */
export function ciLine(checks: readonly CiCheck[] | undefined): string {
  const counted = (checks ?? []).filter(c => c.bucket !== 'skipping' && c.bucket !== 'cancel')
  if (counted.length === 0) return ''
  const pass = counted.filter(c => c.bucket === 'pass').length
  const failed = counted.filter(c => c.bucket === 'fail').map(c => c.name)

  return failed.length > 0 ? `CI ✗ ${failed.join(', ')} · ${pass}/${counted.length} 통과` : `CI ${pass}/${counted.length} 통과`
}

/** 읽기 전용 gh 조회. PR 없음·gh 없음·권한 없음·시간 초과는 모두 undefined. */
export async function pollCi($: EngineInterface, cwd: string): Promise<CiCheck[] | undefined> {
  try {
    const r = await $.process.run(['gh', 'pr', 'checks', '--json', 'name,bucket'], { cwd, timeoutMs: GH_TIMEOUT_MS })

    // gh 는 진행 중 잡이 있으면 8 로 끝날 수 있다 — 목록이 stdout 에 있으니 0·8 만 읽는다.
    return r.exitCode === 0 || r.exitCode === 8 ? parseChecks(r.stdout) : undefined
  } catch {
    return undefined
  }
}
