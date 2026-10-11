#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$PLUGIN/scripts/epoch.sh"

# T1.a AC-1: epoch(초) → ISO
out=$("$SCRIPT" 1777161600 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "2026-04-26T00:00:00Z" ]; then
  PASS=$((PASS+1)); echo "PASS T1.a epoch-sec-to-iso"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a (rc=$rc got='$out')"
fi

# T1.b AC-2: epoch(밀리초) → ISO
out=$("$SCRIPT" 1777161600123 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "2026-04-26T00:00:00.123Z" ]; then
  PASS=$((PASS+1)); echo "PASS T1.b epoch-ms-to-iso"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b (rc=$rc got='$out')"
fi

# T2.a AC-3: ISO(Z) → epoch 초
out=$("$SCRIPT" "2026-04-26T00:00:00Z" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "1777161600" ]; then
  PASS=$((PASS+1)); echo "PASS T2.a iso-to-epoch-sec"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.a (rc=$rc got='$out')"
fi

# T2.b AC-4: ISO(.mmm) → epoch ms
out=$("$SCRIPT" "2026-04-26T00:00:00.123Z" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "1777161600123" ]; then
  PASS=$((PASS+1)); echo "PASS T2.b iso-ms-to-epoch-ms"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.b (rc=$rc got='$out')"
fi

# T3.a AC-5: stdin
out=$(printf '%s' "1777161600" | "$SCRIPT" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "2026-04-26T00:00:00Z" ]; then
  PASS=$((PASS+1)); echo "PASS T3.a stdin"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.a (rc=$rc got='$out')"
fi

# T4.a AC-6: 인식 불가 입력 → stderr + exit 1, stdout 비어있음
stdout_out=$("$SCRIPT" "not-valid" 2>/dev/null); rc=$?
stderr_out=$("$SCRIPT" "not-valid" 2>&1 1>/dev/null)
if [ "$rc" -ne 0 ] && [ -z "$stdout_out" ] && [ -n "$stderr_out" ]; then
  PASS=$((PASS+1)); echo "PASS T4.a invalid-input"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.a (rc=$rc stdout='$stdout_out' stderr='$stderr_out')"
fi

# T4.b AC-7: --help → exit 0 + "Usage"
out=$("$SCRIPT" --help 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "Usage"; then
  PASS=$((PASS+1)); echo "PASS T4.b --help"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.b (rc=$rc out=$out)"
fi

# T4.c AC-8: +00:00 offset → 1777161600
out=$("$SCRIPT" "2026-04-26T00:00:00+00:00" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "1777161600" ]; then
  PASS=$((PASS+1)); echo "PASS T4.c plus00-offset"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.c (rc=$rc got='$out')"
fi

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
