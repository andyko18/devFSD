#!/usr/bin/env node
// ui-probe.cjs — 웹 화면을 실제 브라우저로 여러 폭에서 열어 찍고 기계 판정한다 (20261109-ui-harness)
// Usage: node ui-probe.cjs --out <폴더> [--widths 375,768,1280] <URL>...
//        [--memory <파일> [--start-cmd <명령>]] [--storage-state <파일>] [--mock <html>]... [--expect "<4xx> <메서드> <경로>"]... [--a11y-baseline <파일> [--a11y-baseline-update]]
//   URL 은 이미 떠 있는 화면(http://localhost:3000/tracked) 또는 file:// 경로. dev 서버는 띄우지 않는다.
// 출력 (stdout):
//   UI-PROBE: PASS|FAIL (<N>화면·<M>폭 · 넘침 <a> · 콘솔 오류 <b> · 접근성 심각 <c> | 접근성 SKIP(사유))
//   UI-PROBE: SKIP (NO_TOOL|NO_BROWSER — 사유)        — 판정하지 못함. PASS 로 위장하지 않는다
//   UI-PROBE: SKIP (NO_ENV — 사유)                     — 로그인 상태 파일을 찾지·읽지 못했거나 모양이 맞지 않는다
//   그 아래 문제마다 `  - <화면>@<폭> <종류>: <내용>` 한 줄, 그리고 `  png: <경로>` 줄들
//   접근성 위반 줄 아래에는 요소마다 `      · <선택자>[ — 글자 / 배경 <색> / <색> = <비율> (기준 <비율>)]` (5곳까지 · 넘으면 `외 N곳`)
//   배치 계측(경고 — 판정에 들어가지 않는다): `  - <화면>@<폭> 배치 경고 L-CLIP-X|L-OVERLAP|L-WRAP-CHIP|L-SCROLL-X|L-FIXED-COVER(<이름>): <설명>` · 못 잰 화면·폭은 `배치 계측 못 함: <사유>`
//   요청 실패(경고 — 판정에 들어가지 않는다): `  - <화면>@<폭> 요청 실패 경고: <상태|사유> <메서드> <주소>` — 4xx·5xx 응답과 연결 실패.
//     주소는 쿼리·해시·userinfo 를 뺀다(경로는 남는다). 화면·폭마다 10줄까지(넘으면 `외 N건`). 있을 때만 요약 끝에 ` · 요청 실패 <N>` 이 붙는다.
//   규칙 정의: node ui-probe.cjs --rules  (ui-probe-layout.cjs 가 유일한 곳)
//   <폴더>/ui-probe.json · <폴더>/<화면>@<폭>.png
// rc: 0 PASS · 1 FAIL · 3 SKIP · 2 인자 오류
//
// 왜: 화면 FID 의 67% 가 브라우저를 한 번도 돌리지 않고 통합 테스트 PASS 였고(하류 실측 6/9), 화면 이미지가 한 장도
//   남지 않았으며(0/35), 반응형·접근성 실행 검증이 0 이었다. 하류 저장소에 의존성을 추가하지 않고 돌아야 한다.
// Playwright 찾는 순서: DEVFSD_UI_HARNESS_DIR(주면 그것만) → 현재 폴더와 그 아래 web/·app/·frontend/ 의 node_modules
//   → ~/.cache/devfsd/ui-harness (한 번 설치: npm install --prefix ~/.cache/devfsd/ui-harness playwright-core@1.49.1 axe-core@4.10.2)
// 브라우저: 시스템 Chrome(channel chrome) → Playwright 기본 chromium. axe-core 는 같은 곳에서 찾고 없으면 접근성만 SKIP.
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { createRequire } = require('module');
const { pathToFileURL } = require('url');
const state = require('./ui-probe-state.cjs');
const layout = require('./ui-probe-layout.cjs');

const USAGE = 'usage: node ui-probe.cjs --out <폴더> [--widths 375,768,1280] [--memory <파일> [--start-cmd <명령>]] [--storage-state <파일>] [--mock <html>]... [--expect "<4xx> <메서드> <경로>"]... [--a11y-baseline <파일> [--a11y-baseline-update]] <URL>...';

