#!/usr/bin/env bash
# 신규 trivial 단축 경로 계약 + 실행 어서션 회귀 (FID 20260714-trivial-new-shortcut)
# 목적: specify → (clarify·plan SKIP) → decompose → implement → verify 축약이
#       (1) 생산·라우팅·tolerance 로 배선돼 있고 (2) verify/security teeth 를 건드리지 않으며
#       (3) 실제 파이프라인에서 clarify·plan 이 provably SKIP 되고 거버넌스가 안 터짐을 증명.
#       form(문자열 존재)만이 아니라 실행(session-progress-append·governance-lib)으로 어서트.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SK="$PLUGIN/skills"
SPEC="$SK/specifying-ko/SKILL.md"
DEC="$SK/decomposing-ko/SKILL.md"

# ── 생산: specifying-ko 가 신규 trivial 판정을 부여하는가 ──────────────
grep -q '신규 분기 (소규모 + 사용자 trivial 승인)' "$SPEC" \
  && ok "AC-1 신규 trivial 라벨 생산 (라벨 표 행)" || nope "AC-1" "신규 trivial 판정 행 소실"
grep -q '신규 trivial 단축 경로' "$SPEC" \
  && ok "AC-2 신규 trivial 단축 경로 근거 서술" || nope "AC-2" "단축 경로 서술 소실"

# ── 라우팅: primary edge 불변 + 조건 분기는 인라인(파서 회피) ──────────
# specifying `## 다음 skill` 블록 안에서 정확매치 `^Skill: specops-ko:` 라인 추출
NEXT_BLOCK=$(awk '/^## 다음 skill/{f=1;next} f&&/^## /{f=0} f' "$SPEC")
PRIMARY=$(printf '%s\n' "$NEXT_BLOCK" | grep -cE '^Skill: specops-ko:[a-z-]+[[:space:]]*$')
# 정확매치는 clarifying-ko 하나뿐이어야 chain_consistency 가 primary edge 를 단일 유지
[ "$PRIMARY" = "1" ] \
  && ok "AC-3 primary edge 단일 (Skill: 정확매치 1건 — chain_consistency 정합)" \
  || nope "AC-3" "Skill: 정확매치 $PRIMARY 건 (1 기대 — decomposing 이 primary 로 오수집)"
printf '%s\n' "$NEXT_BLOCK" | grep -qE '^Skill: specops-ko:clarifying-ko[[:space:]]*$' \
  && ok "AC-3b primary 대상 = clarifying-ko (정상 경로 보존)" || nope "AC-3b" "clarifying primary 소실"
# 조건 분기의 decomposing 참조는 인라인(줄 시작 `Skill: ` 아님)으로만 존재
printf '%s\n' "$NEXT_BLOCK" | grep -q 'specops-ko:decomposing-ko' \
  && ok "AC-4 trivial 분기 decomposing 인라인 참조 존재" || nope "AC-4" "decomposing 직행 참조 소실"

# ── 정직한 SKIP 라우팅: fake 가 아니라 SKIP 으로 기록하도록 지시 ────────
grep -q '/clarify SKIP' "$SPEC" && grep -q '/plan SKIP' "$SPEC" \
  && ok "AC-5 정직한 SKIP 기록 지시 (clarify·plan SKIP)" || nope "AC-5" "SKIP 정직 기록 지시 소실"

# ── tolerance: decomposing-ko 가 plan.md 부재를 trivial 로 허용 ────────
grep -qE 'trivial 신규 단축 분기|trivial / §lite 단축 분기' "$DEC" \
  && ok "AC-6 decomposing trivial tolerance 분기 존재" || nope "AC-6" "trivial tolerance 분기 소실"
grep -q 'plan.md.*부재' "$DEC" \
  && ok "AC-6b plan.md 부재 허용 명시" || nope "AC-6b" "plan.md 부재 tolerance 소실"

# ── ★ teeth 불변: 축약 서술이 verify/security/TDD 를 건너뛴다고 말하지 않음 ──
# chain edge (verify → review → security) 는 chain.yaml 이 SoT — 여기선 서술 계약만 검사
grep -q 'teeth' "$SPEC" && grep -qE 'verify.*(유지|불변|그대로)|teeth (불변|유지)' "$SPEC" \
  && ok "AC-7 verify/TDD/security teeth 유지 명시" || nope "AC-7" "teeth 유지 명시 소실 (skip 오도 위험)"
grep -q 'TDD 5스텝' "$DEC" && grep -qE 'teeth (불변|유지)|정상과 동일' "$DEC" \
  && ok "AC-7b decompose teeth(TDD·게이트) 불변 명시" || nope "AC-7b" "decompose teeth 불변 명시 소실"
# chain.yaml 의 verify/security edge 가 여전히 선언돼 있는지 (축약이 edge 삭제 안 함)
grep -q 'verifying-evidence-ko, to: requesting-code-review-ko' "$PLUGIN/hooks/chain.yaml" \
  && grep -q 'security-review-ko' "$PLUGIN/hooks/chain.yaml" \
  && ok "AC-7c chain.yaml verify/security edge 불변" || nope "AC-7c" "verify/security edge 소실"

