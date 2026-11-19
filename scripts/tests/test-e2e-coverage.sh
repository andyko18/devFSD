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
unset DEVFSD_BROWSER_E2E DEVFSD_BROWSER_E2E_MODE DEVFSD_E2E_MIN_COVERAGE DEVFSD_E2E_TIMEOUT_SEC SPECOPS_ROOT SPECOPS_CONFIG SPECOPS CONFIG DEVFSD_UI_HARNESS_DIR

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
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '기준 95%' && printf '%s' "$out" | grep -q '환경변수로 기준을 낮출 수 없다(95% → 50% 무시)' \
  && ok "C4 ★ 환경변수로는 기준을 낮출 수 없다(명령 앞에 값을 붙여 통과시키지 못한다)" || nope "C4" "rc=$rc out=$out"
printf '// FID: %s\ntest("@AC-2 메뉴", () => {})\n' "$F" > "$sb/frontend/e2e/menu.e2e.mjs"
out=$(_cov "$sb" env DEVFSD_E2E_MIN_COVERAGE=100); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '기준 100%' && ok "C4b 환경변수로 기준을 올리는 것은 된다" || nope "C4b" "rc=$rc out=$out"
rm "$sb/frontend/e2e/menu.e2e.mjs"
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

# ── M: 모드 (off · observe · enforce) ───────────────────────────────────
_mode() { printf 'browser_e2e:\n  mode: %s\n' "$2" > "$1/.specops/config.yaml"; }
sb=$(_mk); _mode "$sb" observe
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | tail -n 1 | grep -q '^E2E-COVERAGE: OBSERVE (막았을 것 — 화면 AC 1/2 = 50%' \
  && ok "M1 ★ 관찰 모드 — 기준 미달이어도 막지 않는다(rc 0 · OBSERVE 줄)" || nope "M1" "rc=$rc out=$out"
[ "$(jq -r 'select(.kind=="coverage") | "\(.fid) \(.would_block)"' "$sb/.specops/e2e-observe.jsonl" 2>/dev/null)" = "$F true" ] \
  && ok "M2 ★ 막았을 판정을 e2e-observe.jsonl 에 남긴다" || nope "M2" "$(cat "$sb/.specops/e2e-observe.jsonl" 2>&1)"
printf '// FID: %s\ntest("@AC-2 메뉴", () => {})\n' "$F" > "$sb/frontend/e2e/menu.e2e.mjs"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^E2E-COVERAGE: PASS (.*관찰 모드)$' && [ "$(jq -r .would_block "$sb/.specops/e2e-observe.jsonl" | tail -n 1)" = false ] \
  && ok "M3 관찰 모드에서 통과한 판정도 기록한다(수율을 세려면 분모가 필요하다)" || nope "M3" "rc=$rc out=$out"
sb=$(_mk); _mode "$sb" observe; printf 'AC-1 browser\n' > "$sb/.specops/$F/e2e-scope.txt"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'OBSERVE (막았을 것 — 분류 안 된 AC 3건' && ok "M4 관찰 모드 — 분류 누락도 막지 않고 기록" || nope "M4" "rc=$rc out=$out"
sb=$(_mk); _mode "$sb" enforce
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^E2E-COVERAGE: FAIL' && [ ! -e "$sb/.specops/e2e-observe.jsonl" ] && ok "M5 enforce — 막는다 · 관찰 기록은 쓰지 않는다" || nope "M5" "rc=$rc out=$out"
sb=$(_mk); _mode "$sb" off
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'SKIP (OFF' && ok "M6 mode: off → SKIP" || nope "M6" "rc=$rc out=$out"
sb=$(_mk); _mode "$sb" obzerve
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 1 ] && ok "M7 ★ 모르는 mode 값은 enforce 로 읽는다(오타로 게이트가 꺼지지 않게)" || nope "M7" "rc=$rc out=$out"
sb=$(_mk); printf 'browser_e2e:\n  enabled: true\n  mode: observe\n' > "$sb/.specops/config.yaml"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'OBSERVE' && ok "M8 mode 가 있으면 옛 enabled 보다 mode 를 따른다" || nope "M8" "rc=$rc out=$out"
sb=$(_mk); _mode "$sb" observe
out=$(_cov "$sb" env DEVFSD_BROWSER_E2E_MODE=enforce); rc=$?
[ "$rc" = 1 ] && ok "M9 환경변수로 모드를 올릴 수 있다(observe → enforce)" || nope "M9" "rc=$rc out=$out"
sb=$(_mk); _mode "$sb" enforce
out=$(_cov "$sb" env DEVFSD_BROWSER_E2E_MODE=observe); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '환경변수로 mode 를 낮출 수 없다' && ok "M10 ★ 환경변수로 모드를 낮출 수 없다(enforce → observe 무시)" || nope "M10" "rc=$rc out=$out"
out=$(_cov "$sb" env); printf '%s' "$out" | grep -q '게이트 설정 출처: 작업 트리(기준 브랜치와 대조하지 못했다' \
  && ok "M11 config 가 추적되지 않으면 대조하지 못했다고 알린다(조용히 넘어가지 않는다)" || nope "M11" "$out"

