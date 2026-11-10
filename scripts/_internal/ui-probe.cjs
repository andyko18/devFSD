#!/usr/bin/env node
// ui-probe.cjs — 웹 화면을 실제 브라우저로 여러 폭에서 열어 찍고 기계 판정한다 (20261109-ui-harness)
// Usage: node ui-probe.cjs --out <폴더> [--widths 375,768,1280] <URL>...
//        [--memory <파일> [--start-cmd <명령>]] [--storage-state <파일>] [--mock <html>]... [--a11y-baseline <파일> [--a11y-baseline-update]]
//   URL 은 이미 떠 있는 화면(http://localhost:3000/tracked) 또는 file:// 경로. dev 서버는 띄우지 않는다.
// 출력 (stdout):
//   UI-PROBE: PASS|FAIL (<N>화면·<M>폭 · 넘침 <a> · 콘솔 오류 <b> · 접근성 심각 <c> | 접근성 SKIP(사유))
//   UI-PROBE: SKIP (NO_TOOL|NO_BROWSER — 사유)        — 판정하지 못함. PASS 로 위장하지 않는다
//   UI-PROBE: SKIP (NO_ENV — 사유)                     — 로그인 상태 파일을 찾지·읽지 못했거나 모양이 맞지 않는다
//   그 아래 문제마다 `  - <화면>@<폭> <종류>: <내용>` 한 줄, 그리고 `  png: <경로>` 줄들
//   배치 계측(경고 — 판정에 들어가지 않는다): `  - <화면>@<폭> 배치 경고 L-CLIP-X|L-OVERLAP(<이름>): <설명>` · 못 잰 화면·폭은 `배치 계측 못 함: <사유>`
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

const USAGE = 'usage: node ui-probe.cjs --out <폴더> [--widths 375,768,1280] [--memory <파일> [--start-cmd <명령>]] [--storage-state <파일>] [--mock <html>]... [--a11y-baseline <파일> [--a11y-baseline-update]] <URL>...';

const WARN_IMPACTS = ['critical', 'serious'];
const AXE_TAGS = ['wcag2a', 'wcag2aa', 'wcag21aa'];

