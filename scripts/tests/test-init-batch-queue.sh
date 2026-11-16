#!/usr/bin/env bash
# Phase 0 queue.md 기계 초기화 — 20260812
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
INIT="$PLUGIN/scripts/_internal/init-batch-queue.sh"

_req() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

# T1 attendance형: 시드+세부 → FR-1 SKIP · FR-4 PENDING · CREATED
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
> **FR-1~3 은 PRD 마일스톤 시드**
<!-- seed-fr: FR-1,FR-2,FR-3 -->
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | 직원 출퇴근 기록 + 당월 목록 | M1 | must | (TBD) |
| FR-2 | <한 줄> | M2 | should | (TBD) |
| FR-4 | 사번+비밀번호 로그인 | M1 | must | (TBD) |
| FR-5 | 출근 기록 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$INIT" ".specops/batch-t1" 2>&1); rc=$?
q="$TD/.specops/batch-t1/queue.md"
printf '%s' "$out" | grep -q 'QUEUE-INIT: CREATED' && [ "$rc" -eq 0 ] || { nope "T1a" "rc=$rc out=$out"; rm -rf "$TD"; finish; exit 1; }
grep -qE '\| FR-1 \| — \|.*\| SKIP \|' "$q" \
  && grep -qE '\| FR-4 \| TBD \|.*\| PENDING \|' "$q" \
  && grep -qE '\| FR-5 \| TBD \|.*\| PENDING \|' "$q" \
  && ! grep -qE '\| FR-2 \|' "$q" \
  && ok "T1 attendance형 CREATED + FR-1 SKIP / FR-4 PENDING" \
  || nope "T1" "queue=$(cat "$q")"
rm -rf "$TD"

# T2 [공통] → foundation-scope SKIP
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-4 | **[공통]** 스캐폴딩 | M1 | must | (TBD) |
| FR-5 | 로그인 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$INIT" ".specops/batch-t2" 2>&1); rc=$?
q="$TD/.specops/batch-t2/queue.md"
printf '%s' "$out" | grep -q CREATED && [ "$rc" -eq 0 ] \
  && grep -qE '\| FR-4 \| — \|.*공통부.*\| SKIP \|' "$q" \
  && grep -qE '\| FR-5 \| TBD \|.*\| PENDING \|' "$q" \
  && grep -q 'foundation-scope' "$q" \
  && ok "T2 foundation-scope SKIP" \
  || nope "T2" "rc=$rc out=$out q=$(cat "$q" 2>/dev/null)"
rm -rf "$TD"

# T3 기존 queue → REUSE (내용 불변)
TD=$(mktemp -d)
mkdir -p "$TD/.specops/batch-t3"
echo 'MARKER-ORIGINAL' > "$TD/.specops/batch-t3/queue.md"
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-10 | 기능 A | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$INIT" ".specops/batch-t3" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'QUEUE-INIT: REUSE' && [ "$rc" -eq 0 ] \
  && grep -qx 'MARKER-ORIGINAL' "$TD/.specops/batch-t3/queue.md" \
  && ok "T3 REUSE 불변" \
  || nope "T3" "rc=$rc out=$out"
rm -rf "$TD"

# T4 eligible=0: 시드 분해 + 공통만
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
<!-- seed-fr: FR-1,FR-2,FR-3 -->
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | M1 시드 | M1 | must | (TBD) |
| FR-4 | **[공통]** 코어 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$INIT" ".specops/batch-t4" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'QUEUE-INIT: FAIL' && [ "$rc" -eq 1 ] \
  && [ ! -f "$TD/.specops/batch-t4/queue.md" ] \
  && ok "T4 eligible=0 → FAIL" \
  || nope "T4" "rc=$rc out=$out"
rm -rf "$TD"

# T5 placeholder만 → classify FAIL → QUEUE-INIT FAIL
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | <한 줄> | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$INIT" ".specops/batch-t5" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'QUEUE-INIT: FAIL' && [ "$rc" -eq 1 ] \
  && ok "T5 placeholder만 → FAIL" \
  || nope "T5" "rc=$rc out=$out"
rm -rf "$TD"

# T6 start-all wiring
grep -q 'init-batch-queue\.sh' "$PLUGIN/commands/start-all.md" \
  && ok "T6 start-all wiring" \
  || nope "T6" "missing"

# T7 start-all-auto
grep -q 'init-batch-queue' "$PLUGIN/commands/start-all-auto.md" \
  && ok "T7 start-all-auto" \
  || nope "T7" "auto missing"

