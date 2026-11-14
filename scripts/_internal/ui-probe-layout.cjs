// ui-probe-layout.cjs — 화면 배치 계측(가로 잘림·글자 겹침 + 좁은 폭 3종: 칩 줄바꿈·가로 스크롤에 숨음·고정 막대 가림) (20261110-visual-severity-clip-overlap · 20261114)
// ui-probe.cjs 가 화면을 연 폭마다 measureLayout 을 브라우저 안에서 돌린다. 결과는 경고다 — 판정(PASS·FAIL)에 들어가지 않는다.
// 왜: 문서 폭만 재던 '넘침' 은 overflow:hidden 상자 안에서 잘린 표와 포개진 글자를 0 으로 봤다(실측: 결함 목업 2개 모두 넘침 0).
// 재는 범위: 화면을 연 시점의 상태 · 가로 방향 잘림만. 불투명한 층에 덮여 가려진 글자(열린 드롭다운·모달)는 겹침으로 세지 않는다.
'use strict';

// 규칙 정의는 여기 한 곳이다 — 에이전트 본문과 테스트는 이 ID 를 가리킨다 (`node ui-probe.cjs --rules`)
const RULES = {
  'L-CLIP-X': { label: '가로 잘림', def: '글자·컨트롤이 든 요소가 가로를 가리는 상자(overflow-x hidden·clip — 가로 스크롤 없음)의 가장자리에 걸쳐 일부만 보인다. 가로 방향만 잰다(세로 잘림은 재지 않는다). html·body 가 가로 스크롤을 막은 화면에서는 화면 가장자리가 그 상자다. 말줄임·낭독기 전용 숨김·숨긴 요소·가로 스크롤 영역 안·가림 상자 밖에 기준을 둔 absolute·fixed 자손은 뺀다.' },
  'L-OVERLAP': { label: '글자 겹침', def: '포함 관계가 아닌 두 요소의 보이는 글자가 4px 넘게 포개진다. 화면에 고정된 요소(fixed·sticky)와 불투명한 층에 덮여 가려진 글자는 뺀다(불투명한 배지가 라벨을 완전히 덮는 경우도 잡지 못한다 — 이미지로 본다).' },
  'L-WRAP-CHIP': { label: '칩 줄바꿈', def: '칩·배지·버튼처럼 짧은 글자(16자 이하)를 담은 둥근 상자의 글자가 두 줄 이상으로 꺾인다. 배경이나 테두리가 있고 모서리가 둥근 인라인 상자만 본다(평범한 문단·링크는 보지 않는다).' },
  'L-SCROLL-X': { label: '가로 스크롤에 숨음', def: '가로 스크롤 상자(overflow-x auto·scroll) 안의 내용이 24px 넘게 화면 밖에 숨어 있다. 표를 감싼 상자는 뺀다(표는 래퍼 안 가로 스크롤이 규약이다). 탭 줄·차트가 대상이다.' },
  'L-FIXED-COVER': { label: '고정 막대 가림', def: '화면 아래에 고정된 막대(position fixed · 화면 폭의 절반 이상 · 높이 40% 이하)가 있는데 문서 끝에 그 높이만큼의 아래 여백이 없어, 끝까지 내려도 마지막 글자·입력이 막대 뒤에 가린다.' },
};
const MAX_LINES = 5;

