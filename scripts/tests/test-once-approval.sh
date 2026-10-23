#!/usr/bin/env bash
# test-once-approval.sh — §일괄(질문 묶음 → 승인 묶음 1회 → 무정지) 문서 계약 잠금 (20261023-speed-l1-single)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || exit 1
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SK="$PLUGIN/skills"
# $1=파일 $2=시작 줄 정규식(awk ERE) $3=끝 줄 정규식 — 시작 줄 다음부터 끝 줄 앞까지(끝이 없으면 파일 끝)
#   정규식은 ENVIRON 으로 넘긴다 — awk -v 는 역슬래시 이스케이프를 풀어 `\[` 가 문자 클래스가 된다
_sec() { _S="$2" _E="$3" awk 'f&&$0~ENVIRON["_E"]{exit} f{print} $0~ENVIRON["_S"]{f=1}' "$1"; }
# $1=ID $2=본문 $3…=모두 들어 있어야 하는 고정 문자열
_has() { local id=$1 body=$2 miss="" n; shift 2; for n in "$@"; do printf '%s' "$body" | grep -qF -- "$n" || miss="$miss [$n]"; done
  [ -z "$miss" ] && ok "$id" || nope "$id" "없음:$miss"; }
OA="$SK/specifying-ko/once-approval.md"
[ -f "$OA" ] && ok "O1.a once-approval.md 실재 (AC-3)" || nope "O1.a"
_ob=$(_sec "$OA" '^## 2\. 승인 묶음' '^## 3\. ')
_has "O1.b 승인 묶음 항목 고정 목록 (AC-3)" "$_ob" \
  "1. **intent**" "2. **분석 요약**" "**버린 대안**" "4. **spec·AC**" "5. **화면 경로**" "6. **IF 변경**" "7. **질문 답**" "ASSUMED" "8. **승인 뒤 자동 진행**" "9. **그래도 멈추는 곳**" "**병렬 worktree**"
[ "$(printf '%s\n' "$_ob" | grep -cE '^[0-9]+\. \*\*')" = 9 ] && ok "O1.e 승인 묶음 항목 정확히 9개 (AC-3)" || nope "O1.e" "$(printf '%s\n' "$_ob" | grep -cE '^[0-9]+\. \*\*')"
_has "O1.c 질문 묶음 규칙 (AC-3)" "$(_sec "$OA" '^## 1\. 질문 묶음' '^## 2\. ')" "최대 2회" "많아야 4개" "추천"
_has "O1.d 수정 요청·기록 (AC-3)" "$(_sec "$OA" '^## 3\. ' '^## 4\. ')" "다시 제시" "dev-decision.sh add <FID> approval" "Status: accepted" "/approve"
SP="$SK/specifying-ko/SKILL.md"
_has "O2.a specifying §일괄 판정 — Step 1 분기 검사 안 (AC-2)" "$(_sec "$SP" '진입 신호 검사' '^1\.5\. ')" \
  '**§일괄 판정' '`<!-- step: true -->`·`<!-- auto: true -->` 가 없으면 `§일괄` 이다' '(`entry: auto`·`batch`·`foundation` 은 해당 없음)' 'Step 6 에서 spec §1 에 `**§일괄**: true` 를 적고' 'once-approval.md' '`<!-- step: true -->` 줄은 FID 슬러그·대상 설명에서 뺀다'
