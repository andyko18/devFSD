#!/usr/bin/env bash
# test-tdd-red-evidence.sh — TDD RED 증거 규약 문구 계약 (FID 20260711-tdd-red-evidence)
# 앵커 리터럴: "RED 실측 출력" · "FAIL 라인 ≤10줄" — drift 시 FAIL (의도적 경직, T9 선례)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0

TDD="$PLUGIN/skills/tdd-ko/SKILL.md"
IMP="$PLUGIN/agents/implementer-ko.md"
VER="$PLUGIN/skills/verifying-evidence-ko/SKILL.md"
DCX="$PLUGIN/templates/dispatch-context.md"
TSK="$PLUGIN/templates/tasks.md"

# ── T1: 앵커 "RED 실측 출력" 5소비처 존재 (AC-1·3·6) ──
for f in "$TDD" "$IMP" "$VER" "$DCX" "$TSK"; do
  b=$(basename "$(dirname "$f")")/$(basename "$f")
  grep -q 'RED 실측 출력' "$f" \
    && ok "T1 앵커 존재 — $b" || nope "T1 앵커" "$b 에 'RED 실측 출력' 없음"
done

# ── T2: 발췌 상한 리터럴 5소비처 존재 (AC-7) ──
for f in "$TDD" "$IMP" "$VER" "$DCX" "$TSK"; do
  b=$(basename "$(dirname "$f")")/$(basename "$f")
  grep -q 'FAIL 라인 ≤10줄' "$f" \
    && ok "T2 상한 존재 — $b" || nope "T2 상한" "$b 에 'FAIL 라인 ≤10줄' 없음"
done

# ── T3: 죽은 self-check 잔존 0 (AC-2) ──
if grep -q 'git log로 증명' "$IMP"; then
  nope "T3.a implementer-ko" "'git log로 증명' 잔존 (죽은 self-check — 단일커밋 구조상 항상 불충족)"
else
  ok "T3.a implementer-ko 'git log로 증명' 잔존 0"
fi

# ── T4: tdd-ko 합리화 차단표 행 (AC-1) ──
grep -q '카운트 요약이면 충분' "$TDD" \
  && ok "T4.a tdd-ko 차단표 행 존재" || nope "T4.a 차단표" "'카운트 요약이면 충분' 변명 행 없음"

# ── T5: test_command SSOT (AC-4) ──
if grep -E 'test_command.*optional' "$TSK" >/dev/null; then
  nope "T5.a tasks.md" "test_command 'optional' 주석 잔존 (emit-context 게이트와 모순)"
else
  ok "T5.a tasks.md 'optional' 잔존 0"
fi
n_id=$(grep -c '^  - id:' "$TSK"); n_id=${n_id:-0}
n_tc=$(grep -c '^    test_command:' "$TSK"); n_tc=${n_tc:-0}
[ "$n_id" -ge 1 ] && [ "$n_id" -eq "$n_tc" ] \
  && ok "T5.b 예시 YAML 전 task test_command ($n_id/$n_tc)" \
  || nope "T5.b 예시" "task=$n_id test_command=$n_tc 불일치"
if grep '^    test_command:' "$TSK" | grep -E '&&|\|' >/dev/null; then
  nope "T5.c compound" "test_command 에 &&/파이프 (whitelist 부적합 — gbrain 20260709)"
else
  ok "T5.c test_command plain bash (compound 0)"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
