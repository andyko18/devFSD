#!/usr/bin/env bash
# 학습 환류 루프 — gitignore 영속성 + skill 본문 통합 검증
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)

# T3.a learnings.jsonl 도 ignore 대상 (20260811 정책 전환 — AC-11 폐기)
#   구 정책은 learnings.jsonl 만 예외로 추적했다. 세션 인사이트에 downstream 프로젝트 문맥이
#   섞여 배포 저장소에 올리기 부적합하다는 판단으로 `.specops/` 전량 로컬 전용으로 전환했다.
#   학습 자산은 로컬 `.specops/memory/learnings.jsonl` 에 계속 축적된다(기능 불변).
if git -C "$PLUGIN" check-ignore -q .specops/memory/learnings.jsonl; then
  PASS=$((PASS+1)); echo "PASS T3.a learnings.jsonl ignore (로컬 전용 정책)"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.a learnings.jsonl 이 ignore 안 됨"
fi

# T3.b 일반 FID 산출물은 여전히 ignore (배포 불포함 규약 유지)
if git -C "$PLUGIN" check-ignore -q .specops/20990101-future/spec.md; then
  PASS=$((PASS+1)); echo "PASS T3.b FID 산출물 ignore 유지"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.b FID 산출물이 ignore 안 됨"
fi

# T3.c memory 내 다른 파일도 ignore (예외 없음)
if git -C "$PLUGIN" check-ignore -q .specops/memory/other-file.md; then
  PASS=$((PASS+1)); echo "PASS T3.c memory 기타 파일 ignore 유지"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.c memory 기타 파일이 ignore 안 됨"
fi

# T3.d check-ignore rc 정밀 구분 — rc=0 (ignore) 만 PASS, rc>=2 는 git 오류 (Phase C 보강)
#   rc=1 은 비-ignore = 구 정책 잔존이므로 FAIL 이다. rc 만 보면 오류(rc>=2)와 구분 안 되므로
#   세 갈래를 명시적으로 나눈다.
rc=$(git -C "$PLUGIN" check-ignore -q .specops/memory/learnings.jsonl; echo $?)
if [ "$rc" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T3.d learnings.jsonl ignore (rc=0 정밀 확인)"
elif [ "$rc" -ge 2 ]; then
  FAIL=$((FAIL+1)); echo "FAIL T3.d git check-ignore 오류 (rc=$rc)"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.d learnings.jsonl 이 비-ignore (rc=1 — 구 정책 잔존)"
fi

# ── T4 skill 본문 연결 (AC-5·6·12) ──
PERF="$PLUGIN/skills/performance-test-ko/SKILL.md"
SPEC="$PLUGIN/skills/specifying-ko/SKILL.md"

# T4.a 추출 단계 — collect 호출 + append 연결 + batch 분기 (AC-5)
if grep -q 'gbrain-collect.sh' "$PERF" && grep -q '## 학습 추출' "$PERF" \
   && grep -q 'gbrain-append.sh' "$PERF" \
   && awk '/^## 학습 추출/,/^## 다음 skill/' "$PERF" | grep -q 'BATCH-PERF-DONE'; then
  PASS=$((PASS+1)); echo "PASS T4.a performance-test-ko 추출 단계"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.a 추출 단계 누락"
fi

# T4.b tags 규약 + 건수 상한 (AC-12)
if grep -q '영문 소문자 kebab' "$PERF" && grep -qE '(≤3건|최대 3건)' "$PERF"; then
  PASS=$((PASS+1)); echo "PASS T4.b tags 규약 + 상한"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.b tags 규약/상한 누락"
fi

# T4.c 환류 분기 — recall 호출 + 인용 포맷 + 환류 블록 내 graceful skip (AC-6)
if grep -q 'gbrain-recall.sh' "$SPEC" && grep -q '과거 인사이트 (gbrain' "$SPEC" \
   && awk '/gbrain 과거 인사이트 환류/,/회귀 보호 계약/' "$SPEC" | grep -q 'graceful skip'; then
  PASS=$((PASS+1)); echo "PASS T4.c specifying-ko 환류 분기"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.c 환류 분기 누락"
fi

# ── T5 문서 등재 (AC-8) ──
if grep -q 'gbrain-recall.sh' "$PLUGIN/skills/gbrain-ko/SKILL.md" \
   && grep -q 'gbrain-collect.sh' "$PLUGIN/skills/gbrain-ko/SKILL.md" \
   && grep -q 'gbrain-recall.sh' "$PLUGIN/commands/gbrain.md"; then
  PASS=$((PASS+1)); echo "PASS T5.a 문서 등재"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.a 문서 등재 누락"
fi

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