// 브라우저 안에서 돈다(Playwright 가 직렬화) — 바깥 변수를 참조하지 않는다
function measureLayout() {
  const MINPX = 4;
  const name = (el) => {
    const t = (el.innerText || el.value || el.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim().slice(0, 24);
    const c = typeof el.className === 'string' && el.className.trim() ? `.${el.className.trim().split(/\s+/)[0]}` : '';
    return `<${el.tagName.toLowerCase()}${c}>${t ? ` "${t}"` : ''}`;
  };
  const shown = (el) => {
    if (el.checkVisibility) return el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true });
    const cs = getComputedStyle(el); return cs.display !== 'none' && cs.visibility === 'visible' && cs.opacity !== '0';
  };
  const hasContent = (el) => {
    if (/^(BUTTON|INPUT|SELECT|TEXTAREA|IMG|A)$/.test(el.tagName)) return true;
    const w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT); let n;
    while ((n = w.nextNode())) if (n.nodeValue.trim()) return true;
    return false;
  };

  // 잘림: 가로를 가리는 상자의 가장자리에 걸쳐 일부만 보이는 가장 바깥 요소
  const clip = [];
  // html·body 가 가로를 가리면(overflow-x hidden — 흔한 모바일 땜질) 화면 자체가 가림 상자다: 문서 폭 '넘침' 판정은 이 경우를 0 으로 본다(실측)
  const rootClips = [document.documentElement, document.body].some((e) => /^(hidden|clip)$/.test(getComputedStyle(e).overflowX));
  for (const box of [...(rootClips ? [document.body] : []), ...document.querySelectorAll('body *')]) {
    const isRoot = box === document.body;
    const cs = getComputedStyle(box);
    if (!isRoot && (!/^(hidden|clip)$/.test(cs.overflowX) || cs.textOverflow === 'ellipsis' || !shown(box))) continue;
    const b = box.getBoundingClientRect();
    if (!isRoot && (b.width <= 1 || b.height <= 1)) continue;   // 낭독기 전용 숨김(1px 상자)
    const left = isRoot ? 0 : b.left + box.clientLeft, right = isRoot ? document.documentElement.clientWidth : left + box.clientWidth;
    const walk = (el) => {
      for (const c of el.children) {
        if (!shown(c)) continue;
        // 가림 상자 밖에 기준(containing block)을 둔 absolute·fixed 자손은 그 상자에 잘리지 않는다(카드 안 DOM 의 툴팁·팝오버)
        const pos = getComputedStyle(c).position;
        if (!isRoot && (pos === 'fixed' || (pos === 'absolute' && !(c.offsetParent === box || (c.offsetParent && box.contains(c.offsetParent)))))) continue;
        const r = c.getBoundingClientRect();
        if (r.width <= 1 || r.height <= 1) continue;
        const cut = (r.right > right + MINPX && r.left < right - MINPX) || (r.left < left - MINPX && r.right > left + MINPX);
        if (cut && hasContent(c)) { clip.push(`${name(c)} — ${isRoot ? '화면(가로 스크롤 막힘)' : name(box)} 안에서 ${Math.round(Math.max(r.right - right, left - r.left))}px 가려짐`); continue; }
        if (/^(hidden|clip|auto|scroll)$/.test(getComputedStyle(c).overflowX)) continue;   // 안쪽 가림·스크롤 상자는 자기 차례에 본다
        walk(c);
      }
    };
    walk(box);
  }

  // 겹침: 포함 관계가 아닌 두 요소의 보이는 글자 상자가 포개짐
  const pinned = (el) => {
    for (let e = el; e && e !== document.body; e = e.parentElement) { const p = getComputedStyle(e).position; if (p === 'fixed' || p === 'sticky') return true; }
    return false;
  };
  const visibleRect = (el, r0) => {   // 가리는 조상 상자와 교차한 부분만(낭독기 전용 숨김·잘린 글자 제외)
    let r = { left: r0.left, right: r0.right, top: r0.top, bottom: r0.bottom };
    for (let e = el; e && e !== document.documentElement; e = e.parentElement) {
      const cs = getComputedStyle(e);
      if (cs.overflowX === 'visible' && cs.overflowY === 'visible') continue;
      const b = e.getBoundingClientRect();
      r = { left: Math.max(r.left, b.left), right: Math.min(r.right, b.right), top: Math.max(r.top, b.top), bottom: Math.min(r.bottom, b.bottom) };
      if (r.right <= r.left || r.bottom <= r.top) return null;
    }
    return r;
  };
  const opaque = (e) => {
    const cs = getComputedStyle(e);
    if (cs.backgroundImage !== 'none') return true;
    const m = cs.backgroundColor.match(/rgba?\(([^)]+)\)/); if (!m) return false;
    const p = m[1].split(',').map((x) => parseFloat(x));
    return (p.length < 4 ? 1 : p[3]) >= 0.95;
  };
  const occluded = (A, B, x, y) => {   // 아래쪽 글자가 불투명한 층에 덮였으면 포개져 보이는 것이 아니라 가려진 것이다
    const sy = window.scrollY;
    window.scrollTo({ top: Math.max(0, y + sy - window.innerHeight / 2), behavior: 'instant' });   // smooth 스크롤 화면에서도 바로 옮긴다
    const st = document.elementsFromPoint(x, y + sy - window.scrollY);
    window.scrollTo({ top: sy, behavior: 'instant' });
    const ia = st.indexOf(A.el), ib = st.indexOf(B.el);
    if (ia < 0 || ib < 0) return false;
    return st.slice(0, Math.max(ia, ib)).some(opaque);
  };
  const items = [];
  const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let node;
  while ((node = tw.nextNode())) {
    if (!node.nodeValue.trim()) continue;
    const el = node.parentElement;
    if (!el || /^(SCRIPT|STYLE|NOSCRIPT|OPTION|TITLE)$/.test(el.tagName) || !shown(el) || pinned(el)) continue;
    const rg = document.createRange(); rg.selectNodeContents(node);
    for (const r0 of rg.getClientRects()) {
      const r = visibleRect(el, r0);
      if (r && r.right - r.left >= MINPX && r.bottom - r.top >= MINPX) items.push({ el, r });
    }
  }
  items.sort((a, b) => a.r.top - b.r.top);
  const pairs = []; const overlap = [];
  for (let i = 0; i < items.length; i++) {
    for (let j = i + 1; j < items.length; j++) {
      const A = items[i], B = items[j];
      if (B.r.top >= A.r.bottom - MINPX) break;
      if (A.el === B.el || A.el.contains(B.el) || B.el.contains(A.el)) continue;
      const w = Math.min(A.r.right, B.r.right) - Math.max(A.r.left, B.r.left);
      const h = Math.min(A.r.bottom, B.r.bottom) - Math.max(A.r.top, B.r.top);
      if (w < MINPX || h < MINPX) continue;
      if (pairs.some((k) => (k[0] === A.el && k[1] === B.el) || (k[0] === B.el && k[1] === A.el))) continue;   // 같은 쌍은 한 번
      if (occluded(A, B, Math.max(A.r.left, B.r.left) + w / 2, Math.max(A.r.top, B.r.top) + h / 2)) continue;
      pairs.push([A.el, B.el]);
      overlap.push(`${name(A.el)} ↔ ${name(B.el)} — ${Math.round(w)}×${Math.round(h)}px 겹침`);
    }
  }
  // 줄바꿈: 짧은 글자를 담은 둥근 인라인 상자(칩·배지·버튼)의 글자가 두 줄 이상
  const wrap = [];
  for (const el of document.querySelectorAll('body *')) {
    if (el.children.length > 2 || !shown(el)) continue;
    const cs = getComputedStyle(el);
    if (!/^inline-(flex|block)$/.test(cs.display) && el.tagName !== 'BUTTON') continue;
    const txt = (el.innerText || '').replace(/\s+/g, ' ').trim();
    if (!txt || txt.length > 16) continue;
    const bg = cs.backgroundColor.match(/rgba?\(([^)]+)\)/); const bp = bg ? bg[1].split(',').map((x) => parseFloat(x)) : [];
    const filled = (bp.length === 3 || (bp.length === 4 && bp[3] > 0.05)) || parseFloat(cs.borderTopWidth) > 0;
    if (!filled || parseFloat(cs.borderTopLeftRadius) <= 0) continue;
    const tops = new Set();
    const w2 = document.createTreeWalker(el, NodeFilter.SHOW_TEXT); let t;
    while ((t = w2.nextNode())) {
      if (!t.nodeValue.trim()) continue;
      const rg = document.createRange(); rg.selectNodeContents(t);
      for (const r of rg.getClientRects()) if (r.width >= 1 && r.height >= 1) tops.add(Math.round(r.top / MINPX));
    }
    // 한 줄에 나란한 글자 조각(아이콘 옆 글자)은 top 이 같다 — 줄 높이의 절반 넘게 벌어진 것만 다른 줄로 센다
    const ys = [...tops].sort((a, b) => a - b); let lines = ys.length ? 1 : 0;
    const lh = (parseFloat(cs.lineHeight) || parseFloat(cs.fontSize) * 1.2) / MINPX;
    for (let k = 1; k < ys.length; k++) if (ys[k] - ys[k - 1] > lh / 2) lines++;
    if (lines >= 2) wrap.push(`${name(el)} — ${lines}줄로 꺾임`);
  }

  // 가로 스크롤에 숨음: 표가 아닌 내용이 가로 스크롤 상자 안에서 화면 밖에 있다
  const scroll = [];
  const HIDE_MIN = 24;
  for (const box of document.querySelectorAll('body *')) {
    const cs = getComputedStyle(box);
    if (!/^(auto|scroll)$/.test(cs.overflowX) || !shown(box) || box.clientWidth <= 1) continue;
    if (/^(PRE|CODE|TEXTAREA|SELECT|TABLE)$/.test(box.tagName) || box.querySelector('table')) continue;
    const hid = box.scrollWidth - box.clientWidth;
    if (hid >= HIDE_MIN && hasContent(box)) scroll.push(`${name(box)} — 가로 스크롤 안에 ${Math.round(hid)}px 숨음`);
  }

  // 고정 막대 가림: 아래 고정 막대 높이만큼의 아래 여백이 문서 끝에 없다
  const cover = [];
  const vw = document.documentElement.clientWidth, vh = window.innerHeight;
  let endY = 0;   // 고정되지 않은 글자·입력 가운데 가장 아래(문서 좌표)
  for (const it of items) endY = Math.max(endY, it.r.bottom + window.scrollY);
  for (const c of document.querySelectorAll('input, select, textarea, button')) {
    if (!shown(c) || pinned(c)) continue;
    const r = c.getBoundingClientRect(); if (r.width > 1 && r.height > 1) endY = Math.max(endY, r.bottom + window.scrollY);
  }
  const docH = Math.max(document.documentElement.scrollHeight, vh);
  for (const bar of document.querySelectorAll('body *')) {
    if (getComputedStyle(bar).position !== 'fixed' || !shown(bar)) continue;
    const r = bar.getBoundingClientRect();
    if (Math.abs(r.bottom - vh) > 2 || r.width < vw * 0.5 || r.height < 8 || r.height > vh * 0.4 || !hasContent(bar)) continue;
    const hid = endY - (docH - r.height);
    if (hid > MINPX) cover.push(`${name(bar)} — 문서 끝 ${Math.round(hid)}px 가 고정 막대 뒤에 가린다(아래 여백 없음)`);
  }
  return { clip, overlap, wrap, scroll, cover };
}

