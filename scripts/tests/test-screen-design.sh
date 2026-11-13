#!/usr/bin/env bash
# test-screen-design.sh — 화면 목업 품질 (20261109-screen-quality)
#   frontend-design · 다른 디자인 도구와의 격차 진단: devFSD 는 질문 없이 템플릿으로 즉시 만들고 결과를 렌더해 보지 않았다.
#   템플릿은 보라+다크 기본에 부품 3개(카드·버튼·입력)뿐이었고, 호버·포커스에 보라가 하드코딩돼 팔레트를 바꿔도 샜다.
#   ① 템플릿: 보라 하드코딩 0 · 업무 화면 부품 · 바닥선(포커스·좁은 폭·움직임 줄이기) · 파생 색은 주색에서
#   ② screen-shot.sh: 두 폭 촬영 · 찍지 못하면 SKIP(rc 3 — 통과로 위장하지 않음)
#   ③ frontend-design 원문(Apache-2.0)을 그대로 들여와 따르고, devFSD 보충(판단 지원·상태·토큰 이름·촬영)과 생성 지시 3곳을 연결
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
H="$PLUGIN/templates/screen.html"; G="$PLUGIN/templates/screen-design-guide.md"; SS="$PLUGIN/scripts/_internal/screen-shot.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
ok() { PASS=$((PASS+1)); echo "PASS $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL $1 — $2"; }

# T1 — 보라 하드코딩 0 (기본값·호버·포커스 어디에도)
if grep -qiE '#7C3AED|#6D28D9|#A78BFA|124, ?58, ?237' "$H"; then no "T1 보라 하드코딩" "$(grep -niE '#7C3AED|#6D28D9|#A78BFA|124, ?58, ?237' "$H" | head -2)"
else ok "T1 템플릿에 보라 하드코딩 없음(기본·호버·포커스)"; fi
# T2 — 파생 색은 주색에서 만든다(팔레트를 바꾸면 함께 바뀐다)
for v in -- '--color-primary-hover: color-mix' '--color-primary-soft: color-mix' '--color-ring: color-mix'; do [ "$v" = -- ] && continue
  grep -qF -- "$v" "$H" || { no "T2 파생 색" "없음: $v"; continue; }; done
grep -qF -- '--color-primary-hover: color-mix' "$H" && grep -qF -- '--color-ring: color-mix' "$H" && ok "T2 호버·포커스·옅은 색은 주색에서 color-mix 로 파생"
# T3 — 업무 화면 부품
miss=""; for c in app-shell sidebar nav-item topbar page-header toolbar table badge badge-success badge-warning badge-error tabs kpi pagination alert empty-state skeleton modal toast form-grid btn-ghost btn-danger; do
  grep -qE "\\.${c}[ {,:.\[]" "$H" || miss="$miss $c"; done
[ -z "$miss" ] && ok "T3 업무 화면 부품 22종 정의" || no "T3 부품" "없음:$miss"
# T4 — 바닥선
grep -qF ':focus-visible' "$H" && grep -qE '@media \(max-width: ?768px\)' "$H" && grep -qF 'prefers-reduced-motion' "$H" \
  && ok "T4 바닥선 — 포커스 링 · 좁은 폭 · 움직임 줄이기" || no "T4 바닥선" "focus-visible·768 미디어·reduced-motion 중 없음"
# T5 — 본문이 가운데 400px 카드 하나가 아니다(앱 셸 골격) · 실제 입력은 주석 밖에 없다(계측 0/0 계약)
! grep -qF 'max-width: 400px' "$H" && grep -qF 'class="app-shell"' "$H" && ok "T5 본문 골격은 앱 셸(가운데 좁은 카드 아님)" || no "T5 본문" "가운데 카드 잔존 또는 앱 셸 없음"
body_outside=$(awk '/<!--/{c=1} !c{print} /-->/{c=0}' "$H" | grep -ciE '<(input|select|textarea)[ >]')
[ "$body_outside" -eq 0 ] && ok "T5b 주석 밖 실제 입력 0개" || no "T5b" "주석 밖 입력 ${body_outside}개"

