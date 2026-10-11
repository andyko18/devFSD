#!/usr/bin/env bash
# FR 표 placeholder 가드 — 20260806 templates 전수 스캔
#
# 결함: `/start-all` Phase 0 는 `grep -E '^\| FR-[0-9]+ \|'` 로 FR 을 **기계 파싱**하고
#   "FR 행 0건이면 중단" 만 검사한다. 그런데 `templates/requirements.md` 는
#   `| FR-1 | <한 줄> | M1 | must | (TBD) |` **placeholder 행 3건**을 담고 배포되고,
#   init 의 `_seed_fr_row` 는 PRD 마일스톤이 비면 이 행을 그대로 둔다.
#   → 사용자가 FR 을 하나도 안 썼는데 `/start-all` 이 **3개 기능을 구현하겠다며 진입**하고,
#     Phase 1 이 specifying-ko 에 넘기는 "FR 원문" 은 `<한 줄>` 이다.
#   기존 가드("0건이면 중단")는 **비어 있음** 은 잡지만 **의미 없음** 은 못 잡는다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-fr-table.sh"

_req() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

# T1: ★ placeholder FR 만 있는 요구사항 → 실 FR 0건 판정(FAIL)
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 상태 |
|---|---|---|---|---|
| FR-1 | <한 줄> | M1 | must | (TBD) |
| FR-2 | <한 줄> | M2 | should | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'placeholder' \
  && ok "T1 placeholder FR 만 → 실 FR 0건 FAIL" || nope "T1" "rc=$rc out=$out"
rm -rf "$TD"

# T2: 실제 FR → PASS + 개수 보고
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 상태 |
|---|---|---|---|---|
| FR-1 | 사용자 로그인 | M1 | must | (TBD) |
| FR-2 | 일정 목록 조회 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '2' \
  && ok "T2 실 FR 2건 → PASS" || nope "T2" "rc=$rc out=$out"
rm -rf "$TD"

# T3: 혼재 — 실 FR 1 + placeholder 2 → PASS 하되 placeholder 를 경고로 지목
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 상태 |
|---|---|---|---|---|
| FR-1 | 사용자 로그인 | M1 | must | (TBD) |
| FR-2 | <한 줄> | M2 | should | (TBD) |
| FR-3 | <한 줄> | M3 | nice | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qE 'FR-2.*FR-3|placeholder 2' \
  && ok "T3 혼재 → PASS + placeholder 지목" || nope "T3" "rc=$rc out=$out"
rm -rf "$TD"