# T8 mutation: REUSE exit 무력화 → 덮어쓰기
TD=$(mktemp -d)
mkdir -p "$TD/.specops/batch-t8"
echo 'MARKER-ORIGINAL' > "$TD/.specops/batch-t8/queue.md"
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-10 | 기능 A | M1 | must | (TBD) |
EOF
# ★ 변이본은 실 트리 밖에 둔다 (20260911-run-all-parallel): 종전엔 실 `scripts/_internal/` 에 만들었다 —
#   병렬로 도는 test-shellcheck-lint 의 `find hooks scripts -name '*.sh'` 가 그 파일을 집었다가 삭제 경합을 볼 수 있다
#   (find-tree-writes 실측). 변이본은 SELF(dirname)로 형제 check-fr-table.sh 를 찾으므로 그 파일을 같은 자리에 둔다.
mkdir -p "$TD/_internal"
cp "$PLUGIN/scripts/_internal/check-fr-table.sh" "$TD/_internal/check-fr-table.sh"
mut="$TD/_internal/.init-batch-queue.mut.sh"
awk '
  /^  echo "QUEUE-INIT: REUSE/ { print; getline; print "  true  # mutated: was exit 0"; next }
  { print }
' "$INIT" > "$mut"
chmod +x "$mut"
out=$(cd "$TD" && bash "$mut" ".specops/batch-t8" 2>&1); rc=$?
rm -f "$mut"
if printf '%s' "$out" | grep -q 'CREATED' && ! grep -qx 'MARKER-ORIGINAL' "$TD/.specops/batch-t8/queue.md"; then
  echo 'MARKER-ORIGINAL' > "$TD/.specops/batch-t8/queue.md"
  out_real=$(cd "$TD" && bash "$INIT" ".specops/batch-t8" 2>&1)
  printf '%s' "$out_real" | grep -q REUSE \
    && ok "T8 mutation: REUSE 무력화 → CREATED (비-vacuous)" \
    || nope "T8" "real not REUSE out=$out_real"
else
  nope "T8" "mutation did not overwrite rc=$rc out=$out"
fi
rm -rf "$TD"

# T9 pipe escape helper present + CREATED
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-7 | foo bar baz | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$INIT" ".specops/batch-t9" 2>&1); rc=$?
grep -q "_escape_cell" "$INIT" \
  && grep -q "tr " "$INIT" \
  && [ "$rc" -eq 0 ] \
  && ok "T9 pipe escape (tr) + CREATED" \
  || nope "T9" "rc=$rc out=$out"
rm -rf "$TD"

# T10: 굵은 ID·접미 ID 행도 queue 에 들어가고, 못 읽은 행은 초기화 출력과 queue 머리말에 남는다 (20261009)
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-5 | 주문 목록 | M1 | must | (TBD) |
| **FR-10** | 정산 내보내기 | M2 | nice | (TBD) |
| FR-11b | 주문 엑셀 | M1 | nice | (TBD) |
| FR 12 | 하이픈 없는 ID | M1 | nice | (TBD) |
EOF
out=$(cd "$TD" && bash "$INIT" --milestone all ".specops/batch-t10" 2>&1); rc=$?   # ID 읽기 시험 — 마일스톤 범위(T11~)와 분리
q="$TD/.specops/batch-t10/queue.md"
[ "$rc" -eq 0 ] && grep -q '^| FR-10 | TBD | 정산 내보내기 | PENDING |$' "$q" && grep -q '^| FR-11b | TBD | 주문 엑셀 | PENDING |$' "$q" \
  && ok "T10 굵은 ID·접미 ID → queue PENDING 행(ID 는 장식 없이)" || nope "T10" "rc=$rc out=$out q=$(cat "$q" 2>/dev/null | tr '\n' ' ')"
printf '%s' "$out" | grep -q '해석하지 못한 FR 행 1건' && grep -q '해석하지 못한 FR 행' "$q" && grep -q 'FR 12' "$q" \
  && ! grep -qE '^\|.*FR 12' "$q" \
  && ok "T10b 못 읽은 행 → 초기화 출력 + queue 머리말에 기록(표 행은 아니다)" || nope "T10b" "out=$out q=$(sed -n 1,12p "$q" 2>/dev/null | tr '\n' ' ')"
rm -rf "$TD"