# ── G: 변경이 자기 심사 기준을 느슨하게 바꾸지 못한다 (기준 브랜치 대조) ─────
#   픽스처: config 가 추적되는 저장소 · main 에 기준 설정을 커밋 · 작업 브랜치에서 config 를 바꾼다
_mkgit() {  # <main 의 config 본문(printf 꼴) | 빈 문자열이면 config 없음>
  local sb; sb=$(_mk) || return 1
  ( cd "$sb" && git init -q -b main . && git config user.name t && git config user.email t@example.invalid \
    && { [ -z "$1" ] || printf "$1" > .specops/config.yaml; } && git add -A . && git commit -q -m base && git switch -q -c work ) >/dev/null 2>&1 || return 1
  printf '%s' "$sb"
}
sb=$(_mkgit 'browser_e2e:\n  mode: enforce\n  min_coverage: 95\n')
printf 'browser_e2e:\n  mode: enforce\n  min_coverage: 40\n' > "$sb/.specops/config.yaml"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'min_coverage 를 95 → 40 으로 낮췄다 — 기준 브랜치 값(95%)을 쓴다' && printf '%s' "$out" | grep -q '기준 95%' \
  && ok "G1 ★ 같은 변경에서 기준을 95→40 으로 낮춰도 기준 브랜치 값으로 판정한다" || nope "G1" "rc=$rc out=$out"
( cd "$sb" && git add -A . && git commit -q -m lower ) >/dev/null 2>&1
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '기준 95%' && ok "G2 ★ 낮춘 설정을 작업 브랜치에 커밋해도 마찬가지다(갈림점의 값을 본다)" || nope "G2" "rc=$rc out=$out"
sb=$(_mkgit 'browser_e2e:\n  mode: enforce\n')
printf 'browser_e2e:\n  mode: observe\n' > "$sb/.specops/config.yaml"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'mode 를 enforce → observe 로 느슨하게 바꿨다' && ok "G3 ★ enforce → observe 로 내려도 기준 브랜치의 enforce 로 막는다" || nope "G3" "rc=$rc out=$out"
printf 'browser_e2e:\n  mode: off\n' > "$sb/.specops/config.yaml"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 1 ] && ok "G4 ★ 같은 변경에서 게이트를 꺼도(off) 꺼지지 않는다" || nope "G4" "rc=$rc out=$out"
rm "$sb/.specops/config.yaml"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'SKIP (OFF' && skip "G5 추적되던 config 를 지우면 대조 대상이 사라져 꺼진다(알려진 한계 — 삭제는 diff 에 드러난다)" \
  || { [ "$rc" = 1 ] && ok "G5 config 를 지워도 기준 브랜치 값으로 막는다" || nope "G5" "rc=$rc out=$out"; }
sb=$(_mkgit 'browser_e2e:\n  mode: observe\n  min_coverage: 50\n')
printf 'browser_e2e:\n  mode: enforce\n  min_coverage: 95\n' > "$sb/.specops/config.yaml"
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^E2E-COVERAGE: FAIL (.*기준 95%' && ! printf '%s' "$out" | grep -q '게이트 설정:' \
  && ok "G6 엄하게 바꾸는 것(observe→enforce · 50→95)은 바로 적용된다 · 알림 없음" || nope "G6" "rc=$rc out=$out"
sb=$(_mkgit '')
printf 'browser_e2e:\n  mode: enforce\n  min_coverage: 50\n' > "$sb/.specops/config.yaml"; ( cd "$sb" && git add -A . ) >/dev/null 2>&1
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '기준 50%' && ok "G7 처음 켜는 변경은 스스로 기준을 정한다(기준 브랜치에 게이트가 없었다)" || nope "G7" "rc=$rc out=$out"
sb=$(_mkgit 'browser_e2e:\n  mode: enforce\n  min_coverage: 95\n')
out=$(_cov "$sb" env); rc=$?
[ "$rc" = 1 ] && ! printf '%s' "$out" | grep -q '게이트 설정' && ok "G8 설정을 안 건드리면 알림 없이 종전대로 판정" || nope "G8" "rc=$rc out=$out"

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
sb=$(_mk); _mode "$sb" observe
out=$(_run "$sb" env STUB_MODE=fail); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | tail -n 1 | grep -q '^E2E-RUN: OBSERVE (막았을 것 — 3개 · 통과 1 · 실패 1' && printf '%s' "$out" | grep -q '  - @AC-1 링크가 Space 로 열린다' \
  && [ "$(jq -r 'select(.kind=="run") | .would_block' "$sb/.specops/e2e-observe.jsonl" 2>/dev/null)" = true ] \
  && ok "R9 ★ 관찰 모드 — 시나리오가 실패해도 막지 않고(rc 0) 실패 이름과 기록을 남긴다" || nope "R9" "rc=$rc out=$out"
out=$(_run "$sb" env STUB_MODE=crash); rc=$?
[ "$rc" = 1 ] && ok "R10 관찰 모드여도 실행 자체가 죽으면 FAIL(판정할 결과가 없다)" || nope "R10" "rc=$rc out=$out"
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
grep -q 'OBSERVE' "$D" && grep -q '기준 브랜치' "$D" && grep -q 'e2e-observe.jsonl' "$D" && ok "K3b 절차 문서 — 관찰 모드 처리 · 기준 브랜치 규칙 · 관찰 기록" || nope "K3b" "문구 없음"
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