# T4: 무정보 값(TBD·미정)도 실 FR 아님
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 상태 |
|---|---|---|---|---|
| FR-1 | TBD | M1 | must | (TBD) |
| FR-2 | (미정) | M2 | should | (TBD) |
EOF
(cd "$TD" && bash "$CHK" >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T4 TBD·(미정) → 실 FR 아님" || nope "T4" "rc=$rc"
rm -rf "$TD"

# T5: 루트 requirements.md fallback (탐색 순서 memory → 루트)
TD=$(mktemp -d)
_req "$TD/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 상태 |
|---|---|---|---|---|
| FR-1 | 알림 발송 | M1 | must | (TBD) |
EOF
(cd "$TD" && bash "$CHK" >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T5 루트 fallback 탐색" || nope "T5" "rc=$rc"
rm -rf "$TD"

# T6: requirements.md 부재 → 별도 코드(2) — Phase 0 의 기존 '없음' 안내와 구분
TD=$(mktemp -d)
(cd "$TD" && bash "$CHK" >/dev/null 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "T6 파일 부재 → rc=2 (구분)" || nope "T6" "rc=$rc"
rm -rf "$TD"

# T7: start-all Phase 0 배선 — 기계 파싱 직후 가드 호출
grep -q 'check-fr-table.sh' "$PLUGIN/commands/start-all.md" \
  && ok "T7 start-all Phase 0 배선" || nope "T7" "미배선"

# T8: start-all-auto 도 동일 Phase 0 을 쓰므로 문서 정합
grep -qE 'check-fr-table|Phase 0.*동일' "$PLUGIN/commands/start-all-auto.md" \
  && ok "T8 start-all-auto Phase 0 승계 명시" || nope "T8" "승계 불명"

# ── T9~T11: FR 행이 경고 없이 빠지지 않는다 (20261009-startall-silent-pass) ──
#   종전 파서는 `| FR-<숫자> |` 만 읽었다. ID 를 굵게 쓴 행(`| **FR-10** |`)과 접미 ID(`| FR-11b |`)는
#   실 FR 건수에도, placeholder 경고에도, 분류 결과에도 없이 사라졌다 — 사용자가 적은 기능이 batch 에서 조용히 빠진다
#   (실측 20261008: 연습용 프로젝트에서 두 행이 통째로 누락. batch-state 는 접미 ID 만 끝에 가서 드리프트로 잡았다).
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 상태 |
|---|---|---|---|---|
| FR-5 | 주문 목록 조회 | M1 | must | (TBD) |
| **FR-10** | 정산 내보내기 | M2 | nice | (TBD) |
| FR-11b | 주문 목록 엑셀 | M1 | nice | (TBD) |
| `FR-12` | 백틱으로 감싼 ID | M1 | nice | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" --classify 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx 'ELIGIBLE|FR-10|정산 내보내기|M2' \
  && printf '%s\n' "$out" | grep -qx 'ELIGIBLE|FR-11b|주문 목록 엑셀|M1' \
  && printf '%s\n' "$out" | grep -qx 'ELIGIBLE|FR-12|백틱으로 감싼 ID|M1' \
  && printf '%s\n' "$out" | grep -q '^SUMMARY|real=4|eligible=4|' \
  && ok "T9 ★ 굵은 ID·접미 ID·백틱 ID 행도 FR 로 읽는다(ID 는 장식을 벗겨 낸다)" || nope "T9" "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ')"
rm -rf "$TD"

# T10: FR 행처럼 보이는데 형식이 달라 읽지 못한 행은 **알린다** (조용히 버리지 않는다)
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 상태 |
|---|---|---|---|---|
| FR-5 | 주문 목록 조회 | M1 | must | (TBD) |
| FR 6 | 하이픈 없는 ID | M1 | must | (TBD) |
| FR-x7 | 숫자로 시작하지 않는 ID | M1 | must | (TBD) |
| NFR-1 | 성능 | 응답 200ms | 부하 테스트 | - |
EOF
out=$(cd "$TD" && bash "$CHK" --classify 2>&1); rc=$?
n=$(printf '%s\n' "$out" | grep -c '^UNPARSED|')
[ "$rc" -eq 0 ] && [ "$n" -eq 2 ] && printf '%s\n' "$out" | grep -q '^UNPARSED|.*FR 6' && printf '%s\n' "$out" | grep -q '^UNPARSED|.*FR-x7' \
  && ! printf '%s\n' "$out" | grep -q '^UNPARSED|.*NFR-1' && printf '%s\n' "$out" | grep -q '^SUMMARY|real=1|eligible=1|.*unparsed=2' \
  && ok "T10 ★ FR 처럼 보이나 못 읽은 행 → UNPARSED 레코드 + SUMMARY 건수 (NFR 행은 FR 이 아니다)" || nope "T10" "rc=$rc n=$n out=$(printf '%s' "$out" | tr '\n' ' ')"
out=$(cd "$TD" && bash "$CHK" 2>&1)
printf '%s' "$out" | grep -q '해석하지 못한 FR 행 2건' && printf '%s' "$out" | grep -q 'FR 6' \
  && ok "T10b 사람용 요약에도 못 읽은 행을 경고로 보인다" || nope "T10b" "out=$out"
rm -rf "$TD"

# T11: 장식이 붙은 ID 도 시드·공통부 판정에 그대로 쓰인다(벗겨 낸 ID 로 판정)
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
<!-- seed-fr: FR-1,FR-2,FR-3 -->
| ID | 요구사항 | 마일스톤 | 우선순위 | 상태 |
|---|---|---|---|---|
| **FR-1** | 주문 관리 | M1 | must | (TBD) |
| **FR-4** | [공통] 로그인 | M1 | must | (TBD) |
| **FR-5** | 주문 목록 조회 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" --classify 2>&1)
printf '%s\n' "$out" | grep -qx 'SKIP|FR-1|seed-decomposed|M1' && printf '%s\n' "$out" | grep -qx 'SKIP|FR-4|foundation-scope|M1' \
  && printf '%s\n' "$out" | grep -qx 'ELIGIBLE|FR-5|주문 목록 조회|M1' \
  && ok "T11 굵은 ID 표에서도 시드·공통부 분류가 같다" || nope "T11" "out=$(printf '%s' "$out" | tr '\n' ' ')"
rm -rf "$TD"

# T12: ★ 설명 칸이 빈 FR 행은 placeholder 다 — 칸이 밀려 적격 FR 이 되지 않는다
#   (이번 변경의 초안이 만든 회귀: 탭 구분으로 읽으면 빈 칸이 접혀 마일스톤 `M1` 이 설명 자리로 온다 → ELIGIBLE|FR-15|M1|.
#    그러면 설명 없는 FR 이 batch 구현 대상이 된다. 독립 리뷰가 재현.)
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 상태 |
|---|---|---|---|---|
| FR-5 | 주문 목록 조회 | M1 | must | (TBD) |
| FR-15 | | M1 | must | (TBD) |
| FR-16 | 마일스톤이 빈 행 | | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" --classify 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx 'SKIP|FR-15|placeholder|' && ! printf '%s\n' "$out" | grep -q '^ELIGIBLE|FR-15' \
  && printf '%s\n' "$out" | grep -qx 'ELIGIBLE|FR-16|마일스톤이 빈 행|' \
  && printf '%s\n' "$out" | grep -q '^SUMMARY|real=2|eligible=2|seed_skip=0|placeholder=1|' \
  && ok "T12 ★ 설명이 빈 행 → placeholder · 마일스톤이 빈 행 → 설명 그대로(칸 밀림 없음)" || nope "T12" "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ')"
rm -rf "$TD"

# T12b: UNPARSED 는 칸 전체가 ID 하나처럼 생긴 것만 — 문장·참조 칸은 FR 행이 아니다(경고하지 않는다)
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 상태 |
|---|---|---|---|---|
| FR-5 | 주문 목록 조회 | M1 | must | (TBD) |
| FRAME 2 | 프레임 | M1 | must | (TBD) |
| FR-1, FR-2 | 묶음 참조 | M1 | must | (TBD) |
| FR-3 → T4 | 추적 | M1 | must | (TBD) |
| FRONT-1 | 프론트 | M1 | must | (TBD) |
| FR_7 | 밑줄 ID | M1 | must | (TBD) |
  | FR-8 | 들여쓴 행 | M1 | must | (TBD) |
  | 참고 | 들여쓴 일반 표 행 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$CHK" --classify 2>&1)
n=$(printf '%s\n' "$out" | grep -c '^UNPARSED|')
#   들여쓴 FR 꼴 행은 종전부터 읽지 않는다(batch-state 와 같은 범위). 말없이 빠지지 않게 알리기만 한다 — 적격으로 올리지 않는다.
[ "$n" -eq 2 ] && printf '%s\n' "$out" | grep -qx 'UNPARSED|FR_7' && printf '%s\n' "$out" | grep -qx 'UNPARSED|FR-8 (들여쓴 행)' \
  && ! printf '%s\n' "$out" | grep -qE '^(ELIGIBLE|SKIP)\|FR-8' \
  && printf '%s\n' "$out" | grep -q '^SUMMARY|real=1|eligible=1|.*unparsed=2' \
  && ok "T12b UNPARSED 오탐 없음(FRAME 2·묶음 참조·추적·FRONT-1·들여쓴 일반 행) · 밑줄 ID·들여쓴 FR 행은 알림(적격 아님)" || nope "T12b" "n=$n out=$(printf '%s' "$out" | tr '\n' ' ')"
rm -rf "$TD"

finish
