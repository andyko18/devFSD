#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CMD="$PLUGIN/commands/log.md"

# T6.a /log 커맨드 정의 존재 + gbrain-append 재사용 명시
if [ -f "$CMD" ] && grep -q 'gbrain-append' "$CMD"; then
  PASS=$((PASS+1)); echo "PASS T6.a /log 커맨드"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.a"
fi
echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
