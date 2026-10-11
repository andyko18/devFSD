#!/usr/bin/env bash
# scripts/gbrain-collect.sh 검증 — 격리 sandbox
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$PLUGIN/scripts/gbrain-collect.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
cd "$TD"
FID=20260101-fx
mkdir -p .specops/$FID/handoffs

# T1.a Decided/Risks 수집 + "- (없음)" 필터 + Rejected/무관 라인 제외 + evidence 결과 라인
cat > .specops/$FID/handoffs/specifying.md <<'EOF'
# handoff
## Decided
- 결정 A
- (없음)
## Rejected
- 기각 B
## Risks
- 위험 C
EOF
cat > .specops/$FID/evidence.md <<'EOF'
## verify
**결과**: PASS
PASS=10 FAIL=0
무관 라인
EOF
out=$(bash "$SCRIPT" $FID); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '결정 A' && echo "$out" | grep -q '위험 C' \
   && echo "$out" | grep -q 'PASS=10' && ! echo "$out" | grep -q '기각 B' \
   && ! echo "$out" | grep -qF -- '- (없음)' && ! echo "$out" | grep -q '무관 라인'; then
  PASS=$((PASS+1)); echo "PASS T1.a Decided/Risks 수집 + 필터"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a (rc=$rc out=$out)"
fi

# T1.b 수집물 0 → "COLLECT: EMPTY" + exit 0
FID2=20260101-empty; mkdir -p .specops/$FID2
out=$(bash "$SCRIPT" $FID2); rc=$?
if [ $rc -eq 0 ] && [ "$out" = "COLLECT: EMPTY" ]; then
  PASS=$((PASS+1)); echo "PASS T1.b 수집물 0 → EMPTY + exit 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b (rc=$rc out=$out)"
fi

# T1.c FID 디렉토리 부재 → exit 1 + stderr (A-4 사용 오류 경계)
err=$(bash "$SCRIPT" 20260101-nope 2>&1 >/dev/null); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'ERROR'; then
  PASS=$((PASS+1)); echo "PASS T1.c 디렉토리 부재 → exit 1"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.c (rc=$rc err=$err)"
fi

# T1.d 회귀 — "- (없음)" 부분 문자열 포함 실데이터 bullet 은 수집, 라인 전체 placeholder 만 필터
FID3=20260101-substr; mkdir -p .specops/$FID3/handoffs
cat > .specops/$FID3/handoffs/planning.md <<'EOF'
# handoff
## Decided
- 결정 X - (없음) 아님
- (없음)
EOF
out=$(bash "$SCRIPT" $FID3); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '결정 X - (없음) 아님' \
   && ! echo "$out" | grep -qE -- '^- \(없음\)[[:space:]]*$'; then
  PASS=$((PASS+1)); echo "PASS T1.d 부분 문자열 bullet 수집 + 전체 매치 placeholder 필터"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.d (rc=$rc out=$out)"
fi

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