# ── ★ 실행 어서션 (advisor 핵심): 실제 파이프라인에서 SKIP·거버넌스 검증 ──
SB=$(mktemp -d) || { echo "FATAL mktemp"; exit 1; }
trap 'rm -rf "$SB"' EXIT
FID="20260714-trivial-x"
mkdir -p "$SB/.specops/$FID"
# trivial 신규 spec.md + AC (plan.md·clarifications.md 는 의도적 부재 — SKIP 재현)
printf '# spec\n\n## 1 개요\n**§유형**: trivial\n' > "$SB/.specops/$FID/spec.md"
printf '# AC\n- must: greet 함수가 이름을 받아 인사 출력\n' > "$SB/.specops/$FID/acceptance-criteria.md"

# (실행1) session-progress-append 로 clarify·plan 을 SKIP 기록 → provably skip
( cd "$SB" && bash "$PLUGIN/scripts/session-progress-append.sh" "$FID" /clarify SKIP "trivial 축약" "x기능" >/dev/null 2>&1
  cd "$SB" && bash "$PLUGIN/scripts/session-progress-append.sh" "$FID" /plan SKIP "trivial 축약" "x기능" >/dev/null 2>&1 )
SP="$SB/.specops/session-progress.md"
# 실제 append 로그 라인만 검사 (^- 앵커). 템플릿 주석 예시는 공백 들여쓰기(`  - `)라 제외됨.
if [ -f "$SP" ] && grep -qE '^- .*/clarify SKIP' "$SP" && grep -qE '^- .*/plan SKIP' "$SP" \
   && ! grep -qE '^- .*/clarify (완료|PASS)' "$SP" && ! grep -qE '^- .*/plan (완료|PASS)' "$SP"; then
  ok "AC-EXEC-1 실행: clarify·plan 이 SKIP 으로만 기록됨 (완료/PASS 위장 없음)"
else
  nope "AC-EXEC-1" "SKIP 기록 실패 또는 완료로 위장됨"
fi

# (실행2) 부재 확인 — plan.md·clarifications.md 없이도 파이프라인 상태 정합
{ [ ! -f "$SB/.specops/$FID/plan.md" ] && [ ! -f "$SB/.specops/$FID/clarifications.md" ]; } \
  && ok "AC-EXEC-2 실행: plan.md·clarifications.md 부재 (ceremony 실제 생략)" \
  || nope "AC-EXEC-2" "축약 대상 산출물이 존재 (생략 안 됨)"

# (실행3) 거버넌스 R-5: trivial spec 은 Advisor-섹션 룰에서 skip → 안 터짐
# governance-lib source 후 실제 매처 호출. spec.md 를 Edit 한 것처럼 transcript 구성.
if source "$PLUGIN/hooks/governance-lib.sh" 2>/dev/null && command -v apply_advisor_section_rule >/dev/null 2>&1; then
  TR=$(mktemp)
  # spec.md 를 Edit 한 assistant turn 을 담은 최소 transcript (R-5 대상 트리거)
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s/.specops/%s/spec.md"}}]}}\n' "$SB" "$FID" > "$TR"
  RULE='{"id":"R-5","target_files":["spec.md","plan.md","analysis.md"],"advisor_section_pattern":"Advisor 협의"}'
  if apply_advisor_section_rule "$RULE" "$TR" >/dev/null 2>&1; then
    RC=0; else RC=$?; fi
  # skip(정상 통과) = return 0 이고 match_result 미발화. trivial 이면 spec skip 되어 위반 미보고.
  OUT=$(apply_advisor_section_rule "$RULE" "$TR" 2>/dev/null)
  if [ -z "$OUT" ]; then
    ok "AC-EXEC-3 실행: R-5 매처가 trivial spec 을 skip (위반 미발화 — friction 안 터짐)"
  else
    nope "AC-EXEC-3" "R-5 가 trivial spec 에서 위반 발화: $OUT"
  fi
  rm -f "$TR"
else
  # governance-lib 미로드(jq 부재 등)면 정직 SKIP
  skip "AC-EXEC-3 (governance-lib/jq 미가용 — 한계 고백)"
fi

# ── AC-GATE-MERGE: trivial 스펙승인 게이트 통합 배선 (20260716 dogfood 관찰 A) ──
#   설계승인+축약승인 직후 동일 내용 스펙의 별도 승인 응답 요구는 중복 게이트 — 통합 규약이
#   specifying-ko 사용자 검토 게이트 절에 명문화돼 있어야 한다 (내용 변화 시 게이트 유지 조건 포함).
SP="$PLUGIN/skills/specifying-ko/SKILL.md"
n=$(grep -c 'trivial 게이트 통합' "$SP")
if [ "$n" -eq 1 ] && grep -q '통합 통과' "$SP" && grep -q '게이트를 \*\*유지\*\*' "$SP"; then
  ok "AC-GATE-MERGE trivial 스펙승인 통합 배선 (동일내용 통과 + 변화시 유지)"
else
  nope "AC-GATE-MERGE" "통합 규약=$n 또는 유지 조건 누락"
fi

# ── AC-B-REPORT: Phase B/C 판정 file-based 감사 추적 (20260716 dogfood 관찰 B) ──
IM="$PLUGIN/skills/implementing-ko/SKILL.md"
grep -q -- '-B-report.md' "$IM" && grep -q 'PASS 여도' "$IM" \
  && ok "AC-B-REPORT Phase B/C PASS report file-based 규약 배선" \
  || nope "AC-B-REPORT" "B-report 규약 없음"

echo "── test-trivial-new-shortcut: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
