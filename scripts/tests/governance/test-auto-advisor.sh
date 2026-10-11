#!/usr/bin/env bash
# §auto advisor 보조 자문 통합 회귀 — 3 분기 advisor 텍스트 + graceful fallback 문구 가드
# 한계: presence-only(문구 존재만 검증) — 삽입 위치·흐름 통합은 미검증. 본문 리워딩 시 grep 완화 필요.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

# T1: clarifying §auto advisor + fallback + 주권
C="$PLUGIN/skills/clarifying-ko/SKILL.md"
grep -q 'advisor()' "$C" && ok "AC-1 clarify advisor 자문" || nope "AC-1" "advisor 미존재"
grep -q '미연결' "$C" && ok "AC-R-2a clarify fallback" || nope "AC-R-2a" "fallback 미존재"
grep -q 'ASSUMED.*유지' "$C" && ok "AC-R-3a clarify 주권보존" || nope "AC-R-3a" "주권 미존재"

# T2: planning §auto cap advisor + fallback
P="$PLUGIN/skills/planning-ko/SKILL.md"
grep -q 'advisor().*1회 자문' "$P" && ok "AC-3 planning advisor" || nope "AC-3" "advisor 미존재"
grep -q 'graceful fallback' "$P" && ok "AC-R-2b planning fallback" || nope "AC-R-2b" "fallback 미존재"

# T3: verifying §auto fix_loop advisor + fallback
V="$PLUGIN/skills/verifying-evidence-ko/SKILL.md"
grep -q 'advisor().*자문 시도' "$V" && ok "AC-4 verify advisor" || nope "AC-4" "advisor 미존재"
grep -q 'graceful fallback' "$V" && ok "AC-R-2c verify fallback" || nope "AC-R-2c" "fallback 미존재"

# T4: advisor-ko §auto 무인 행 + 주권
A="$PLUGIN/skills/advisor-ko/SKILL.md"
grep -q '§auto 무인' "$A" && ok "AC-5 advisor §auto 행" || nope "AC-5" "§auto 행 미존재"
grep -q '결정 대행 아님' "$A" && ok "AC-R-3b advisor 주권명시" || nope "AC-R-3b" "주권 미존재"

# T5: 연결 진단 § (C3 20260716) — 도구 미노출 시 4원인 진단 + 사용자 안내 의무.
#   pairing(advisor ≥ main) 이 대표 원인 — main 상향 시 advisor 가 조용히 깨지는 함정 명문화.
n=$(grep -c '연결 진단' "$A")
[ "$n" -ge 1 ] && grep -q 'pairing 무효' "$A" && grep -q 'CLAUDE_CODE_DISABLE_ADVISOR_TOOL' "$A" \
  && grep -q '동급 이상' "$A" \
  && ok "AC-6 advisor 연결 진단 § (4원인+pairing)" || nope "AC-6" "진단 §=$n 또는 원인 누락"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