# T6 — screen-shot.sh: 인자 오류 rc 2 · 지정 Chrome 이 없으면 SKIP rc 3(통과 위장 금지)
bash "$SS" >/dev/null 2>&1; [ $? -eq 2 ] && ok "T6a 인자 없음 → rc 2" || no "T6a" "rc 2 아님"
out=$(SCREEN_SHOT_CHROME=/nonexistent/chrome bash "$SS" "$H" "$TMP/x" 2>&1); rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q '^SCREEN-SHOT: SKIP (찍지 못함' && [ ! -e "$TMP/x@1280.png" ] \
  && ok "T6b Chrome 없음 → SKIP(rc 3) · 파일 없음" || no "T6b" "rc=$rc out=[$out]"
# T6c — Chrome 이 있으면 실제로 두 장을 만든다(없는 환경은 SKIP — 이 검사는 위장하지 않는다)
out=$(SCREEN_SHOT_PROBE=0 bash "$SS" "$H" "$TMP/real" 2>&1); rc=$?
if [ "$rc" -eq 3 ]; then echo "SKIP T6c (이 환경에 Chrome 없음)"
elif [ "$rc" -eq 0 ] && [ -s "$TMP/real@1280.png" ] && [ -s "$TMP/real@390.png" ]; then ok "T6c Chrome 있음 → 1280·390 두 장 생성"
else no "T6c" "rc=$rc out=[$out]"; fi

# T6g~T6m — 촬영 끝에 배치 계측 파일 <접두>.probe.txt (FID 20261110-visual-severity-clip-overlap AC-7 ①②)
FC="$TMP/fake-chrome"; cat > "$FC" <<'EOT'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in --screenshot=*) printf 'PNG' > "${a#--screenshot=}" ;; esac; done
EOT
chmod +x "$FC"
FKP="$TMP/fkp"; mkdir -p "$FKP/node_modules/playwright-core" "$TMP/empty-h"
cat > "$FKP/node_modules/playwright-core/index.js" <<'EOT'
// 가짜 Playwright — 계측 호출(fn.name === 'measureLayout')에만 FAKE_LAYOUT 을 돌려준다. 연 URL·폭을 FAKE_PW_LOG 에 남긴다
const fs = require('fs');
const L = process.env.FAKE_LAYOUT ? JSON.parse(process.env.FAKE_LAYOUT) : { clip: [], overlap: [] };
const log = (o) => { if (process.env.FAKE_PW_LOG) fs.appendFileSync(process.env.FAKE_PW_LOG, JSON.stringify(o) + '\n'); };
exports.chromium = { launch: async () => ({ newContext: async (opts) => { log({ width: opts.viewport.width }); return { newPage: async () => ({ on() {},
  goto: async (u) => { log({ url: u }); },
  evaluate: async (fn) => { if (typeof fn === 'function' && fn.name === 'measureLayout') { if (process.env.FAKE_LAYOUT_THROW) throw new Error('layout boom'); return L; } return false; },
  screenshot: async ({ path: p }) => fs.writeFileSync(p, 'x'), addScriptTag: async () => {} }), close: async () => {} }; }, close: async () => {} }) };
