#!/usr/bin/env bash
# design-reviewer-ko 계약 — evaluator·판정 시그널·start-all 배선
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

AG="$PLUGIN/agents/design-reviewer-ko.md"
SA="$PLUGIN/commands/start-all.md"

[ -f "$AG" ] || { nope "T0 agent 파일" "부재"; finish; }

grep -q '^role: evaluator' "$AG" \
  && ok "T1 role: evaluator" || nope "T1" "evaluator 마커 없음"

# Write/Edit 하드 박탈 — tools 라인에 Write|Edit 없어야 함
tools=$(awk '/^tools:/{print; exit}' "$AG")
printf '%s' "$tools" | grep -Eqi 'Write|Edit' \
  && nope "T2 tools" "Write/Edit 잔존: $tools" \
  || ok "T2 tools Write/Edit 부재"

grep -q 'DESIGN-REVIEW-RESULT' "$AG" \
  && ok "T3 판정 시그널" || nope "T3" "DESIGN-REVIEW-RESULT 없음"

grep -q '실측 의무' "$AG" && grep -q 'Interactions' "$AG" \
  && ok "T4 실측·Interactions 관점" || nope "T4" "실측/Interactions 부재"

grep -q 'devfsd:design-reviewer-ko' "$SA" \
  && grep -q 'design-review.md' "$SA" \
  && ok "T5 start-all dispatch 배선" || nope "T5" "start-all 미배선"

# A 또는 B 산출 시 항상 — SKIP은 둘 다 없을 때만
grep -qE '하나라도 산출|항상' "$SA" \
  && ok "T6 항상 리뷰 계약" || nope "T6" "항상 조건 부재"

# Wave B: Critical cap §auto 정지 + Important-only 자동통과 + Critical 집계줄 파싱
grep -qE '\^Critical:|Critical:\[\[:space:\]\]' "$SA" \
  && grep -q 'Important-only cap' "$SA" \
  && grep -qE 'Critical cap|§auto 자동통과 금지' "$SA" \
  && ok "T7 Critical 정지·Important auto-pass 산문" \
  || nope "T7" "Wave B Critical/Important 계약 부재"

# ── 문서·일관성 P0 드리프트 락 (gen-eval agents 수 · CLAUDE foundation 5.5) ──
GE="$PLUGIN/docs/harness-principles.md"
CL="$PLUGIN/CLAUDE.md"
[ -f "$GE" ] || { nope "T8 gen-eval 파일" "부재"; finish; }
[ -f "$CL" ] || { nope "T11 CLAUDE.md" "부재"; finish; }

# T8: harness 매트릭스에 design-reviewer-ko 필수 (제거 시 FAIL — ghost-agent 재발 방지)
grep -q 'design-reviewer-ko' "$GE" \
  && ok "T8 gen-eval design-reviewer-ko" \
  || nope "T8" "generator-evaluator에 design-reviewer-ko 부재"

# T9: agents 16종 표기 + Evaluator 목록에 design-reviewer (구 '7종뿐' 회귀 금지)
grep -q '16종' "$GE" \
  && grep -q 'design-reviewer-ko' "$GE" \
  && ! grep -q '7종뿐' "$GE" \
  && ok "T9 gen-eval agents 16종 (7종뿐 부재)" \
  || nope "T9" "16종/design-reviewer 누락 또는 7종뿐 잔존"