_has "O2.b intent 표에 §일괄 행 (AC-4)" "$(_sec "$SP" '^1\.5\. ' '^2\. ')" '| §일괄' '승인 묶음'
_has "O2.c Step 3~5 §일괄 (AC-4)" "$(_sec "$SP" '^2\. \*\*Visual' '^5\.5\. ')" '**§일괄**: 질문을 한 번에 묶어 1회' '**§일괄**: 고르게 하지 않고' '**§일괄**: 섹션별 승인 없이'
_has "O2.d 화면 5.5 §일괄 (AC-4)" "$(_sec "$SP" '^5\.5\. ' '^5\.6\. ')" '**§일괄 이면 화면을 모두 만든 뒤**' '화면마다 하지 않고' '**[§auto 이외 모드]** (기존 동작):'
_has "O2.e IF 5.6 §일괄 (AC-4)" "$(_sec "$SP" '^5\.6\. ' '^6\. ')" '**§일괄 이면 바꾸는 인터페이스를**' '확인을 묻지 않은 채'
_has "O2.h Step 6 §일괄 라벨 (AC-2)" "$(_sec "$SP" '^6\. \*\*설계 문서 작성' '^7\. ')" '**§일괄 라벨**' '`**§일괄**: true`'
_g=$(_sec "$SP" '^### 사용자 검토 게이트' '^## ')
_has "O2.f 스펙 검토 게이트 §일괄 — 위치 lite·trivial = 여기 · 정상 = clarifying 끝 (AC-4)" "$_g" '**[§일괄 모드]**' '승인 묶음은 clarifying-ko 끝에서' '정상 경로는 묻지 않고 clarifying-ko 를 호출한다' '아래 기존 동작은 `--step`(`<!-- step: true -->`)일 때만 적용한다' '위 trivial 통합 규칙(설계 승인 + 축약 승인 2회 전제)은 `§일괄` 에 적용하지 않는다' '**[§auto·trivial 이외 모드]** (기존 동작)'
_has "O2.i lite 승인·스펙 검토·슬러그 줄 (AC-4)" "$(cat "$SP")" '(**§일괄**: 여기서 묻지 않는다 — 이 1회는 Step 8 자리의 승인 묶음으로' '(**§일괄**: `### 사용자 검토 게이트` 의 [§일괄 모드])' '#   args 의 주석 줄(`<!-- step: true -->` 등)은 슬러그에서 뺀다'
_l1=$(printf '%s\n' "$_g" | grep -nF '**[§일괄 모드]**' | head -1 | cut -d: -f1); _l2=$(printf '%s\n' "$_g" | grep -nF '**[§auto·trivial 이외 모드]** (기존 동작)' | head -1 | cut -d: -f1)
{ [ -n "$_l1" ] && [ -n "$_l2" ] && [ "$_l1" -lt "$_l2" ]; } && ok "O2.g §일괄 문단이 기존 동작 앞 (AC-4)" || nope "O2.g" "l1=$_l1 l2=$_l2"
AN="$SK/analyzing-ko/SKILL.md"
_has "O3.a analyzing Step 7 §일괄 (AC-4)" "$(_sec "$AN" '^### Step 7' '^### Step 8')" '**[§일괄]**' '분석 검토는 승인 묶음으로 넘깁니다(§일괄)' 'once-approval.md' '[y/n] 을 묻지 않고 Step 8 로 간다' '아래는 `--step` 일 때의 동작이다'
_has "O3.b analyzing lite-mini §일괄 (AC-4)" "$(_sec "$AN" '^## \[lite-mini 분기\]' '^## 체크리스트')" '**§일괄** 이면 Step 7' '묻지 않고 지난다' '`<!-- step: true -->` 줄도 뺀다'
_has "O3.c analyzing Step 0 step 표지 제거 (AC-1)" "$(_sec "$AN" '^### Step 0' '^### Step 1')" '`<!-- step: true -->` 줄도 함께 뺀다'
CL="$SK/clarifying-ko/SKILL.md"
_has "O4.a clarifying §일괄 절 (AC-4)" "$(_sec "$CL" '^## §일괄 모드' '^## ')" '질문 묶음 2회째' '많아야 4개' 'once-approval.md' '승인 전에는 planning-ko 를 호출하지 않는다' '`status: ASSUMED`'
# AC-R-1 — --step 경로의 기존 게이트 문구 보존 (개수까지)
_has "O9.a 기존 게이트 문구 보존 (AC-R-1)" "$(cat "$SP" "$CL" "$AN")" \
  '**[§auto·trivial 이외 모드]** (기존 동작)' '**[§auto 이외 모드]** (기존 동작):' '**BLOCKING**: 한 번에 한 질문'
