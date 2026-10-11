#!/usr/bin/env bash
# Wave 2 U5 (FID 20260514) — implementing-ko 본문 정책 grep 검증
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PLUGIN=$(dirname "$PLUGIN")
F="$PLUGIN/skills/implementing-ko/SKILL.md"

# T1.a: cap=2 정책 명시
grep -q "cap=2" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T1.a cap=2 명시"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T1.a cap=2 부재"; }

# T1.b: Phase B HARD GATE 메시지
grep -qE "HARD-GATE.*Phase B" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T1.b Phase B HARD GATE"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T1.b Phase B HARD GATE 부재"; }

# T1.c: Phase C HARD GATE 메시지
grep -qE "HARD-GATE.*Phase C" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T1.c Phase C HARD GATE"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T1.c Phase C HARD GATE 부재"; }

# T1.d: implementer-ko subagent_type 명시
grep -q "specops-ko:implementer-ko" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T1.d implementer-ko subagent_type"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T1.d implementer-ko subagent_type 부재"; }

# T1.e: reviews/ 디렉토리 경로 명시
grep -qE "reviews/.*feedback" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T1.e reviews/ 디렉토리"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T1.e reviews/ 디렉토리 부재"; }

# T1.f: emit-context.sh 컨텍스트 자동 생성 명시
grep -q "emit-context" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T1.f emit-context 자동 생성"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T1.f emit-context 자동 생성 부재"; }

# T1.g: dispatch-log.md 자동 append 명시
grep -q "dispatch-log" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T1.g dispatch-log.md 명시"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T1.g dispatch-log.md 부재"; }

# T1.h: 자동 재dispatch 정책 (Phase B/C 1회 자동) 명시
grep -qE "(자동 재dispatch|1회 자동)" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T1.h 자동 재dispatch 정책"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T1.h 자동 재dispatch 정책 부재"; }

# ── T2 머지-race 단위검증 (implementing-ko L88-92 DAG-AWARE PARALLEL 부모 머지) ──
# 경계 (한계 고백): git apply --index 머지 합성/충돌 abort 로직만 검증한다.
#   LLM 이 단일 메시지에 멀티 Task tool_use 를 emit 하는 **실제 병렬 dispatch 자체는
#   bash 로 검증 불가** (S7 gh-pr-MERGED 와 동일 범주) — dogfood run 으로만 증명 가능.
mr_tmp=$(mktemp -d)
(
  cd "$mr_tmp" && git init -q m && cd m
  git config user.email t@example.com && git config user.name t
  echo base > base.txt && git add base.txt && git commit -qm base
  git worktree add -q ../w1 -b l1 && ( cd ../w1 && echo a > fileA.txt && git add fileA.txt )
  git worktree add -q ../w2 -b l2 && ( cd ../w2 && echo b > fileB.txt && git add fileB.txt )
  git -C ../w1 diff --cached > ../l1.patch
  git -C ../w2 diff --cached > ../l2.patch
) >/dev/null 2>&1
mrm="$mr_tmp/m"

# T2.a (M1): 2 disjoint leaf staged diff → git apply --index 순차 합성 (양쪽 산출물 반영)
( cd "$mrm" && git apply --index "$mr_tmp/l1.patch" && git apply --index "$mr_tmp/l2.patch" ) >/dev/null 2>&1
if [ -f "$mrm/fileA.txt" ] && [ -f "$mrm/fileB.txt" ]; then
  PASS=$((PASS+1)); echo "PASS T2.a (M1) disjoint 2패치 git apply --index 순차 합성"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.a (M1) disjoint 합성 실패"
fi

# T2.b (M3): overlap (같은 파일 다른 내용) → git apply --index --check 거부 (충돌 abort)
( cd "$mrm" && git reset -q --hard ) >/dev/null 2>&1
(
  cd "$mrm" && git worktree add -q ../c1 -b cc1 && ( cd ../c1 && echo X > shared.txt && git add shared.txt )
  git worktree add -q ../c2 -b cc2 && ( cd ../c2 && echo Y > shared.txt && git add shared.txt )
  git -C ../c1 diff --cached > ../c1.patch && git -C ../c2 diff --cached > ../c2.patch
) >/dev/null 2>&1
( cd "$mrm" && git apply --index "$mr_tmp/c1.patch" ) >/dev/null 2>&1
if ( cd "$mrm" && git apply --index --check "$mr_tmp/c2.patch" ) >/dev/null 2>&1; then
  FAIL=$((FAIL+1)); echo "FAIL T2.b (M3) overlap 충돌 미감지 (부분 적용 위험)"
else
  PASS=$((PASS+1)); echo "PASS T2.b (M3) overlap → git apply --check 거부 (abort 가능)"
fi
rm -rf "$mr_tmp"

# T2.c (M2): 부모 머지 순서 정책 (output count 적은 leaf 먼저) SKILL 명시
grep -qE "output count 적은|머지 순서" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T2.c (M2) 부모 머지 순서 정책 명시"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T2.c (M2) 머지 순서 정책 부재"; }

# ── T3 end-loaded 리뷰 모드 (기본) ──
# T3.a: review_mode / end-loaded 기본 명시
grep -qE "end-loaded" "$F" \
  && grep -qE "review_mode" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T3.a end-loaded + review_mode"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T3.a end-loaded/review_mode 부재"; }

# T3.b: per-task 레거시 opt-in
grep -qE "per-task" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T3.b per-task 레거시"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T3.b per-task 부재"; }

# T3.c: end-loaded B/C 산출물 per-tid 규약 (audit 정합)
grep -qE "reviews/<tid>-B-report|reviews/<tid>-C-report" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T3.c per-tid B/C report 규약"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T3.c per-tid report 규약 부재"; }

