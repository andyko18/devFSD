#!/usr/bin/env bash
# test-batch-orchestration.sh — /start-all batch 오케스트레이션 결정적 시뮬 (FID 20260711-g0-batch-e2e)
# 검증 대상: commands/start-all.md 의 queue 상태기계 규칙 재현 (본체 무접촉 — 읽기 전용 계약)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# ── fixture: requirements (FR 3행 + 비FR 행 1) ──
cat > "$TMP/req.md" <<'EOF'
# 요구사항
| ID | 요구사항 | 마일스톤 | 우선순위 |
|---|---|---|---|
| FR-1 | 기능 A | M1 | must |
| FR-2 | 기능 B | M1 | must |
| FR-3 | 기능 C | M2 | should |
| NFR-1 | 성능 | M1 | must |
EOF

# ── T1: Phase 0 재현 — FR 파싱 + queue 초기화 (start-all.md:33 grep 기준 · :46-51 포맷) ──
mkdir -p "$TMP/.specops/batch-t"
Q="$TMP/.specops/batch-t/queue.md"
{
  echo "| FR-ID | FID | FR 설명(1줄) | Status |"
  echo "|---|---|---|---|"
  grep -E '^\| FR-[0-9]+ \|' "$TMP/req.md" | while IFS='|' read -r _ frid desc _rest; do
    frid=$(echo "$frid" | tr -d ' '); desc=$(echo "$desc" | sed 's/^ *//;s/ *$//')
    echo "| $frid | TBD | $desc | PENDING |"
  done
} > "$Q"
n_fr=$(grep -cE '^\| FR-[0-9]+ \|.*PENDING' "$Q")
grep -q 'NFR-1' "$Q" && has_nfr=1 || has_nfr=0
[ "$n_fr" -eq 3 ] && [ "$has_nfr" -eq 0 ] \
  && ok "T1.a Phase 0 재현 — FR 3행 PENDING·비FR 제외 (start-all.md:33·46-51)" \
  || nope "T1.a Phase 0" "fr=$n_fr nfr=$has_nfr"

# ── T2: 전이 — PLAN_DONE 갱신 (start-all.md:66 — FID 기입 + Status) ──
sed -i.bak 's/^| FR-1 | TBD | 기능 A | PENDING |$/| FR-1 | 20260711-a | 기능 A | PLAN_DONE |/' "$Q" && rm -f "$Q.bak"
grep -q '| FR-1 | 20260711-a | 기능 A | PLAN_DONE |' "$Q" \
  && ok "T2.a PLAN_DONE 전이 (start-all.md:66)" || nope "T2.a 전이" "갱신 실패"

# ── T3: 재진입 — 기존 queue 재사용 (start-all.md:43-44 — 존재 시 초기화 스킵·상태 보존) ──
if [ ! -f "$Q" ]; then
  echo "재초기화 발생" > "$Q"   # 존재하므로 이 분기 미진입이 규칙
fi
grep -q 'PLAN_DONE' "$Q" && ! grep -q '재초기화 발생' "$Q" \
  && ok "T3.a 재진입 상태 보존 (start-all.md:43-44 — 재초기화 미발생)" || nope "T3.a 재진입" "PLAN_DONE 소실 또는 재초기화됨"

# ── T4: batch-state 게이트 통합 — 부분 완료 → exit 1 (start-all.md:95-101) ──
out=$(bash "$PLUGIN/scripts/batch-state.sh" "$TMP/.specops/batch-t" "$TMP/req.md" 2>&1); code=$?
[ "$code" -eq 1 ] && echo "$out" | grep -q "FR-2" \
  && ok "T4.a 게이트 — 부분 완료 exit 1 + 미완 목록" || nope "T4.a 게이트" "exit=$code"