# ── 마일스톤 범위 (20261116) — /init-project 는 M1 만 설계를 끝내는데 /start-all 이 M2·M3 까지 한 batch 에 넣었다 ──
_ms_req() {
  _req "$1/.specops/memory/requirements.md" <<'EOF'
<!-- seed-fr: FR-1,FR-2,FR-3 -->
<!-- foundation-fr: FR-4 -->
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | 예약 — 마일스톤 시드 | M1 | must | FR-4~FR-8 로 분해 |
| FR-2 | 관리 — 마일스톤 시드 | M2 | should | FR-12 로 분해 |
| FR-4 | [공통] 스캐폴딩 | M1 | must | (TBD) |
| FR-12 | 회의실 관리 | M2 | should | M2 시점에 분해 |
| FR-7 | 회의실 목록 | M1 | must | (TBD) |
| FR-8 | 예약 현황 | M1 | must | (TBD) |
| FR-15 | 알림 | M3 | nice | M3 시점에 분해 |
| FR-20 | 마일스톤 없는 기능 |  | nice | (TBD) |
EOF
}

# T11 기본(first): 가장 이른 마일스톤(M1)만 PENDING · 다른 마일스톤은 SKIP 행 · 머리말 milestone 줄 · SCOPE 안내
TD=$(mktemp -d); _ms_req "$TD"
out=$(cd "$TD" && bash "$INIT" ".specops/batch-t11" 2>&1); rc=$?
q="$TD/.specops/batch-t11/queue.md"
[ "$rc" -eq 0 ] && [ "$(grep -c '| PENDING |$' "$q")" -eq 3 ] \
  && grep -q '^| FR-7 | TBD | 회의실 목록 | PENDING |$' "$q" && grep -q '^| FR-8 | TBD | 예약 현황 | PENDING |$' "$q" \
  && grep -q '^| FR-20 | TBD | 마일스톤 없는 기능 | PENDING |$' "$q" \
  && ok "T11a 기본 범위 = 가장 이른 마일스톤 — M1 FR 과 마일스톤 칸이 빈 FR 만 PENDING" || nope "T11a" "rc=$rc out=$out q=$(tr '\n' ' ' < "$q")"
grep -q '^| FR-12 | — | (다른 마일스톤 — M2) | SKIP |$' "$q" && grep -q '^| FR-15 | — | (다른 마일스톤 — M3) | SKIP |$' "$q" \
  && grep -q '^- \*\*FR-12 = SKIP\*\* — later-milestone (M2)$' "$q" \
  && ok "T11b 다른 마일스톤 FR → SKIP 행 + 머리말 사유" || nope "T11b" "q=$(tr '\n' ' ' < "$q")"
grep -qx '> milestone: M1' "$q" && ok "T11c 머리말에 범위 1줄(batch-state 가 읽는다)" || nope "T11c" "q=$(sed -n 1,8p "$q" | tr '\n' ' ')"
printf '%s\n' "$out" | grep -q '^QUEUE-INIT: SCOPE — 마일스톤 M1 대상 3건 · 다른 마일스톤 제외 2건(M2 1건 · M3 1건)' \
  && printf '%s\n' "$out" | grep -q '/start-all --all' \
  && ok "T11d 초기화 출력에 범위·제외 건수·뒤집는 법" || nope "T11d" "out=$out"
# 시드·공통부는 범위와 무관하게 종전 사유 그대로
grep -q '^| FR-1 | — | (마일스톤 시드 — 세부 FR로 분해됨) | SKIP |$' "$q" && grep -q '^| FR-2 | — | (마일스톤 시드 — 세부 FR로 분해됨) | SKIP |$' "$q" \
  && grep -q '^| FR-4 | — | (공통부 — /start-foundation 담당) | SKIP |$' "$q" \
  && ok "T11e 시드·공통부 SKIP 사유는 범위가 덮어쓰지 않는다" || nope "T11e" "q=$(tr '\n' ' ' < "$q")"
rm -rf "$TD"

# T12 이름 지정: M2 만 PENDING · M1·M3 은 SKIP
TD=$(mktemp -d); _ms_req "$TD"
out=$(cd "$TD" && bash "$INIT" --milestone M2 ".specops/batch-t12" 2>&1); rc=$?
q="$TD/.specops/batch-t12/queue.md"
[ "$rc" -eq 0 ] && grep -q '^| FR-12 | TBD | 회의실 관리 | PENDING |$' "$q" \
  && grep -q '^| FR-7 | — | (다른 마일스톤 — M1) | SKIP |$' "$q" && grep -q '^| FR-15 | — | (다른 마일스톤 — M3) | SKIP |$' "$q" \
  && grep -qx '> milestone: M2' "$q" \
  && ok "T12 --milestone M2 → 그 마일스톤만 PENDING" || nope "T12" "rc=$rc out=$out q=$(tr '\n' ' ' < "$q")"
