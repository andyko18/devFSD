#!/usr/bin/env bash
# test-batch-plan-digest.sh — Phase 2 짧은 digest 스크립트
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || exit 1
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCRIPT="$PLUGIN/scripts/_internal/batch-plan-digest.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.specops/batch-d" \
  "$TMP/.specops/20260101-a" "$TMP/.specops/20260101-b"
cat > "$TMP/.specops/batch-d/queue.md" <<'EOF'
| FR-ID | FID | 설명 | Status |
|---|---|---|---|
| FR-1 | 20260101-a | one | PLAN_DONE |
| FR-2 | 20260101-b | two | PLAN_DONE |
EOF
printf '**§유형**: feature\n' > "$TMP/.specops/20260101-a/spec.md"
: > "$TMP/.specops/20260101-a/plan.md"
cat > "$TMP/.specops/20260101-a/tasks.md" <<'EOF'
```yaml
tasks:
  - id: T1
    ac: [AC-1]
  - id: T2
    ac: [AC-2]
```
EOF
printf '**§유형**: foundation\n' > "$TMP/.specops/20260101-b/spec.md"
: > "$TMP/.specops/20260101-b/plan.md"
# b: tasks missing

out=$(bash "$SCRIPT" "$TMP/.specops/batch-d" 2>&1); code=$?

[ "$code" -eq 0 ] && ok "T1 exit 0" || nope "T1" "exit=$code"
echo "$out" | grep -q '20260101-a' && echo "$out" | grep -q 'feature' \
  && ok "T2 FID+유형" || nope "T2" "$out"
echo "$out" | grep -qE '20260101-a \| feature \| 2 \|' \
  && ok "T3 태스크수 2" || nope "T3" "$out"
echo "$out" | grep -q '20260101-b' && echo "$out" | grep -q 'missing' \
  && ok "T4 tasks missing" || nope "T4" "$out"
# 본문 덤프 금지 — plan.md 내용이 출력에 없어야 (파일은 비어 있음)
! echo "$out" | grep -qi '구현 플랜' \
  && ok "T5 본문 미덤프" || nope "T5" "본문 의심"

finish
