// ui-probe-layout.cjs — 화면 배치 계측(가로 잘림·글자 겹침) (20261110-visual-severity-clip-overlap)
// ui-probe.cjs 가 화면을 연 폭마다 measureLayout 을 브라우저 안에서 돌린다. 결과는 경고다 — 판정(PASS·FAIL)에 들어가지 않는다.
// 왜: 문서 폭만 재던 '넘침' 은 overflow:hidden 상자 안에서 잘린 표와 포개진 글자를 0 으로 봤다(실측: 결함 목업 2개 모두 넘침 0).
// 재는 범위: 화면을 연 시점의 상태 · 가로 방향 잘림만. 불투명한 층에 덮여 가려진 글자(열린 드롭다운·모달)는 겹침으로 세지 않는다.
'use strict';

// 규칙 정의는 여기 한 곳이다 — 에이전트 본문과 테스트는 이 ID 를 가리킨다 (`node ui-probe.cjs --rules`)
const RULES = {
  'L-CLIP-X': { label: '가로 잘림', def: '글자·컨트롤이 든 요소가 가로를 가리는 상자(overflow-x hidden·clip — 가로 스크롤 없음)의 가장자리에 걸쳐 일부만 보인다. 가로 방향만 잰다(세로 잘림은 재지 않는다). html·body 가 가로 스크롤을 막은 화면에서는 화면 가장자리가 그 상자다. 말줄임·낭독기 전용 숨김·숨긴 요소·가로 스크롤 영역 안·가림 상자 밖에 기준을 둔 absolute·fixed 자손은 뺀다.' },
  'L-OVERLAP': { label: '글자 겹침', def: '포함 관계가 아닌 두 요소의 보이는 글자가 4px 넘게 포개진다. 화면에 고정된 요소(fixed·sticky)와 불투명한 층에 덮여 가려진 글자는 뺀다(불투명한 배지가 라벨을 완전히 덮는 경우도 잡지 못한다 — 이미지로 본다).' },
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
  return { clip, overlap };
}

const unmeasured = (reason) => ({ state: 'unmeasured', reason });

// 브라우저가 돌려준 값을 믿지 않는다 — 모양이 아니면 0건이 아니라 '계측 못 함'
function normalize(m) {
  const strs = (a) => Array.isArray(a) && a.every((x) => typeof x === 'string');
  if (!m || typeof m !== 'object' || !strs(m.clip) || !strs(m.overlap)) return unmeasured('계측 결과를 읽지 못함');
  return { state: 'ok', clip: m.clip, overlap: m.overlap };
}

// 한 화면을 잰다 — 예외는 그 화면·폭의 '계측 못 함' 이 되고 호출자로 번지지 않는다
async function run(page) {
  try { return normalize(await page.evaluate(measureLayout)); }
  catch (e) { return unmeasured(`계측 중 오류: ${String(e.message || e).split('\n')[0].slice(0, 120)}`); }
}

// rows: [{ tag: '<화면>@<폭>', layout }] → 경고 줄들과 요약 줄 끝에 덧붙일 말(경고·못 잰 것이 모두 0 이면 '' — 종전 요약 줄 그대로)
function summarize(rows) {
  const lines = []; let clip = 0, overlap = 0, miss = 0;
  for (const { tag, layout } of rows) {
    if (!layout || layout.state !== 'ok') { miss++; lines.push(`${tag} 배치 계측 못 함: ${(layout && layout.reason) || '계측하지 않음'}`); continue; }
    for (const [id, list] of [['L-CLIP-X', layout.clip], ['L-OVERLAP', layout.overlap]]) {
      const head = `${tag} 배치 경고 ${id}(${RULES[id].label}): `;
      for (const d of list.slice(0, MAX_LINES)) lines.push(head + d);
      if (list.length > MAX_LINES) lines.push(`${head}외 ${list.length - MAX_LINES}건`);
    }
    clip += layout.clip.length; overlap += layout.overlap.length;
  }
  const n = clip + overlap;
  return { lines, note: `${n ? ` · 배치 경고 ${n}(잘림 ${clip} · 겹침 ${overlap})` : ''}${miss ? ` · 배치 계측 못 함 ${miss}` : ''}` };
}

function rulesTable() {
  return ['| 규칙 | 정의 |', '|---|---|', ...Object.entries(RULES).map(([id, r]) => `| ${id} | ${r.label} — ${r.def} |`)];
}

module.exports = { RULES, measureLayout, run, unmeasured, summarize, rulesTable };
