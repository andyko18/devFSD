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

grep -q 'specops-ko:design-reviewer-ko' "$SA" \
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
GE="$PLUGIN/skills/generator-evaluator-ko/SKILL.md"
CL="$PLUGIN/CLAUDE.md"
[ -f "$GE" ] || { nope "T8 gen-eval 파일" "부재"; finish; }
[ -f "$CL" ] || { nope "T11 CLAUDE.md" "부재"; finish; }

# T8: harness 매트릭스에 design-reviewer-ko 필수 (제거 시 FAIL — ghost-agent 재발 방지)
grep -q 'design-reviewer-ko' "$GE" \
  && ok "T8 gen-eval design-reviewer-ko" \
  || nope "T8" "generator-evaluator에 design-reviewer-ko 부재"

# T9: agents 11종 표기 + Evaluator 목록에 design-reviewer (구 '7종뿐' 회귀 금지)
grep -q '11종' "$GE" \
  && grep -q 'design-reviewer-ko' "$GE" \
  && ! grep -q '7종뿐' "$GE" \
  && ok "T9 gen-eval agents 11종 (7종뿐 부재)" \
  || nope "T9" "11종/design-reviewer 누락 또는 7종뿐 잔존"

# T10: agents/*.md 실측 == 11, gen-eval이 그와 모순되는 7종뿐 미포함
ag_count=$(ls "$PLUGIN"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$ag_count" -eq 11 ] && ! grep -q '7종뿐' "$GE" \
  && ok "T10 agents 실측 11 + gen-eval 비모순" \
  || nope "T10" "agents=$ag_count (기대 11) 또는 gen-eval 7종뿐"

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
if [ "${_cn:-0}" -eq 20 ] && [ -z "$_mis" ] && printf '%s\n' "$_tbl" | grep -qF '| 안티패턴 |'; then
  ok "T13 관점 표가 카탈로그 20개 ID 를 심각도 열대로 인용 · Critical 0 · 안티패턴 행"
else
  nope "T13" "카탈로그 ${_cn}개 불일치:$_mis"
fi

# T14: S-A11Y-LABEL 설명이 이름 없는 input(aria·label for↔id 짝·감쌈) 기준 (FID 20261005-screen-label-guidance AC-4)
_ra=$(grep -F 'S-A11Y-LABEL' "$AG" | sed -n 1p)
_ra_ok() { printf '%s' "$1" | grep -q '이름 없는 input' && printf '%s' "$1" | grep -q 'for' && printf '%s' "$1" | grep -q '감쌈' && printf '%s' "$1" | grep -qF '`a11y-label`'; }
if _ra_ok "$_ra"; then ok "T14.a S-A11Y-LABEL 설명 = 이름 없는 input(aria·for↔id 짝·감쌈) + 실측 표기 유지"; else nope "T14.a" "설명 불충족: ${_ra:0:80}"; fi
if ! _ra_ok "$(printf '%s' "$_ra" | sed 's/이름 없는 input/label 누락 input/')"; then ok "T14.b 음성 — 구 문구(label 누락 input)로 되돌리면 단언이 FAIL"; else nope "T14.b" "구 문구가 통과"; fi

finish
