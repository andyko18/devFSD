#!/usr/bin/env node
// ui-probe-state.cjs — ui-probe.cjs 의 화면 기록(--memory)·접근성 기준선(--a11y-baseline) 규칙 (20261110-ui-probe-memory-mock-baseline)
// 브라우저 없이 시험되는 순수 함수만 둔다. 파일 형식은 plan §3.
'use strict';
const fs = require('fs');
const path = require('path');

const META = '_widest';

function readJson(file) {
  let raw;
  try { raw = fs.readFileSync(file, 'utf8'); } catch (e) {
    return (e.code === 'ENOENT' || e.code === 'ENOTDIR') ? { state: 'missing' } : { state: 'broken', reason: String(e.message || e).split('\n')[0].slice(0, 160) };
  }
  try { return { state: 'ok', value: JSON.parse(raw) }; } catch (_) { return { state: 'broken', reason: 'JSON 오류' }; }
}

function isOrigin(s) {
  try { const u = new URL(s); return (u.protocol === 'http:' || u.protocol === 'https:') && u.origin === s; } catch (_) { return false; }
}

function loadMemory(file) {
  const r = readJson(file);
  if (r.state !== 'ok') return r;
  const m = r.value;
  if (!m || typeof m !== 'object' || Array.isArray(m)) return { state: 'broken', reason: '최상위가 객체가 아니다' };
  if (!isOrigin(m.baseUrl)) return { state: 'broken', reason: 'baseUrl 이 http(s) origin 이 아니다' };
  if (!Array.isArray(m.routes) || m.routes.length === 0 || !m.routes.every((x) => typeof x === 'string' && x.startsWith('/'))) {
    return { state: 'broken', reason: 'routes 가 비어 있지 않은 경로 문자열 배열이 아니다' };
  }
  return { state: 'ok', value: m };
}

function memoryUrls(m) { return m.routes.map((r) => m.baseUrl + r); }

// 이번 실행의 URL 들이 기록에 쓸 수 있는 모양인지: 전부 http(s) 이고 origin 이 하나
function describeUrls(urls) {
  let origin = '';
  const routes = [];
  for (const u of urls) {
    let p;
    try { p = new URL(u); } catch (_) { return { ok: false, reason: `URL 을 읽지 못함: ${u}` }; }
    if (p.protocol !== 'http:' && p.protocol !== 'https:') return { ok: false, reason: 'http(s) 가 아닌 화면이 있다(file:// 등)' };
    if (origin && p.origin !== origin) return { ok: false, reason: 'origin 이 하나가 아니다' };
    origin = p.origin;
    const route = p.pathname + p.search;
    if (!routes.includes(route)) routes.push(route);
  }
  return { ok: true, origin, routes };
}

function mergeMemory(existing, run) {
  const prev = existing || {};
  const routes = [...(prev.routes || [])];
  for (const r of run.routes) if (!routes.includes(r)) routes.push(r);
  const out = { baseUrl: run.origin, routes };
  const startCmd = run.startCmd || prev.startCmd;
  const storageState = run.storageState || prev.storageState;
  if (startCmd) out.startCmd = startCmd;
  if (storageState) out.storageState = storageState;
  return out;
}

function parseBaseline(file) {
  const r = readJson(file);
  if (r.state !== 'ok') return r;
  const b = r.value;
  if (!b || typeof b !== 'object' || Array.isArray(b)) return { state: 'broken', reason: '최상위가 객체가 아니다' };
  for (const [k, v] of Object.entries(b)) {
    if (!Number.isInteger(v) || v < 1) return { state: 'broken', reason: `${k} 값이 1 이상의 정수가 아니다` };
  }
  if (!(META in b)) return { state: 'broken', reason: `${META} 가 없다` };
  return { state: 'ok', value: b };
}

// current: {"<slug>|<규칙>": 노드 수}. 기준선에 없거나 노드 수가 늘면 fresh, 같거나 줄면 same
function compareBaseline(base, current) {
  const fresh = [];
  let same = 0;
  for (const [key, cur] of Object.entries(current)) {
    const prev = base[key];
    if (prev === undefined || cur > prev) fresh.push({ key, cur, prev });
    else same++;
  }
  return { fresh, same };
}

// 점검한 화면(slugs)의 항목만 이번 결과로 바꾸고 나머지는 보존한다. base 가 null 이면 이번 결과만.
function mergeBaseline(base, slugs, current, widest) {
  const out = {};
  if (base) for (const [k, v] of Object.entries(base)) if (k !== META && !slugs.includes(k.split('|')[0])) out[k] = v;
  Object.assign(out, current);
  out[META] = widest;
  return Object.fromEntries(Object.entries(out).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
}

function writeJson(file, obj) {
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n');
    fs.renameSync(tmp, file);   // 쓰는 도중 깨진 파일이 남지 않게
    return { ok: true };
  } catch (e) { return { ok: false, reason: String(e.message || e).split('\n')[0].slice(0, 160) }; }
}

// 실패한 요청의 주소를 출력용으로 줄인다 — 쿼리·해시는 버린다(토큰·개인정보가 실리는 자리다).
//   data:·blob: 와 origin 이 없는 스킴(about:·javascript:·확장 주소)은 스킴만, 읽지 못한 주소는 원문을 내지 않는다.
//   userinfo(user:pass@)는 origin 에 들지 않아 빠진다. 경로는 남는다 — 경로에 실린 값(/reset/<토큰>)까지는 가리지 못한다.
function requestLabel(u) {
  let p;
  try { p = new URL(String(u)); } catch (_) { return '(주소를 읽지 못함)'; }
  if (p.protocol === 'file:') return `file://${p.pathname}`.slice(0, 160);
  if (p.protocol === 'data:' || p.protocol === 'blob:' || p.origin === 'null') return p.protocol;
  const base = `${p.origin}${p.pathname}`;
  return base.slice(0, 160);
}

module.exports = { readJson, loadMemory, memoryUrls, describeUrls, mergeMemory, parseBaseline, compareBaseline, mergeBaseline, writeJson, requestLabel };