# ── T5: 전체 IMPL_DONE → 게이트 clean (start-all.md:88 전이 후) ──
# 전이는 실제 흐름대로 스크립트로 한다 — FID 칸을 채우지 않은 행은 IMPL_DONE 이 될 수 없다(20261009).
#   종전 fixture 는 sed 로 Status 만 일괄 바꿔 FR-2·FR-3 의 FID 칸을 `TBD` 로 둔 채 "clean" 을 기대했다 —
#   batch-state 가 FID 칸이 빈 완료 행을 말없이 건너뛰던 구멍에 기대던 것이다.
_QS="$PLUGIN/scripts/_internal/queue-set-status.sh"
bash "$_QS" "$Q" FR-1 IMPL_DONE >/dev/null 2>&1
bash "$_QS" "$Q" FR-2 IMPL_DONE 20260711-b >/dev/null 2>&1
bash "$_QS" "$Q" FR-3 IMPL_DONE 20260711-c >/dev/null 2>&1
# batch-state teeth: IMPL_DONE FID 마다 per-FR 산출물 3종(review-base.sha·evidence.md·review-request.md) + 진행기록 — 시뮬 생성
: > "$TMP/.specops/session-progress.md"
for _f in 20260711-a 20260711-b 20260711-c; do
  mkdir -p "$TMP/.specops/$_f"
  : > "$TMP/.specops/$_f/review-base.sha"; : > "$TMP/.specops/$_f/evidence.md"; : > "$TMP/.specops/$_f/review-request.md"
  printf '## %s\n- 2026-07-11 10:00 /verify PASS (evidence.md, AC 2/2)\n' "$_f" >> "$TMP/.specops/session-progress.md"
done
# NFR 드리프트 잔여 방지 — req 는 FR 3행뿐이므로 drift 0 기대... (req 에 NFR-1 은 FR_RE 미매칭)
bash "$PLUGIN/scripts/batch-state.sh" "$TMP/.specops/batch-t" "$TMP/req.md" >/dev/null 2>&1; code=$?
[ "$code" -eq 0 ] \
  && ok "T5.a 전체 IMPL_DONE → 게이트 exit 0 (start-all.md:88·95)" || nope "T5.a clean" "exit=$code"
#   FID 칸이 빈 행은 스크립트가 IMPL_DONE 으로 바꾸지 않는다 — 위 fixture 가 기대던 경로가 닫혔는지
printf '| FR-ID | FID | FR 설명(1줄) | Status |\n|---|---|---|---|\n| FR-9 | TBD | x | PLAN_DONE |\n' > "$TMP/q-tbd.md"
bash "$_QS" "$TMP/q-tbd.md" FR-9 IMPL_DONE >/dev/null 2>&1; code=$?
[ "$code" -ne 0 ] && grep -q 'PLAN_DONE' "$TMP/q-tbd.md" \
  && ok "T5.b FID 칸이 TBD 인 행 → IMPL_DONE 전이 거부" || nope "T5.b" "exit=$code"

# ── T6: e2e [S8] 문서 계약 (AC-4) ──
E2E="$PLUGIN/skills/e2e-test-ko/SKILL.md"
grep -q '^## \[S8\] BATCH' "$E2E" && grep -q 'V22' "$E2E" && grep -q 'V23' "$E2E" && grep -q 'V24' "$E2E" \
  && ok "T6.a e2e [S8]+V22~24 정의" || nope "T6.a [S8]" "블록/V 정의 없음"

# ── T7: V 개수 동기 3곳 (AC-5) ──
c1=$(grep -c '25개 검증 항목(V1~V25)' "$E2E"); c2=$(grep -c '25개 검증 항목' "$PLUGIN/commands/e2e-test.md")
r21=$(grep -c '21개 검증 항목' "$E2E" "$PLUGIN/commands/e2e-test.md" | awk -F: '{s+=$2} END{print s}')
[ "$c1" -ge 1 ] && [ "$c2" -ge 1 ] && [ "$r21" -eq 0 ] \
  && ok "T7.a V 개수 25 동기·21 잔존 0" || nope "T7.a V 동기" "c1=$c1 c2=$c2 r21=$r21"

# ── T8: Phase 2.5 batch 통합 design-first (화면→IF) 계약 ──
# dogfood 발견: start-all 이 화면 design-first 를 각 FR specify 에 못 끼워 화면설계가 몰림.
# 후속: 인터페이스도 FR별 5.6이 아니라 Phase 2.5-B로 옮겨 통상 순서(화면→IF) 복원.
SA="$PLUGIN/commands/start-all.md"
SAA="$PLUGIN/commands/start-all-auto.md"
# T8.a: start-all 에 Phase 2.5 화면+IF — 화면 스타일은 DESIGN.md 토큰(외부 디자인 플러그인 호출 없음)
grep -q 'Phase 2.5' "$SA" && ! grep -q 'ui-ux-pro-max' "$SA" && grep -q 'DESIGN.md 토큰 적용' "$SA" && grep -q '통합 인터페이스' "$SA" \
  && ok "T8.a start-all Phase 2.5 화면+IF + DESIGN.md 토큰" || nope "T8.a" "Phase 2.5/IF/DESIGN.md 토큰 부재 또는 외부 호출 잔존"
