#!/usr/bin/env bash
# test-ui-e2e-signals.sh — 화면 UI E2E 루프 신호 계약 (FID 20260712-ui-e2e-loop-closure)
# 앵커 리터럴(Q6): "화면 동기화 권고"·"UI/화면 관점"·"화면 렌더"·"Web Vitals"
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0

VER="$PLUGIN/skills/verifying-evidence-ko/SKILL.md"
CR="$PLUGIN/agents/code-reviewer-ko.md"
INT="$PLUGIN/skills/integration-test-ko/SKILL.md"
PERF="$PLUGIN/skills/performance-test-ko/SKILL.md"

# ── T1: verify 역방향 net screens/ 대조 (AC-1) ──
grep -q '화면 동기화 권고' "$VER" && grep -q 'screens/' "$VER" \
  && ok "T1.a verify screens/ 대조 (화면 동기화 권고)" || nope "T1.a verify" "screens/ 역방향 net 부재"

# ── T2: code-reviewer UI/화면 관점 (AC-2) ──
grep -q 'UI/화면 관점' "$CR" && grep -q 'screens/' "$CR" \
  && ok "T2.a code-reviewer UI/화면 관점" || nope "T2.a code-reviewer" "UI 관점 부재"

# ── T3: integration UI detection 신호 (AC-3) ──
grep -q '화면 렌더' "$INT" \
  && ok "T3.a integration UI 신호 (화면 렌더)" || nope "T3.a integration" "UI 표면 신호 부재"

# ── T4: performance Web Vitals 신호 (AC-4) ──
grep -q 'Web Vitals' "$PERF" && grep -qE 'LCP|CLS|FCP' "$PERF" \
  && ok "T4.a performance Web Vitals" || nope "T4.a performance" "Web Vitals 신호 부재"

# ── T5: delegation-doc — downstream 위임 + e2e-runner 선택적(하드 dispatch 부재 검증) (AC-5) ──
# I-1(plan-reviewer): AC-5 는 "하드 dispatch 문구 부재"까지 검증 명시 → negative grep 필수
if grep -q 'e2e-runner' "$INT" && grep -qE 'downstream|Playwright|Cypress' "$INT" \
   && ! grep -qE '(반드시|무조건|필수)[^가-힣]{0,20}e2e-runner|e2e-runner[^가-힣]{0,20}(반드시|무조건|필수)' "$INT"; then
  ok "T5.a delegation (downstream·e2e-runner 선택적·하드 dispatch 부재)"
else
  nope "T5.a delegation" "위임 부재 또는 하드 dispatch 강제 문구 존재"
fi

# ── T6: 백엔드 신호 무회귀 — 기존 앵커 보존 (AC-R-1) ──
grep -q 'DB CRUD 왕복' "$INT" && grep -qE 'p95|RPS' "$PERF" \
  && ok "T6.a 백엔드 신호 보존 (DB CRUD·p95/RPS)" || nope "T6.a 무회귀" "기존 백엔드 신호 소실"

echo ""
finish
