#!/usr/bin/env bash
# 시드 FR 자동 SKIP — 20260812
#
# 결함: init 가 FR-1~3 을 M1~M3 시드로 채운 뒤 세부 FR-4+ 를 붙이면,
#   check-fr-table 이 시드도 실 FR 로 세어 /start-all queue PENDING 에 넣고 이중 구현한다.
#   Argus 는 queue 헤더에서 수동 SKIP — 본 가드가 그 절차를 기계화한다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-fr-table.sh"

_req() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

# T-s1: attendance형 — 마커 + FR-1(M1) + FR-4(M1) → FR-1 seed-decomposed, FR-4 ELIGIBLE
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
> **FR-1~3 은 PRD 마일스톤 시드** — 세부 FR 로 분해하세요.
<!-- seed-fr: FR-1,FR-2,FR-3 -->
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | 직원 출퇴근 기록 + 당월 목록 | M1 | must | (TBD) |
| FR-2 | <한 줄> | M2 | should | (TBD) |
| FR-4 | 사번+비밀번호 로그인 | M1 | must | (TBD) |
| FR-5 | 출근 기록 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" --classify 2>&1); rc=$?
printf '%s' "$out" | grep -qE '^SKIP\|FR-1\|seed-decomposed\|M1$' \
  && printf '%s' "$out" | grep -qE '^ELIGIBLE\|FR-4\|' \
  && printf '%s' "$out" | grep -qE '^SUMMARY\|real=3\|eligible=2\|seed_skip=1\|' \
  && [ "$rc" -eq 0 ] \
  && ok "T-s1 attendance형 → FR-1 seed-decomposed, FR-4 ELIGIBLE" \
  || nope "T-s1" "rc=$rc out=$out"
rm -rf "$TD"

# T-s2: 시드만 3건 실문장·마커·세부 없음 → SEED_SKIP 0
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
<!-- seed-fr: FR-1,FR-2,FR-3 -->
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | M1 범위 | M1 | must | (TBD) |
| FR-2 | M2 범위 | M2 | should | (TBD) |
| FR-3 | M3 범위 | M3 | nice | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" --classify 2>&1); rc=$?
printf '%s' "$out" | grep -qE '^SUMMARY\|real=3\|eligible=3\|seed_skip=0\|' \
  && ! printf '%s' "$out" | grep -q 'seed-decomposed' \
  && [ "$rc" -eq 0 ] \
  && ok "T-s2 시드만·미분해 → SEED_SKIP 0" \
  || nope "T-s2" "rc=$rc out=$out"
rm -rf "$TD"

# T-s3: 마커 없음 + FR-1/FR-2 동 M1 → SEED_SKIP 0 (오탐 방지)
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 상태 |
|---|---|---|---|---|
| FR-1 | 사용자 로그인 | M1 | must | (TBD) |
| FR-2 | 일정 목록 조회 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" --classify 2>&1); rc=$?
printf '%s' "$out" | grep -qE '^SUMMARY\|real=2\|eligible=2\|seed_skip=0\|' \
  && ! printf '%s' "$out" | grep -q 'seed-decomposed' \
  && [ "$rc" -eq 0 ] \
  && ok "T-s3 마커 없음 → SEED_SKIP 0" \
  || nope "T-s3" "rc=$rc out=$out"
rm -rf "$TD"

# T-s4: 기본 모드 stdout 시드 SKIP 요약
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
<!-- seed-fr: FR-1,FR-2,FR-3 -->
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | M1 시드 | M1 | must | (TBD) |
| FR-4 | 세부 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
printf '%s' "$out" | grep -q '시드 SKIP 1건: FR-1' \
  && [ "$rc" -eq 0 ] \
  && ok "T-s4 기본 모드 시드 SKIP 요약" \
  || nope "T-s4" "rc=$rc out=$out"
rm -rf "$TD"

# T-s5: start-all Phase 0 배선
grep -q 'check-fr-table.sh --classify' "$PLUGIN/commands/start-all.md" \
  && grep -q 'seed-decomposed' "$PLUGIN/commands/start-all.md" \
  && grep -qE 'Status=`SKIP`|Status=\`SKIP\`|SKIP' "$PLUGIN/commands/start-all.md" \
  && ok "T-s5 start-all --classify·seed-decomposed·SKIP 배선" \
  || nope "T-s5" "start-all.md 미배선"

# T-s6: start-all-auto 승계
grep -qE 'check-fr-table\.sh --classify|seed-decomposed|시드 SKIP' "$PLUGIN/commands/start-all-auto.md" \
  && ok "T-s6 start-all-auto 시드 SKIP 승계" \
  || nope "T-s6" "start-all-auto 승계 불명"

# T-s7 mutation: 시드 SKIP 분기 무력화 시 T-s1 조건 실패 재현 (비-vacuous)
TD=$(mktemp -d)
MUT=$(mktemp)
sed 's/seed_marker=1/seed_marker=0  # mutation: force no seed skip/' "$CHK" >"$MUT"
chmod +x "$MUT"
_req "$TD/.specops/memory/requirements.md" <<'EOF'
<!-- seed-fr: FR-1,FR-2,FR-3 -->
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | M1 시드 | M1 | must | (TBD) |
| FR-4 | 세부 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$MUT" --classify 2>&1); rc=$?
if printf '%s' "$out" | grep -q 'seed-decomposed'; then
  nope "T-s7 mutation" "시드 분기 무력화했는데도 seed-decomposed 출력 — mutation 무효"
else
  printf '%s' "$out" | grep -qE '^ELIGIBLE\|FR-1\|' \
    && printf '%s' "$out" | grep -qE 'seed_skip=0' \
    && [ "$rc" -eq 0 ] \
    && ok "T-s7 mutation: 시드 분기 무력화 → FR-1 ELIGIBLE (비-vacuous)" \
    || nope "T-s7" "rc=$rc out=$out"
fi
rm -rf "$TD" "$MUT"

# T-s8: 한글 fallback 마커만 (HTML 주석 없음 — attendance 소급)
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
> 아래 FR-1~3 은 PRD 마일스톤 시드 — 세부 FR 로 분해하세요.
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | M1 시드 | M1 | must | (TBD) |
| FR-4 | 세부 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" --classify 2>&1); rc=$?
printf '%s' "$out" | grep -qE '^SKIP\|FR-1\|seed-decomposed\|M1$' \
  && [ "$rc" -eq 0 ] \
  && ok "T-s8 한글 마일스톤 시드 fallback" \
  || nope "T-s8" "rc=$rc out=$out"
rm -rf "$TD"

# T-s9: 템플릿에 seed-fr HTML 마커
grep -qE '<!--[[:space:]]*seed-fr:[[:space:]]*FR-1,FR-2,FR-3[[:space:]]*-->' \
  "$PLUGIN/templates/requirements.md" \
  && ok "T-s9 templates/requirements.md seed-fr 마커" \
  || nope "T-s9" "템플릿 마커 부재"

finish
