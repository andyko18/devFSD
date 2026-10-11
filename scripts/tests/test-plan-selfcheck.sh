#!/usr/bin/env bash
# test-plan-selfcheck.sh — plan 자체검토 4항목 + AC 개수 상한 안내 (FID 20260808-plan-selfcheck-ac-cap)
#
# 근거: 20260808 세션 실측 — plan-reviewer 1회차 FAIL 3/3, 토큰 525k(서브에이전트의 52%).
#       FID2·FID3 의 Critical 이 동일 클래스였다 — 기존 테스트가 폐기 대상 의미를 계약으로
#       고정하고 있는데 plan 이 일부만 승계 대상으로 특정. 그 반복을 자체검토에서 끊는다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

PLAN="$PLUGIN/skills/planning-ko/SKILL.md"
SPEC="$PLUGIN/skills/specifying-ko/SKILL.md"
# 자체 검토 절만 잘라낸다 — 문서 다른 곳의 우연 일치로 공허 통과하는 것을 막는다.
_sec() { sed -n '/^## 자체 검토/,/^## 독립 리뷰/p' "$PLAN"; }
# 종료 앵커가 개명되면 sed 범위가 EOF 까지 조용히 확장된다(fail-open) — 앵커 실재를 먼저 잠근다.
grep -q '^## 독립 리뷰' "$PLAN" \
  || { nope "T0" "종료 앵커 '## 독립 리뷰' 부재 — _sec 범위가 EOF 로 확장됨"; finish; }

# T1 (AC-1): 자체 검토에 4항목이 더 있고 각 축을 다룬다
_s=$(_sec)
n=$(printf '%s' "$_s" | grep -cE '^\*\*[0-9]+\. ')
printf '%s' "$_s" | grep -q '기존 테스트' \
  && printf '%s' "$_s" | grep -qE '항상 통과|구조적으로' \
  && printf '%s' "$_s" | grep -q '복구' \
  && printf '%s' "$_s" | grep -qE 'RED 예상|추론' \
  && [ "${n:-0}" -ge 7 ] \
  && ok "T1 자체검토 ${n}항목 + 4축 존재" || nope "T1" "n=$n"

# T2 (AC-2): 절감이 목적이므로 "짧게" 단서가 있어야 한다
#   항목만 늘리면 plan 이 길어져 역효과다 — 그 위험을 문서가 스스로 경고하는지 본다.
printf '%s' "$_s" | grep -qE '짧게|한 줄|간결' \
  && ok "T2 짧게 쓰기 단서 존재" || nope "T2" "단서 부재"

# T3 (AC-3): AC 개수 상한 안내 + should 성격 명시
#   ⚠️ whole-file grep 을 쓰면 안 된다 — `상한` 은 "질문 상한"(다른 절), `should` 는
#      `must·should·nice-to-have`(AC 우선순위 값)에 매치해 **should 성격만 지워도 통과**한다
#      (Phase C 프로브 P3 실증). 해당 **행을 먼저 추출**해 행 안에서만 본다.
_ac_line=$(grep -m1 'AC 개수 상한' "$SPEC")
[ -n "$_ac_line" ] \
  && printf '%s' "$_ac_line" | grep -qE '상한|넘기지' \
  && printf '%s' "$_ac_line" | grep -qE 'should|하드 게이트가 아니' \
  && ok "T3 AC 개수 상한 안내(should)" || nope "T3" "상한 안내 부재 또는 should 성격 미명시"

# T4 (AC-R-1b): 기존 문구 보존 — 추가만 했는지
#   ⚠️ SPEC 쪽 양성 대조군으로 `check-ac-format\.sh` 를 쓰면 안 된다 — 본 FID 가 추가한
#      AC 상한 행 자체가 그 문자열을 포함해 **자기 추가분이 대조군을 오염**시킨다.
#      결과: 보존 대상인 기존 "AC 필수 필드" bullet 을 통삭제해도 통과했다(P5 실증).
#      기존 행에만 있는 고유 문자열로 앵커한다.
printf '%s' "$_s" | grep -q '스펙 커버리지' \
  && printf '%s' "$_s" | grep -q '플레이스홀더 스캔' \
  && printf '%s' "$_s" | grep -q '타입 일관성' \
  && grep -q 'AC 필수 필드 (기계 검증)' "$SPEC" \
  && grep -q '서식이 아니라 스위치' "$SPEC" \
  && ok "T4 기존 문구 보존 (추가만)" || nope "T4" "기존 문구 훼손"

finish
