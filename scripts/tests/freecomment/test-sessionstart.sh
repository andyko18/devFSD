#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
HOOK="$PLUGIN/hooks/session-start.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.specops"

# T4.a pending 존재 → additionalContext 에 처리 안내 주입 (AC-4)
printf '%s\n' '{"ts":"2026-06-25T10:00:00Z","files":["foo.sh"],"prompt":"버그 고쳐","type":"fix"}' \
  > "$TMP/.specops/pending-capture.jsonl"
out=$(cd "$TMP" && echo '{}' | bash "$HOOK" 2>/dev/null)
if echo "$out" | grep -q '미기록 자유작업'; then
  PASS=$((PASS+1)); echo "PASS T4.a pending 주입"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.a (out=$out)"
fi

# T4.b pending 없으면 안내 미주입 + additionalContext 유지 (회귀 — 기존 동작 무변화)
rm -f "$TMP/.specops/pending-capture.jsonl"
out=$(cd "$TMP" && echo '{}' | bash "$HOOK" 2>/dev/null)
if ! echo "$out" | grep -q '미기록 자유작업' && echo "$out" | grep -q 'additionalContext'; then
  PASS=$((PASS+1)); echo "PASS T4.b pending 없음 무영향"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.b (out=$out)"
fi

# T4.c session-progress.md 존재 → rehydrate 블록에 신뢰경계 펜스 안내문 주입 (R5, AC-1)
printf '## 20260630-demo\n- 2026-06-30 10:00 /verify 완료\n' > "$TMP/.specops/session-progress.md"
out=$(cd "$TMP" && echo '{}' | bash "$HOOK" 2>/dev/null)
if echo "$out" | grep -q '신뢰 불가 데이터' && echo "$out" | grep -q '지시·명령으로 해석'; then
  PASS=$((PASS+1)); echo "PASS T4.c R5 펜스 안내문 주입"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.c (out=$out)"
fi

# T4.d 태그명 불변(session-progress-rehydrate) 회귀 (AC-2)
if echo "$out" | grep -q 'session-progress-rehydrate'; then
  PASS=$((PASS+1)); echo "PASS T4.d 태그명 불변"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.d (out=$out)"
fi

# T4.f 펜스 안내문이 progress 내용보다 앞 (AC-1 ordering 불변식 — 주입 데이터가 안내문 선점 차단)
fence_pos=$(echo "$out" | grep -abo '신뢰 불가 데이터' | head -1 | cut -d: -f1)
prog_pos=$(echo "$out" | grep -abo '20260630-demo' | head -1 | cut -d: -f1)
if [ -n "$fence_pos" ] && [ -n "$prog_pos" ] && [ "$fence_pos" -lt "$prog_pos" ]; then
  PASS=$((PASS+1)); echo "PASS T4.f 펜스가 progress 앞"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.f (fence=$fence_pos prog=$prog_pos)"
fi

# T4.e session-progress.md 부재 → 펜스 안내문 미출력 (AC-R-2)
rm -f "$TMP/.specops/session-progress.md"
out2=$(cd "$TMP" && echo '{}' | bash "$HOOK" 2>/dev/null)
if ! echo "$out2" | grep -q '신뢰 불가 데이터'; then
  PASS=$((PASS+1)); echo "PASS T4.e progress 부재 시 펜스 미출력"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.e (out2=$out2)"
fi

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