# T8.b: design-first 순서 — Phase 2.5 가 Phase 3(구현) 앞에 위치
l25=$(grep -n 'Phase 2.5' "$SA" | head -1 | cut -d: -f1)
l3=$(grep -n '^### Phase 3 ' "$SA" | head -1 | cut -d: -f1)
{ [ -n "$l25" ] && [ -n "$l3" ] && [ "$l25" -lt "$l3" ]; } \
  && ok "T8.b design-first 순서 (Phase 2.5 < Phase 3 구현)" || nope "T8.b 순서" "2.5=$l25 3=$l3"
# T8.c: UI 부재 시 화면만 SKIP → IF(B)로 진행 (Phase 3 직행 금지)
grep -q 'SCREEN-DESIGN: SKIP' "$SA" && grep -q 'B(인터페이스)로 진행' "$SA" \
  && ok "T8.c UI 부재 시 화면 SKIP→IF" || nope "T8.c skip" "SCREEN→B 진행 부재"
# T8.c2: Phase 1은 5.5·5.6 SKIP
grep -qE '5\.5·5\.6 SKIP' "$SA" \
  && ok "T8.c2 Phase 1 Step 5.5·5.6 SKIP" || nope "T8.c2" "이중 SKIP 앵커 부재"
# T8.d: 인프라 전파 — start-all-auto 에도 Phase 2.5 화면→IF
grep -q 'Phase 2.5' "$SAA" && grep -qE '2\.5-B|화면→|화면·인터페이스' "$SAA" \
  && ok "T8.d start-all-auto 전파 (Phase 2.5 화면→IF)" || nope "T8.d 전파" "start-all-auto 누락"
# T8.e: 구현이 화면·IF 계약 소비
grep -q '설계 계약' "$SA" && grep -qE 'screens/|api-spec' "$SA" \
  && ok "T8.e 구현이 screens/·api-spec 설계계약 소비" || nope "T8.e teeth" "구현 계약 연결 부재"
# T8.f: Phase 2.5-D 무거운 설계 리뷰 배선
grep -q 'design-reviewer-ko' "$SA" && grep -q 'DESIGN-REVIEW-RESULT' "$SA" \
  && grep -q '이 설계로 구현 진행' "$SA" \
  && ok "T8.f Phase 2.5-D design-reviewer + E 게이트" || nope "T8.f" "D/E 배선 부재"
# T8.g: FAIL 재시도 1회 + Critical/Important cap 분기 (Wave B)
grep -q '재dispatch 1회' "$SA" \
  && grep -qE 'Critical cap|Critical≥1|Critical>=1' "$SA" \
  && grep -q 'Important-only cap' "$SA" \
  && ok "T8.g design-review FAIL 재시도·Critical/Important cap" || nope "T8.g" "재시도/cap 분기 부재"
# T8.h: start-all-auto에 D 단계 전파
grep -q 'design-reviewer-ko' "$SAA" && grep -q 'design-review.md' "$SAA" \
  && ok "T8.h start-all-auto design-review 전파" || nope "T8.h" "auto 전파 누락"
# T8.i: §auto Critical 정지 · Important-only 자동통과 (Wave B)
grep -qE 'Critical.*정지|Critical cap.*정지' "$SAA" \
  && grep -qE 'Important-only|Important.*자동통과' "$SAA" \
  && ok "T8.i start-all-auto Critical 정지 / Important auto-pass" \
  || nope "T8.i" "auto Critical/Important 계약 누락"

# ── T9: Step B batch 통합·E2E 배선 계약 (FID 20260716-start-all-batch-e2e) ──
# dogfood 발견: start-all Step B(integration)가 "통합 표면(API·DB)"만 스캔해
# UI batch 인데도 E2E 가 흐름 밖으로 새어 사후 수동 보충(PR #3)됨.
# fix = integration-test-ko 가 이미 가진 UI 표면 E2E 위임을 Step B 배선에 노출.
# T9.a: Step B 가 UI 표면·E2E 위임 명시 (통합만이 아님)
grep -q 'Step B: batch 레벨 통합·E2E' "$SA" && grep -qE 'UI 표면|E2E 위임' "$SA" \
  && ok "T9.a Step B 통합·E2E 배선 (UI 표면 노출)" || nope "T9.a" "Step B E2E 미노출"
