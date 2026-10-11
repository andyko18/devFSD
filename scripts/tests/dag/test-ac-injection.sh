#!/usr/bin/env bash
# v0.4a W2 — AC injection contract validation 테스트
# 3 fixture × validate-context.sh 검증
# 컨벤션: templates/test-conventions-bash.md (PASS=N FAIL=N 카운터)

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
FIXTURES="$PLUGIN/scripts/tests/dag/fixtures/dispatch-context"
VALIDATE="$PLUGIN/scripts/dag/validate-context.sh"

# T1.a — 5 컨텍스트 모두 제공 → exit 0 (정상)
if bash "$VALIDATE" "$FIXTURES/01-complete.md" 2>/dev/null; then
  PASS=$((PASS+1)); echo "PASS T1.a 01-complete → exit 0 (5 컨텍스트 모두 제공)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a — exit $? (정상 fixture 인데 실패)"
fi

# T1.b — whitelist 누락 → exit 1 (NEEDS_CONTEXT 트리거)
if ! bash "$VALIDATE" "$FIXTURES/02-missing-whitelist.md" 2>/dev/null; then
  PASS=$((PASS+1)); echo "PASS T1.b 02-missing-whitelist → exit 1 (whitelist 비어있음 감지)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b — whitelist 비어있는데 정상 판정"
fi

# T1.b 추가 — stderr에 "수정 허용 파일" 메시지 포함 확인
err=$(bash "$VALIDATE" "$FIXTURES/02-missing-whitelist.md" 2>&1 >/dev/null)
if echo "$err" | grep -q "수정 허용 파일"; then
  PASS=$((PASS+1)); echo "PASS T1.b.err stderr에 누락 항목 명시"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b.err — stderr=$err"
fi

# T1.c — spec.md 섹션 누락 → exit 1
if ! bash "$VALIDATE" "$FIXTURES/03-missing-spec-section.md" 2>/dev/null; then
  PASS=$((PASS+1)); echo "PASS T1.c 03-missing-spec-section → exit 1 (spec 경로 누락 감지)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.c — spec 경로 없는데 정상 판정"
fi

# T1.d — 파일 없음 → exit 2 (사용법 오류)
err=$(bash "$VALIDATE" "/tmp/nonexistent-context.md" 2>&1 >/dev/null)
ec=$?
if [ "$ec" -eq 2 ] && echo "$err" | grep -q "파일 없음"; then
  PASS=$((PASS+1)); echo "PASS T1.d 파일 없음 → exit 2 + stderr 메시지"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.d (exit=$ec, err=$err)"
fi

# T1.e — 사용법 오류 (인자 0개) → exit 2
ec=0
bash "$VALIDATE" 2>/dev/null || ec=$?
if [ "$ec" -eq 2 ]; then
  PASS=$((PASS+1)); echo "PASS T1.e 인자 0개 → exit 2 (usage)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.e (exit=$ec)"
fi

echo ""
echo "==== Results: PASS=$PASS FAIL=$FAIL ===="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