const WARN_IMPACTS = ['critical', 'serious'];
const A11Y_DETAIL_MAX = 5;   // 위반 줄 아래에 적는 요소 수 — 나머지는 '외 N곳' (전체는 ui-probe.json)
// 위반 줄 아래 요소 상세. detail 이 없는 결과(예전 기록·상세를 못 받은 실행)는 줄을 내지 않는다
function a11yDetailLines(v) {
  const d = Array.isArray(v.detail) ? v.detail : [];
  if (!d.length) return [];
  const lines = d.slice(0, A11Y_DETAIL_MAX).map((x) => `      · ${x.t}${x.c ? ` — 글자 / 배경 ${x.c}` : ''}`);
  const rest = Math.max(Number(v.nodes) || 0, d.length) - Math.min(d.length, A11Y_DETAIL_MAX);
  if (rest > 0) lines.push(`      · 외 ${rest}곳`);
  return lines;
}
const AXE_TAGS = ['wcag2a', 'wcag2aa', 'wcag21aa'];
const REQ_FAIL_FROM = 400;            // 이 상태 코드부터 실패한 요청으로 센다
const REQ_LINES_MAX = 10;             // 화면·폭마다 출력하는 요청 실패 줄 상한
const REQ_ABORTED = 'net::ERR_ABORTED';   // 화면 이동이 끊은 요청 — 실패가 아니다
// 예상한 응답 선언 (`--expect "<상태> <메서드> <경로>"` · 화면 기록의 expect) — 계약에 적힌 4xx 응답(로그인 화면이 로그인 여부를 보려고
//   부르는 /me 의 401 등)을 크로미움이 콘솔 오류로 남겨 점검이 FAIL 하던 것을 선언으로 뺀다. 좁게만 받는다: 4xx 상태 하나 · 메서드 하나 ·
//   정확한 경로 하나(와일드카드·쿼리 없음). 5xx 와 앱이 낸 콘솔 오류는 선언할 수 없다. 처리한 것과 쓰이지 않은 선언은 출력에 남긴다.
//   점검하는 화면과 **같은 origin** 의 응답만 맞춘다(같은 경로를 가진 다른 서버의 4xx 까지 지우지 않는다). 쿼리는 보지 않는다 — 같은 경로면 맞는다.
const EXPECT_RE = state.EXPECT_RE;
const parseExpect = (e) => { const m = EXPECT_RE.exec(e); return { raw: e, status: m[1], method: m[2], path: m[3] }; };
const pathOf = (u) => { try { return new URL(String(u)).pathname; } catch (_) { return ''; } };
const originOf = (u) => { try { return new URL(String(u)).origin; } catch (_) { return ''; } };

function parseArgs(argv) {
  const a = { out: '', widths: [375, 768, 1280], urls: [], memory: '', startCmd: '', storageState: '', mocks: [], expects: [], baseline: '', baselineUpdate: false, rules: false, missing: [] };
  let i = 0;
  const next = (k) => { if (i + 1 >= argv.length || argv[i + 1].startsWith('--')) { a.missing.push(k); return ''; } i += 1; return argv[i]; };
  for (; i < argv.length; i++) {
    const k = argv[i];
    if (k === '--out') a.out = next(k);
    else if (k === '--widths') a.widths = next(k).split(',').map(Number).filter((n) => n > 0);
    else if (k === '--memory') a.memory = next(k);
    else if (k === '--start-cmd') a.startCmd = next(k);
    else if (k === '--storage-state') a.storageState = next(k);
    else if (k === '--mock') a.mocks.push(next(k));
    else if (k === '--expect') a.expects.push(next(k));
    else if (k === '--a11y-baseline') a.baseline = next(k);
    else if (k === '--a11y-baseline-update') a.baselineUpdate = true;
    else if (k === '--rules') a.rules = true;
    else a.urls.push(k);
  }
  return a;
}

function fail2(msg) { process.stderr.write(`${msg}\n`); process.exit(2); }