# T10: agents/*.md 실측 == 16, gen-eval이 그와 모순되는 7종뿐 미포함
ag_count=$(ls "$PLUGIN"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$ag_count" -eq 16 ] && ! grep -q '7종뿐' "$GE" \
  && ok "T10 agents 실측 16 + gen-eval 비모순" \
  || nope "T10" "agents=$ag_count (기대 16) 또는 gen-eval 7종뿐"

# T10b: gen-eval 실재 에이전트 줄의 이름 집합 == agents/*.md · Generator/Evaluator 수 == 실측
_ge_set=$(grep '^\*\*실재 에이전트는' "$GE" | grep -oE '`[a-z-]+-ko`' | tr -d '`' | sort -u)
_ag_set=$(ls "$PLUGIN"/agents/*.md | xargs -n1 basename | sed 's/\.md$//' | sort -u)
_ev_n=$(grep -l '^role: evaluator' "$PLUGIN"/agents/*.md | wc -l | tr -d ' ')
[ -n "$_ge_set" ] && [ "$_ge_set" = "$_ag_set" ] \
  && grep -q "${ag_count}종뿐\*\*: Generator $((ag_count - _ev_n)) (" "$GE" && grep -q "/ Evaluator ${_ev_n} (" "$GE" \
  && ok "T10b gen-eval 에이전트 집합·Generator/Evaluator 수 == 실측" \
  || nope "T10b" "gen-eval 실재 에이전트 줄이 agents/ 와 다르다(이름 집합 또는 Generator·Evaluator 수)"

# T11: CLAUDE foundation Step 5.5 전면-skip 단정 금지 · 셸/allowlist 존재
#   구 문구: "Step 5.5 는 skip" / "Step 5.5(화면 루프) skip"
#   허용: "전면 skip 하지 않는다" + 셸 allowlist
if grep -qE 'Step 5\.5[[:space:]]*는[[:space:]]*skip|Step 5\.5\(화면 루프\)[[:space:]]*skip' "$CL"; then
  nope "T11" "CLAUDE foundation Step 5.5 전면-skip 잔존"
elif grep -qE '셸|allowlist|foundation-shell' "$CL"; then
  ok "T11 CLAUDE foundation 5.5 셸 전용"
else
  nope "T11" "CLAUDE에 셸/allowlist/foundation-shell 부재"
fi

# 변이(비-vacuous): design-reviewer 토큰 제거 시 T8과 동형 판정이 FAIL이어야 함
mut=$(mktemp)
sed '/design-reviewer-ko/d' "$GE" >"$mut"
grep -q 'design-reviewer-ko' "$mut" \
  && nope "T8.m" "변이 sed 실패(토큰 잔존)" \
  || ok "T8.m design-reviewer 제거 변이 → T8 동형 FAIL 경로"
rm -f "$mut"

# T12: 장르 규칙 행 심각도 (FID 20260929-enterprise-genre-rules AC-6)
_gr=$(grep -F '| 장르 규칙 |' "$AG" | head -1)
_gi=$(printf '%s' "$_gr" | awk -F'|' '{print $4}')   # $2=관점 $3=Critical $4=Important $5=Minor
_gm=$(printf '%s' "$_gr" | awk -F'|' '{print $5}')
if [ -n "$_gr" ] && printf '%s' "$_gi" | grep -q '미충족' && printf '%s' "$_gi" | grep -q 'genre' \
   && printf '%s' "$_gm" | grep -q 'unknown' && printf '%s' "$_gm" | grep -qF '사유 없는 override'; then
  ok "T12 장르 규칙 — 미충족 Important · unknown·사유 없는 override Minor"
else
  nope "T12" "행='${_gr}'"
fi

# T13: 리뷰어 관점 표 ↔ 규칙 카탈로그 심각도 일치 (FID 20260929-design-rule-id-catalog AC-5)
#   ## 6관점 검증 기준 표만 읽는다 — 실측 의무 표 등 다른 표는 열 의미가 달라 오판한다.
_CQ="$PLUGIN/scripts/_internal/check-screen-quality.sh"
_cat=$(bash "$_CQ" --rules 2>/dev/null | awk -F'|' '{id=$2; s=$3; gsub(/^ +| +$/,"",id); gsub(/^ +| +$/,"",s)} id ~ /^[SGA]-/ {print id, s}')
_cn=$(printf '%s\n' "$_cat" | grep -c . || true)
_tbl=$(awk '/^## 6관점 검증 기준/{f=1;next} f&&/^## /{exit} f&&/^\|/' "$AG")
_mis=""
while read -r _id _sev; do
  [ -n "$_id" ] || continue
  read -r _c _i _m <<<"$(printf '%s\n' "$_tbl" | awk -F'|' -v k="\`$_id\`" '
    { if (index($3,k)) c=1; if (index($4,k)) i=1; if (index($5,k)) m=1 } END { print c+0, i+0, m+0 }')"
  case "$_sev" in
    Important) _want="0 1 0" ;;
    Minor)     _want="0 0 1" ;;
    단계형)    _want="0 1 1" ;;
    *)         _want="?" ;;
  esac
  [ "$_c $_i $_m" = "$_want" ] || _mis="$_mis ${_id}(${_sev}→${_c}${_i}${_m})"   # 중괄호 필수 — bash 3.2 는 `$_sev→` 의 멀티바이트 첫 바이트를 변수명에 붙여 set -u 로 abort 한다
done <<EOF
$_cat
EOF
if [ "${_cn:-0}" -eq 22 ] && [ -z "$_mis" ] && printf '%s\n' "$_tbl" | grep -qF '| 안티패턴 |'; then
  ok "T13 관점 표가 카탈로그 22개 ID 를 심각도 열대로 인용 · Critical 0 · 안티패턴 행"
else
  nope "T13" "카탈로그 ${_cn}개 불일치:$_mis"
fi

# T14: S-A11Y-LABEL 설명이 이름 없는 input(aria·label for↔id 짝·감쌈) 기준 (FID 20261005-screen-label-guidance AC-4)
_ra=$(grep -F 'S-A11Y-LABEL' "$AG" | sed -n 1p)
_ra_ok() { printf '%s' "$1" | grep -q '이름 없는 input' && printf '%s' "$1" | grep -q 'for' && printf '%s' "$1" | grep -q '감쌈' && printf '%s' "$1" | grep -qF '`a11y-label`'; }
if _ra_ok "$_ra"; then ok "T14.a S-A11Y-LABEL 설명 = 이름 없는 input(aria·for↔id 짝·감쌈) + 실측 표기 유지"; else nope "T14.a" "설명 불충족: ${_ra:0:80}"; fi
if ! _ra_ok "$(printf '%s' "$_ra" | sed 's/이름 없는 input/label 누락 input/')"; then ok "T14.b 음성 — 구 문구(label 누락 input)로 되돌리면 단언이 FAIL"; else nope "T14.b" "구 문구가 통과"; fi

# ── T15~T17: 촬영 이미지 배선 (FID 20261110-design-visual-review-loop AC-1·AC-2·AC-3) ──
#   연결 문자열 잠금이다 — 에이전트가 실제로 이미지를 보고 따르는지는 측정하지 않는다(한계).
UD="$PLUGIN/agents/ui-designer-ko.md"
_sa_A=$(awk '/^#### A\. /{f=1;next} f&&/^#### /{exit} f' "$SA")
_sa_A2=$(awk '/^#### A2\. /{f=1;next} f&&/^#### /{exit} f' "$SA")
_sa_D=$(awk '/^#### D\. /{f=1;next} f&&/^#### /{exit} f' "$SA")
_t15() {  # $1=A절 $2=A2절 $3=D절
  local m="" k
  for k in 'templates/frontend-design-guide.md' 'templates/screen-design-guide.md' 'screen-shot.sh' '.specops/<BATCH_ID>/shots/<name>' '1280·390' 'SCREEN-SHOT: SKIP' '찍지 못하면 멈추지 않는다' '`|` 로 시작 금지' 'foundation 셸은 찍지 않는다'; do
    printf '%s' "$1" | grep -qF -- "$k" || m="$m [A:$k]"
  done
  printf '%s' "$2" | grep -qF '.specops/<BATCH_ID>/shots/' || m="$m [A2:shots]"
  printf '%s' "$3" | grep -qF '.specops/<BATCH_ID>/shots/' || m="$m [D:shots]"
  printf '%s' "$m"
}
_m15=$(_t15 "$_sa_A" "$_sa_A2" "$_sa_D")
[ -z "$_m15" ] && ok "T15.a start-all 2.5-A 지침·촬영·다듬기·촬영 실패 비차단 + A2·D 입력에 촬영 폴더" || nope "T15.a" "누락:$_m15"
_n15a=$(_t15 "$(printf '%s' "$_sa_A" | grep -vF 'screen-shot.sh')" "$_sa_A2" "$_sa_D")
_n15b=$(_t15 "$_sa_A" "$(printf '%s' "$_sa_A2" | sed 's#\.specops/<BATCH_ID>/shots/##')" "$_sa_D")
_n15c=$(_t15 "$_sa_A" "$_sa_A2" "$(printf '%s' "$_sa_D" | sed 's#\.specops/<BATCH_ID>/shots/##')")
{ [ -n "$_n15a" ] && [ "$_n15b" = " [A2:shots]" ] && [ "$_n15c" = " [D:shots]" ]; } \
  && ok "T15.b 음성 — 촬영 줄·A2 입력·D 입력을 각각 지운 사본은 그 지점만 FAIL" || nope "T15.b" "a='$_n15a' b='$_n15b' c='$_n15c'"
# T15.c: 촬영 실패 줄 자체가 '| 로 시작 금지' 를 갖는다 — 이 문구는 A 절의 다른 줄에도 있어 절 단위 검사로는 공허하다
_skl=$(printf '%s\n' "$_sa_A" | grep -F 'SCREEN-SHOT: SKIP — <name>')
{ [ -n "$_skl" ] && printf '%s' "$_skl" | grep -qF '`|` 로 시작 금지' && printf '%s' "$_skl" | grep -qF 'queue.md'; } \
  && ok "T15.c 촬영 실패 줄에 queue.md 산문 줄·\`|\` 금지" || nope "T15.c" "줄='${_skl:0:120}'"
printf '%s' "${_skl//\`|\` 로 시작 금지/}" | grep -qF '`|` 로 시작 금지' && nope "T15.d" "지운 줄에도 문구가 남는다" || ok "T15.d 음성 — 그 줄에서 문구를 지우면 FAIL"
# T15.e: A 절 키마다 — 그 키를 지운 사본은 그 키만 FAIL (키별 진단력)
_k15bad=""
for k in 'templates/frontend-design-guide.md' 'templates/screen-design-guide.md' 'screen-shot.sh' '.specops/<BATCH_ID>/shots/<name>' '1280·390' 'SCREEN-SHOT: SKIP' '찍지 못하면 멈추지 않는다' 'foundation 셸은 찍지 않는다'; do
  [ "$(_t15 "${_sa_A//"$k"/}" "$_sa_A2" "$_sa_D")" = " [A:$k]" ] || _k15bad="$_k15bad [$k]"
done
[ -z "$_k15bad" ] && ok "T15.e 음성 — A 절 키 8개를 하나씩 지우면 그 키만 FAIL" || nope "T15.e" "진단 불일치:$_k15bad"
if ! command -v node >/dev/null 2>&1; then echo "SKIP T16.0 (node 없음 — 규칙 ID 대조 생략)"; _RID="L-CLIP-X L-OVERLAP L-WRAP-CHIP L-SCROLL-X L-FIXED-COVER"; else
_RID=$(node "$PLUGIN/scripts/_internal/ui-probe.cjs" --rules 2>/dev/null | sed -n 's/^| \(L-[A-Z-]*\) |.*/\1/p' | tr '\n' ' ' | sed 's/ $//'); fi
[ "$_RID" = "L-CLIP-X L-OVERLAP L-WRAP-CHIP L-SCROLL-X L-FIXED-COVER" ] && ok "T16.0 배치 규칙 ID 는 ui-probe --rules 에서 읽는다(정의 한 곳)" || nope "T16.0" "읽은 ID: [$_RID]"
_K16="@1280.png|@390.png|위계|정렬|390 폭에서의 잘림·겹침|촬영 이미지 없음|.probe.txt|$(printf '%s' "$_RID" | sed 's/ /|/g')|계측 못 함"   # 규칙 ID 는 읽은 값에서 조립한다
_K16UD='계측 오탐 의심|`[시각]` 접두의 **Minor**(증명 줄 불필요)|인용할 것 없이 이미지에서 받은 인상뿐이면|문제를 못 본 화면에는 `[시각]` 줄을 쓰지 않는다|그 규칙 ID 와 줄을 인용해 **Important**|계측 결과가 없거나 적중이 없으면 이 예외는 없다|0건으로 읽지 않는다|목적 문장 ↔ Layout·목업'
_K16AG='계측 오탐 의심|`배치 경고 0건` 은 계측이 재는 범위|`[시각]` 접두의 **Minor 로만**|그 줄을 인용해 **Important** 로 낸다|위반 없음으로 쓰지 않는다|리뷰어는 계측을 직접 돌리지 않는다'
_t16() {  # $1=에이전트 본문 $2=키 목록(| 구분)
  local m="" k; local IFS='|'
  for k in $2; do printf '%s' "$1" | grep -qF -- "$k" || m="$m [$k]"; done
  printf '%s' "$m"
}
_ud=$(cat "$UD"); _ag=$(cat "$AG")
[ -z "$(_t16 "$_ud" "$_K16|$_K16UD")" ] && ok "T16.a ui-designer-ko — 촬영 이미지·계측 결과 입력 · 근거별 심각도 · 문제 없으면 줄 없음(AC-1)" || nope "T16.a" "누락:$(_t16 "$_ud" "$_K16|$_K16UD")"
_k16bad=""; _oIFS=$IFS; IFS='|'
for k in $_K16 $_K16UD; do IFS=$_oIFS; [ "$(_t16 "${_ud//"$k"/}" "$_K16|$_K16UD")" = " [$k]" ] || _k16bad="$_k16bad ud[$k]"; IFS='|'; done
for k in $_K16 $_K16AG; do IFS=$_oIFS; [ "$(_t16 "${_ag//"$k"/}" "$_K16|$_K16AG")" = " [$k]" ] || _k16bad="$_k16bad ag[$k]"; IFS='|'; done
IFS=$_oIFS
[ -z "$_k16bad" ] && ok "T16.b 음성 — 두 에이전트에서 키를 하나씩 지우면 그 키만 FAIL" || nope "T16.b" "진단 불일치:$_k16bad"
_t16d() { printf '%s' "$1" | grep -qF '증명 줄 불필요' && printf '%s' "$1" | grep -qF 'Important 의 빈칸 증명 규칙은 그대로다'; }
_t16d "$_ud" && ok "T16.d ui-designer-ko — 인상뿐인 지적은 증명 줄 불필요 · Important 빈칸 증명 규칙 유지" || nope "T16.d" "문구 없음"
{ ! _t16d "${_ud//증명 줄 불필요/}" && ! _t16d "${_ud//Important 의 빈칸 증명 규칙은 그대로다/}"; } && ok "T16.e 음성 — 두 문구를 각각 지우면 FAIL" || nope "T16.e" "지워도 통과한다"
_old16='여기서 본 것은 `[시각]` 접두의 **Minor 로만** 적는다'
! printf '%s' "$_ud" | grep -qF "$_old16" && printf '%s\n%s' "$_ud" "$_old16" | grep -qF "$_old16" \
  && ok "T16.f ui-designer-ko — 'Minor 로만 적는다' 종전 문장 없음(되살린 사본에서는 잔존 판정이 발화)" || nope "T16.f" "종전 문장 잔존"
_fm() { awk 'NR==1&&/^---/{f=1;next} f&&/^---/{exit} f' "$1" | grep -E '^(model|effort|tools|role):' | tr '\n' ';'; }
[ "$(_fm "$UD")" = "model: opus;effort: high;tools: Read, Grep, Glob, Bash, Write;" ] \
  && ok "T16.c ui-designer-ko frontmatter 불변(model·effort·tools)" || nope "T16.c" "$(_fm "$UD")"
_m17=$(_t16 "$_ag" "$_K16|$_K16AG")
_row=$(printf '%s\n' "$_ag" | grep -E '^\| 배치\(렌더 계측\) \|')
_RID_MIN="L-WRAP-CHIP L-SCROLL-X L-FIXED-COVER"   # 좁은 폭 어림 규칙 — Minor 칸에만 (20261114)
_t17row() {  # $1=표 행 → 잘림·겹침 ID 는 Important 칸에만, 좁은 폭 어림 규칙 ID 는 Minor 칸에만 있는가
  local m="" id imp min crit
  crit=$(printf '%s' "$1" | awk -F'|' '{print $3}'); imp=$(printf '%s' "$1" | awk -F'|' '{print $4}'); min=$(printf '%s' "$1" | awk -F'|' '{print $5}')
  for id in $_RID; do
    case " $_RID_MIN " in
      *" $id "*) { printf '%s' "$min" | grep -qF "$id" && ! printf '%s%s' "$crit" "$imp" | grep -qF "$id"; } || m="$m [표:$id]" ;;
      *) { printf '%s' "$imp" | grep -qF "$id" && ! printf '%s%s' "$crit" "$min" | grep -qF "$id"; } || m="$m [표:$id]" ;;
    esac
  done
  printf '%s' "$m"
}
_m17="$_m17$(_t17row "$_row")"
printf '%s' "$_ag" | grep -qF 'Critical 은 주지 않는다' || _m17="$_m17 [계측 적중 Critical 금지]"
printf '%s' "$_ag" | grep -qF 'Critical·Important 로 올리지 않는다' || _m17="$_m17 [승격 금지]"
printf '%s' "$_ag" | grep -qF '이미지는 위 `[시각]` Minor 의 근거로만 쓴다' || _m17="$_m17 [6종 문장]"
printf '%s' "$_ag" | grep -qF '소스를 눈으로 보고 시각 품질을 단정하지 않는다' && _m17="$_m17 [구 문장 잔존]"
[ -z "$_m17" ] && ok "T17.a design-reviewer-ko 촬영 이미지 입력 · [시각] Minor 상한 · 6종 Important 는 계측으로만 · 구 문장 제거" || nope "T17.a" "$_m17"
printf '%s\n%s' "$_ag" '소스를 눈으로 보고 시각 품질을 단정하지 않는다' | grep -qF '소스를 눈으로 보고 시각 품질을 단정하지 않는다' \
  && ok "T17.c 양성 대조 — 구 문장을 되살린 사본에서는 잔존 판정이 발화한다" || nope "T17.c" "잔존 판정 미발화"
_swap=$(printf '%s' "$_row" | awk -F'|' 'BEGIN{OFS="|"}{t=$4;$4=$5;$5=t;print}')
[ -n "$_row" ] && [ -n "$(_t17row "$_swap")" ] && ok "T17.d 음성 — 표의 Important·Minor 칸을 맞바꾼 사본은 FAIL" || nope "T17.d" "맞바꿔도 통과한다"
[ "$(_fm "$AG")" = "model: sonnet;effort: high;role: evaluator;tools: Read, Grep, Glob, Bash;" ] \
  && ok "T17.b design-reviewer-ko frontmatter 불변(model·effort·role·tools — Write/Edit 없음)" || nope "T17.b" "$(_fm "$AG")"

# ── T18: 배치 계측 결과 배선 — 지침 ③ · 단일 경로 (FID 20261110-visual-severity-clip-overlap AC-7 ①②④) ──
SG="$PLUGIN/templates/screen-design-guide.md"; SP="$PLUGIN/skills/specifying-ko/SKILL.md"
_sg3=$(awk '/^## ③ /{f=1;next} f&&/^## /{exit} f' "$SG")
_sp66=$(grep -F 'subagent_type: "devfsd:ui-designer-ko"' "$SP")
_t18() {  # $1=③절 $2=6.6 dispatch 줄
  local m=""
  printf '%s' "$1" | grep -qF '.probe.txt' || m="$m [guide:probe.txt]"
  printf '%s' "$1" | grep -qF 'UI-PROBE: SKIP' || m="$m [guide:SKIP]"
  printf '%s' "$1" | grep -qF '찍을 때마다 덮어쓴다' || m="$m [guide:덮어쓴다]"
  printf '%s' "$1" | grep -qF '0건으로 읽지 않는다' || m="$m [guide:0건 아님]"
  printf '%s' "$2" | grep -qF '.specops/<FID>/shots/' || m="$m [6.6:shots]"
  printf '%s' "$2" | grep -qF '.probe.txt' || m="$m [6.6:probe.txt]"
  printf '%s' "$m"
}
[ -z "$(_t18 "$_sg3" "$_sp66")" ] && ok "T18.a 계측 결과 배선 — 지침 ③(남김·SKIP·덮어씀·0건 아님) · specifying 6.6 입력(촬영 폴더·계측 결과)" || nope "T18.a" "누락:$(_t18 "$_sg3" "$_sp66")"
_n18=""
[ "$(_t18 "${_sg3//UI-PROBE: SKIP/}" "$_sp66")" = " [guide:SKIP]" ] || _n18="$_n18 guide:SKIP"
[ "$(_t18 "${_sg3//찍을 때마다 덮어쓴다/}" "$_sp66")" = " [guide:덮어쓴다]" ] || _n18="$_n18 guide:덮어쓴다"
[ "$(_t18 "$_sg3" "${_sp66//.probe.txt/}")" = " [6.6:probe.txt]" ] || _n18="$_n18 6.6:probe"
[ "$(_t18 "$_sg3" "${_sp66//.specops\/<FID>\/shots\//}")" = " [6.6:shots]" ] || _n18="$_n18 6.6:shots"
[ -z "$_n18" ] && ok "T18.b 음성 — 지점마다 지우면 그 지점만 FAIL" || nope "T18.b" "진단 불일치:$_n18"

# ── T19: 배치 계측 결과 배선 — start-all 2.5 (AC-7 ③) ──
_t19() {  # $1=A절 $2=A2절 $3=D절
  local m=""
  printf '%s' "$1" | grep -qF '.probe.txt' || m="$m [A:probe.txt]"
  printf '%s' "$2" | grep -qF '.probe.txt' || m="$m [A2:probe.txt]"
  printf '%s' "$3" | grep -qF '.probe.txt' || m="$m [D:probe.txt]"
  printf '%s' "$m"
}
[ -z "$(_t19 "$_sa_A" "$_sa_A2" "$_sa_D")" ] && ok "T19.a start-all — A(남김)·A2(화면 전문가 입력)·D(리뷰어 입력)에 배치 계측 결과" || nope "T19.a" "누락:$(_t19 "$_sa_A" "$_sa_A2" "$_sa_D")"
_n19=""
[ "$(_t19 "${_sa_A//.probe.txt/}" "$_sa_A2" "$_sa_D")" = " [A:probe.txt]" ] || _n19="$_n19 A"
[ "$(_t19 "$_sa_A" "${_sa_A2//.probe.txt/}" "$_sa_D")" = " [A2:probe.txt]" ] || _n19="$_n19 A2"
[ "$(_t19 "$_sa_A" "$_sa_A2" "${_sa_D//.probe.txt/}")" = " [D:probe.txt]" ] || _n19="$_n19 D"
[ -z "$_n19" ] && ok "T19.b 음성 — 절마다 지우면 그 절만 FAIL" || nope "T19.b" "진단 불일치:$_n19"

finish
