#!/usr/bin/env bash
# gate-preflight.sh — 보안·통합·성능 게이트 사전 판정 (20261112 speed)
#   계약: 표면이 분명히 없을 때만 SKIP 을 기록하고, 애매하면 APPLY(skill 이 판정). SKIP 근거는 spec 절·줄을 인용한다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
GP="$PLUGIN/scripts/_internal/gate-preflight.sh"
RR="$PLUGIN/scripts/_internal/release-ready.sh"
ok() { PASS=$((PASS+1)); echo "PASS $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL $1 — ${2:-}"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FID=20261112-gp-fixture

# 픽스처: main 에 초기 커밋 → 작업 브랜치에서 변경. $2=spec 본문 · $3.. = 변경할 파일 경로
_mk() {
  local d="$TMP/$1"; shift
  local spec="$1"; shift
  mkdir -p "$d/.specops/$FID" "$d/src"
  ( cd "$d" && git init -q -b main && printf 'x\n' > README.md && printf '.specops/\n' > .gitignore \
    && git add README.md .gitignore && git -c user.name=t -c user.email=t@e.com commit -qm init && git checkout -q -b work ) || return 1
  printf '%s\n' "$spec" > "$d/.specops/$FID/spec.md"
  printf '## %s\n' "$FID" > "$d/.specops/session-progress.md"
  local f
  for f in "$@"; do mkdir -p "$d/$(dirname "$f")"; printf 'changed\n' > "$d/$f"; done
  ( cd "$d" && git add -A && git -c user.name=t -c user.email=t@e.com commit -qm change ) || return 1
  printf '%s' "$d"
}
_run() { ( cd "$1" && shift && bash "$GP" "$@" 2>&1 ); }

SPEC_CLI='# spec
## 1. 목표
줄 수를 세는 명령줄 도구.
## 2. 범위
- 입력 파일의 줄 수를 출력한다
## 5. 비기능 요구 (NFR)
- 셸 스크립트 한 개로 구현한다'
SPEC_API='# spec
## 2. 범위
- 주문 조회 API 엔드포인트를 추가한다
## 5. NFR
- p95 응답 시간 200ms 이하'

# G1 문서만 바꾼 FID → 세 게이트 모두 SKIP, 곧바로 performance-test-ko(PR 게이트)
d=$(_mk g1 "$SPEC_CLI" docs/guide.md)
out=$(_run "$d" "$FID"); rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^GATE security SKIP §2\. 범위 L4-5 ' \
  && printf '%s\n' "$out" | grep -q '^GATE integration SKIP ' && printf '%s\n' "$out" | grep -q '^GATE performance SKIP §5\. 비기능 요구 (NFR) L6-7 ' \
  && printf '%s\n' "$out" | grep -qx 'NEXT: performance-test-ko' \
  && ok "G1 문서 전용 변경 → 3게이트 SKIP(절·줄 인용) · NEXT=performance-test-ko" || no "G1" "rc=$rc out=[$out]"
ev="$d/.specops/$FID/evidence.md"
[ "$(grep -c '^\*\*결과\*\*: SKIP' "$ev" 2>/dev/null)" = 3 ] && grep -q '^## /security-review — ' "$ev" && grep -q '^## /integration-test — ' "$ev" \
  && grep -q '^## /performance-test — ' "$ev" && grep -q '^\*\*근거\*\*: SECURITY: SKIP — §2\. 범위 L4-5' "$ev" \
  && ok "G1b evidence.md 에 게이트별 SKIP 절 3개(게이트 skill 과 같은 제목·근거 형식)" || no "G1b" "$(cat "$ev" 2>/dev/null)"
sp="$d/.specops/session-progress.md"
grep -q '/security-review SKIP' "$sp" && grep -q '/integration-test SKIP' "$sp" && grep -q '/performance-test SKIP' "$sp" \
  && ok "G1c session-progress 에 SKIP 3줄" || no "G1c" "$(cat "$sp")"
# 기록이 release-ready 의 인용 판정(skip::cite_status)을 통과하는 형식인가 — BARE 면 PR 이 막힌다
( . "$PLUGIN/scripts/skip-tracker.sh"; for g in security integration performance; do
    [ "$(skip::verdicts "$ev" "$g" | tail -1)" = SKIP ] || exit 1
    skip::cite_status "$ev" "$g" | grep -qx BARE && exit 1
  done; exit 0 ) && ok "G1d ★ 기록한 SKIP 이 skip-tracker 판독에서 SKIP·CITED (release-ready 가 막지 않는다)" || no "G1d" "판독 불일치"
grep -qx 'security=SKIP' "$d/.specops/$FID/gate-preflight.txt" && ok "G1e 판정 저장(gate-preflight.txt)" || no "G1e"

# G2 재실행 — 이미 기록된 게이트는 다시 쓰지 않는다
out=$(_run "$d" "$FID")
[ "$(grep -c '^## /security-review' "$ev")" = 1 ] && printf '%s\n' "$out" | grep -q '^GATE security RECORDED' && printf '%s\n' "$out" | grep -qx 'NEXT: performance-test-ko' \
  && ok "G2 재실행은 중복 기록하지 않는다(RECORDED) · NEXT 불변" || no "G2" "$out"

# G3 코드 변경 + 통합 낱말 없음 + NFR 임계값 없음 → security 만 APPLY
d=$(_mk g3 "$SPEC_CLI" src/count.sh)
out=$(_run "$d" "$FID")
printf '%s\n' "$out" | grep -q '^GATE security APPLY ' && printf '%s\n' "$out" | grep -q '^GATE integration SKIP ' \
  && printf '%s\n' "$out" | grep -qx 'NEXT: security-review-ko' && ! grep -q '^## /security-review' "$d/.specops/$FID/evidence.md" \
  && ok "G3 코드 변경 → security APPLY(기록 없음) · integration·performance SKIP · NEXT=security-review-ko" || no "G3" "$out"
out=$(_run "$d" "$FID" --next-after security)
[ "$out" = 'NEXT: performance-test-ko' ] && ok "G3b --next-after security → integration 을 건너뛰고 performance-test-ko" || no "G3b" "$out"

# G4 ★ 통합·성능 신호가 있으면 SKIP 하지 않는다(생략 방향 오판 금지)
d=$(_mk g4 "$SPEC_API" src/orders.ts)
out=$(_run "$d" "$FID")
printf '%s\n' "$out" | grep -q '^GATE security APPLY ' && printf '%s\n' "$out" | grep -q '^GATE integration APPLY ' && printf '%s\n' "$out" | grep -q '^GATE performance APPLY ' \
  && [ ! -s "$d/.specops/$FID/evidence.md" ] && printf '%s\n' "$out" | grep -qx 'NEXT: security-review-ko' \
  && ok "G4 ★ API·p95 신호 → 3게이트 APPLY · 아무것도 기록하지 않는다" || no "G4" "$out"
out=$(_run "$d" "$FID" --next-after security); [ "$out" = 'NEXT: integration-test-ko' ] && ok "G4b --next-after security → integration-test-ko" || no "G4b" "$out"

# G5 ★ 경로만으로도 통합 신호(spec 에 낱말이 없어도 routes/ 를 고치면 APPLY)
d=$(_mk g5 "$SPEC_CLI" src/routes/orders.js)
out=$(_run "$d" "$FID"); printf '%s\n' "$out" | grep -q '^GATE integration APPLY ' && ok "G5 ★ 변경 경로(routes/)가 통합 신호" || no "G5" "$out"

# G6 ★ 근거 절을 못 찾으면 SKIP 하지 않는다 — 범위·NFR 절 없는 spec + 문서 전용 변경
d=$(_mk g6 '# spec
그냥 본문만 있다' docs/a.md)
out=$(_run "$d" "$FID")
! printf '%s\n' "$out" | grep -q ' SKIP ' && printf '%s\n' "$out" | grep -qx 'NEXT: security-review-ko' && [ ! -s "$d/.specops/$FID/evidence.md" ] \
  && ok "G6 ★ 인용할 절이 없으면 전부 APPLY(인용 없는 SKIP 을 만들지 않는다)" || no "G6" "$out"

# G7 판정 불가 → rc 1, 아무것도 쓰지 않는다 (§batch · spec 부재 · FID 오류 · 저장 판정 없음)
d=$(_mk g7 "**§batch**: true
$SPEC_CLI" docs/a.md)
out=$(_run "$d" "$FID"); rc=$?
[ "$rc" = 1 ] && [ ! -e "$d/.specops/$FID/evidence.md" ] && [ ! -e "$d/.specops/$FID/gate-preflight.txt" ] && ok "G7 §batch → rc 1 · 무기록" || no "G7" "rc=$rc $out"
rm -f "$d/.specops/$FID/spec.md"; _run "$d" "$FID" >/dev/null; [ $? = 1 ] && ok "G7b spec.md 부재 → rc 1" || no "G7b"
_run "$d" "not-a-fid" >/dev/null; [ $? = 1 ] && ok "G7c FID 형식 오류 → rc 1" || no "G7c"
_run "$d" "$FID" --next-after security >/dev/null; [ $? = 1 ] && ok "G7d 저장된 판정 없음 → --next-after rc 1" || no "G7d"

# G8 ★ 직전 판정이 FAIL 인 게이트는 건너뛰지 않는다
d=$(_mk g8 "$SPEC_CLI" docs/guide.md)
printf '\n## /security-review — 2026-11-12T00:00:00Z\n\n**결과**: FAIL\n**근거**: crit=1\n' > "$d/.specops/$FID/evidence.md"
out=$(_run "$d" "$FID")
printf '%s\n' "$out" | grep -q '^GATE security APPLY ' && printf '%s\n' "$out" | grep -qx 'NEXT: security-review-ko' \
  && ok "G8 ★ 직전 security FAIL → APPLY (SKIP 으로 덮지 않는다)" || no "G8" "$out"

# G9 플러그인 repo 에서는 skill 문서가 코드다 — 문서 전용으로 보지 않는다
d=$(_mk g9 "$SPEC_CLI" skills/x-ko/SKILL.md .claude-plugin/plugin.json)
out=$(_run "$d" "$FID"); printf '%s\n' "$out" | grep -q '^GATE security APPLY ' && ok "G9 플러그인 repo 의 SKILL.md 변경 → security APPLY" || no "G9" "$out"

# ── 문서 잠금: verify 가 사전 판정을 부르고, 게이트 skill 이 저장된 판정으로 다음을 고른다 ──
V="$PLUGIN/skills/verifying-evidence-ko/SKILL.md"; S="$PLUGIN/skills/security-review-ko/SKILL.md"; P="$PLUGIN/skills/performance-test-ko/SKILL.md"
grep -qF 'scripts/_internal/gate-preflight.sh <FID>' "$V" && grep -qF '`NEXT:` 줄의 skill 을 호출한다' "$V" && grep -qF 'rc 1 이면' "$V" \
  && ok "D1 verifying-evidence-ko 가 gate-preflight 를 부르고 NEXT 를 따른다(rc 1 은 종전 경로)" || no "D1"
grep -qF 'gate-preflight.sh <FID> --next-after security' "$S" && ok "D2 security-review-ko 가 --next-after 로 다음 게이트를 고른다" || no "D2"
grep -qF 'gate-preflight.sh' "$P" && grep -qF '판정을 다시 하지 않고' "$P" && ok "D3 performance-test-ko 가 사전 SKIP 기록을 재판정하지 않는다" || no "D3"
grep -q '{from: verifying-evidence-ko, to: security-review-ko}' "$PLUGIN/hooks/chain.yaml" \
  && ! grep -q '{from: verifying-evidence-ko, to: requesting-code-review-ko}' "$PLUGIN/hooks/chain.yaml" \
  && ok "D4 chain primary edge: verifying-evidence-ko → security-review-ko" || no "D4"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