const unmeasured = (reason) => ({ state: 'unmeasured', reason });

// 브라우저가 돌려준 값을 믿지 않는다 — 모양이 아니면 0건이 아니라 '계측 못 함'
function normalize(m) {
  const strs = (a) => Array.isArray(a) && a.every((x) => typeof x === 'string');
  if (!m || typeof m !== 'object' || !strs(m.clip) || !strs(m.overlap)) return unmeasured('계측 결과를 읽지 못함');
  // 좁은 폭 규칙 3칸은 없을 수 있다(없으면 0건) — 있는데 모양이 틀리면 0건으로 읽지 않는다
  const opt = {};
  for (const k of ['wrap', 'scroll', 'cover']) { if (m[k] === undefined) opt[k] = []; else if (strs(m[k])) opt[k] = m[k]; else return unmeasured('계측 결과를 읽지 못함'); }
  return { state: 'ok', clip: m.clip, overlap: m.overlap, ...opt };
}

// 한 화면을 잰다 — 예외는 그 화면·폭의 '계측 못 함' 이 되고 호출자로 번지지 않는다
async function run(page) {
  try { return normalize(await page.evaluate(measureLayout)); }
  catch (e) { return unmeasured(`계측 중 오류: ${String(e.message || e).split('\n')[0].slice(0, 120)}`); }
}

