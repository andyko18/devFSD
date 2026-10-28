#!/usr/bin/env bash
# test-session-progress-backup — AC-1~3 검증 (백업·직전상태·복원·template fallback·비차단·무손상)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
APPEND="$PLUGIN/scripts/session-progress-append.sh"
ENSURE="$PLUGIN/hooks/ensure-session-progress.sh"

# T1.a AC-1: append 후 .bak가 직전 상태 보존
TD=$(mktemp -d); mkdir -p "$TD/.specops"
printf '## 20260615-x · test\n- old line\n' > "$TD/.specops/session-progress.md"
( cd "$TD" && bash "$APPEND" 20260615-x /verify PASS "m" >/dev/null 2>&1 )
if [ -f "$TD/.specops/session-progress.md.bak" ] && grep -q "old line" "$TD/.specops/session-progress.md.bak"; then
  PASS=$((PASS+1)); echo "PASS T1.a AC-1 .bak 직전 상태 보존"
else FAIL=$((FAIL+1)); echo "FAIL T1.a"; fi

# T1.b AC-R-1: append prepend 무손상
if grep -q "/verify PASS" "$TD/.specops/session-progress.md"; then
  PASS=$((PASS+1)); echo "PASS T1.b AC-R-1 prepend 무손상"
else FAIL=$((FAIL+1)); echo "FAIL T1.b"; fi
rm -rf "$TD"

# T2.a AC-3: TARGET 삭제 후 ensure → .bak 복원
TD2=$(mktemp -d); mkdir -p "$TD2/.specops"
printf '## 20260615-y · hist\n- 작업 이력\n' > "$TD2/.specops/session-progress.md.bak"
( cd "$TD2" && bash "$ENSURE" >/dev/null 2>&1 )
if [ -f "$TD2/.specops/session-progress.md" ] && grep -q "작업 이력" "$TD2/.specops/session-progress.md"; then
  PASS=$((PASS+1)); echo "PASS T2.a AC-3 .bak 복원(이력 유지)"
else FAIL=$((FAIL+1)); echo "FAIL T2.a"; fi
rm -rf "$TD2"

# T2.b AC-3: .bak 부재 시 template fallback
TD3=$(mktemp -d); mkdir -p "$TD3/.specops"
( cd "$TD3" && bash "$ENSURE" >/dev/null 2>&1 )
if [ -f "$TD3/.specops/session-progress.md" ] && ! grep -q "작업 이력" "$TD3/.specops/session-progress.md"; then
  PASS=$((PASS+1)); echo "PASS T2.b AC-3 .bak 부재 template fallback"
else FAIL=$((FAIL+1)); echo "FAIL T2.b"; fi
rm -rf "$TD3"

# T2.c AC-2: TARGET 부재서 append exit 0
TD4=$(mktemp -d); mkdir -p "$TD4/.specops"
( cd "$TD4" && bash "$APPEND" 20260615-z /specify 완료 "m" >/dev/null 2>&1 ); rc=$?
if [ $rc -eq 0 ] && [ -f "$TD4/.specops/session-progress.md" ]; then
  PASS=$((PASS+1)); echo "PASS T2.c AC-2 append exit 0(백업 비차단)"
else FAIL=$((FAIL+1)); echo "FAIL T2.c (rc=$rc)"; fi
rm -rf "$TD4"

# T2.d AC-2: 백업 cp 실패(readonly .bak 덮어쓰기 거부) → append exit 0 prepend (진짜 비차단)
#   root 는 444 파일도 덮어써 cp 가 실패하지 않는다 — 실패 경로를 못 타 통과가 공허하므로 SKIP
if [ "$(id -u)" -eq 0 ]; then
  echo "SKIP T2.d AC-2 cp 실패(readonly .bak) — root 로 실행 중(권한 검사 무의미)"
else
  TD5=$(mktemp -d); mkdir -p "$TD5/.specops"
  printf '## 20260615-w · t\n- line\n' > "$TD5/.specops/session-progress.md"
  : > "$TD5/.specops/session-progress.md.bak"; chmod 444 "$TD5/.specops/session-progress.md.bak"
  ( cd "$TD5" && bash "$APPEND" 20260615-w /verify PASS "m" >/dev/null 2>&1 ); rc=$?
  if [ $rc -eq 0 ] && grep -q "/verify PASS" "$TD5/.specops/session-progress.md"; then
    PASS=$((PASS+1)); echo "PASS T2.d AC-2 cp 실패(readonly .bak)해도 prepend·exit 0(진짜 비차단)"
  else FAIL=$((FAIL+1)); echo "FAIL T2.d (rc=$rc)"; fi
  chmod 644 "$TD5/.specops/session-progress.md.bak" 2>/dev/null; rm -rf "$TD5"
fi

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
