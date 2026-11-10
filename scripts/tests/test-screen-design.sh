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
  [ "$(cat "$TMP/p2.probe.txt")" = '배치 경고 0건 (390·1280 폭 · 화면을 연 상태 기준 · 세로 잘림과 불투명한 층에 덮인 글자는 재지 않는다)' ] \
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

echo "── test-screen-design: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
