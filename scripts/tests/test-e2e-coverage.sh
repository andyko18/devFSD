#!/usr/bin/env bash
# 실제 브라우저 시나리오 — 커버리지 판정(e2e-coverage.sh)과 실행 판정(e2e-run.sh) (20261119 · 선택 기능)
#
# 왜 필요한가: 이 판정이 틀리면 ① 꺼 둔 프로젝트가 게이트에 막히거나 ② 분모를 줄여(AC 를 빼거나 사유 없이 제외해) 95% 를
#   채운 것처럼 보이거나 ③ 못 돌린 것·실패한 것이 PASS 로 적힌다. 실 브라우저·실 node 시나리오는 부르지 않는다(stub).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0

COV="$PLUGIN/scripts/_internal/e2e-coverage.sh"
RUN="$PLUGIN/scripts/_internal/e2e-run.sh"
F=20261119-e2e-x
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P); trap 'rm -rf "$TMP"' EXIT
unset DEVFSD_BROWSER_E2E DEVFSD_E2E_MIN_COVERAGE DEVFSD_E2E_TIMEOUT_SEC SPECOPS_ROOT SPECOPS_CONFIG DEVFSD_UI_HARNESS_DIR

# 하류 구조 픽스처: AC 4개(화면 2 · 백엔드 1 · 해당 없음 1) + 시나리오 파일 1개(AC-1 만 덮음)
_mk() {
  local sb; sb=$(mktemp -d "$TMP/sb.XXXXXX") || return 1
  mkdir -p "$sb/.specops/$F" "$sb/frontend/e2e" "$sb/frontend/node_modules/pkg"
  printf '# AC\n\n### AC-1: 로그인 화면\n\n### AC-2: 메뉴 이동\n\n### AC-3: 토큰 검증\n\n### AC-R-1: 기존 동작 보존\n' > "$sb/.specops/$F/acceptance-criteria.md"
  printf 'AC-1 browser\nAC-2 browser\nAC-3 backend — 서버 응답만 본다\nAC-R-1 none — 빌드 설정 검사\n' > "$sb/.specops/$F/e2e-scope.txt"
  printf '// FID: %s\ntest("@AC-1 로그인 링크가 보인다", () => {})\n' "$F" > "$sb/frontend/e2e/login.e2e.mjs"
  printf '%s' "$sb"
}
_cov() { ( cd "$1" && shift && "$@" bash "$COV" "$F" 2>&1 ); }
_on() { printf 'browser_e2e:\n  enabled: true\n' > "$1/.specops/config.yaml"; }

# ── C: 커버리지 판정 ─────────────────────────────────────────────────────
out=$(_cov "$(_mk)" env); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q '^E2E-COVERAGE: SKIP (OFF' && ok "C1 ★ 켜지 않으면 판정하지 않는다(SKIP · rc 3)" || nope "C1" "rc=$rc out=$out"

sb=$(_mk); _on "$sb"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | tail -n 1 | grep -q '^E2E-COVERAGE: FAIL (화면 AC 1/2 = 50% · 기준 95% · 백엔드 1 · 해당 없음 1)$' \
  && printf '%s' "$out" | grep -q '  - AC-2 시나리오 없음' && ok "C2 화면 AC 2개 중 1개만 덮음 → FAIL 50% · 빠진 AC 를 짚는다" || nope "C2" "rc=$rc out=$out"

