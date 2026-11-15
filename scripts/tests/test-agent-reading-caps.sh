#!/usr/bin/env bash
# 계획 단계 에이전트의 읽기 상한 (20261114 소스 검토 · 하류 실측)
#   하류 한 프로젝트의 작업 10건에서 계획 리뷰어·테스트 전문가 1회가 맥락 약 480K 토큰까지 갔다. 같은 plan.md(최대 100KB)를
#   통째로 여러 번 읽었고(계획 리뷰어 Read 결과 중앙 150K자 · 범위 지정 Read 비율 35%), 부모 프롬프트에만 있던 실행 상한은
#   에이전트 정의에 없었으며 기본 경로(commands/basic.md)의 전문가 호출에는 그 문장 자체가 없었다.
#   이 스위트는 8개 정의가 같은 "읽기 상한" 절을 갖고, 기본 경로 호출이 실행 상한을 적게 하는지 잠근다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

AGENTS="plan-reviewer test-designer req-designer ui-designer db-designer arch-designer api-designer security-designer"
sect() { awk -v h="$2" 'index($0,h)==1 { f=1; next } f && /^## / { exit } f { print }' "$1"; }

for a in $AGENTS; do
  f="$PLUGIN/agents/$a-ko.md"
  body=$(sect "$f" '## 읽기 상한')
  if [ -n "$body" ] \
     && printf '%s' "$body" | grep -qF 'offset' && printf '%s' "$body" | grep -qF 'limit' \
     && printf '%s' "$body" | grep -qF '통째로 두 번' \
     && printf '%s' "$body" | grep -qF '2회 이내' && printf '%s' "$body" | grep -qF '전체 스위트'; then
    ok "R1.$a ★ '## 읽기 상한' 절 — 절 단위 Read(offset/limit) · 같은 파일 통째 재읽기 금지 · 긴 명령 2회 · 전체 스위트 금지"
  else
    nope "R1.$a" "절이 없거나 핵심 문구(offset·limit·통째로 두 번·2회 이내·전체 스위트) 누락"
  fi
done

# 절 위치 — 빈 출력 규칙 앞(정의의 규칙 묶음 안). 위치가 흩어지면 읽는 쪽이 놓친다.
bad=""
for a in $AGENTS; do
  f="$PLUGIN/agents/$a-ko.md"
  l1=$(grep -n '^## 읽기 상한' "$f" | head -1 | cut -d: -f1); l2=$(grep -n '^## 빈 출력 규칙' "$f" | head -1 | cut -d: -f1)
  { [ -n "$l1" ] && [ -n "$l2" ] && [ "$l1" -lt "$l2" ]; } || bad="$bad $a"
done
[ -z "$bad" ] && ok "R2 8개 정의 모두 '읽기 상한' 이 '빈 출력 규칙' 앞에 있다" || nope "R2" "위치 어긋남:$bad"

# 절이 정의마다 같은 규칙을 말한다 — 한 정의만 약해지는 drift 방지(핵심 문장 8곳 동일)
n=$(for a in $AGENTS; do sect "$PLUGIN/agents/$a-ko.md" '## 읽기 상한' | grep -F '통째로 두 번' | head -1; done | sort -u | wc -l | tr -d ' ')
[ "$n" = 1 ] && ok "R3 핵심 문장이 8개 정의에서 글자까지 같다(drift 방지)" || nope "R3" "서로 다른 문장 ${n}종"

# 기본 경로: 전문가 호출 프롬프트에 실행 상한을 적게 한다(planning-ko 의 같은 규칙이 기본 경로에는 없었다)
BA="$PLUGIN/commands/basic.md"
line=$(grep -n 'EXPERTS: <에이전트' "$BA" | tail -1 | cut -d: -f1)
txt=$(sed -n "${line}p" "$BA")
{ printf '%s' "$txt" | grep -qF '긴 명령' && printf '%s' "$txt" | grep -qF '2회 이내' && printf '%s' "$txt" | grep -qF '전체 스위트' && printf '%s' "$txt" | grep -qF 'plan.md'; } \
  && ok "R4 ★ 기본 경로 전문가 호출이 프롬프트에 실행 상한(긴 명령 2회 · 전체 스위트 금지 · plan.md 절 단위 읽기)을 적게 한다" \
  || nope "R4" "basic.md 의 EXPERTS 줄에 실행·읽기 상한이 없다"

# 풀 경로 계획 skill 도 같은 읽기 규칙을 부모 프롬프트에 싣게 한다
PL="$PLUGIN/skills/planning-ko/SKILL.md"
grep -qF '같은 문서를 통째로 두 번 읽지' "$PL" \
  && ok "R5 planning-ko 의 전문가·리뷰어 실행 예산이 읽기 규칙(같은 문서 통째 재읽기 금지)도 싣게 한다" || nope "R5" "planning-ko 에 읽기 규칙 없음"

# 대조: 이 규칙이 리뷰 범위를 줄이지 않는다 — 한 번은 전부 읽는다는 문구가 있다
n=$(for a in $AGENTS; do sect "$PLUGIN/agents/$a-ko.md" '## 읽기 상한' | grep -cF '한 번은 끝까지'; done | paste -sd+ - | bc)
[ "$n" = 8 ] && ok "R6 ★ 대조: 상한은 반복 읽기만 막는다 — 8개 정의 모두 '한 번은 끝까지 읽는다'(리뷰 범위를 줄이지 않는다)" || nope "R6" "'한 번은 끝까지' 문구 ${n}곳(8곳 필요)"

finish
