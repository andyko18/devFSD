#!/usr/bin/env bash
# Wave 2 U5 (FID 20260514) — Phase B/C cap=2 정합 검증 (dispatch-log fixture 시뮬레이션)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PLUGIN=$(dirname "$PLUGIN")

# helper: dispatch-log.md fixture 의 task-id 블록 footer 의 cap 카운트 추출
extract_cap() {
  local f="$1"
  local task="$2"
  awk -v t="## $task" '
    $0 ~ t {found=1; next}
    found && /재시도 누적/ {print; exit}
    /^## task-/ && found {exit}
  ' "$f"
}

# T1.a: B 1회 FAIL → 재dispatch PASS → footer B=1/2 C=0/2
tmp=$(mktemp -d)
cat > "$tmp/log.md" << 'LOG'
# Dispatch Log — fid-fixture

## task-1: component-a

| # | 시각 | Phase | agent | 결과 | feedback 경로 |
|---|---|---|---|---|---|
| 1 | 2026-05-14T10:00 | A | implementer-ko | PASS | - |
| 2 | 2026-05-14T10:01 | B | spec-reviewer-ko | FAIL | reviews/task-1-B-feedback.md |
| 3 | 2026-05-14T10:02 | A (재) | implementer-ko | PASS | - |
| 4 | 2026-05-14T10:03 | B (재) | spec-reviewer-ko | PASS | - |

**재시도 누적: B=1/2 C=0/2 (cap=2)**

---
LOG
out=$(extract_cap "$tmp/log.md" "task-1")
if [[ "$out" == *"B=1/2"* && "$out" == *"C=0/2"* && "$out" == *"cap=2"* ]]; then
  PASS=$((PASS+1)); echo "PASS T1.a B=1/2 (재dispatch 후 PASS)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a (out='$out')"
fi

# T1.b: B 2회 모두 FAIL → cap 초과 footer B=2/2 + HARD GATE 라인
cat > "$tmp/log.md" << 'LOG'
## task-1: component-a

| # | 시각 | Phase | agent | 결과 | feedback 경로 |
|---|---|---|---|---|---|
| 1 | 2026-05-14T10:00 | A | implementer-ko | PASS | - |
| 2 | 2026-05-14T10:01 | B | spec-reviewer-ko | FAIL | reviews/task-1-B-feedback.md |
| 3 | 2026-05-14T10:02 | A (재) | implementer-ko | PASS | - |
| 4 | 2026-05-14T10:03 | B (재) | spec-reviewer-ko | FAIL | reviews/task-1-B-feedback.md |

**재시도 누적: B=2/2 C=0/2 (cap=2 EXCEEDED — HARD GATE)**

---
LOG
out=$(extract_cap "$tmp/log.md" "task-1")
if [[ "$out" == *"B=2/2"* && "$out" == *"EXCEEDED"* ]]; then
  PASS=$((PASS+1)); echo "PASS T1.b B=2/2 EXCEEDED"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b (out='$out')"
fi

# T1.c: C cap 초과 footer C=2/2
cat > "$tmp/log.md" << 'LOG'
## task-2: component-b

| # | 시각 | Phase | agent | 결과 | feedback 경로 |
|---|---|---|---|---|---|
| 1 | 2026-05-14T10:00 | A | implementer-ko | PASS | - |
| 2 | 2026-05-14T10:01 | B | spec-reviewer-ko | PASS | - |
| 3 | 2026-05-14T10:02 | C | code-reviewer-ko | FAIL | reviews/task-2-C-feedback.md |
| 4 | 2026-05-14T10:03 | A (재) | implementer-ko | PASS | - |
| 5 | 2026-05-14T10:04 | C (재) | code-reviewer-ko | FAIL | reviews/task-2-C-feedback.md |

**재시도 누적: B=0/2 C=2/2 (cap=2 EXCEEDED — HARD GATE)**

---
LOG
out=$(extract_cap "$tmp/log.md" "task-2")
if [[ "$out" == *"C=2/2"* && "$out" == *"EXCEEDED"* ]]; then
  PASS=$((PASS+1)); echo "PASS T1.c C=2/2 EXCEEDED"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.c (out='$out')"
fi

# T1.d: implementing-ko 본문이 cap=2 + HARD GATE 메시지 정의 (D1 정합)
F="$PLUGIN/skills/implementing-ko/SKILL.md"
if grep -q "cap=2" "$F" \
  && grep -qE "HARD-GATE.*Phase B" "$F" \
  && grep -qE "HARD-GATE.*Phase C" "$F"; then
  PASS=$((PASS+1)); echo "PASS T1.d implementing-ko 본문 cap=2 + HARD GATE"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.d implementing-ko 본문 정합 실패"
fi

rm -rf "$tmp"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
