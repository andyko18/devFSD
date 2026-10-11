#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$PLUGIN/scripts/slug.sh"

# T1.a --help → exit 0 + "Usage" 출력
out=$("$SCRIPT" --help 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "Usage"; then
  PASS=$((PASS+1)); echo "PASS T1.a --help"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a (rc=$rc out=$out)"
fi

# T2.a "Hello World" → "hello-world"
out=$("$SCRIPT" "Hello World"); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "hello-world" ]; then
  PASS=$((PASS+1)); echo "PASS T2.a uppercase"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.a (got='$out')"
fi

# T2.b "  hello   world  " → "hello-world" (연속 공백 + 앞뒤 공백)
out=$("$SCRIPT" "  hello   world  "); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "hello-world" ]; then
  PASS=$((PASS+1)); echo "PASS T2.b spaces"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.b (got='$out')"
fi

# T2.c "hello!@#world" → "hello-world" (특수문자)
out=$("$SCRIPT" "hello!@#world"); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "hello-world" ]; then
  PASS=$((PASS+1)); echo "PASS T2.c special-chars"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.c (got='$out')"
fi

# T3.a "안녕" → "annyeong" (한글 only)
out=$("$SCRIPT" "안녕"); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "annyeong" ]; then
  PASS=$((PASS+1)); echo "PASS T3.a 한글-only"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.a (got='$out')"
fi

# T3.b "안녕 World 2024" → "annyeong-world-2024" (혼합)
out=$("$SCRIPT" "안녕 World 2024"); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "annyeong-world-2024" ]; then
  PASS=$((PASS+1)); echo "PASS T3.b 혼합"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.b (got='$out')"
fi

# T3.c "Hello 세계" → "hello-segye"
out=$("$SCRIPT" "Hello 세계"); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "hello-segye" ]; then
  PASS=$((PASS+1)); echo "PASS T3.c 영문+한글"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.c (got='$out')"
fi

# T4.a 빈 문자열 → 빈 출력 + exit 0
out=$("$SCRIPT" ""); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "" ]; then
  PASS=$((PASS+1)); echo "PASS T4.a 빈-입력"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.a (rc=$rc got='$out')"
fi

# T4.b stdin 파이프: echo "Hello 세계" | slug.sh → "hello-segye"
out=$(printf '%s' "Hello 세계" | "$SCRIPT"); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "hello-segye" ]; then
  PASS=$((PASS+1)); echo "PASS T4.b stdin-pipe"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.b (rc=$rc got='$out')"
fi

# T4.c 공백만 있는 입력 → 빈 출력 + exit 0 (AC-8)
out=$("$SCRIPT" "   "); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "" ]; then
  PASS=$((PASS+1)); echo "PASS T4.c 공백-only"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.c (rc=$rc got='$out')"
fi

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
