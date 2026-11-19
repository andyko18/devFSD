// e2e-support.mjs — 실제 브라우저 시나리오의 공용 도구 (devFSD 템플릿 · 하류의 e2e 폴더에 복사해 쓴다)
//
// 시나리오 파일 규약 (scripts/_internal/e2e-run.sh · e2e-coverage.sh 가 읽는다):
//   - 이름은 `*.e2e.mjs`, 첫머리에 `// FID: <FID>` 한 줄
//   - 테스트 이름에 `@AC-<id>` 태그 — 이 태그로 수용 기준과 대조한다
//   - 러너는 Node 내장 `node:test` + `node:assert/strict`
// 지키는 것:
//   - 단언은 관측값으로 한다(보이는 글자 · role · 포커스된 요소 · URL · 보낸 요청의 메서드·경로·헤더)
//   - 고정 대기(sleep · waitForTimeout) 금지 — locator 자동 대기 · waitFor · waitForResponse 로 기다린다. 재시도 0
//   - 판정할 수 없는 조건은 지우지 말고 `test(이름, { todo: '<사유>' }, …)` 로 남긴다 — 숫자로 드러난다
// 알아 둘 것 (20261119 시범 실측):
//   - dev 서버는 React StrictMode 로 effect 가 두 번 돌고 HMR 웹소켓이 bfcache 를 막는다.
//     "정확히 1회"·뒤로 가기 복귀 같은 조건은 운영 빌드(build + preview)로 띄워 본다.
//   - 응답을 붙잡아 두면 내비게이션 완료 대기에 걸린다 — 이동 직후 상태는 `route.abort('aborted')` 로 본다.
//   - 시간 경계(300ms 등)는 `page.clock` 으로 시계를 멈춰 판정한다.
import { spawn } from 'node:child_process'
import { createRequire } from 'node:module'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))

/** Playwright 를 찾는다 — 하류 node_modules(playwright · playwright-core) → devFSD 공용 캐시. 없으면 설치 안내와 함께 던진다. */
export function loadPlaywright() {
  const harness = process.env.DEVFSD_UI_HARNESS_DIR ?? join(homedir(), '.cache/devfsd/ui-harness')
  for (const base of [HERE, process.cwd(), harness]) {
    const req = createRequire(join(base, 'package.json'))
    for (const name of ['playwright', 'playwright-core']) {
      try {
        return req(name)
      } catch {
        // 다음 후보
      }
    }
  }
  throw new Error(`Playwright 를 찾지 못했다 — 한 번 설치: npm install --prefix ${harness} playwright-core`)
}

/** 시스템 Chrome 을 먼저 쓰고, 없으면 Playwright 의 chromium. */
export async function launchBrowser() {
  const { chromium } = loadPlaywright()
  try {
    return await chromium.launch({ channel: 'chrome', headless: true })
  } catch {
    return chromium.launch({ headless: true })
  }
}

/**
 * 서버를 자식 프로세스로 띄우고 url 이 응답할 때까지 기다린다. 끝나면 반드시 stop() 을 부른다(프로세스 그룹째 끈다).
 * @param {{ cmd: string, args?: string[], cwd?: string, url: string, timeoutMs?: number }} o
 */
export async function startServer({ cmd, args = [], cwd = process.cwd(), url, timeoutMs = 60_000 }) {
  const child = spawn(cmd, args, { cwd, detached: true, stdio: ['ignore', 'pipe', 'pipe'] })
  let log = ''
  child.stdout.on('data', d => (log += d))
  child.stderr.on('data', d => (log += d))
  let exited = false
  child.on('exit', () => (exited = true))
  const deadline = Date.now() + timeoutMs
  for (;;) {
    if (exited) throw new Error(`서버가 먼저 종료됐다\n${log}`)
    try {
      if ((await fetch(url)).ok) break
    } catch {
      // 아직 뜨는 중
    }
    if (Date.now() > deadline) throw new Error(`서버 기동 시간 초과(${timeoutMs}ms)\n${log}`)
    await new Promise(r => setImmediate(r))
  }
  return {
    stop: () =>
      new Promise(resolve => {
        if (exited) return resolve()
        child.on('exit', () => resolve())
        try {
          process.kill(-child.pid, 'SIGTERM')
        } catch {
          resolve()
        }
      }),
  }
}

/** JSON 응답 — `page.route(…, r => r.fulfill(json(200, {...})))` */
export const json = (status, body, headers = {}) => ({
  status,
  headers: { 'content-type': 'application/json', ...headers },
  body: JSON.stringify(body),
})

/**
 * 선언하지 않은 백엔드 요청을 599 로 막는다 — 가로채지 않은 요청이 조용히 프록시로 새지 않게.
 * 이 뒤에 등록한 `page.route` 가 먼저 맞는다(Playwright 는 나중에 등록한 경로를 먼저 본다).
 */
export async function blockUndeclared(page, pattern = '**/api/**') {
  await page.route(pattern, r => r.fulfill({ status: 599, body: `e2e: 선언하지 않은 요청 ${r.request().method()} ${r.request().url()}` }))
}

/** 조건이 참이 될 때까지 폴링한다(고정 대기 아님). 시간 안에 안 되면 마지막 값을 실어 던진다. */
export async function until(read, ok, { timeoutMs = 5_000, what = '조건' } = {}) {
  const deadline = Date.now() + timeoutMs
  let last
  for (;;) {
    last = await read()
    if (ok(last)) return last
    if (Date.now() > deadline) throw new Error(`${what} 을 기다리다 시간 초과 — 마지막 값: ${JSON.stringify(last)}`)
    await new Promise(r => setImmediate(r))
  }
}
