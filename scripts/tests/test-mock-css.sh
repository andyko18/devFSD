#!/usr/bin/env bash
# test-mock-css.sh — 목업 CSS 이식 (20261109-mock-css-transplant)
#   디자인 진단: 같은 날 만든 두 앱이 목업 클래스 생존율 8%(stock-mng — 입력·버튼 14/14 가 브라우저 기본 모양)와 91%(media)로 갈렸다.
#   갈린 이유는 계획서가 우연히 "목업 토큰을 합친다" 고 적었는지 여부뿐이었다 — 이식 지시·검사가 체인에 없었다.
#   ① check-mock-css.sh: 목업(screens/*.html <style>)에 정의된 클래스 중 앱 CSS 에 살아남은 비율(경고 전용)
#   ② planning-ko · plan-reviewer-ko · demo-ko · implementing-ko 의 연결 문구
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
CHK="$PLUGIN/scripts/_internal/check-mock-css.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
ok() { PASS=$((PASS+1)); echo "PASS $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL $1 — $2"; }

_mock() {  # $1=repo — 목업 클래스 4개(card · btn · grid · badge) + url 안의 .png(클래스 아님) + 숫자 .5(클래스 아님)
  mkdir -p "$1/screens"
  cat > "$1/screens/home.html" <<'EOF'
<html><head><style>
  :root { --c: #fff; }
  .card { padding: 16px; transition: opacity .5s; }
  .btn, .btn:hover { border-radius: 8px; background: url(bg.png); }
  .grid > .badge { gap: 1.5rem; }
</style></head><body><div class="card"><button class="btn">x</button></div></body></html>
EOF
}

# M1 — 절반 생존: card·btn 만 앱 CSS 에 있다 → 50% (2/4), 경고 아님(문턱 미만이 아니다)
r="$TMP/m1"; _mock "$r"; mkdir -p "$r/web/app"; printf '.card{padding:16px}\n.btn{border-radius:8px}\n' > "$r/web/app/globals.css"
out=$(bash "$CHK" "$r" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^MOCK-CSS: OK 50% (2/4)' && ok "M1 생존 2/4 → OK 50% · png·숫자는 클래스로 세지 않음" || no "M1" "rc=$rc out=[$out]"

# M2 — 전멸에 가까움: card 만 → 25% WARN, 빠진 클래스 이름을 댄다
r="$TMP/m2"; _mock "$r"; mkdir -p "$r/web/app"; printf '.card{padding:16px}\nbody{margin:0}\n' > "$r/web/app/globals.css"
out=$(bash "$CHK" "$r" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^MOCK-CSS: WARN 25% (1/4)' && printf '%s' "$out" | grep -q 'badge' && printf '%s' "$out" | grep -q 'btn' \
  && ok "M2 생존 1/4 → WARN 25% + 빠진 클래스 목록 · 차단하지 않음(rc 0)" || no "M2" "rc=$rc out=[$out]"

# M3 — node_modules·.next·screens 아래 CSS 는 앱 CSS 가 아니다 (거기 있어도 생존으로 세지 않는다)
r="$TMP/m3"; _mock "$r"; mkdir -p "$r/node_modules/x" "$r/.next/s" "$r/web"
printf '.card{}.btn{}.grid{}.badge{}\n' > "$r/node_modules/x/a.css"; cp "$r/node_modules/x/a.css" "$r/.next/s/b.css"; cp "$r/node_modules/x/a.css" "$r/screens/x.css"
printf 'body{margin:0}\n' > "$r/web/app.css"
out=$(bash "$CHK" "$r" 2>&1)
printf '%s' "$out" | grep -q '^MOCK-CSS: WARN 0% (0/4)' && ok "M3 node_modules·.next·screens 의 CSS 는 제외" || no "M3" "out=[$out]"

# M4 — Tailwind 앱은 클래스 이름이 목업과 달라 생존율로 볼 수 없다 → SKIP(사유)
r="$TMP/m4"; _mock "$r"; mkdir -p "$r/web"; printf '@tailwind base;\n' > "$r/web/globals.css"
out=$(bash "$CHK" "$r" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^MOCK-CSS: SKIP (Tailwind' && ok "M4 Tailwind → SKIP(사유)" || no "M4" "rc=$rc out=[$out]"

# M5 — 목업 없음 / 앱 CSS 없음 → SKIP(사유) · 조용한 OK 금지
r="$TMP/m5"; mkdir -p "$r"; out=$(bash "$CHK" "$r" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^MOCK-CSS: SKIP (목업 없음' && ok "M5a 목업 없음 → SKIP" || no "M5a" "rc=$rc out=[$out]"
r="$TMP/m5b"; _mock "$r"; out=$(bash "$CHK" "$r" 2>&1)
printf '%s' "$out" | grep -q '^MOCK-CSS: SKIP (앱 CSS 없음' && ok "M5b 앱 CSS 없음 → SKIP" || no "M5b" "out=[$out]"

# M6 — 인자 오류는 rc 2
bash "$CHK" "$TMP/없는-폴더" >/dev/null 2>&1; [ $? -eq 2 ] && ok "M6 없는 폴더 → rc 2" || no "M6" "rc 2 아님"

# W — 연결 문구 (계획 첫 태스크 · 리뷰어 점검 · 데모에서 실행 · 최소 구현 예외)
grep -qF '목업 CSS 이식' "$PLUGIN/skills/planning-ko/SKILL.md" && grep -qF '**첫 태스크**' "$PLUGIN/skills/planning-ko/SKILL.md" \
  && ok "W1 planning-ko — 화면 FID 는 목업 CSS 이식을 첫 태스크로" || no "W1" "planning-ko 규칙 없음"
grep -qF '목업 CSS 이식' "$PLUGIN/agents/plan-reviewer-ko.md" && ok "W2 plan-reviewer-ko — 이식 태스크 점검" || no "W2" "plan-reviewer-ko 점검 없음"
grep -qF 'check-mock-css.sh' "$PLUGIN/skills/demo-ko/SKILL.md" && ok "W3 demo-ko — 화면 종류에서 생존율 검사 실행" || no "W3" "demo-ko 연결 없음"
grep -qF '화면 CSS 는 목업이 기준' "$PLUGIN/skills/implementing-ko/SKILL.md" && ok "W4 implementing-ko — 화면 CSS 는 최소 구현 대상 아님" || no "W4" "implementing-ko 문구 없음"

echo "── test-mock-css: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