function firstDup(names) {
  const seen = new Set();
  for (const n of names) { if (seen.has(n)) return n; seen.add(n); }
  return '';
}

function candidates() {
  if (process.env.DEVFSD_UI_HARNESS_DIR) return [process.env.DEVFSD_UI_HARNESS_DIR];
  const cwd = process.cwd();
  return [cwd, path.join(cwd, 'web'), path.join(cwd, 'app'), path.join(cwd, 'frontend'),
    path.join(os.homedir(), '.cache', 'devfsd', 'ui-harness')];
}

function resolveFrom(names) {
  for (const dir of candidates()) {
    const req = createRequire(path.join(dir, 'package.json'));
    for (const n of names) {
      try { return { mod: req(n), file: req.resolve(n), dir }; } catch (_) { /* 다음 후보 */ }
    }
  }
  return null;
}

// Playwright storageState 모양: 객체 · cookies 가 있으면 name·value 문자열을 가진 객체 배열 · origins 가 있으면 배열. {} 는 정상
function storageStateShapeOk(v) {
  const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x);
  if (!isObj(v)) return false;
  if ('cookies' in v && !(Array.isArray(v.cookies) && v.cookies.every((c) => isObj(c) && typeof c.name === 'string' && typeof c.value === 'string'))) return false;
  if ('origins' in v && !Array.isArray(v.origins)) return false;
  return true;
}

function slugOf(u) {
  try {
    const p = new URL(u);
    const base = p.protocol === 'file:' ? path.basename(p.pathname).replace(/\.html?$/, '') : (p.pathname.replace(/^\/+|\/+$/g, '') || 'home');
    return base.replace(/[^A-Za-z0-9가-힣._-]+/g, '-').slice(0, 60) || 'page';
  } catch (_) { return 'page'; }
}

async function launch(chromium) {
  try { return await chromium.launch({ channel: 'chrome', headless: true }); } catch (_) { /* 시스템 Chrome 없음 */ }
  return chromium.launch({ headless: true });
}