[ "$(grep -cF '분析 결과 검토. 진행? [y/n]' "$AN")" = 2 ] && ok "O9.c analyzing 검토 게이트 문구 2곳 보존 (AC-R-1)" || nope "O9.c" "$(grep -cF '분析 결과 검토. 진행? [y/n]' "$AN")"
# ── 승인 뒤 게이트 (Task 3) ──
_pe=$(_sec "$SK/planning-ko/SKILL.md" '^## 실행 전환' '^## ')
_has "O5.a planning 실행 전환 §일괄 (AC-5)" "$_pe" '**[§일괄 모드]**' '묻지 않고 서브에이전트 주도' '아래 질문은 `--step` 일 때만 한다' '어느 쪽으로 할까요?'
_l1=$(printf '%s\n' "$_pe" | grep -nF '**[§일괄 모드]**' | head -1 | cut -d: -f1); _l2=$(printf '%s\n' "$_pe" | grep -nF '어느 쪽으로 할까요?' | head -1 | cut -d: -f1)
{ [ -n "$_l1" ] && [ -n "$_l2" ] && [ "$_l1" -lt "$_l2" ]; } && ok "O5.f §일괄 문단이 실행 방식 질문 앞 (AC-5)" || nope "O5.f" "l1=$_l1 l2=$_l2"
_has "O5.b worktree 동의 표 §일괄 행 (AC-5)" "$(_sec "$SK/using-git-worktrees-ko/SKILL.md" '^## 생성 동의 게이트' '^## ')" '| §일괄 | 승인 묶음이 동의' '§auto/batch/§일괄 면 해당 행 적용' '`§일괄` 은 `^\*\*§일괄\*\*:[[:space:]]*true`'
_has "O5.c decomposing 규모 초과 §일괄 승격 (AC-5)" "$(_sec "$SK/decomposing-ko/SKILL.md" '^## trivial / §lite 단축 분기' '^## 체크리스트')" '**`§일괄`** 도 묻지 않고' 'dev-decision.sh add <FID> order' '정상 경로(clarify → plan)에 올리고'
_has "O5.d verify 상한 §일괄 (AC-5)" "$(_sec "$SK/verifying-evidence-ko/SKILL.md" '^### \[§auto 모드\] fix_loop cap 초과 처리' '^### ')" '**`§일괄`**' '사용자에게 보이고 판단을 받는다' '`§auto` 또는 `§일괄` 로 읽는다' '전역 재시도 뒤에도 남으면'
_has "O5.e PR 게이트 §일괄 ASSUMED (AC-5)" "$(_sec "$SK/performance-test-ko/SKILL.md" '^### 2\. 끝 보고' '^### 3\. ')" '`§일괄` 이면' "grep -n 'ASSUMED'" 'auto-state.md'
[ "$(grep -cF 'PR을 생성하시겠습니까? [y/n]' "$SK/performance-test-ko/SKILL.md")" = 2 ] && ok "O9.b PR 게이트 문구 2곳 보존 (AC-R-1)" || nope "O9.b" "$(grep -cF 'PR을 생성하시겠습니까? [y/n]' "$SK/performance-test-ko/SKILL.md")"
# 라벨 계약 — 쓰는 쪽(spec §1 `**§일괄**: true`)과 읽는 쪽 5곳의 정규식이 한 종류이고 실제로 맞는다
_re=$(grep -ohE "grep -qE '[^']*§일괄[^']*' \.specops/<FID>/spec\.md" "$SK/specifying-ko/SKILL.md" "$SK/clarifying-ko/SKILL.md" "$SK/planning-ko/SKILL.md" "$SK/verifying-evidence-ko/SKILL.md" "$SK/performance-test-ko/SKILL.md" | sed -E "s/^grep -qE '([^']*)'.*/\1/")
_n=$(printf '%s\n' "$_re" | grep -c .); _u=$(printf '%s\n' "$_re" | sort -u | grep -c .); _r1=$(printf '%s\n' "$_re" | head -1)
{ [ "$_n" = 5 ] && [ "$_u" = 1 ] && printf '**§일괄**: true\n' | grep -qE "$_r1" \
  && ! printf '**§일괄**: false\n' | grep -qE "$_r1" && ! printf '§일괄: true\n' | grep -qE "$_r1" && ! printf '**§auto**: true\n' | grep -qE "$_r1"; } \
  && ok "O8.a 라벨 정규식 5곳·1종 · 양성 1 음성 3 (AC-2·4·5)" || nope "O8.a" "n=$_n u=$_u re=$_r1"
# ── 진입 명령 --step (Task 4) ──
for c in start maintain start-lite maintain-lite; do
  _has "O6.$c commands/$c.md Process 의 --step·기본 §일괄 (AC-1)" "$(_sec "$PLUGIN/commands/$c.md" '^## Process' '^## ')" '`--step`' '<!-- step: true -->' '`§일괄`' 'once-approval.md' '없으면 넣지 않는다'
done
_has "O6.pos.start step 줄은 args 맨 앞 (AC-1)" "$(_sec "$PLUGIN/commands/start.md" '^## Process' '^## ')" '`<!-- step: true -->` 줄을 args 맨 앞에'
for c in maintain start-lite maintain-lite; do
  _has "O6.pos.$c step 줄은 약속어 다음 (AC-1)" "$(_sec "$PLUGIN/commands/$c.md" '^## Process' '^## ')" '약속어 줄(`<!-- entry: … -->`) 바로 다음 줄에'
done
_has "O7.a using-specops-ko 기본 동작 안내 (AC-1)" "$(cat "$SK/using-specops-ko/SKILL.md")" '**기본 동작 `§일괄`**' '`--step` — 슬래시로만(자연어 추론 금지)'
_has "O7.b README 진입로 --step (AC-1)" "$(_sec "$PLUGIN/README.md" '^## 진입로' '^## ')" '`--step`' '한 번에 승인'
finish
