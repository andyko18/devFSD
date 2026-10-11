#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCRIPT="$PLUGIN/scripts/b64dec.sh"


# T2.a: 인자 디코딩 "aGVsbG8=" → "hello" (AC-4)
out=$("$SCRIPT" "aGVsbG8="); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "hello" ] \
  && ok "T2.a 인자 디코딩" || fail "T2.a (rc=$rc out='$out')"

# T2.b: stdin 디코딩 (AC-5)
out=$(printf '%s' "aGVsbG8=" | "$SCRIPT"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "hello" ] \
  && ok "T2.b stdin 디코딩" || fail "T2.b (rc=$rc out='$out')"

# T2.c: 잘못된 입력 → stderr 에러 + exit 1 (AC-6)
err=$("$SCRIPT" "!!!invalid!!!" 2>&1 1>/dev/null); rc=$?
[ "$rc" -ne 0 ] && [ -n "$err" ] \
  && ok "T2.c 잘못된 입력 exit 1 + stderr" || fail "T2.c (rc=$rc err='$err')"

# T2.d: --help → exit 0 + "Usage" 포함
out=$("$SCRIPT" --help 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "Usage" \
  && ok "T2.d --help" || fail "T2.d (rc=$rc out='$out')"

# T2.e: 패딩 2개 "dGVzdA==" → "test" (AC-4 확장)
out=$("$SCRIPT" "dGVzdA=="); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "test" ] \
  && ok "T2.e 패딩 2개 디코딩" || fail "T2.e (rc=$rc out='$out')"

# T2.f: 패딩 누락 "aGVsbG8" (길이 7) → exit 1 + stderr (I-1 회귀 테스트)
err=$("$SCRIPT" "aGVsbG8" 2>&1 1>/dev/null); rc=$?
[ "$rc" -ne 0 ] && [ -n "$err" ] \
  && ok "T2.f 패딩 누락 exit 1" || fail "T2.f (rc=$rc err='$err')"

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
