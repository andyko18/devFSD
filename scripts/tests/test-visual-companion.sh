#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS_DIR="$PLUGIN/skills/brainstorming-ko/scripts"

# T1: server.cjs 존재 확인 (AC-1)
[ -f "$SCRIPTS_DIR/server.cjs" ] \
  && echo "T1.a PASS: server.cjs 존재" && PASS=$((PASS+1)) \
  || { echo "T1.a FAIL: server.cjs 미존재"; FAIL=$((FAIL+1)); }

# T1: package.json ws 의존성 (AC-1)
[ -f "$SCRIPTS_DIR/package.json" ] && grep -q '"ws"' "$SCRIPTS_DIR/package.json" \
  && echo "T1.b PASS: package.json ws 의존성" && PASS=$((PASS+1)) \
  || { echo "T1.b FAIL: package.json 미존재 또는 ws 누락"; FAIL=$((FAIL+1)); }

# T2: start-server.sh exec-bit (AC-3)
[ -x "$SCRIPTS_DIR/start-server.sh" ] \
  && echo "T2.a PASS: start-server.sh exec-bit" && PASS=$((PASS+1)) \
  || { echo "T2.a FAIL: start-server.sh 미존재 또는 exec-bit 누락"; FAIL=$((FAIL+1)); }

# T3: stop-server.sh exec-bit (AC-4)
[ -x "$SCRIPTS_DIR/stop-server.sh" ] \
  && echo "T3.a PASS: stop-server.sh exec-bit" && PASS=$((PASS+1)) \
  || { echo "T3.a FAIL: stop-server.sh 미존재 또는 exec-bit 누락"; FAIL=$((FAIL+1)); }

# T4: frame-template.html WebSocket 코드 (AC-5)
[ -f "$SCRIPTS_DIR/frame-template.html" ] \
  && grep -q 'ws://localhost:4242' "$SCRIPTS_DIR/frame-template.html" \
  && grep -q 'id="content"' "$SCRIPTS_DIR/frame-template.html" \
  && echo "T4.a PASS: frame-template.html WebSocket+content" && PASS=$((PASS+1)) \
  || { echo "T4.a FAIL: frame-template.html 미존재 또는 필수 코드 누락"; FAIL=$((FAIL+1)); }

# T5: helper.js sendToVisualCompanion + 오류 처리 (AC-6)
[ -f "$SCRIPTS_DIR/helper.js" ] \
  && grep -q 'sendToVisualCompanion' "$SCRIPTS_DIR/helper.js" \
  && grep -qE "(catch|reject|onerror|on\('error'|on\(\"error\")" "$SCRIPTS_DIR/helper.js" \
  && echo "T5.a PASS: helper.js sendToVisualCompanion + 오류 처리" && PASS=$((PASS+1)) \
  || { echo "T5.a FAIL: helper.js 미존재, sendToVisualCompanion 누락, 또는 오류 처리 코드 누락"; FAIL=$((FAIL+1)); }

# T6: specifying-ko 포팅 주석 없음 + 사용 가이드 존재 (AC-7)
! grep -q 'Phase 1 현재.*visual-companion.*포팅' \
    "$PLUGIN/skills/specifying-ko/SKILL.md" \
  && grep -q 'start-server.sh' "$PLUGIN/skills/specifying-ko/SKILL.md" \
  && echo "T6.a PASS: specifying-ko 포팅 주석 없음 + 사용 가이드 존재" && PASS=$((PASS+1)) \
  || { echo "T6.a FAIL: specifying-ko 포팅 주석 여전히 존재 또는 사용 가이드 텍스트 없음"; FAIL=$((FAIL+1)); }

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
