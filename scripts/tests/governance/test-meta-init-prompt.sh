#!/usr/bin/env bash
# T21 — using-specops-ko 메타 §프로젝트 최초 진입 감지 4분기 검증 (FID 20260507)
# 메타 skill 은 Claude 가 평가하는 분기라 bash 직접 실행 불가 →
#   (a) 정적: SKILL.md 본문이 4분기 메시지 모두 명시 (clarifications.md Q5)
#   (b) fixture: 4 분기 조건 ([ -d .specops ] x [ -f CLAUDE.md ]) 가 의도대로 평가
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd ../.. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SKILL="$PLUGIN/skills/using-specops-ko/SKILL.md"


eval_branch() {
  # echo branch label for given (.specops, CLAUDE.md) combination
  local has_specops="$1" has_claude="$2"
  if [ "$has_specops" = "0" ] && [ "$has_claude" = "0" ]; then
    echo "전체"
  elif [ "$has_specops" = "1" ] && [ "$has_claude" = "0" ]; then
    echo "부분-claude"
  elif [ "$has_specops" = "0" ] && [ "$has_claude" = "1" ]; then
    echo "부분-specops"
  else
    echo "정상"
  fi
}

# ── T1.a 둘 다 부재 → "전체 안내" grep + fixture 조건 ──
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
has_specops=$([ -d .specops ] && echo 1 || echo 0)
has_claude=$([ -f CLAUDE.md ] && echo 1 || echo 0)
branch=$(eval_branch "$has_specops" "$has_claude")
cd /tmp && rm -rf "$TMPDIR"
if [ "$branch" = "전체" ] && grep -q "프로젝트가 초기화되지 않았습니다" "$SKILL"; then
  ok "T1.a 둘 다 부재 → 분기='전체' + SKILL.md 메시지 명시"
else
  nope "T1.a 전체" "branch=${branch}, SKILL grep 결과 확인 필요"
fi

# ── T2.a CLAUDE.md만 부재 → "부분 안내 (CLAUDE.md)" grep + fixture ──
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
mkdir -p .specops
has_specops=$([ -d .specops ] && echo 1 || echo 0)
has_claude=$([ -f CLAUDE.md ] && echo 1 || echo 0)
branch=$(eval_branch "$has_specops" "$has_claude")
cd /tmp && rm -rf "$TMPDIR"
if [ "$branch" = "부분-claude" ] && grep -q "CLAUDE.md\` 가 없습니다" "$SKILL"; then
  ok "T2.a CLAUDE.md 만 부재 → 분기='부분-claude' + SKILL.md 메시지 명시"
else
  nope "T2.a 부분-claude" "branch=${branch}"
fi

# ── T3.a .specops 만 부재 → "부분 안내 (.specops/)" grep + fixture ──
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
touch CLAUDE.md
has_specops=$([ -d .specops ] && echo 1 || echo 0)
has_claude=$([ -f CLAUDE.md ] && echo 1 || echo 0)
branch=$(eval_branch "$has_specops" "$has_claude")
cd /tmp && rm -rf "$TMPDIR"
if [ "$branch" = "부분-specops" ] && grep -q "\.specops/\` 가 없습니다" "$SKILL"; then
  ok "T3.a .specops 만 부재 → 분기='부분-specops' + SKILL.md 메시지 명시"
else
  nope "T3.a 부분-specops" "branch=${branch}"
fi

# ── T4.a 둘 다 존재 → 안내 X (정상 진입) + fixture ──
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
mkdir -p .specops
touch CLAUDE.md
has_specops=$([ -d .specops ] && echo 1 || echo 0)
has_claude=$([ -f CLAUDE.md ] && echo 1 || echo 0)
branch=$(eval_branch "$has_specops" "$has_claude")
cd /tmp && rm -rf "$TMPDIR"
if [ "$branch" = "정상" ] && grep -qE "안내 X|정상 specifying-ko 진입" "$SKILL"; then
  ok "T4.a 둘 다 존재 → 분기='정상' + SKILL.md '안내 X' 명시"
else
  nope "T4.a 정상" "branch=${branch}"
fi

echo ""
echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