async function probeOne(browser, url, width, out, axeFile, doAxe, ssFile, expects) {
  const ctx = await browser.newContext({ viewport: { width, height: 900 }, ...(ssFile ? { storageState: ssFile } : {}) });
  const page = await ctx.newPage();
  const consoleErrors = [];
  const expected = [];   // 선언에 맞아 실패로 세지 않은 응답 — 같은 것은 한 번만 적는다
  // 콘솔 줄에는 메서드가 없다 — 그래서 선언에 맞은 **응답**을 (상태·경로)별로 세어 두고, 그 건수만큼만 콘솔 줄을 뺀다.
  //   세지 않으면 "401 GET /me" 선언이 POST /me 의 401 콘솔 오류까지 지운다. 응답과 콘솔 줄의 도착 순서는 정해져 있지 않아 끝에서 맞춘다(settle).
  const pageOrigin = originOf(url);
  const hits = new Map();          // `${status} ${path}` → 선언에 맞은 응답 수
  const pending = [];              // 요청 실패 꼴의 콘솔 줄 — 끝에서 판정
  const noteExpected = (e, u) => {
    const k = `${e.status} ${e.method} ${state.requestLabel(u)}`; if (!expected.includes(k)) expected.push(k); e.used = true;
    const h = `${e.status} ${pathOf(u)}`; hits.set(h, (hits.get(h) || 0) + 1);
  };
  page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const text = m.text();
    // 브라우저가 실패한 요청에 스스로 남기는 줄만 선언과 맞춘다 — 앱이 낸 오류(TypeError 등)는 주소가 같아도 그대로 센다
    const st = (/^Failed to load resource.*status of (\d{3})/.exec(text) || [])[1];
    const loc = st && typeof m.location === 'function' ? m.location() : null;
    if (st && loc && loc.url && originOf(loc.url) === pageOrigin) pending.push({ text, key: `${st} ${pathOf(loc.url)}` });
    else consoleErrors.push(text.slice(0, 200));
  });
  const settle = () => {
    for (const c of pending) { const n = hits.get(c.key) || 0; if (n > 0) hits.set(c.key, n - 1); else consoleErrors.push(c.text.slice(0, 200)); }
    pending.length = 0;
  };
  page.on('pageerror', (e) => consoleErrors.push(String(e.message || e).slice(0, 200)));
  // 실패한 요청 — 콘솔 오류 문구에는 어느 요청인지 없다. 같은 요청(상태·메서드·주소)은 한 번만 적는다
  const failedRequests = [];
  const noteReq = (what, method, u) => { const k = `${what} ${method} ${state.requestLabel(u)}`; if (!failedRequests.includes(k)) failedRequests.push(k); };
  page.on('response', (res) => {
    const st = res.status(); if (st < REQ_FAIL_FROM) return;
    const method = res.request().method(); const p = pathOf(res.url());
    const e = originOf(res.url()) === pageOrigin && expects.find((x) => x.status === String(st) && x.method === method && x.path === p);
    if (e) noteExpected(e, res.url()); else noteReq(String(st), method, res.url());
  });
  page.on('requestfailed', (req) => { const f = req.failure(); const why = (f && f.errorText) || 'failed'; if (why !== REQ_ABORTED) noteReq(why, req.method(), req.url()); });
  const r = { url, width, png: '', overflow: false, consoleErrors, failedRequests, expected, a11y: null, loadError: '', layout: null };
  try {
    await page.goto(url, { waitUntil: 'networkidle', timeout: 20000 }).catch(() => page.goto(url, { waitUntil: 'load', timeout: 20000 }));
  } catch (e) { r.loadError = String(e.message || e).slice(0, 200); r.layout = layout.unmeasured('열기 실패'); await ctx.close(); settle(); return r; }
  r.overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  r.png = path.join(out, `${slugOf(url)}@${width}.png`);
  await page.screenshot({ path: r.png, fullPage: true });
  if (doAxe && axeFile) {
    await page.addScriptTag({ path: axeFile });
    r.a11y = await page.evaluate(async (tags) => {
      // eslint-disable-next-line no-undef
      const res = await axe.run(document, { runOnly: { type: 'tag', values: tags } });
      // detail: 어느 요소인지(선택자)와, 대비 위반이면 색 쌍 — 건수만으로는 고칠 곳을 찾지 못한다. 화면당 규칙마다 앞 20곳까지만 싣는다
      const one = (n) => { const d = (n.any || []).map((c) => c.data).find((x) => x && x.fgColor) || null;
        return { t: String((n.target || []).join(' ')).slice(0, 120), c: d ? `${d.fgColor} / ${d.bgColor} = ${d.contrastRatio} (기준 ${d.expectedContrastRatio})` : '' }; };
      return res.violations.map((v) => ({ id: v.id, impact: v.impact, nodes: v.nodes.length, help: v.help, detail: v.nodes.slice(0, 20).map(one) }));
    }, AXE_TAGS);
  }
  r.layout = await layout.run(page);   // 화면 상태(스크롤)를 건드릴 수 있어 판정 입력을 다 모은 뒤 마지막에 잰다
  await ctx.close();
  settle();   // 닫은 뒤에 맞춘다 — 닫히기 직전에 도착한 콘솔 줄이 판정에서 빠지지 않게
  return r;
}

async function shootMock(browser, mockFile, width, out) {
  const abs = path.resolve(mockFile);
  const href = pathToFileURL(abs).href;
  const tag = slugOf(href);
  if (!fs.existsSync(abs)) return { tag, error: '파일 없음' };
  const ctx = await browser.newContext({ viewport: { width, height: 900 } });
  try {
    const page = await ctx.newPage();
    await page.goto(href, { waitUntil: 'load', timeout: 20000 });
    const png = path.join(out, `${tag}@${width}.mock.png`);
    await page.screenshot({ path: png, fullPage: true });
    return { tag, png };
  } catch (e) {
    return { tag, error: String(e.message || e).split('\n')[0].slice(0, 160) };
  } finally { await ctx.close(); }
}

