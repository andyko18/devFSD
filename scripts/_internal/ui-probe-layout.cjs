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

// 브라우저 안에서 돈다(Playwright 가 직렬화) — 바깥 변수를 참조하지 않는다. 본문은 Task 2 에서 채운다(이름은 바꾸지 않는다 — 테스트 대역이 fn.name 으로 구분한다)
function measureLayout() {
  return { clip: [], overlap: [] };
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