# T3.d: 생략 금지 vs 시점 통합 구분
grep -qE "시점만|시점 통합" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T3.d 시점 통합(생략 아님)"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T3.d 시점 통합 문구 부재"; }

# T3.e: decomposing/templates 에 review_mode 배선
DEC="$PLUGIN/skills/decomposing-ko/SKILL.md"
TPL="$PLUGIN/templates/tasks.md"
grep -qE "review_mode" "$DEC" && grep -qE "review_mode: end-loaded" "$TPL" \
  && { PASS=$((PASS+1)); echo "PASS T3.e decomposing+template review_mode"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T3.e decomposing/template review_mode 부재"; }

# T3.f: requesting Step 0 end-loaded skip
REQ="$PLUGIN/skills/requesting-code-review-ko/SKILL.md"
grep -qE "end-loaded" "$REQ" && grep -qE "review-skip" "$REQ" \
  && { PASS=$((PASS+1)); echo "PASS T3.f requesting end-loaded skip"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T3.f requesting end-loaded skip 부재"; }

# T3.g: batch-end-loaded 제거 — /start-all도 FID end-loaded
! grep -qE "batch-end-loaded" "$F" \
  && grep -qE "end-loaded" "$F" \
  && { PASS=$((PASS+1)); echo "PASS T3.g batch-end-loaded 부재·end-loaded 유지"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T3.g batch-end-loaded 잔존 또는 end-loaded 부재"; }

# T3.h: decomposing §batch → end-loaded (FR마다 B/C)
! grep -qE "batch-end-loaded" "$DEC" \
  && grep -qE "§batch|/start-all" "$DEC" \
  && grep -qE "end-loaded" "$DEC" \
  && { PASS=$((PASS+1)); echo "PASS T3.h decomposing §batch end-loaded"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T3.h decomposing §batch end-loaded 부재"; }

# ── T4 최초 B/C 쌍 병렬 (20261006-review-bc-parallel) ──
_sec=$(awk '/^### 최초 B\/C 쌍 병렬/ { f=1; next } f && /^## |^### / { exit } f { print }' "$F")
_has() { printf '%s' "$_sec" | grep -qF -- "$1"; }
_has '한 메시지에서 동시 dispatch' && _has '재라운드·per-task 는 직렬 B→C' \
  && { PASS=$((PASS+1)); echo "PASS T4.a 최초 쌍 동시 dispatch + 재라운드·per-task 직렬"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T4.a 동시 dispatch/직렬 유지 문구 부재"; }
_has '실 트리 변조 금지' && _has '임시 복사본' \
  && { PASS=$((PASS+1)); echo "PASS T4.b 두 프롬프트 변조 금지 재명시"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T4.b 변조 금지 재명시 부재"; }
_has 'BC-PAR-CHECK:<tid>' && _has 'check-review-audit.sh' \
  && { PASS=$((PASS+1)); echo "PASS T4.c 사후 대조 행 형식 + 기계 검사 연결"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T4.c 사후 대조 행/검사 연결 부재"; }
_has 'B PASS' && _has 'C 폐기(B FAIL)' && _has 'B feedback·C 보고서 경로를 함께' \
  && { PASS=$((PASS+1)); echo "PASS T4.d B PASS 채택 / B FAIL 폐기·재dispatch 첨부"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T4.d 사후 대조 분기 문구 부재"; }
_has '실패한 쪽만' && _has 'Evaluator 모델 불가 fallback' && _has '사후 대조 규칙은 동일' \
  && { PASS=$((PASS+1)); echo "PASS T4.e 한쪽 dispatch 실패 → 그쪽만 fallback·사후 대조 규칙 동일"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T4.e 한쪽 실패 fallback·사후 대조 규칙 동일 문구 부재"; }
_has 'strict 위험 프로파일의 B/C 축소 금지와 충돌하지 않는다' \
  && { PASS=$((PASS+1)); echo "PASS T4.h 병렬은 축소가 아니다 (strict B/C 축소 금지와 비충돌 명시)"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T4.h strict 비충돌 명시 부재"; }
# 음성 대조: 절에서 '한 메시지에서 동시 dispatch' 를 지우면 T4.a 판정식이 FAIL 이어야 한다(잠금이 공허하지 않다)
_sec_neg=$(printf '%s' "$_sec" | sed 's/한 메시지에서 동시 dispatch/한 번씩 순서대로 dispatch/')
if [ -z "$_sec" ] || printf '%s' "$_sec_neg" | grep -qF -- '한 메시지에서 동시 dispatch'; then
  FAIL=$((FAIL+1)); echo "FAIL T4.f 음성 대조 — 변이 후에도 통과"
else PASS=$((PASS+1)); echo "PASS T4.f 음성 대조 — 변이하면 T4.a 문구가 사라진다"; fi

_DOC="$PLUGIN/docs/lifecycle-start-end-loaded.md"
grep -qF 'BC-PAR-CHECK:<tid>' "$_DOC" && grep -qF '재라운드는 직렬' "$_DOC" \
  && { PASS=$((PASS+1)); echo "PASS T4.g lifecycle 문서 정합 (병렬 쌍·사후 대조·재라운드 직렬)"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T4.g lifecycle 문서에 병렬 쌍 문구 부재"; }

_has 'tid 단위다' && _has 'C cap 을 소모하지 않으며' && _has '옛 `-B-feedback.md`' \
  && { PASS=$((PASS+1)); echo "PASS T4.i B FAIL tid 단위 채택·cap 비소모·stale feedback 안내"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T4.i B FAIL tid 단위 채택·cap 비소모·stale feedback 안내 부재"; }

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
