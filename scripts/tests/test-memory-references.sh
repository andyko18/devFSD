#!/usr/bin/env bash
# T20 — specifying-ko Step 1 의 .specops/memory/* 자동 감지 검증 (FID 20260507)
# specifying-ko 는 Claude skill 이라 bash 직접 실행 불가 → 다음 2 방식 조합:
#   (a) 정적 검증: SKILL.md 본문이 10종 감지 표 + spec.md §참조 인용 패턴 명시
#   (b) fixture 검증: ls .specops/memory/*.md 이 OS 명령으로 의도대로 동작 (graceful skip + 부분 매칭)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SKILL="$PLUGIN/skills/specifying-ko/SKILL.md"


# ── T1.a 정적: SKILL.md 가 10종 .specops/memory/*.md 모두 명시 ──
# 20260917: process-design 추가 (구 intent.md 개명 — 기능 단위 intent 와 분리)
expected=(constitution requirements architecture frontend-architecture backend-architecture api-spec data-model process-design screens-overview test-strategy)
missing=()
for n in "${expected[@]}"; do
  grep -q "${n}\.md" "$SKILL" || missing+=("$n")
done
if [ ${#missing[@]} -eq 0 ]; then
  ok "T1.a SKILL.md 가 10종 .specops/memory/*.md 모두 명시 (감지 표)"
else
  nope "T1.a 10종 명시" "누락: ${missing[*]}"
fi

# ── T2.a 정적: spec.md §참조 인용 패턴 + graceful skip 명시 ──
if grep -q "spec.md.*§참조" "$SKILL" \
   && grep -q "graceful skip" "$SKILL" \
   && grep -q "회귀 보호" "$SKILL"; then
  ok "T2.a SKILL.md 본문 — spec.md §참조 인용 + graceful skip + 회귀 보호 명시"
else
  nope "T2.a 인용 패턴" "spec.md/§참조 또는 graceful skip 또는 회귀 보호 키워드 부재"
fi

# ── T3.a fixture: .specops/memory/ 부재 → ls 빈 결과 (graceful skip 전제) ──
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
out=$(ls .specops/memory/*.md 2>/dev/null)
cd /tmp && rm -rf "$TMPDIR"
if [ -z "$out" ]; then
  ok "T3.a .specops/memory/ 부재 → ls 빈 결과 (graceful skip 전제 보장 — 기존 dogfood 회귀 보호)"
else
  nope "T3.a 부재 ls" "예상 빈 결과인데 출력=$out"
fi

# ── T4.a fixture: 부분 존재 → ls 가 존재하는 것만 반환 ──
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
mkdir -p .specops/memory
touch .specops/memory/constitution.md .specops/memory/requirements.md .specops/memory/test-strategy.md
got=$(ls .specops/memory/*.md 2>/dev/null | xargs -n1 basename | sort | tr '\n' ' ')
cd /tmp && rm -rf "$TMPDIR"
expected_str="constitution.md requirements.md test-strategy.md "
if [ "$got" = "$expected_str" ]; then
  ok "T4.a 부분 존재 → ls 가 존재하는 3종만 반환 (constitution/requirements/test-strategy)"
else
  nope "T4.a 부분 매칭" "got='$got' expected='$expected_str'"
fi

# ── T5.a 정적: SKILL.md 가 CONTEXT.md 감지 + graceful skip + §참조 명시 ──
if grep -q "CONTEXT\.md" "$SKILL" \
   && grep -A2 "CONTEXT\.md.*자동 감지" "$SKILL" | grep -q "graceful skip" \
   && grep -A3 "CONTEXT\.md.*자동 감지" "$SKILL" | grep -q "§참조"; then
  ok "T5.a SKILL.md — CONTEXT.md 자동 감지 + graceful skip + §참조 명시"
else
  nope "T5.a CONTEXT.md 감지" "CONTEXT.md 또는 graceful skip 또는 §참조 패턴 부재"
fi

# ── T6.a 정적: SKILL.md 가 docs/adr/ 감지 + graceful skip + §참조 명시 ──
if grep -q "docs/adr" "$SKILL" \
   && grep -A2 "docs/adr" "$SKILL" | grep -q "graceful skip\|wc -l" \
   && grep -A3 "docs/adr" "$SKILL" | grep -q "§참조"; then
  ok "T6.a SKILL.md — docs/adr/ 자동 감지 + graceful skip + §참조 명시"
else
  nope "T6.a ADR 감지" "docs/adr 또는 graceful skip 또는 §참조 패턴 부재"
fi

echo ""
echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