printf '// FID: %s\ntest("@AC-2 메뉴", () => {})\n' "$F" > "$sb/frontend/e2e/menu.e2e.mjs"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^E2E-COVERAGE: PASS (화면 AC 2/2 = 100%' && ok "C3 전부 덮음 → PASS 100%" || nope "C3" "rc=$rc out=$out"

sb=$(_mk); _on "$sb"
out=$(_cov "$sb" env DEVFSD_E2E_MIN_COVERAGE=50); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '기준 50%' && ok "C4 기준은 환경변수로 낮출 수 있다(50% → PASS)" || nope "C4" "rc=$rc out=$out"
printf 'browser_e2e:\n  enabled: true\n  min_coverage: 40   # 시범\n' > "$sb/.specops/config.yaml"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '기준 40%' && ok "C5 기준은 config 로도 정한다(주석 달린 값)" || nope "C5" "rc=$rc out=$out"

# 분모 줄이기 차단
sb=$(_mk); _on "$sb"; printf 'AC-1 browser\nAC-3 backend — 서버\nAC-R-1 none — 빌드\n' > "$sb/.specops/$F/e2e-scope.txt"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '분류 안 된 AC 1건' && printf '%s' "$out" | grep -q '  - AC-2 분류 없음' \
  && ok "C6 ★ 분류에서 빠진 AC 가 있으면 FAIL(AC 를 빼서 100% 를 만들 수 없다)" || nope "C6" "rc=$rc out=$out"
sb=$(_mk); _on "$sb"; printf 'AC-1 browser\nAC-2 backend\nAC-3 backend — 서버\nAC-R-1 none — 빌드\n' > "$sb/.specops/$F/e2e-scope.txt"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '사유 없는 제외 1건' && ok "C7 ★ 사유 없이 backend·none 으로 뺀 AC 가 있으면 FAIL" || nope "C7" "rc=$rc out=$out"

# 다른 FID 의 시나리오·표지 없는 파일·node_modules 안의 파일은 세지 않는다
sb=$(_mk); _on "$sb"
printf '// FID: 20261119-other\ntest("@AC-2 남의 것", () => {})\n' > "$sb/frontend/e2e/other.e2e.mjs"
printf 'test("@AC-2 표지 없음", () => {})\n' > "$sb/frontend/e2e/nomark.e2e.mjs"
printf '// FID: %s\ntest("@AC-2 의존성 안", () => {})\n' "$F" > "$sb/frontend/node_modules/pkg/x.e2e.mjs"
printf '// FID: %s-extra\ntest("@AC-2 이름이 앞부분만 같은 FID", () => {})\n' "$F" > "$sb/frontend/e2e/prefix.e2e.mjs"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '화면 AC 1/2' && ok "C8 ★ 다른 FID · 표지 없는 파일 · node_modules · 앞부분만 같은 FID 는 세지 않는다" || nope "C8" "rc=$rc out=$out"

sb=$(_mk); _on "$sb"; printf '// FID: %s\ntest("@AC-1 a @AC-2 b @AC-9 없는 번호", () => {})\n' "$F" > "$sb/frontend/e2e/login.e2e.mjs"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'AC-9 태그가 가리키는 AC 가 문서에 없다' && ok "C9 문서에 없는 AC 태그는 경고만(판정은 그대로)" || nope "C9" "rc=$rc out=$out"

sb=$(_mk); _on "$sb"; rm "$sb/.specops/$F/e2e-scope.txt"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'SKIP (NO_SCOPE' && ok "C10 분류 파일이 없으면 SKIP(NO_SCOPE) — PASS 가 아니다" || nope "C10" "rc=$rc out=$out"
sb=$(_mk); _on "$sb"; printf 'AC-1 backend — a\nAC-2 backend — b\nAC-3 backend — c\nAC-R-1 none — d\n' > "$sb/.specops/$F/e2e-scope.txt"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'SKIP (NO_BROWSER_AC' && ok "C11 화면 AC 가 0개면 SKIP(NO_BROWSER_AC) — 0/0 을 100% 로 치지 않는다" || nope "C11" "rc=$rc out=$out"
out=$(cd "$(_mk)" && bash "$COV" "$F" --force 2>&1); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '화면 AC 1/2' && ok "C12 --force 는 꺼져 있어도 센다" || nope "C12" "rc=$rc out=$out"
out=$(cd "$(_mk)" && bash "$COV" "../x" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "C13 FID 에 경로 문자 → 사용법 오류(rc 2)" || nope "C13" "rc=$rc out=$out"

# ── R: 실행 판정 (node stub — TAP 요약만 흉내낸다) ───────────────────────
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/node" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_ARGS"
printf 'harness=%s\n' "${DEVFSD_UI_HARNESS_DIR-unset}" >> "$STUB_ARGS"
case "${STUB_MODE:-pass}" in
  pass) printf 'ok 1 - @AC-1 a\n# tests 3\n# pass 2\n# fail 0\n# todo 1\n' ;;
  fail) printf 'not ok 1 - @AC-1 링크가 Space 로 열린다\nnot ok 2 - @AC-2 보류 # TODO 사유\n# tests 3\n# pass 1\n# fail 1\n# todo 1\n'; exit 1 ;;
  zero) printf '# tests 0\n# pass 0\n# fail 0\n# todo 0\n' ;;
  crash) echo 'SyntaxError: boom'; exit 1 ;;
  hang) sleep 30 ;;
esac
EOF
chmod +x "$BIN/node"
export STUB_ARGS="$TMP/args.log"
_run() { ( cd "$1" && shift && PATH="$BIN:$PATH" "$@" bash "$RUN" "$F" 2>&1 ); }

