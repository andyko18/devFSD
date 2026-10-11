#!/usr/bin/env bash
# test-plan-to-tasks.sh — plan.md → tasks.md 골격 생성기 회귀
#   FID 20260809-plan-to-tasks-generator
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "$0")/../../.." && pwd)
GEN="$PLUGIN/scripts/dag/plan-to-tasks.sh"
FX="$PLUGIN/scripts/tests/dag/fixtures/plan-to-tasks"
PASS=0; FAIL=0
ok()   { echo "PASS $1"; PASS=$((PASS+1)); }
nope() { echo "FAIL $1 — $2"; FAIL=$((FAIL+1)); }
finish() { echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ] || exit 1; exit 0; }

# T0 가드 — fixture 가 git 에 추적(또는 stage)되는가.
#   `.specops/*` 를 fixture 로 쓰면 .gitignore 때문에 다른 clone 에서 0건이 되어
#   아래 전건이 **공허 통과**한다. untracked 는 ls-files 에 잡히지 않으므로
#   fixture 생성 후 반드시 git add 해야 한다(실측: untracked 0 / staged 1).
_tracked=$(cd "$PLUGIN" && git ls-files scripts/tests/dag/fixtures/plan-to-tasks/ | wc -l | tr -d ' ')
[ "$_tracked" -ge 6 ] \
  && ok "T0 fixture git 추적 ${_tracked}건" \
  || { nope "T0" "fixture 미추적(${_tracked}건) — 다른 clone 에서 공허 통과"; finish; }