rm -rf "$TD"

# T13 all: 종전 동작(전 마일스톤 PENDING) · 범위 줄·SCOPE 안내 없음
TD=$(mktemp -d); _ms_req "$TD"
out=$(cd "$TD" && bash "$INIT" --milestone all ".specops/batch-t13" 2>&1); rc=$?
q="$TD/.specops/batch-t13/queue.md"
[ "$rc" -eq 0 ] && [ "$(grep -c '| PENDING |$' "$q")" -eq 5 ] && ! grep -q 'milestone:' "$q" && ! grep -q '다른 마일스톤' "$q" \
  && ! printf '%s\n' "$out" | grep -q 'SCOPE' \
  && ok "T13 --milestone all → 전 마일스톤 PENDING(종전) · 범위 표시 없음" || nope "T13" "rc=$rc out=$out q=$(tr '\n' ' ' < "$q")"
rm -rf "$TD"

# T14 없는 마일스톤 이름(오타) → FAIL + 표에 있는 마일스톤 안내 · queue 를 만들지 않는다
TD=$(mktemp -d); _ms_req "$TD"
out=$(cd "$TD" && bash "$INIT" --milestone M9 ".specops/batch-t14" 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q "QUEUE-INIT: FAIL — 마일스톤 'M9' 에 batch 대상 FR 0건 (적격 FR 이 있는 마일스톤: M2 · M1 · M3)" \
  && [ ! -f "$TD/.specops/batch-t14/queue.md" ] \
  && ok "T14 없는 마일스톤 → FAIL + 있는 마일스톤 안내 · queue 미생성" || nope "T14" "rc=$rc out=$out"
rm -rf "$TD"

# T15 마일스톤 칸이 전부 비면 기본 범위도 종전과 같다(전부 PENDING · SKIP 0)
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-5 | 주문 목록 |  | must | (TBD) |
| FR-6 | 주문 상세 |  | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$INIT" ".specops/batch-t15" 2>&1); rc=$?
q="$TD/.specops/batch-t15/queue.md"
[ "$rc" -eq 0 ] && [ "$(grep -c '| PENDING |$' "$q")" -eq 2 ] && ! grep -q 'milestone:' "$q" && ! printf '%s\n' "$out" | grep -q 'SCOPE' \
  && ok "T15 마일스톤 칸이 전부 빔 → 거르지 않는다(종전과 같음)" || nope "T15" "rc=$rc out=$out q=$(tr '\n' ' ' < "$q")"
rm -rf "$TD"

# T16 first 는 표 순서가 아니라 숫자가 가장 작은 마일스톤 — M10·M2 행이 먼저 나와도 M1
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-9 | 나중 기능 | M10 | nice | (TBD) |
| FR-5 | 둘째 기능 | M2 | must | (TBD) |
| FR-6 | 첫 기능 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$INIT" ".specops/batch-t16" 2>&1); rc=$?
q="$TD/.specops/batch-t16/queue.md"
[ "$rc" -eq 0 ] && grep -qx '> milestone: M1' "$q" && grep -q '^| FR-6 | TBD | 첫 기능 | PENDING |$' "$q" && [ "$(grep -c '| PENDING |$' "$q")" -eq 1 ] \
  && ok "T16 first = 숫자가 가장 작은 마일스톤(표 순서 아님 · M10 을 M2 앞으로 읽지 않는다)" || nope "T16" "rc=$rc out=$out q=$(tr '\n' ' ' < "$q")"
rm -rf "$TD"

# T17 숫자 꼴이 아닌 마일스톤이 섞이면 표에 먼저 나온 것
TD=$(mktemp -d)
_req "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-5 | 첫 기능 | 베타 | must | (TBD) |
| FR-6 | 둘째 기능 | M1 | must | (TBD) |
EOF
out=$(cd "$TD" && bash "$INIT" ".specops/batch-t17" 2>&1); rc=$?
q="$TD/.specops/batch-t17/queue.md"
[ "$rc" -eq 0 ] && grep -qx '> milestone: 베타' "$q" && grep -q '^| FR-6 | — | (다른 마일스톤 — M1) | SKIP |$' "$q" \
  && ok "T17 숫자 꼴이 아닌 이름이 섞이면 표에 먼저 나온 마일스톤" || nope "T17" "rc=$rc out=$out q=$(tr '\n' ' ' < "$q")"
rm -rf "$TD"

finish
