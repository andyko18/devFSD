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
grep -q "devfsd:implementer-ko" "$F" \
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
_has '한 메시지에서 동시 dispatch' && _has 'per-task 는 직렬 B→C' && _has 'end-loaded 는 재리뷰가 없다' \
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
grep -qF 'BC-PAR-CHECK:<tid>' "$_DOC" && grep -qF '재리뷰 없이 verify' "$_DOC" \
  && { PASS=$((PASS+1)); echo "PASS T4.g lifecycle 문서 정합 (병렬 쌍·사후 대조·재라운드 직렬)"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T4.g lifecycle 문서에 병렬 쌍 문구 부재"; }

_has 'tid 단위다' && _has '재리뷰는 하지 않는다' && _has '옛 `-B-feedback.md`' \
  && { PASS=$((PASS+1)); echo "PASS T4.i B FAIL tid 단위 채택·cap 비소모·stale feedback 안내"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T4.i B FAIL tid 단위 채택·cap 비소모·stale feedback 안내 부재"; }

# ── T5 수정 라운드 — end-loaded 는 재리뷰 없이 verify (20261112 speed) ──
_fx=$(awk '/^### 수정 라운드/ { f=1; next } f && /^## |^### / { exit } f { print }' "$F")
_fxh() { printf '%s' "$_fx" | grep -qF -- "$1"; }
_fxh '**수정 라운드 1회**' && _fxh '고친 뒤 B·C 를 다시 부르지 않는다' && _fxh '**재리뷰 없이** `verifying-evidence-ko` 로 간다' \
  && { PASS=$((PASS+1)); echo "PASS T5.a 수정 라운드 1회 · 재리뷰 없이 verify"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T5.a 수정 라운드/재리뷰 없음 문구 부재"; }
_fxh '**Critical 미해결**' && _fxh '「cap 초과 처리」' && _fxh 'verify 로 넘기지 않는다' \
  && { PASS=$((PASS+1)); echo "PASS T5.b Critical 미해결 정지 유지 (cap 초과 처리 → HARD GATE)"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T5.b Critical 미해결 정지 문구 부재"; }
_fxh '| REVIEW-FIX:<tid> | implementer-ko | FIXED |' && _fxh '`NEEDS_DISCUSSION` 은 종전대로 사용자 판단 대기' && _fxh '`review_mode: per-task`' \
  && { PASS=$((PASS+1)); echo "PASS T5.c 수정 기록 행 · NEEDS_DISCUSSION 유지 · 되돌리는 방법(per-task)"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T5.c 기록 행/NEEDS_DISCUSSION/되돌림 부재"; }
# 기록 행의 결과 칸에 DONE·IMPL 을 쓰지 않는다 (재개 판독기가 구현 증거로 읽는다)
printf '%s\n' "$_fx" | grep -oE '`\| [^`]*REVIEW-FIX[^`]*`' | grep -qE 'DONE|IMPL' \
  && { FAIL=$((FAIL+1)); echo "FAIL T5.d REVIEW-FIX 행에 DONE·IMPL"; } \
  || { PASS=$((PASS+1)); echo "PASS T5.d REVIEW-FIX 행에 DONE·IMPL 없음"; }
# 금지 목록이 재리뷰를 다시 의무화하지 않는다 (종전 문구 잔존 = 두 지시가 맞선다)
! grep -qF -- '- 재리뷰 생략 금지' "$F" && ! grep -qF '재라운드는 직렬 B→C' "$F" \
  && { PASS=$((PASS+1)); echo "PASS T5.e 종전 재리뷰 의무 문구 잔존 없음"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T5.e 종전 재리뷰 의무 문구가 남아 있다"; }

# ── T6 태스크 묶기 · 동시 dispatch 기본 (20261112 speed) ──
_mg=$(awk '/^### 작은 변경은 묶는다/ { f=1; next } f && /^## |^### / { exit } f { print }' "$DEC")
_mgh() { printf '%s' "$_mg" | grep -qF -- "$1"; }
_mgh '**작은 변경은 태스크 3개 이하**' && _mgh '구현 파일(테스트·문서 제외)이 5개 이하' && _mgh '**같은 파일을 고치는 태스크 둘은 하나로 합친다**' \
  && { PASS=$((PASS+1)); echo "PASS T6.a 작은 변경 태스크 3개 이하 · 같은 파일은 합친다"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T6.a 태스크 묶기 규칙 부재"; }
_mgh '크기가 아니라 독립성' && _mgh '**`depends_on` 은 실제 산출 의존이 있을 때만 적는다**' && _mgh '한 메시지에서 동시에 dispatch' \
  && { PASS=$((PASS+1)); echo "PASS T6.b 분할 기준=독립성 · depends_on 은 실제 의존만"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T6.b 분할 기준/depends_on 규칙 부재"; }
# 분할을 압박하던 종전 문구가 남아 있으면 묶기 규칙과 맞선다
! grep -qF '각 태스크 = 2~5분 작업 단위' "$DEC" && ! grep -qF '태스크가 5분을 초과한다면' "$DEC" && ! grep -qF '1 태스크 = 2~5분' "$DEC" \
  && ! grep -qF '단일 태스크 > 3 파일 수정' "$PLUGIN/agents/plan-reviewer-ko.md" && ! grep -qF '태스크 크기 5분 초과 추정' "$PLUGIN/agents/plan-reviewer-ko.md" \
  && { PASS=$((PASS+1)); echo "PASS T6.c 분할 압박 문구(2~5분 태스크·3파일 초과 Critical) 제거"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T6.c 분할 압박 문구가 남아 있다"; }
grep -qF '태스크를 잘게 쪼개라고 지적하지 않는다' "$PLUGIN/agents/plan-reviewer-ko.md" \
  && grep -qF '파일 수·예상 소요만으로 Critical·Important 를 주지 않는다' "$PLUGIN/agents/plan-reviewer-ko.md" \
  && { PASS=$((PASS+1)); echo "PASS T6.d plan-reviewer 가 분할을 요구하지 않는다"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T6.d plan-reviewer 분할 비요구 문구 부재"; }
grep -qF '**동시 dispatch 가 기본이다 (20261112)**' "$F" && grep -qF '**반드시 한 메시지의 `Agent` 호출 여러 개로 함께** 보낸다' "$F" \
  && grep -qF '| SERIAL:<tid> | - | 직렬 |' "$F" \
  && { PASS=$((PASS+1)); echo "PASS T6.e implementing 동시 dispatch 기본 · 직렬 사유 기록"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T6.e 동시 dispatch 기본 문구 부재"; }
# plan-reviewer: Critical 줄 형식 고정(부모의 기계 판정 입력) — Important 만이면 2회차 없음
grep -qF '`Critical: <N>건` 줄은 **형식 그대로** 쓴다' "$PLUGIN/agents/plan-reviewer-ko.md" \
  && grep -qF 'Critical≥1 일 때만 2회차를 부른다' "$PLUGIN/agents/plan-reviewer-ko.md" \
  && { PASS=$((PASS+1)); echo "PASS T6.f plan-reviewer Critical 줄 형식 고정 · 2회차는 Critical 일 때만"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T6.f plan-reviewer 판정 줄 규칙 부재"; }

# ── T7 plan 단계 전문가·리뷰어 실행 예산 (20261112 speed) ──
_PLN="$PLUGIN/skills/planning-ko/SKILL.md"
_bud=$(grep -F '**전문가·리뷰어 실행 예산 (20261112)**' "$_PLN")
_budh() { printf '%s' "$_bud" | grep -qF -- "$1"; }
_budh '실행 상한을 **숫자로** 적는다' && _budh '실행은 2회 이내' && _budh '전체 스위트(`run-all.sh` 류)는 실행하지 않는다' && _budh '`[검증 불가]`' \
  && { PASS=$((PASS+1)); echo "PASS T7.a plan 단계 dispatch 실행 상한(긴 명령 2회·전체 스위트 금지·검증 불가 표기)"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T7.a plan 단계 실행 예산 부재"; }
_budh '**보안 전문가 패스가 발동한 FID**' && _budh 'strict 로 보고 상한을 적지 않는다' && _budh '**추가하지 않는다**' \
  && { PASS=$((PASS+1)); echo "PASS T7.b 고위험(보안 패스 발동)은 상한 제외 · 계약 밖 점검 추가 금지"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T7.b strict 제외/계약 밖 금지 문구 부재"; }
# 구현 단계 리뷰어 예산 (20261112-reviewer-run-cap) — lite·standard 상한은 그대로, strict 에도 상한, 전체 스위트는 위험도 무관 금지
_ibud=$(awk '/^### 리뷰어 실행 예산/ { f = 1; next } f && /^## / { exit } f' "$F")
_ibh() { printf '%s' "$_ibud" | grep -qF -- "$1"; }
_ibh '핵심 실행 2회 이내' && _ibh '되돌려-관찰 3회 이내' \
  && { PASS=$((PASS+1)); echo "PASS T7.c 구현 단계 리뷰어 예산 — lite·standard 상한(B 2회·C 3회) 불변"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T7.c lite·standard 상한 문구 변경됨"; }
_ibh '`strict` 는 대상 테스트 실행 B 4회 이내·C 6회 이내' && ! _ibh '제한 없음' \
  && { PASS=$((PASS+1)); echo "PASS T7.d strict 에도 실행 상한(B 4회·C 6회) · 무제한 문구 없음"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T7.d strict 실행 상한 부재 또는 '제한 없음' 잔존 — 고위험 FID 의 리뷰어 재실행이 무제한이 된다"; }
_ibh '전체 스위트(`run-all.sh` 류) 실행은 위험도와 무관하게 하지 않는다' && _ibh '`strict` 를 포함해 dispatch 프롬프트에' \
  && { PASS=$((PASS+1)); echo "PASS T7.e 전체 스위트 실행 금지가 위험도 무관 · strict dispatch 에도 상한을 숫자로"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T7.e 전체 스위트 금지(위험도 무관) 또는 strict dispatch 상한 표기 부재"; }
_ibh '`[검증 불가]`' && _ibh '조용히 통과시키지 않는다' \
  && { PASS=$((PASS+1)); echo "PASS T7.f 상한에 닿아 확인 못 한 항목은 [검증 불가] 로 보고"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T7.f 상한 도달 항목의 [검증 불가] 보고 지시 부재"; }
_ibh 'B·C 각 1회 필수와 독립 되돌려-관찰 증거는 줄이지 않는다' \
  && { PASS=$((PASS+1)); echo "PASS T7.g 품질 하한(B·C 각 1회 · 되돌려-관찰 증거) 불변"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T7.g 품질 하한 문구 소실"; }

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