# T1 — 표준형 파싱 성공 (AC-1)
out=$("$GEN" --plan "$FX/01-h3-5step.md" 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^## Task 1: 첫 컴포넌트' \
  && ok "T1 h3/5step 파싱" || nope "T1" "rc=$rc 또는 Task 헤더 부재"

# T2 — Task 블록 밖 내용이 새지 않는다 (AC-5 경계)
printf '%s' "$out" | grep -q '여기는 Task 블록 밖이다' \
  && nope "T2" "Task 경계 밖 내용 유출" || ok "T2 Task 경계 밖 미포함"

# T3 — 출처 스탬프 4토큰 (AC-4)
#   _miss 누적 패턴 — 루프 안에서 nope+break 후 밖에서 ok 를 다시 부르면
#   중간 토큰 누락 시 PASS·FAIL 이 동시에 올라 리포트가 자기모순이 된다.
_head=$(printf '%s' "$out" | head -10)
_miss=""
for tok in 'plan-to-tasks' '의존 그래프' 'AC' '파괴적'; do
  printf '%s' "$_head" | grep -q "$tok" || _miss="$_miss [$tok]"
done
[ -z "$_miss" ] && ok "T3 출처 스탬프 4토큰" || nope "T3" "스탬프 토큰 누락:$_miss"

# T4 — 구조 동등성: Step 수 일치 (AC-5·AC-10)
_p=$(grep -cE '^- \[ \] \*\*(Step|스텝) [0-9]+' "$FX/01-h3-5step.md")
_g=$(printf '%s' "$out" | grep -cE '^- \[ \] \*\*(Step|스텝) [0-9]+')
[ "$_p" -eq "$_g" ] && [ "$_p" -eq 5 ] \
  && ok "T4 Step 수 동등 ($_p)" || nope "T4" "plan=$_p 골격=$_g"

# T5 — 가변 Step: 2개·9개 Task 를 5로 채우거나 자르지 않는다 (AC-10)
out2=$("$GEN" --plan "$FX/02-h2-varstep.md" 2>/dev/null); rc2=$?
if [ "$rc2" -ne 0 ]; then nope "T5" "rc=$rc2 (AC-1 전건 exit 0)"; else
_g2=$(printf '%s' "$out2" | grep -cE '^- \[ \] \*\*(Step|스텝) [0-9]+')
_t2=$(printf '%s' "$out2" | grep -c '^## Task ')
[ "$_g2" -eq 11 ] && [ "$_t2" -eq 2 ] \
  && ok "T5 가변 Step 보존 (2+9=11)" || nope "T5" "Step=$_g2(기대 11) Task=$_t2(기대 2)"
fi

# T6 — 한글 표기 + 파일 라벨 6종 원문 보존 (AC-11)
out3=$("$GEN" --plan "$FX/03-ko-labels.md" 2>/dev/null); rc3=$?
if [ "$rc3" -ne 0 ]; then nope "T6" "rc=$rc3 (AC-1 전건 exit 0)"; else
_miss=""
for lab in '수정' '테스트' '생성' 'Modify' '삭제' 'Create'; do
  printf '%s' "$out3" | grep -q "^- ${lab}: " || _miss="$_miss $lab"
done
[ -z "$_miss" ] && ok "T6 파일 라벨 6종 원문 보존" || nope "T6" "누락:$_miss"
fi

# T7 — 중첩 펜스 (AC-12). 판별 3중: 내부 내용 보존 · 함정이 h3 유지(태스크 승격 아님) · 태스크 1개
#   fixture 04 의 내부 3-fence 가 **홀수**여야 naive 토글 변이가 잡힌다.
#   짝수면 변이 출력이 정상과 diff 0 이 되어 이 어서션이 원리적으로 무력해진다(실측 반증).
out4=$("$GEN" --plan "$FX/04-nested-fence.md" 2>/dev/null)
_t7n=$(printf '%s' "$out4" | grep -c '^## Task ')
printf '%s' "$out4" | grep -q '이 줄은 4-backtick 블록 안이다' \
  && printf '%s' "$out4" | grep -q '^### Task 9: 펜스 안 함정' \
  && [ "$_t7n" -eq 1 ] \
  && ok "T7 중첩 펜스 보존" || nope "T7" "펜스 경계 오인 (^## Task=$_t7n, 기대 1)"

# ── T8~T12: 거부 계약 · read-only · DAG 무오염 (Task 2) ────────────────

# T8 — Task 0건 → rc=1 + stdout 빈손 (AC-2)
o=$("$GEN" --plan "$FX/05-prose-no-task.md" 2>/dev/null); rc=$?
[ "$rc" -eq 1 ] && [ -z "$o" ] \
  && ok "T8 산문형 전면 거부" || nope "T8" "rc=$rc stdout=${#o}자 (기대 rc=1·0자)"

# T9 — Step 0개 Task → rc=1 + stdout 빈손. **정상 Task 1개가 있어도** 부분 출력 금지
o=$("$GEN" --plan "$FX/06-zero-step.md" 2>/dev/null); rc=$?
[ "$rc" -eq 1 ] && [ -z "$o" ] \
  && ok "T9 Step0 Task 전면 거부(부분 출력 없음)" || nope "T9" "rc=$rc stdout=${#o}자"

# T10 — 거부 사유 3종이 서로 구별된다 (AC-2 검증 방법)
e1=$("$GEN" --plan "$FX/does-not-exist.md" 2>&1 >/dev/null)
e2=$("$GEN" --plan "$FX/05-prose-no-task.md" 2>&1 >/dev/null)
e3=$("$GEN" --plan "$FX/06-zero-step.md" 2>&1 >/dev/null)
if [ "$e1" != "$e2" ] && [ "$e2" != "$e3" ] && [ "$e1" != "$e3" ] \
   && printf '%s' "$e1" | grep -q '없음' \
   && printf '%s' "$e2" | grep -q '0건' \
   && printf '%s' "$e3" | grep -q 'Step 0개'; then
  ok "T10 거부 사유 3종 구별"
else
  nope "T10" "사유 미구별 — [$e1] [$e2] [$e3]"
fi

# T11 — read-only (AC-6): 실행 전후 워킹트리 델타 0
#   `A && md5 || A && md5sum` 은 좌결합이라 md5 성공 후에도 md5sum 이 항상 실행된다.
if command -v md5 >/dev/null 2>&1; then _H=md5; else _H=md5sum; fi
_before=$(cd "$PLUGIN" && git status --porcelain | sort | $_H)
"$GEN" --plan "$FX/01-h3-5step.md" >/dev/null 2>&1
"$GEN" --plan "$FX/05-prose-no-task.md" >/dev/null 2>&1
_after=$(cd "$PLUGIN" && git status --porcelain | sort | $_H)
[ "$_before" = "$_after" ] \
  && ok "T11 read-only (워킹트리 델타 0)" || nope "T11" "파일 변경 발생"

# T12 — DAG 무오염 (AC-3): 골격에 YAML 블록이 없어 병렬 batch 가 열리지 않는다
#   `depends_on: []` 를 전 태스크에 내면 find_independent_batch 가 무경고로
#   `T1 T2 T3` 를 반환한다(실측). 그래서 아예 만들지 않는 것이 계약이다.
_tmp="${TMPDIR:-/tmp}/p2t-$$.md"
"$GEN" --plan "$FX/02-h2-varstep.md" > "$_tmp" 2>/dev/null
# shellcheck source=/dev/null
. "$PLUGIN/scripts/dag/parse-dag.sh"
# ★ 가드 — 파서 부재·함수 개명 시 _y 가 빈손이 되어 batch=0 으로 **영구 통과**한다(Phase C I-5).
type dag::extract_yaml >/dev/null 2>&1 \
  || { nope "T12" "dag::extract_yaml 미정의 — 어서션이 공허해진다"; finish; }
_y=$(dag::extract_yaml "$_tmp" 2>/dev/null)
_batch=$(dag::find_independent_batch "$_y" 2>/dev/null | grep -c . || true)
rm -f "$_tmp"
[ "${_batch:-0}" -le 1 ] \
  && ok "T12 DAG 무오염 (batch=${_batch:-0} ≤ 1)" || nope "T12" "거짓 병렬 batch=${_batch}"

# ── T13~T15: decomposing-ko 배선 (Task 3) ─────────────────────────────

D="$PLUGIN/skills/decomposing-ko/SKILL.md"

# T13 — 배선 절 존재 + fallback 명시 (AC-7)
grep -q 'plan-to-tasks.sh' "$D" \
  && grep -qE 'rc≠0|실패.*기존|fallback' "$D" \
  && ok "T13 생성기 배선 + fallback 명시" || nope "T13" "배선 또는 fallback 문구 부재"

# T14 — 생성기가 만들지 않는 4섹션을 decomposing 이 쓴다는 지시가 있다
_miss=""
for s14 in '의존 그래프' 'AC → Task 매핑' '파괴적 작업' '진행 상태'; do
  grep -q "$s14" "$D" || _miss="$_miss [$s14]"
done
[ -z "$_miss" ] && ok "T14 미생성 4섹션 작성 지시" || nope "T14" "누락:$_miss"

# T15 — chain edge 무손상 (AC-7): 기존 계약 문자열 보존
#   ★ 잠금 문자열은 **실측한 실존 리터럴**이어야 한다. 'BATCH-PHASE1-DONE:decomposing-ko' 는
#     repo 전체 0건 — 그걸 잠그면 영구 FAIL 이다(plan-reviewer 1회차 적발).
grep -q 'BATCH-PHASE1-DONE' "$D" \
  && grep -q 'implementing-ko 를 호출합니다' "$D" \
  && grep -q '호출 직전 한 줄 선언' "$D" \
  && ok "T15 기존 chain 계약 보존" || nope "T15" "기존 계약 문자열 소실"

# ── T16: run-all 편입 (AC-9) ──────────────────────────────────────────
#   기존 배선의 **회귀 잠금**이지 신규 기능의 RED 가 아니다 — 선-green 이 정상.
grep -q 'scripts/tests/dag/test-\*\.sh' "$PLUGIN/scripts/tests/run-all.sh" \
  && ok "T16 run-all glob 이 dag/ 하위를 편입" || nope "T16" "glob 미포함 — 스위트가 CI 에서 안 돈다"

# ── T17: reconcile-check 펜스 길이추적 회귀 잠금 (구현 중 발견) ──────────
#   본 FID 의 plan.md 가 fixture 04 를 문서화하며 **의도적으로 짝 없는 3-backtick** 을
#   담자, reconcile-check 의 `grep -cE '^```'` 오탐으로 R18(실 산출물 오탐 0)이 red 가 됐다.
#   길이추적으로 고쳤고, 되돌아가면 같은 오탐이 재발한다.
grep -q 'else if (n >= f) f = 0' "$PLUGIN/scripts/_internal/reconcile-check.sh" \
  && ok "T17 reconcile-check 펜스 길이추적 보존" \
  || nope "T17" "길이추적 소실 — 중첩 펜스 문서를 불완전으로 오탐한다"

# ── T18~T19: Phase C 프로브 격추분 (경계 입력) ─────────────────────────

# T18 — 닫는 펜스가 여는 펜스보다 **길어도** 닫힌다 (CommonMark: 여는 펜스 이상)
#   `==` 로 두면 3-open/4-close 인 유효 문서에서 뒤 Task 가 펜스 안으로 오인돼 무음 병합된다.
out18=$("$GEN" --plan "$FX/07-long-close-fence.md" 2>/dev/null)
_t18=$(printf '%s' "$out18" | grep -c '^## Task ')
[ "$_t18" -eq 2 ] \
  && ok "T18 긴 닫는 펜스 (3-open/4-close) 정상 종료" || nope "T18" "무음 병합 (^## Task=$_t18, 기대 2)"

# T19 — 코드펜스 **안**의 Step 은 실제 스텝이 아니다 → zero-step 거부가 발동해야 한다
#   가드가 없으면 "스텝 문법을 예시로만 담은 Task" 가 AC-2 거부를 우회한다(rc=0).
o19=$("$GEN" --plan "$FX/08-fenced-step-only.md" 2>/dev/null); rc19=$?
[ "$rc19" -eq 1 ] && [ -z "$o19" ] \
  && ok "T19 펜스 안 예시 Step 은 미계수 (zero-step 거부)" || nope "T19" "rc=$rc19 stdout=${#o19}자 (기대 rc=1·0자)"

finish
