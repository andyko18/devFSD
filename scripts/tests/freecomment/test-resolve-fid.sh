#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
H="$PLUGIN/scripts/freework-resolve-fid.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.specops"
sp="$TMP/.specops/session-progress.md"

# T1: fid 빈값 → NEW
out=$(cd "$TMP" && bash "$H" "" 2>/dev/null)
[ "$out" = "NEW" ] && { PASS=$((PASS+1)); echo "PASS T1 빈fid→NEW"; } || { FAIL=$((FAIL+1)); echo "FAIL T1 (out=$out)"; }

# T2: 진행 중 FID (종결마커 없음) → ATTACH (AC-R-5)
cat > "$sp" <<'EOF'
## 20260625-active-feat
- 2026-06-25 10:00 /implement 진행 (T1 작성)
EOF
out=$(cd "$TMP" && bash "$H" "20260625-active-feat" 2>/dev/null)
[ "$out" = "ATTACH:20260625-active-feat" ] && { PASS=$((PASS+1)); echo "PASS T2 진행중→ATTACH"; } || { FAIL=$((FAIL+1)); echo "FAIL T2 (out=$out)"; }

# T3: 종결된 FID (PR 마커) → NEW (AC-R-6)
cat > "$sp" <<'EOF'
## 20260625-done-feat
- 2026-06-25 09:25 /lifecycle DONE (PR #113 생성 완료)
- 2026-06-25 09:08 /implement DONE
EOF
out=$(cd "$TMP" && bash "$H" "20260625-done-feat" 2>/dev/null)
[ "$out" = "NEW" ] && { PASS=$((PASS+1)); echo "PASS T3 종결PR→NEW"; } || { FAIL=$((FAIL+1)); echo "FAIL T3 (out=$out)"; }

# T4: 종결마커 /finish DONE → NEW
cat > "$sp" <<'EOF'
## 20260625-fin-feat
- 2026-06-25 11:00 /finish DONE (branch 정리)
EOF
out=$(cd "$TMP" && bash "$H" "20260625-fin-feat" 2>/dev/null)
[ "$out" = "NEW" ] && { PASS=$((PASS+1)); echo "PASS T4 finish→NEW"; } || { FAIL=$((FAIL+1)); echo "FAIL T4 (out=$out)"; }

# T5: 단계완료(/specify 완료)는 종결 아님 → ATTACH
cat > "$sp" <<'EOF'
## 20260625-mid-feat
- 2026-06-25 12:00 /specify 완료 (spec.md)
EOF
out=$(cd "$TMP" && bash "$H" "20260625-mid-feat" 2>/dev/null)
[ "$out" = "ATTACH:20260625-mid-feat" ] && { PASS=$((PASS+1)); echo "PASS T5 단계완료→ATTACH"; } || { FAIL=$((FAIL+1)); echo "FAIL T5 (out=$out)"; }

# T6: 진행중 줄에 본문 "PR #999 참조 중" (생성 인접 아님) → ATTACH (false-positive 방어)
cat > "$sp" <<'EOF'
## 20260625-ref-feat
- 2026-06-25 13:00 /implement 진행 (PR #999 참조 중)
EOF
out=$(cd "$TMP" && bash "$H" "20260625-ref-feat" 2>/dev/null)
[ "$out" = "ATTACH:20260625-ref-feat" ] && { PASS=$((PASS+1)); echo "PASS T6 PR참조중→ATTACH"; } || { FAIL=$((FAIL+1)); echo "FAIL T6 (out=$out)"; }

# T7: 진행중 줄에 "PR 관련 이슈 생성 완료" (#번호+생성 인접 아님) → ATTACH (false-positive 방어)
cat > "$sp" <<'EOF'
## 20260625-issue-feat
- 2026-06-25 14:00 /plan 완료 (PR 관련 이슈 생성 완료)
EOF
out=$(cd "$TMP" && bash "$H" "20260625-issue-feat" 2>/dev/null)
[ "$out" = "ATTACH:20260625-issue-feat" ] && { PASS=$((PASS+1)); echo "PASS T7 이슈생성→ATTACH"; } || { FAIL=$((FAIL+1)); echo "FAIL T7 (out=$out)"; }

# T8: `/finishing 완료` 는 종결이다 — 메타 스킬의 재개 통보가 종결로 치는 목록과 같아야 한다
cat > "$sp" <<'EOF'
## 20260625-fin-feat
- 2026-06-25 15:00 /finishing 완료 (브랜치 정리)
- 2026-06-25 14:00 /lifecycle DONE (PR 생성 완료)
EOF
out=$(cd "$TMP" && bash "$H" "20260625-fin-feat" 2>/dev/null)
[ "$out" = "NEW" ] && { PASS=$((PASS+1)); echo "PASS T8 /finishing 완료→NEW"; } || { FAIL=$((FAIL+1)); echo "FAIL T8 (out=$out)"; }
# T9: 진행 중 줄의 '완료' 는 종결이 아니다 (/plan 완료 → ATTACH)
cat > "$sp" <<'EOF'
## 20260625-mid-feat
- 2026-06-25 14:00 /plan 완료 (plan.md)
EOF
out=$(cd "$TMP" && bash "$H" "20260625-mid-feat" 2>/dev/null)
[ "$out" = "ATTACH:20260625-mid-feat" ] && { PASS=$((PASS+1)); echo "PASS T9 /plan 완료→ATTACH"; } || { FAIL=$((FAIL+1)); echo "FAIL T9 (out=$out)"; }
# T10: `DONE (PR …)` 단독형도 종결이다 — 메타 스킬의 종결 목록(/lifecycle DONE · /finishing 완료 · PR #N 생성 · DONE (PR)과 같아야 한다
cat > "$sp" <<'EOF'
## 20260625-pr-feat
- 2026-06-25 16:00 /start DONE (PR 올림)
EOF
out=$(cd "$TMP" && bash "$H" "20260625-pr-feat" 2>/dev/null)
[ "$out" = "NEW" ] && { PASS=$((PASS+1)); echo "PASS T10 DONE (PR …)→NEW"; } || { FAIL=$((FAIL+1)); echo "FAIL T10 (out=$out)"; }

echo "---"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