// 기준선 모드: plain(기준선 안 씀 — 종전과 같음) · compare(새 위반만 FAIL) · record(기록만, FAIL 로 치지 않음)
function decideBaseline(a, widest, extra) {
  if (!a.baseline) return { mode: 'plain', base: null };
  const p = state.parseBaseline(a.baseline);
  const usable = p.state === 'ok' && p.value._widest === widest ? p.value : null;
  if (p.state === 'ok' && !usable) extra.push(`기준선 폭(${p.value._widest})과 이번 폭(${widest})이 달라 무시함`);
  if (p.state === 'broken') extra.push(`기준선 파일을 읽지 못해 무시함: ${a.baseline}`);
  if (p.state === 'missing' || a.baselineUpdate) return { mode: 'record', base: usable };
  return usable ? { mode: 'compare', base: usable } : { mode: 'plain', base: null };
}

async function main() {
  const a = parseArgs(process.argv.slice(2));
  if (a.rules) { for (const l of layout.rulesTable()) console.log(l); process.exit(0); }
  if (a.missing.length) fail2(`${a.missing[0]} 에 값이 없다`);
  if (!a.out || a.widths.length === 0 || (a.urls.length === 0 && !a.memory)) fail2(USAGE);
  if (a.baselineUpdate && !a.baseline) fail2('--a11y-baseline-update 는 --a11y-baseline 과 함께 쓴다');
  for (const e of a.expects) if (!EXPECT_RE.test(e)) fail2(`--expect 는 "<4xx 상태> <메서드> <경로>" 하나다(예: "401 GET /api/v1/me" · 와일드카드·쿼리·5xx 는 받지 않는다): ${e}`);
  let mem = { state: 'missing' };
  const urlsFromMemory = a.urls.length === 0;
  if (a.memory) {
    mem = state.loadMemory(a.memory);
    if (urlsFromMemory) {
      if (mem.state === 'missing') fail2(`기록 없음: ${a.memory}`);
      if (mem.state === 'broken') fail2(`기록을 읽지 못함: ${a.memory} (${mem.reason})`);
      a.urls = state.memoryUrls(mem.value);
    }
    if (mem.state === 'broken' && mem.code === 'expect') fail2(`기록을 읽지 못함: ${a.memory} (${mem.reason})`);   // 깨진 선언을 조용히 버리지 않는다
  }
  const expectRaw = [...new Set([...(mem.state === 'ok' ? mem.value.expect || [] : []), ...a.expects])];
  const expects = expectRaw.map(parseExpect);
  if (a.memory || a.baseline || a.mocks.length) {
    const dup = firstDup(a.urls.map(slugOf)) || firstDup(a.mocks.map((m) => slugOf(pathToFileURL(path.resolve(m)).href)));
    if (dup) fail2(`화면 이름 중복: ${dup}`);
  }
  const ssFile = a.storageState || (mem.state === 'ok' ? mem.value.storageState || '' : '');
  if (ssFile) {
    const r = state.readJson(ssFile);
    if (r.state !== 'ok') {
      console.log(`UI-PROBE: SKIP (NO_ENV — 로그인 상태 파일을 ${r.state === 'missing' ? '찾지 못했다' : '읽지 못했다'}: ${ssFile})`);
      process.exit(3);
    }
    if (!storageStateShapeOk(r.value)) {
      console.log(`UI-PROBE: SKIP (NO_ENV — 로그인 상태 파일의 모양이 맞지 않는다: ${ssFile})`);
      process.exit(3);
    }
  }
  const pw = resolveFrom(['playwright', 'playwright-core']);
  if (!pw) {
    console.log('UI-PROBE: SKIP (NO_TOOL — Playwright 를 찾지 못했다. 한 번 설치: npm install --prefix ~/.cache/devfsd/ui-harness playwright-core@1.49.1 axe-core@4.10.2 · 스크린샷만은 screen-shot.sh)');
    process.exit(3);
  }
  const axe = resolveFrom(['axe-core']);
  const axeFile = axe ? path.join(path.dirname(axe.file), 'axe.min.js') : '';
  fs.mkdirSync(a.out, { recursive: true });
  let browser;
  try { browser = await launch(pw.mod.chromium); } catch (e) {
    console.log(`UI-PROBE: SKIP (NO_BROWSER — 브라우저를 띄우지 못했다: ${String(e.message || e).split('\n')[0].slice(0, 160)})`);
    process.exit(3);
  }
  const results = [];
  const extra = [];
  const mockPngs = [];
  const mockErr = new Set();
  const widest = Math.max(...a.widths);
  for (const url of a.urls) {
    for (const w of a.widths) results.push(await probeOne(browser, url, w, a.out, axeFile, w === widest, ssFile, expects));
  }
  for (const m of a.mocks) {
    for (const w of a.widths) {
      const r = await shootMock(browser, m, w, a.out);
      if (r.png) mockPngs.push(r.png);
      else if (!mockErr.has(r.tag)) { mockErr.add(r.tag); extra.push(`${r.tag} 목업 촬영 실패: ${r.error}`); }
    }
  }
  await browser.close();

  const widestRows = results.filter((r) => r.width === widest);
  const viol = [];
  for (const r of widestRows) for (const v of r.a11y || []) if (WARN_IMPACTS.includes(v.impact)) viol.push({ slug: slugOf(r.url), ...v });
  const cur = Object.fromEntries(viol.map((v) => [`${v.slug}|${v.id}`, v.nodes]));
  const allAxe = Boolean(axeFile) && !results.some((r) => r.loadError) && widestRows.every((r) => Array.isArray(r.a11y));
  const bl = decideBaseline(a, widest, extra);

  const L = layout.summarize(results.map((r) => ({ tag: `${slugOf(r.url)}@${r.width}`, layout: r.layout })));
  const issues = [];
  let over = 0, cerr = 0, severe = 0, minor = 0, same = 0, recorded = 0, nreq = 0, nexp = 0;
  for (const r of results) {
    const tag = `${slugOf(r.url)}@${r.width}`;
    if (r.loadError) { issues.push(`${tag} 열기 실패: ${r.loadError}`); continue; }
    if (r.overflow) { over++; issues.push(`${tag} 가로 넘침: 문서 폭이 화면 폭(${r.width})보다 넓다`); }
    for (const m of r.consoleErrors) { cerr++; issues.push(`${tag} 콘솔 오류: ${m}`); }
    nreq += r.failedRequests.length;
    nexp += r.expected.length;
    for (const q of r.expected) issues.push(`${tag} 예상한 응답: ${q} (선언됨 — 실패로 세지 않음)`);
    for (const q of r.failedRequests.slice(0, REQ_LINES_MAX)) issues.push(`${tag} 요청 실패 경고: ${q}`);
    if (r.failedRequests.length > REQ_LINES_MAX) issues.push(`${tag} 요청 실패 경고: 외 ${r.failedRequests.length - REQ_LINES_MAX}건`);
    for (const v of r.a11y || []) {
      if (!WARN_IMPACTS.includes(v.impact)) minor++;
      else if (bl.mode === 'plain') { severe++; issues.push(`${tag} 접근성 ${v.impact} ${v.id}(${v.nodes}곳): ${v.help}`, ...a11yDetailLines(v)); }
    }
  }
  if (bl.mode === 'compare') {
    const c = state.compareBaseline(bl.base, cur);
    same = c.same;
    for (const f of c.fresh) {
      const v = viol.find((x) => `${x.slug}|${x.id}` === f.key);
      severe++;
      issues.push(`${v.slug}@${widest} 접근성 ${v.impact} ${v.id}(${f.cur}곳, ${f.prev === undefined ? '기준선 없음' : `기준선 ${f.prev}곳`}): ${v.help}`, ...a11yDetailLines(v));
    }
  }
  if (bl.mode === 'record') {
    if (allAxe) {
      const slugs = widestRows.map((r) => slugOf(r.url));
      const w = state.writeJson(a.baseline, state.mergeBaseline(a.baselineUpdate ? bl.base : null, slugs, cur, widest));
      if (w.ok) { recorded = viol.length; for (const v of viol) extra.push(`기준선 기록: ${v.slug}@${widest} ${v.impact} ${v.id}(${v.nodes}곳)`, ...a11yDetailLines(v)); }   // 막지 않는 줄이지만 어느 요소인지는 적는다 — 방금 만든 화면의 위반이 섞였는지 보게
      else extra.push(`기록을 쓰지 못함: ${a.baseline} (${w.reason})`);
    } else extra.push(`기준선을 쓰지 않음: ${axeFile ? '열기에 실패한 화면이 있다' : 'axe-core 를 찾지 못했다'}`);
  }

  const loadFail = results.some((r) => r.loadError);
  if (a.memory && (!urlsFromMemory || a.startCmd || a.storageState)) {
    const d = state.describeUrls(a.urls);
    if (!d.ok) extra.push(`기록 안 함: ${d.reason}`);
    else if (loadFail) extra.push('기록 안 함: 열기에 실패한 화면이 있다');
    else if (mem.state === 'broken') extra.push('기록 안 함: 기존 기록을 읽지 못함');
    else {
      const merged = state.mergeMemory(mem.state === 'ok' ? mem.value : null, { origin: d.origin, routes: d.routes, startCmd: a.startCmd, storageState: a.storageState, expect: expects.filter((e) => e.used && a.expects.includes(e.raw)).map((e) => e.raw) });   // 이번 실행에서 실제로 맞은 선언만 남긴다(오타·과한 선언이 기록에 굳지 않게)
      const dup = firstDup(merged.routes.map((r) => slugOf(merged.baseUrl + r)));
      if (dup) extra.push(`기록 안 함: 화면 이름 중복: ${dup}`);
      else {
        const w = state.writeJson(a.memory, merged);
        if (!w.ok) extra.push(`기록을 쓰지 못함: ${a.memory} (${w.reason})`);
      }
    }
  }

  if (!loadFail) for (const e of expects) if (!e.used) extra.push(`나오지 않은 선언: ${e.raw} (이 실행에서 그 응답이 없었다 — 더는 필요 없으면 화면 기록의 expect 에서 지운다)`);
  const verdict = (over || cerr || severe || loadFail) ? 'FAIL' : 'PASS';
  let a11yNote = axeFile ? `접근성 심각 ${severe}${minor ? ` · 경미 ${minor}` : ''}` : '접근성 SKIP(axe-core 없음)';
  if (axeFile && bl.mode === 'compare') a11yNote += ` · 기준선 ${same}`;
  if (axeFile && bl.mode === 'record') a11yNote += ` · 기준선 기록 ${recorded}`;
  console.log(`UI-PROBE: ${verdict} (${a.urls.length}화면·${a.widths.length}폭 · 넘침 ${over} · 콘솔 오류 ${cerr} · ${a11yNote}${L.note}${nreq ? ` · 요청 실패 ${nreq}` : ''}${nexp ? ` · 예상한 응답 ${nexp}` : ''})`);
  for (const i of issues) console.log(i.startsWith('      · ') ? i : `  - ${i}`);   // 요소 상세 줄은 위반 줄에 딸린 줄이라 머리표를 붙이지 않는다
  for (const w of L.lines) console.log(`  - ${w}`);
  for (const e of extra) console.log(e.startsWith('      · ') ? e : `  - ${e}`);
  for (const r of results) if (r.png) console.log(`  png: ${r.png}`);
  for (const m of mockPngs) console.log(`  mock: ${m}`);
  fs.writeFileSync(path.join(a.out, 'ui-probe.json'), JSON.stringify({ verdict, widths: a.widths, playwright: pw.dir, axe: Boolean(axeFile), ...(mockPngs.length ? { mocks: mockPngs } : {}), results }, null, 2));
  process.exit(verdict === 'PASS' ? 0 : 1);
}

main().catch((e) => { console.log(`UI-PROBE: SKIP (NO_BROWSER — 실행 중 오류: ${String(e.message || e).split('\n')[0].slice(0, 160)})`); process.exit(3); });
