#!/usr/bin/env bash
# specops-ko v0.1 smoke test · FID 20260420-count-artifacts
# scripts/_internal/count-artifacts.sh 의 AC-1~AC-6 검증
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
SCRIPT="bash ./scripts/_internal/count-artifacts.sh"

# T1 usage (AC-4)
err=$($SCRIPT 2>&1 >/dev/null) ; rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'usage:'; then
  PASS=$((PASS+1)); echo "PASS T1 usage"
else
  FAIL=$((FAIL+1)); echo "FAIL T1 usage (rc=$rc, err=$err)"
fi

# T2 경로 미존재 (AC-3)
err=$($SCRIPT /nonexistent/ghost 2>&1 >/dev/null) ; rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'not found'; then
  PASS=$((PASS+1)); echo "PASS T2 not-found"
else
  FAIL=$((FAIL+1)); echo "FAIL T2 not-found (rc=$rc, err=$err)"
fi

# T3a 정상: 3 .md + 1 하위디렉토리 (AC-1)
tmp=$(mktemp -d)
: > "$tmp/spec.md"; : > "$tmp/plan.md"; : > "$tmp/tasks.md"
mkdir "$tmp/subdir"
out=$($SCRIPT "$tmp") ; rc=$?
if [ "$out" = "3" ] && [ $rc -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T3a count=3"
else
  FAIL=$((FAIL+1)); echo "FAIL T3a count=3 (out=$out rc=$rc)"
fi
rm -rf "$tmp"

# T3b 빈 폴더 (AC-2)
tmp=$(mktemp -d)
out=$($SCRIPT "$tmp") ; rc=$?
if [ "$out" = "0" ] && [ $rc -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T3b empty=0"
else
  FAIL=$((FAIL+1)); echo "FAIL T3b empty=0 (out=$out rc=$rc)"
fi
rm -rf "$tmp"

# T3c 혼합 .md와 비.md (AC-5)
tmp=$(mktemp -d)
: > "$tmp/spec.md"; : > "$tmp/plan.md"; : > "$tmp/notes.txt"; : > "$tmp/config.yaml"
out=$($SCRIPT "$tmp") ; rc=$?
if [ "$out" = "2" ] && [ $rc -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T3c mixed=2"
else
  FAIL=$((FAIL+1)); echo "FAIL T3c mixed=2 (out=$out rc=$rc)"
fi
rm -rf "$tmp"

# T3d 재귀 차단 (AC-6)
tmp=$(mktemp -d)
: > "$tmp/top.md"
mkdir "$tmp/sub"
: > "$tmp/sub/inner.md"
out=$($SCRIPT "$tmp") ; rc=$?
if [ "$out" = "1" ] && [ $rc -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T3d no-recurse=1"
else
  FAIL=$((FAIL+1)); echo "FAIL T3d no-recurse=1 (out=$out rc=$rc)"
fi
rm -rf "$tmp"

# T4 실행권한 부여 (인프라)
if [ -x scripts/_internal/count-artifacts.sh ]; then
  PASS=$((PASS+1)); echo "PASS T4 exec-bit"
else
  FAIL=$((FAIL+1)); echo "FAIL T4 exec-bit (scripts/_internal/count-artifacts.sh not executable)"
fi

echo "passed=$PASS failed=$FAIL"
exit $FAIL
