#!/usr/bin/env bash
# test-session-start-reconcile.sh — SessionStart 훅의 재개 desync 자동표면화 배선 테스트
# 배경: 훅은 session-progress 최신 블록을 재수화 주입한다. desync 시 그 블록이 과소보고 →
#   재개 모델이 "미구현" 오판 (dogfood test1 FR-3, 24h 정체). 훅이 reconcile-check --hook 을
#   자동 실행해 DESYNC 경고+재개점을 <session-progress-reconcile> 로 함께 주입하는지 검증.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HOOK="$PLUGIN/hooks/session-start.sh"

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

ok() { PASS=$((PASS+1)); echo "PASS $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL $1 — $2"; }

# ── S1: DESYNC FID (progress=/tasks, 증거=implement+verify) → 훅 출력에 reconcile DESYNC 주입 ──
mkdir -p "$TMP/s1/.specops/20260104-desync"
( cd "$TMP/s1"
  printf '## 20260104-desync · stalled\n\n- 2026-01-04T00:00:00Z /tasks 완료 (tasks.md)\n' > .specops/session-progress.md
  touch .specops/20260104-desync/spec.md .specops/20260104-desync/plan.md .specops/20260104-desync/tasks.md
  printf '| 1 | ts | A:T1 | implementer-ko | DONE | x |\n' > .specops/20260104-desync/dispatch-log.md
  printf 'RUN-VERIFICATION-RESULT: PASS\n' > .specops/20260104-desync/evidence.md
)
out=$( cd "$TMP/s1" && bash "$HOOK" 2>/dev/null ); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'session-progress-reconcile' \
   && printf '%s' "$out" | grep -qiE 'DESYNC|과소보고'; then
  ok "S1 desync 자동표면화 주입"
else no "S1" "rc=$rc out=[$(printf '%s' "$out" | head -c 400)]"; fi

# ── S2: in-sync FID (progress=/specify, 증거=spec.md) → reconcile 주입 없음 (오탐 0) ──
mkdir -p "$TMP/s2/.specops/20260105-sync"
( cd "$TMP/s2"
  printf '## 20260105-sync · ok\n\n- 2026-01-05T00:00:00Z /specify 완료 (spec.md)\n' > .specops/session-progress.md
  touch .specops/20260105-sync/spec.md
)
out=$( cd "$TMP/s2" && bash "$HOOK" 2>/dev/null ); rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qF 'session-progress-reconcile'; then
  ok "S2 정합 주입 없음"
else no "S2" "rc=$rc out=[$(printf '%s' "$out" | head -c 400)]"; fi

# ── S3: .specops 없음 → 훅 크래시 없이 유효 JSON (메타skill 주입 유지) ──
mkdir -p "$TMP/s3"
out=$( cd "$TMP/s3" && bash "$HOOK" 2>/dev/null ); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'hookSpecificOutput' \
   && ! printf '%s' "$out" | grep -qF 'session-progress-reconcile'; then
  ok "S3 no-specops 안전"
else no "S3" "rc=$rc out=[$(printf '%s' "$out" | head -c 400)]"; fi

# ── S4: 정합 + 산출물 불완전 → 완결성 notice 주입, DESYNC 단언 금지 ──
# 20260807-reconcile-completeness: `--hook` 은 DESYNC 없이 완결성 경고만 반환할 수 있게 됐다.
# 종전 notice 는 무조건 "과소보고 중… 재개점부터 진행하라" 로 단언해, 과소보고도 재개점도
# 없는 상태에서 거짓 지시가 매 세션 주입됐다(Phase C Important).
mkdir -p "$TMP/s4/.specops/20260106-warnonly"
( cd "$TMP/s4"
  printf '## 20260106-warnonly · ok\n\n- 2026-01-06T00:00:00Z /plan 완료 (plan.md)\n' > .specops/session-progress.md
  touch .specops/20260106-warnonly/spec.md .specops/20260106-warnonly/clarifications.md
  printf '# plan\n## 1. 가정\n' > .specops/20260106-warnonly/plan.md   # heading-end 불완전
)
out=$( cd "$TMP/s4" && bash "$HOOK" 2>/dev/null ); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'session-progress-reconcile' \
   && printf '%s' "$out" | grep -qF '불완전 가능' \
   && printf '%s' "$out" | grep -qF '완결성 힌트' \
   && ! printf '%s' "$out" | grep -qF '과소보고 중'; then
  ok "S4 경고-only → 완결성 notice (DESYNC 거짓단언 없음)"
else no "S4" "rc=$rc out=[$(printf '%s' "$out" | head -c 500)]"; fi

echo "── test-session-start-reconcile: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