# T9.b: E2E 는 downstream 위임 (플러그인 브라우저 인프라 미보유 — Playwright/Cypress)
grep -qE 'Playwright|Cypress' "$SA" && grep -q '브라우저 인프라 미보유' "$SA" \
  && ok "T9.b E2E downstream 위임 (브라우저 인프라 미보유 명시)" || nope "T9.b" "downstream 위임 부재"
# T9.c: UI batch 는 E2E skip 금지 (두 표면 모두 부재 시에만 graceful skip)
grep -q 'UI batch 인데 E2E 를 건너뛰면 안 된다' "$SA" \
  && ok "T9.c UI batch E2E skip 금지 (두 표면 부재 시에만 skip)" || nope "T9.c" "E2E skip 금지 미명시"
# T9.d: Phase 3 완료 헤더·PR test plan 정합 (통합·E2E·성능)
grep -q '통합·E2E·성능' "$SA" && grep -qE 'E2E\) PASS 또는 SKIP' "$SA" \
  && ok "T9.d 헤더·PR test plan E2E 정합" || nope "T9.d" "헤더/test plan 정합 누락"
# T9.e: start-all-auto 가 Step B(E2E 포함) 상속 (Phase 0~3 동일 참조 — 인프라 전파)
grep -q 'Phase 0~3.*동일' "$PLUGIN/commands/start-all-auto.md" \
  && ok "T9.e start-all-auto Step B(E2E) 상속 (Phase 0~3 동일)" || nope "T9.e" "start-all-auto 상속 참조 소실"

# ── T10: Phase 3 per-FR (implement → verify → request/receive) ──
grep -q 'per FR 순차 구현' "$SA" \
  && ! grep -q 'batch-end-loaded' "$SA" \
  && ok "T10.a per-FR Phase 3 (batch-end-loaded 부재)" || nope "T10.a" "per-FR 복구 실패"
grep -q 'implementing-ko' "$SA" && grep -q 'verifying-evidence-ko' "$SA" \
  && grep -q 'requesting-code-review-ko' "$SA" \
  && ok "T10.b FR별 implement→verify→request" || nope "T10.b" "체인 부재"
grep -q 'end-loaded' "$SA" && grep -q 'review-skip.md' "$SA" \
  && ok "T10.c end-loaded skip 경로" || nope "T10.c" "end-loaded skip 부재"
grep -q '한 번에 뭉쳐 돌리지 않는다' "$SA" \
  && ok "T10.d per-FR 뭉개짐 금지" || nope "T10.d" "뭉개짐 경계 문구 부재"

# ── T11: Phase 2 batch plan-review defer ──
grep -q 'DEFERRED' "$SA" && grep -q 'plan-reviewer' "$SA" \
  && ok "T11.a Phase 2 DEFERRED/plan-reviewer" || nope "T11.a" "DEFER 배선 부재"
grep -q 'batch-plan-digest.sh' "$SA" \
  && ok "T11.b digest 스크립트 배선" || nope "T11.b" "digest 미배선"
# Phase 2 절(### Phase 2 — … ### Phase 2.5) 안에서만 순서 검증 — 본문 앞쪽 언급 제외
phase2=$(awk '/^### Phase 2 —/{p=1} p; /^### Phase 2\.5/{if(p&&!seen++) exit}' "$SA")
echo "$phase2" | grep -q 'Batch plan-review' \
  && echo "$phase2" | grep -q 'batch-plan-digest' \
  && l_pr=$(echo "$phase2" | grep -n 'Batch plan-review' | head -1 | cut -d: -f1) \
  && l_dg=$(echo "$phase2" | grep -n 'batch-plan-digest' | head -1 | cut -d: -f1) \
  && [ -n "$l_pr" ] && [ -n "$l_dg" ] && [ "$l_pr" -lt "$l_dg" ] \
  && ok "T11.c 순서 plan-review < digest (Phase 2 절)" || nope "T11.c" "pr=$l_pr dg=$l_dg"
grep -qE 'DEFERRED → Phase 2 batch|plan-reviewer DEFER' "$PLUGIN/skills/planning-ko/SKILL.md" \
  && ok "T11.d planning-ko DEFER" || nope "T11.d" "planning DEFER 부재"
