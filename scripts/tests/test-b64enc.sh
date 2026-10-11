#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCRIPT="$PLUGIN/scripts/b64enc.sh"


# T1.a: 인자 인코딩 "hello" → "aGVsbG8=" (AC-1)
out=$("$SCRIPT" "hello"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "aGVsbG8=" ] \
  && ok "T1.a 인자 인코딩" || fail "T1.a (rc=$rc out='$out')"

# T1.b: stdin 인코딩 (AC-2)
out=$(printf '%s' "hello" | "$SCRIPT"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "aGVsbG8=" ] \
  && ok "T1.b stdin 인코딩" || fail "T1.b (rc=$rc out='$out')"

# T1.c: --help → exit 0 + "Usage" 포함 (AC-3)
out=$("$SCRIPT" --help 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "Usage" \
  && ok "T1.c --help usage" || fail "T1.c (rc=$rc out='$out')"

# T1.d: 빈 인자 → 빈 출력 exit 0 (AC-11)
out=$("$SCRIPT" ""); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "" ] \
  && ok "T1.d 빈 문자열 exit 0" || fail "T1.d (rc=$rc out='$out')"

# T1.e: 공백 포함 문자열 (AC-1 확장)
expected=$(printf '%s' "hello world" | base64 | tr -d '\n')
out=$("$SCRIPT" "hello world"); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "$expected" ] \
  && ok "T1.e 공백 포함 인코딩" || fail "T1.e (rc=$rc out='$out' expected='$expected')"

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
