#!/usr/bin/env bash
# test-ui-probe.sh — 브라우저 점검 하네스 (20261110-ui-probe)
#   하류 실측: 화면 FID 의 통합 테스트가 브라우저를 돌리지 않고 PASS(6/9) · 화면 이미지 0/35 · 반응형·접근성 실행 검증 0.
#   ① ui-probe.cjs: 인자 오류 rc 2 · 도구 없음 SKIP(NO_TOOL) rc 3(PASS 위장 금지)
#   ② Playwright 가 있는 환경이면 실제로: 깨끗한 화면 PASS · 넘침+콘솔 오류+접근성 critical FAIL · 3폭 PNG
#   ③ integration-test-ko 브라우저 줄 의무 · demo-ko 가 PNG 를 보여 준다
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P="$PLUGIN/scripts/_internal/ui-probe.cjs"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
ok() { PASS=$((PASS+1)); echo "PASS $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL $1 — $2"; }

if ! command -v node >/dev/null 2>&1; then echo "SKIP 전체 (node 없음)"; echo "── test-ui-probe: PASS=$PASS FAIL=$FAIL ──"; exit 0; fi

# U1 — 인자 오류 rc 2
node "$P" >/dev/null 2>&1; [ $? -eq 2 ] && ok "U1 인자 없음 → rc 2" || no "U1" "rc 2 아님"

# U2 — Playwright 를 찾지 못하면 SKIP(NO_TOOL) rc 3 · 설치 안내 · 파일 없음
mkdir -p "$TMP/empty"
out=$(cd "$TMP/empty" && DEVFSD_UI_HARNESS_DIR="$TMP/empty" node "$P" --out "$TMP/o2" "file://$TMP/x.html" 2>&1); rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q '^UI-PROBE: SKIP (NO_TOOL' && printf '%s' "$out" | grep -qF 'npm install --prefix ~/.cache/devfsd/ui-harness' && [ ! -e "$TMP/o2/ui-probe.json" ] \
  && ok "U2 도구 없음 → SKIP(NO_TOOL) rc 3 · 설치 안내 · 결과 파일 없음" || no "U2" "rc=$rc out=[$out]"

# U3 — 실제 브라우저 (Playwright 가 있는 환경만 — 없으면 SKIP 을 적고 위장하지 않는다)
cat > "$TMP/good.html" <<'EOF'
<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>정상</title></head>
<body><main><h1>재고</h1><label for="q">검색</label><input id="q"><button type="button">발주</button></main></body></html>
EOF
cat > "$TMP/bad.html" <<'EOF'
<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>문제</title></head>
<body><main><h1>재고</h1><div style="width:900px">넓은 표</div><button type="button"></button></main><script>console.error("load failed")</script></body></html>
EOF
out=$(node "$P" --out "$TMP/og" "file://$TMP/good.html" 2>&1); rc=$?
if [ "$rc" -eq 3 ]; then echo "SKIP U3 (이 환경에 Playwright·브라우저 없음: $(printf '%s' "$out" | head -1))"
else
  [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^UI-PROBE: PASS (1화면·3폭' && [ -s "$TMP/og/good@375.png" ] && [ -s "$TMP/og/good@768.png" ] && [ -s "$TMP/og/good@1280.png" ] && [ -s "$TMP/og/ui-probe.json" ] \
    && ok "U3a 깨끗한 화면 → PASS rc 0 · 3폭 PNG · ui-probe.json" || no "U3a" "rc=$rc out=[$out]"
  out=$(node "$P" --out "$TMP/ob" "file://$TMP/bad.html" 2>&1); rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '^UI-PROBE: FAIL' && printf '%s' "$out" | grep -qF 'bad@375 가로 넘침' \
    && printf '%s' "$out" | grep -qF '콘솔 오류: load failed' && ! printf '%s' "$out" | grep -qF 'bad@1280 가로 넘침' \
    && ok "U3b 넘침(375·768만)·콘솔 오류 → FAIL rc 1" || no "U3b" "rc=$rc out=[$out]"
  if printf '%s' "$out" | grep -qF '접근성 SKIP'; then echo "SKIP U3c (axe-core 없음)"
  else printf '%s' "$out" | grep -qE 'bad@1280 접근성 critical button-name' && ok "U3c 이름 없는 버튼 → 접근성 critical" || no "U3c" "out=[$out]"; fi
fi

# U4 — 연결: integration-test-ko 브라우저 줄 의무 · demo-ko PNG 표시
INT="$PLUGIN/skills/integration-test-ko/SKILL.md"; DEMO="$PLUGIN/skills/demo-ko/SKILL.md"
miss=""; for n in 'ui-probe.cjs' '**브라우저**: 실행(' '**브라우저**: 미실행(NO_TOOL|NO_ENV|NO_SERVER|USER_SKIP' 'PASS 로 적지 않는다' '375·768·1280'; do grep -qF -- "$n" "$INT" || miss="$miss [$n]"; done
[ -z "$miss" ] && ok "U4a integration-test-ko — 하네스 실행 · 브라우저 줄 의무 · SKIP 위장 금지" || no "U4a" "없음:$miss"
grep -qF '.specops/<FID>/ui/*.png' "$DEMO" && grep -qF 'UI-PROBE:' "$DEMO" && ok "U4b demo-ko — 하네스 PNG·판정 줄을 보여 준다" || no "U4b" "연결 없음"

echo "── test-ui-probe: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