function parseArgs(argv) {
  const a = { out: '', widths: [375, 768, 1280], urls: [], memory: '', startCmd: '', storageState: '', mocks: [], baseline: '', baselineUpdate: false, rules: false, missing: [] };
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

async function probeOne(browser, url, width, out, axeFile, doAxe, ssFile) {
  const ctx = await browser.newContext({ viewport: { width, height: 900 }, ...(ssFile ? { storageState: ssFile } : {}) });
  const page = await ctx.newPage();
  const consoleErrors = [];
  page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 200)); });
  page.on('pageerror', (e) => consoleErrors.push(String(e.message || e).slice(0, 200)));
  const r = { url, width, png: '', overflow: false, consoleErrors, a11y: null, loadError: '', layout: null };
  try {
    await page.goto(url, { waitUntil: 'networkidle', timeout: 20000 }).catch(() => page.goto(url, { waitUntil: 'load', timeout: 20000 }));
  } catch (e) { r.loadError = String(e.message || e).slice(0, 200); r.layout = layout.unmeasured('열기 실패'); await ctx.close(); return r; }
  r.overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  r.png = path.join(out, `${slugOf(url)}@${width}.png`);
  await page.screenshot({ path: r.png, fullPage: true });
  if (doAxe && axeFile) {
    await page.addScriptTag({ path: axeFile });
    r.a11y = await page.evaluate(async (tags) => {
      // eslint-disable-next-line no-undef
      const res = await axe.run(document, { runOnly: { type: 'tag', values: tags } });
      return res.violations.map((v) => ({ id: v.id, impact: v.impact, nodes: v.nodes.length, help: v.help }));
    }, AXE_TAGS);
  }
  r.layout = await layout.run(page);   // 화면 상태(스크롤)를 건드릴 수 있어 판정 입력을 다 모은 뒤 마지막에 잰다
  await ctx.close();
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
  let mem = { state: 'missing' };
  const urlsFromMemory = a.urls.length === 0;
  if (a.memory) {
    mem = state.loadMemory(a.memory);
    if (urlsFromMemory) {
      if (mem.state === 'missing') fail2(`기록 없음: ${a.memory}`);
      if (mem.state === 'broken') fail2(`기록을 읽지 못함: ${a.memory} (${mem.reason})`);
      a.urls = state.memoryUrls(mem.value);
    }
  }
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
    for (const w of a.widths) results.push(await probeOne(browser, url, w, a.out, axeFile, w === widest, ssFile));
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
  let over = 0, cerr = 0, severe = 0, minor = 0, same = 0, recorded = 0;
  for (const r of results) {
    const tag = `${slugOf(r.url)}@${r.width}`;
    if (r.loadError) { issues.push(`${tag} 열기 실패: ${r.loadError}`); continue; }
    if (r.overflow) { over++; issues.push(`${tag} 가로 넘침: 문서 폭이 화면 폭(${r.width})보다 넓다`); }
    for (const m of r.consoleErrors) { cerr++; issues.push(`${tag} 콘솔 오류: ${m}`); }
    for (const v of r.a11y || []) {
      if (!WARN_IMPACTS.includes(v.impact)) minor++;
      else if (bl.mode === 'plain') { severe++; issues.push(`${tag} 접근성 ${v.impact} ${v.id}(${v.nodes}곳): ${v.help}`); }
    }
  }
  if (bl.mode === 'compare') {
    const c = state.compareBaseline(bl.base, cur);
    same = c.same;
    for (const f of c.fresh) {
      const v = viol.find((x) => `${x.slug}|${x.id}` === f.key);
      severe++;
      issues.push(`${v.slug}@${widest} 접근성 ${v.impact} ${v.id}(${f.cur}곳, ${f.prev === undefined ? '기준선 없음' : `기준선 ${f.prev}곳`}): ${v.help}`);
    }
  }
  if (bl.mode === 'record') {
    if (allAxe) {
      const slugs = widestRows.map((r) => slugOf(r.url));
      const w = state.writeJson(a.baseline, state.mergeBaseline(a.baselineUpdate ? bl.base : null, slugs, cur, widest));
      if (w.ok) { recorded = viol.length; for (const v of viol) extra.push(`기준선 기록: ${v.slug}@${widest} ${v.impact} ${v.id}(${v.nodes}곳)`); }
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
      const merged = state.mergeMemory(mem.state === 'ok' ? mem.value : null, { origin: d.origin, routes: d.routes, startCmd: a.startCmd, storageState: a.storageState });
      const dup = firstDup(merged.routes.map((r) => slugOf(merged.baseUrl + r)));
      if (dup) extra.push(`기록 안 함: 화면 이름 중복: ${dup}`);
      else {
        const w = state.writeJson(a.memory, merged);
        if (!w.ok) extra.push(`기록을 쓰지 못함: ${a.memory} (${w.reason})`);
      }
    }
  }

  const verdict = (over || cerr || severe || loadFail) ? 'FAIL' : 'PASS';
  let a11yNote = axeFile ? `접근성 심각 ${severe}${minor ? ` · 경미 ${minor}` : ''}` : '접근성 SKIP(axe-core 없음)';
  if (axeFile && bl.mode === 'compare') a11yNote += ` · 기준선 ${same}`;
  if (axeFile && bl.mode === 'record') a11yNote += ` · 기준선 기록 ${recorded}`;
  console.log(`UI-PROBE: ${verdict} (${a.urls.length}화면·${a.widths.length}폭 · 넘침 ${over} · 콘솔 오류 ${cerr} · ${a11yNote}${L.note})`);
  for (const i of issues) console.log(`  - ${i}`);
  for (const w of L.lines) console.log(`  - ${w}`);
  for (const e of extra) console.log(`  - ${e}`);
  for (const r of results) if (r.png) console.log(`  png: ${r.png}`);
  for (const m of mockPngs) console.log(`  mock: ${m}`);
  fs.writeFileSync(path.join(a.out, 'ui-probe.json'), JSON.stringify({ verdict, widths: a.widths, playwright: pw.dir, axe: Boolean(axeFile), ...(mockPngs.length ? { mocks: mockPngs } : {}), results }, null, 2));
  process.exit(verdict === 'PASS' ? 0 : 1);
}

main().catch((e) => { console.log(`UI-PROBE: SKIP (NO_BROWSER — 실행 중 오류: ${String(e.message || e).split('\n')[0].slice(0, 160)})`); process.exit(3); });