grep -q 'Phase 1에서 §batch plan-reviewer 실행' "$SA" \
  && ok "T11.e 안티패턴 Phase1 reviewer" || nope "T11.e" "안티패턴 부재"

# ── T13: Critical 판정 방식 대칭 (20260806 /start-all-auto 분석) ─────────────
# 결함: Phase 2.5-D(design-review)는 `^Critical:[[:space:]]*[1-9]` **기계 grep** 으로
#   Critical 을 판정하는데, Phase 2(plan-review)는 "Critical≥1" **산문 판단**뿐이었다.
#   plan-reviewer 도 동일 포맷(`Critical: <N>건`)을 출력하므로 기계화가 가능한데,
#   §auto 무인에서 모델이 오판하면 **Critical plan 이 자동통과**한다(사람 없음).
grep -qE 'plan-review\.md.*\^Critical|Critical:\[\[:space:\]\]\*\[1-9\].*plan' "$SA" \
  || grep -A 2 'FAIL\*\* \(재시도 후\)' "$SA" | grep -qE '\^Critical:\[\[:space:\]\]\*\[1-9\]' \
  && ok "T13.a Phase 2 plan-review Critical 기계 판정" \
  || nope "T13.a" "plan-review Critical 이 산문 판단 — §auto 오판 시 Critical 자동통과"

# T13.b: 두 판정이 동일 패턴을 쓴다 (드리프트 방지)
n=$(grep -cE '\^Critical:\[\[:space:\]\]\*\[1-9\]' "$SA" || true)
[ "${n:-0}" -ge 2 ] \
  && ok "T13.b Critical grep 패턴 2곳 이상(plan·design 대칭)" \
  || nope "T13.b" "패턴 ${n}곳 — 대칭 아님"

# ── T12: BATCH_ID 충돌 방지 + ACTIVE 기반 재개 (M2, 20260806) ────────────────
# 구 규약 `batch-<YYYYMMDD>` 는 날짜가 곧 재개 키였다 — 같은 날 두 번째 /start-all 이
# 이전 batch 의 queue.md 를 재사용해 서로 다른 requirements 가 한 큐에 뭉갰다.
# 재개 키를 **ACTIVE 마커**로 옮기고(이미 PR 게이트 판정 범위로 존재), 신규 id 에 시각을 붙인다.
grep -qE 'batch-<YYYYMMDD>-<HHMM>' "$SA" \
  && ok "T12.a 신규 BATCH_ID 에 시각 접미" || nope "T12.a" "batch-<YYYYMMDD>-<HHMM> 부재"

# 재개는 날짜가 아니라 ACTIVE 마커로 판정해야 한다
grep -qE '\.specops/batch-\*/ACTIVE' "$SA" \
  && ok "T12.b ACTIVE 마커로 진행 batch 탐색" || nope "T12.b" "ACTIVE 글롭 탐색 부재"

# 복수 ACTIVE 는 모호 — 자동 선택 금지, 사용자 게이트
grep -qE '2개 이상|복수.*ACTIVE|여러 개' "$SA" \
  && ok "T12.c 복수 ACTIVE → 사용자 선택 게이트" || nope "T12.c" "모호성 게이트 부재"

# 하위호환: 기존 batch-YYYYMMDD(시각 없음) 도 ACTIVE 있으면 재개
grep -qE '하위호환|기존 `batch-<YYYYMMDD>`' "$SA" \
  && ok "T12.d 구 포맷 하위호환 명시" || nope "T12.d" "하위호환 문구 부재"

# 구 규약 잔존 금지 — 날짜만으로 재개한다는 서술이 남으면 드리프트
grep -qE 'BATCH_ID = "batch-<YYYYMMDD>"[^-]' "$SA" \
  && nope "T12.e 구 날짜-only 규약 잔존" "batch-<YYYYMMDD> 단독 정의 남음" \
  || ok "T12.e 구 날짜-only 규약 제거"

# 훅 판정은 포맷 무관(glob) — 회귀 락
grep -qE '\.specops/batch-\*/ACTIVE' "$PLUGIN/hooks/pretool-governance.sh" \
  && ok "T12.f 훅 ACTIVE 글롭 포맷 무관" || nope "T12.f" "훅 글롭 변경됨"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
