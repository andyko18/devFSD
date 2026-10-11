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
out=$(cd "$TD" && bash "$INIT" ".specops/batch-t10" 2>&1); rc=$?
q="$TD/.specops/batch-t10/queue.md"
[ "$rc" -eq 0 ] && grep -q '^| FR-10 | TBD | 정산 내보내기 | PENDING |$' "$q" && grep -q '^| FR-11b | TBD | 주문 엑셀 | PENDING |$' "$q" \
  && ok "T10 굵은 ID·접미 ID → queue PENDING 행(ID 는 장식 없이)" || nope "T10" "rc=$rc out=$out q=$(cat "$q" 2>/dev/null | tr '\n' ' ')"
printf '%s' "$out" | grep -q '해석하지 못한 FR 행 1건' && grep -q '해석하지 못한 FR 행' "$q" && grep -q 'FR 12' "$q" \
  && ! grep -qE '^\|.*FR 12' "$q" \
  && ok "T10b 못 읽은 행 → 초기화 출력 + queue 머리말에 기록(표 행은 아니다)" || nope "T10b" "out=$out q=$(sed -n 1,12p "$q" 2>/dev/null | tr '\n' ' ')"
rm -rf "$TD"

finish