sb=$(_mk); : > "$STUB_ARGS"
out=$(_run "$sb" env STUB_MODE=pass); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | tail -n 1 | grep -q '^E2E-RUN: PASS (3개 · 통과 2 · 판정 보류 1)$' && ok "R1 전부 통과 → PASS · 판정 보류 수를 드러낸다" || nope "R1" "rc=$rc out=$out"
grep -q -- '--test' "$STUB_ARGS" && grep -q 'login.e2e.mjs' "$STUB_ARGS" && grep -q '^harness=.*ui-harness$' "$STUB_ARGS" && [ -s "$sb/.specops/$F/e2e/run.txt" ] \
  && ok "R2 node --test 로 이 FID 파일을 돌리고 · 공용 캐시 위치를 넘기고 · 전문을 run.txt 에 남긴다" || nope "R2" "$(cat "$STUB_ARGS")"
out=$(_run "$(_mk)" env STUB_MODE=fail); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | tail -n 1 | grep -q '^E2E-RUN: FAIL (3개 · 통과 1 · 실패 1 · 판정 보류 1)$' \
  && printf '%s' "$out" | grep -q '  - @AC-1 링크가 Space 로 열린다' && ! printf '%s' "$out" | grep -q '@AC-2 보류' \
  && ok "R3 ★ 실패 → FAIL · 실패한 시나리오 이름만(판정 보류는 실패 목록에 넣지 않는다)" || nope "R3" "rc=$rc out=$out"
out=$(_run "$(_mk)" env STUB_MODE=crash); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^E2E-RUN: FAIL (실행 실패' && ok "R4 ★ 요약 없이 죽으면 FAIL(PASS 로 읽지 않는다)" || nope "R4" "rc=$rc out=$out"
out=$(_run "$(_mk)" env STUB_MODE=zero); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'SKIP (NO_SPEC' && ok "R5 ★ 0개 실행은 PASS 가 아니라 SKIP" || nope "R5" "rc=$rc out=$out"
sb=$(_mk); rm "$sb/frontend/e2e/login.e2e.mjs"
out=$(_run "$sb" env); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'SKIP (NO_SPEC' && ok "R6 이 FID 의 시나리오 파일이 없으면 SKIP(NO_SPEC)" || nope "R6" "rc=$rc out=$out"
out=$(_run "$(_mk)" env STUB_MODE=hang DEVFSD_E2E_TIMEOUT_SEC=2); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'SKIP (TIMEOUT' && ok "R7 상한을 넘기면 SKIP(TIMEOUT) — 멈춘 채 두지 않는다" || nope "R7" "rc=$rc out=$out"
out=$(cd "$(_mk)" && PATH="/usr/bin:/bin" bash "$RUN" "$F" 2>&1); rc=$?
if command -v node >/dev/null 2>&1 && PATH="/usr/bin:/bin" command -v node >/dev/null 2>&1; then
  skip "R8 이 환경은 /usr/bin 에 node 가 있어 '없음' 경로를 재현하지 못한다"
else
  [ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'SKIP (NO_TOOL' && ok "R8 node 가 없으면 SKIP(NO_TOOL)" || nope "R8" "rc=$rc out=$out"
fi

# ── K: 배선 ──────────────────────────────────────────────────────────────
D="$PLUGIN/skills/integration-test-ko/browser-e2e.md"
grep -q 'browser-e2e.md' "$PLUGIN/skills/integration-test-ko/SKILL.md" && [ -f "$D" ] \
  && ok "K1 integration-test-ko 가 절차 문서를 가리킨다" || nope "K1" "배선 없음"
grep -q 'e2e-coverage.sh' "$D" && grep -q 'e2e-run.sh' "$D" && grep -q 'e2e-scope.txt' "$D" && grep -q 'templates/e2e-support.mjs' "$D" \
  && ok "K2 절차 문서 — 분류 · 실행 · 커버리지 · 지원 모듈" || nope "K2" "절차 누락"
grep -q 'PASS 로 적지 않는다' "$D" && grep -q '약하게 고치지 않는다' "$D" && ok "K3 절차 문서 — SKIP 은 PASS 가 아니다 · 실패한 시나리오를 약하게 고치지 않는다" || nope "K3" "문구 없음"
[ -f "$PLUGIN/templates/e2e-support.mjs" ] && grep -q 'export function loadPlaywright' "$PLUGIN/templates/e2e-support.mjs" && grep -q 'export async function startServer' "$PLUGIN/templates/e2e-support.mjs" \
  && ok "K4 지원 모듈 템플릿 — Playwright 탐색 · 서버 기동" || nope "K4" "템플릿 없음"
if command -v node >/dev/null 2>&1; then
  node --check "$PLUGIN/templates/e2e-support.mjs" 2>/dev/null && ok "K5 지원 모듈 템플릿 문법" || nope "K5" "문법 오류"
else
  skip "K5 node 없음 — 템플릿 문법 검사 생략"
fi

echo ""
finish