EOT
shot() { SCREEN_SHOT_CHROME="$FC" bash "$SS" "$H" "$1" 2>&1; }
cntf() { awk -v k="$2" 'index($0, k) { n++ } END { print n + 0 }' "$1"; }   # 파일에서 문자열이 든 줄 수(런타임에 만들어지는 로그 줄이라 소스에 리터럴이 없다)
if ! command -v node >/dev/null 2>&1; then echo "SKIP T6g~T6m (node 없음)"; else
  out=$(DEVFSD_UI_HARNESS_DIR="$TMP/empty-h" shot "$TMP/p1"); rc=$?
  [ "$rc" -eq 0 ] && [ -s "$TMP/p1.probe.txt" ] && grep -q '^UI-PROBE: SKIP (NO_TOOL' "$TMP/p1.probe.txt" && [ "$(wc -l < "$TMP/p1.probe.txt" | tr -d ' ')" = 1 ] && printf '%s\n' "$out" | grep -qxF "SCREEN-PROBE: $TMP/p1.probe.txt" \
    && ok "T6g 계측 도구 없음 — 촬영 rc 는 그대로 0 · probe.txt 에 SKIP 한 줄 · SCREEN-PROBE 줄" || no "T6g" "rc=$rc [$out] [$(cat "$TMP/p1.probe.txt" 2>&1)]"
  : > "$TMP/pw.log"
  out=$(DEVFSD_UI_HARNESS_DIR="$FKP" FAKE_PW_LOG="$TMP/pw.log" FAKE_LAYOUT='{"clip":["<table> — <div.card> 안에서 512px 가려짐"],"overlap":[]}' shot "$TMP/p2"); rc=$?
  [ "$rc" -eq 0 ] && [ "$(grep -c 'L-CLIP-X' "$TMP/p2.probe.txt")" = 2 ] && ! grep -qE '^UI-PROBE:|png:' "$TMP/p2.probe.txt" \
    && ok "T6h 적중 — probe.txt 에 폭마다 경고 줄만(판정 줄·png 줄 없음)" || no "T6h" "rc=$rc [$(cat "$TMP/p2.probe.txt" 2>&1)]"
  [ "$(cntf "$TMP/pw.log" '{"width":390}')" = 1 ] && [ "$(cntf "$TMP/pw.log" '{"width":1280}')" = 1 ] && [ "$(cntf "$TMP/pw.log" 'width')" = 2 ] && [ "$(cntf "$TMP/pw.log" "{\"url\":\"file://$H\"}")" = 2 ] \
    && ok "T6i 계측은 찍은 그 화면을 390·1280 두 폭으로 연다(인자 전달)" || no "T6i" "[$(cat "$TMP/pw.log")]"
  DEVFSD_UI_HARNESS_DIR="$FKP" shot "$TMP/p2" >/dev/null
  [ "$(sed -n 1p "$TMP/p2.probe.txt")" = '배치 경고 0건 (390·1280 폭 · 화면을 연 상태 기준 · 세로 잘림과 불투명한 층에 덮인 글자는 재지 않는다)' ] && ! grep -q 'L-CLIP-X' "$TMP/p2.probe.txt" \
    && ok "T6j 다시 찍으면 덮어쓴다 — 적중이 사라지면 0건 한 줄" || no "T6j" "[$(cat "$TMP/p2.probe.txt" 2>&1)]"
  out=$(DEVFSD_UI_HARNESS_DIR="$FKP" FAKE_LAYOUT_THROW=1 shot "$TMP/p5"); rc=$?
  [ "$rc" -eq 0 ] && [ "$(grep -c '계측 중 오류: layout boom' "$TMP/p5.probe.txt")" = 2 ] && ! grep -q '0건' "$TMP/p5.probe.txt" \
    && ok "T6k 계측 예외 — probe.txt 에 '계측 못 함' 줄이 남고 0건으로 바뀌지 않는다" || no "T6k" "rc=$rc [$(cat "$TMP/p5.probe.txt" 2>&1)]"
  echo stale > "$TMP/p3.probe.txt"; echo stale > "$TMP/p4.probe.txt"   # 낡은 파일이 남지 않는지 본다
  out=$(SCREEN_SHOT_PROBE=0 DEVFSD_UI_HARNESS_DIR="$FKP" shot "$TMP/p3"); rc=$?
  [ "$rc" -eq 0 ] && [ ! -e "$TMP/p3.probe.txt" ] && ! printf '%s' "$out" | grep -q 'SCREEN-PROBE' && [ "$(printf '%s\n' "$out" | grep -c '^SCREEN-SHOT: ')" = 2 ] \
    && ok "T6l SCREEN_SHOT_PROBE=0 — 계측 안 함 · 낡은 파일도 지워짐 · 촬영 출력은 종전과 같다" || no "T6l" "rc=$rc [$out]"
  out=$(SCREEN_SHOT_CHROME=/nonexistent/chrome DEVFSD_UI_HARNESS_DIR="$FKP" bash "$SS" "$H" "$TMP/p4" 2>&1); rc=$?
  [ "$rc" -eq 3 ] && [ ! -e "$TMP/p4.probe.txt" ] && ok "T6m 찍지 못하면(rc 3) 계측 파일이 없다 — 낡은 파일도 지워짐" || no "T6m" "rc=$rc"
  # T6n~T6p — 접근성(대비) 결과도 probe.txt 에 남는다 — 목업 단계에서 고치게 (20261114: 생성 3화면 전부 대비 위반인데 촬영 계측이 말해 주지 않았다)
  FKA="$TMP/fka"; mkdir -p "$FKA/node_modules/axe-core"; cp -R "$FKP/node_modules/playwright-core" "$FKA/node_modules/"; : > "$FKA/node_modules/axe-core/index.js"; : > "$FKA/node_modules/axe-core/axe.min.js"
  sed -i.bak -e 's|evaluate: async (fn) => {|evaluate: async (fn, arg) => {|' -e 's|return false; },|if (Array.isArray(arg)) return process.env.FAKE_A11Y ? JSON.parse(process.env.FAKE_A11Y) : []; return false; },|' "$FKA/node_modules/playwright-core/index.js"
  DEVFSD_UI_HARNESS_DIR="$FKA" FAKE_A11Y='[{"id":"color-contrast","impact":"serious","nodes":2,"help":"H3","detail":[{"t":".badge-warning","c":"#9a6700 / #f3ede0 = 4.17 (기준 4.5:1)"}]},{"id":"region","impact":"moderate","nodes":1,"help":"H4"}]' shot "$TMP/p6" >/dev/null
  r1=1; sed -n 1p "$TMP/p6.probe.txt" | grep -q '^배치 경고 0건' && sed -n 2p "$TMP/p6.probe.txt" | grep -qE '@1280 접근성 serious color-contrast\(2곳\): H3$' && r1=0   # 배치 줄이 먼저, 접근성 줄이 그 뒤
  grep -qF '      · .badge-warning — 글자 / 배경 #9a6700 / #f3ede0 = 4.17' "$TMP/p6.probe.txt"; r2=$?; grep -q 'region' "$TMP/p6.probe.txt"; r3=$?
  [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$r3" -ne 0 ] && ok "T6n ★ 접근성 심각 위반 — 위반 줄과 요소 상세가 probe.txt 에(경미한 것은 빼고)" || no "T6n" "[$(cat "$TMP/p6.probe.txt" 2>&1)]"
  sed -i.bak 's|goto: async (u) => { log({ url: u }); },|goto: async (u) => { log({ url: u }); if (process.env.FAKE_GOTO_FAIL) throw new Error("boom"); },|' "$FKA/node_modules/playwright-core/index.js"
  DEVFSD_UI_HARNESS_DIR="$FKA" FAKE_GOTO_FAIL=1 shot "$TMP/p8" >/dev/null
  grep -qxF '접근성 계측 못 함 (화면을 열지 못했다 — 위반 없음이 아니다)' "$TMP/p8.probe.txt" && ! grep -q '접근성 심각 0건' "$TMP/p8.probe.txt" \
    && ok "T6s ★ 화면을 열지 못한 계측 — 접근성을 0건으로 쓰지 않는다" || no "T6s" "[$(cat "$TMP/p8.probe.txt" 2>&1)]"
  DEVFSD_UI_HARNESS_DIR="$FKA" shot "$TMP/p6" >/dev/null
  [ "$(sed -n 2p "$TMP/p6.probe.txt")" = '접근성 심각 0건 (1280 폭 · 대비 포함 WCAG 2.1 AA)' ] && [ "$(wc -l < "$TMP/p6.probe.txt" | tr -d ' ')" = 2 ] \
    && ok "T6o 위반이 없으면 0건 한 줄(잰 폭을 적는다)" || no "T6o" "[$(cat "$TMP/p6.probe.txt" 2>&1)]"
  echo stale > "$TMP/p7@390.full.png"; out=$(DEVFSD_UI_HARNESS_DIR="$FKP" shot "$TMP/p7")
  [ "$(cat "$TMP/p7@390.full.png")" = x ] && [ "$(cat "$TMP/p7@1280.full.png")" = x ] && [ "$(printf '%s\n' "$out" | grep -c '^SCREEN-SHOT-FULL: ')" = 2 ] && [ "$(printf '%s\n' "$out" | grep -c '^SCREEN-SHOT: ')" = 2 ] \
    && ok "T6q ★ 화면 전체 촬영 — 계측이 찍은 전체 높이 PNG 를 <접두>@<폭>.full.png 로 남긴다(고정 높이 촬영은 긴 화면 아래쪽을 못 본다)" || no "T6q" "[$out]"
  out=$(DEVFSD_UI_HARNESS_DIR="$TMP/empty-h" shot "$TMP/p7")
  [ ! -e "$TMP/p7@390.full.png" ] && [ ! -e "$TMP/p7@1280.full.png" ] && ! printf '%s' "$out" | grep -q 'SCREEN-SHOT-FULL' && ok "T6r 계측 도구가 없으면 전체 촬영도 없다 — 낡은 파일을 남기지 않는다" || no "T6r" "[$out]"
  DEVFSD_UI_HARNESS_DIR="$FKP" shot "$TMP/p7" >/dev/null
  [ "$(sed -n 2p "$TMP/p7.probe.txt")" = '접근성 계측 못 함 (axe-core 없음 — 위반 없음이 아니다)' ] && ok "T6p axe-core 없음 — 0건으로 쓰지 않는다" || no "T6p" "[$(cat "$TMP/p7.probe.txt" 2>&1)]"
fi

# T7 — frontend-design 원문을 그대로 들여왔다(Apache-2.0 고지·라이선스 사본) + devFSD 보충 지침
FD="$PLUGIN/templates/frontend-design-guide.md"; FDL="$PLUGIN/templates/frontend-design-LICENSE.txt"
miss=""; for n in '# Frontend Design' 'Work in two passes' 'Spend your boldness in one place' 'the SaaS-card kit' 'taking screenshots to review' 'Errors don'"'"'t apologize'; do grep -qF -- "$n" "$FD" || miss="$miss [$n]"; done
[ -z "$miss" ] && ok "T7a frontend-design 원문 핵심 문장 6종 그대로" || no "T7a" "없음:$miss"
grep -qF 'Apache License 2.0' "$FD" && grep -qF '원문 그대로' "$FD" && grep -qF 'Apache License' "$FDL" && grep -qF 'Version 2.0' "$FDL" \
  && ok "T7b 출처·Apache 2.0 고지 + 라이선스 전문 사본" || no "T7b" "출처 고지 또는 LICENSE 사본 없음"
miss=""; for n in 'frontend-design-guide.md' 'frontend-design 원문이 우선' '판단 지원' '증감' '진행·대비 막대' 'check-mock-css.sh' 'screen-shot.sh' '확인한 척하지 않는다'; do grep -qF -- "$n" "$G" || miss="$miss [$n]"; done
[ -z "$miss" ] && ok "T7c 보충 지침 — 원문 우선 · 판단 지원 · 토큰 이름(이식 검사) · 촬영 · 정직" || no "T7c" "없음:$miss"
grep -qF '강조색은 화면당 한 곳' "$G" && no "T7d" "지나친 절제 규칙(강조 한 곳)이 남아 있다 — 블라인드 비교에서 판단 지원 부족의 원인" || ok "T7d '강조색은 화면당 한 곳' 규칙 제거"

# T8 — 생성 지시 3곳 연결 (Step 5.5 · /design-screen · /design-screens)
for f in skills/specifying-ko/SKILL.md commands/design-screen.md commands/design-screens.md; do
  grep -qF 'frontend-design-guide.md' "$PLUGIN/$f" && grep -qF 'screen-design-guide.md' "$PLUGIN/$f" && grep -qF 'screen-shot.sh' "$PLUGIN/$f" \
    && ok "T8 $f — frontend-design 원문 → 보충 → 찍고 다듬기" || no "T8 $f" "원문·보충·촬영 연결 없음"
done

# T9 — 색 대비: 템플릿 기본 토큰과 디자인 방향 9종의 상태색이 글자로 쓰여도 WCAG AA(4.5)를 넘는다 (20261114 실측: 경고색 #9A6700 이 자기 옅은 배경 위에서 4.17 — 생성 3화면 7곳 위반의 유일한 원인)
if ! command -v python3 >/dev/null 2>&1; then echo "SKIP T9 (python3 없음)"; else
  out=$(python3 - "$H" "$PLUGIN/templates/design-directions.md" <<'PY'
import re, sys
def rgb(h): h = h.lstrip('#'); return [int(h[i:i+2], 16) for i in (0, 2, 4)]
def lum(c):
    f = lambda v: v/12.92 if v <= 0.03928 else ((v+0.055)/1.055)**2.4
    r, g, b = [f(x/255) for x in c]; return 0.2126*r + 0.7152*g + 0.0722*b
def cr(a, b): la, lb = lum(a), lum(b); return (max(la, lb)+0.05)/(min(la, lb)+0.05)
def mix(fg, bg, p): return [round(f*p + b*(1-p)) for f, b in zip(fg, bg)]
bad = []; n = 0
html = open(sys.argv[1], encoding='utf-8').read()
tok = dict(re.findall(r'--color-([a-z-]+):\s*(#[0-9A-Fa-f]{6})', html))
softp = {k: int(v)/100 for k, v in re.findall(r'--color-([a-z]+)-soft:\s*color-mix\(in srgb, var\(--color-[a-z]+\) (\d+)%', html)}
for name in ('warning', 'error', 'success', 'primary'):
    c = rgb(tok[name]); p = softp[name]
    for under in ('panel', 'bg', 'surface'):
        v = cr(c, mix(c, rgb(tok[under]), p)); n += 1
        if v < 4.5: bad.append('template %s on %s-soft@%s %.2f' % (name, name, under, v))
    for under in ('panel', 'bg', 'surface'):
        v = cr(c, rgb(tok[under])); n += 1
        if v < 4.5: bad.append('template %s on %s %.2f' % (name, under, v))
    v = cr(c, mix(rgb(tok['primary']), rgb(tok['panel']), softp['primary'])); n += 1   # 선택된 행(주색 옅은 배경) 위의 상태 글자
    if v < 4.5: bad.append('template %s on primary-soft %.2f' % (name, v))
rows = [l for l in open(sys.argv[2], encoding='utf-8') if re.match(r'\| \d+ \|', l)]
for l in rows:
    c = [x.strip() for x in l.strip().strip('|').split('|')]
    BG, SF, T2, ER, OK = rgb(c[9]), rgb(c[10]), rgb(c[12]), rgb(c[14]), rgb(c[15])
    for nm, col, p in (('Text Secondary', T2, 0), ('Error', ER, softp['error']), ('Success', OK, softp['success'])):
        for bn, bg in (('Background', BG), ('Surface', SF)):
            v = cr(col, bg); n += 1
            if v < 4.5: bad.append('dir %s %s on %s %.2f' % (c[0], nm, bn, v))
            if p:
                v = cr(col, mix(col, bg, p)); n += 1
                if v < 4.5: bad.append('dir %s %s on soft@%s %.2f' % (c[0], nm, bn, v))
print('rows=%d pairs=%d bad=%d' % (len(rows), n, len(bad)))
for b in bad: print('  ' + b)
PY
)
  printf '%s\n' "$out" | sed -n 1p | grep -qE '^rows=9 pairs=[0-9]+ bad=0$' && ok "T9a ★ 템플릿 토큰 4색 × 배경 7종 · 방향 9종 상태색·보조 글자 — 전부 대비 4.5 이상" || no "T9a" "$out"
  grep -qF '대비 4.5' "$G" && grep -qF '접근성 serious color-contrast' "$G" && ok "T9b 보충 지침 — 색 글자 대비 기준과 촬영 계측의 대비 줄" || no "T9b" "지침에 대비 규칙 없음"
  miss=""; for n in '좁은 폭(390)' 'white-space: nowrap' '세로 목록' '행 카드' '.full.png' '지우지 않는다' '막대 높이만큼' '첫 화면 높이 자리'; do grep -qF -- "$n" "$G" || miss="$miss [$n]"; done
  [ -z "$miss" ] && ok "T9c 보충 지침 — 좁은 폭 규칙(줄바꿈·차트·행 카드는 값을 지우지 않음·고정 막대 아래 여백)과 전체 촬영의 고정 요소 읽는 법 (20261114 블라인드: 좁은 폭 최약 · 재측정에서 행 카드 정보 손실)" || no "T9c" "없음:$miss"
fi

echo "── test-screen-design: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