// rows: [{ tag: '<화면>@<폭>', layout }] → 경고 줄들과 요약 줄 끝에 덧붙일 말(경고·못 잰 것이 모두 0 이면 '' — 종전 요약 줄 그대로)
function summarize(rows) {
  const lines = []; let clip = 0, overlap = 0, wrap = 0, scroll = 0, cover = 0, miss = 0;
  for (const { tag, layout } of rows) {
    if (!layout || layout.state !== 'ok') { miss++; lines.push(`${tag} 배치 계측 못 함: ${(layout && layout.reason) || '계측하지 않음'}`); continue; }
    const extraRules = [['L-WRAP-CHIP', layout.wrap || []], ['L-SCROLL-X', layout.scroll || []], ['L-FIXED-COVER', layout.cover || []]];
    for (const [id, list] of [['L-CLIP-X', layout.clip], ['L-OVERLAP', layout.overlap], ...extraRules]) {
      const head = `${tag} 배치 경고 ${id}(${RULES[id].label}): `;
      for (const d of list.slice(0, MAX_LINES)) lines.push(head + d);
      if (list.length > MAX_LINES) lines.push(`${head}외 ${list.length - MAX_LINES}건`);
    }
    clip += layout.clip.length; overlap += layout.overlap.length;
    wrap += extraRules[0][1].length; scroll += extraRules[1][1].length; cover += extraRules[2][1].length;
  }
  const n = clip + overlap + wrap + scroll + cover;
  // 좁은 폭 규칙은 0 이 아닐 때만 덧붙인다 — 없으면 종전 요약 줄 그대로다
  const more = `${wrap ? ` · 줄바꿈 ${wrap}` : ''}${scroll ? ` · 스크롤 숨음 ${scroll}` : ''}${cover ? ` · 고정 가림 ${cover}` : ''}`;
  return { lines, note: `${n ? ` · 배치 경고 ${n}(잘림 ${clip} · 겹침 ${overlap}${more})` : ''}${miss ? ` · 배치 계측 못 함 ${miss}` : ''}` };
}

function rulesTable() {
  return ['| 규칙 | 정의 |', '|---|---|', ...Object.entries(RULES).map(([id, r]) => `| ${id} | ${r.label} — ${r.def} |`)];
}

module.exports = { RULES, measureLayout, run, unmeasured, summarize, rulesTable };
