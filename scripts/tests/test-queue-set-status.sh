#!/usr/bin/env bash
# test-queue-set-status.sh — queue.md Status 기계 갱신 검증 (FID 20260828-queue-label-drift)
#
# 계기: argus batch-20260729 실측. 종전 갱신 경로는 start-all.md 산문 지시를 받은
#   **모델 손편집**뿐이었고, 모델이 `**IMPL_DONE**` 로 적자 소비자 3곳이 전건 불일치해
#   산출물·review-skip 검사가 **대상 0건으로 조용히 통과**했다(FR 31건 무검증).
#   읽는 쪽 정규화(queue-lib)가 사후 방어라면, 이 스크립트는 유입 자체를 끊는다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCRIPT="$PLUGIN/scripts/_internal/queue-set-status.sh"
LIB="$PLUGIN/scripts/_internal/queue-lib.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

mk_queue() {  # <path>
  cat > "$1" <<'EOF'
# batch queue

| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-a | 종목 마스터 동기화 — KOSPI200 + KOSDAQ150 | PENDING |
| FR-2 | 20260101-b | 캔들 수집 | **IMPL_DONE** |
| FR-3 | 20260101-c | 지표 | SKIP |
EOF
}

_status_of() {  # <queue> <FR-ID> → 정규화 라벨
  . "$LIB"
  awk -F'|' -v want="$2" "$QUEUE_AWK_QNORM"'
    /^[[:space:]]*\|/ {
      if (qnorm($2) == want) {
        for (i = NF; i >= 1; i--) if (qnorm($i) != "") { print qnorm($i); exit }
      }
    }' "$1"
}

# ── T1 정상 갱신 ──
Q="$TMP/t1.md"; mk_queue "$Q"
out=$(bash "$SCRIPT" "$Q" FR-1 IMPL_DONE 2>&1); code=$?
if [ "$code" -eq 0 ] && [ "$(_status_of "$Q" FR-1)" = "IMPL_DONE" ]; then
  ok "T1 PENDING → IMPL_DONE 갱신"
else
  nope "T1 갱신 실패" "exit=$code out=$out"
fi

# ── T2 다른 행 무손상 ── (같은 파일 계속 사용)
if [ "$(_status_of "$Q" FR-3)" = "SKIP" ]; then
  ok "T2 무관 행 무손상"
else
  nope "T2 무관 행 오염" "FR-3=$(_status_of "$Q" FR-3)"
fi

# ── T3 설명 컬럼 보존 — 한국어·em dash 가 살아남아야 한다 ──
#    행 재조립 방식이면 설명의 특수문자가 깨질 수 있다. 실제 내용으로 잠근다.
if grep -q '종목 마스터 동기화 — KOSPI200 + KOSDAQ150' "$Q"; then
  ok "T3 설명 컬럼 원문 보존 (em dash·한국어)"
else
  nope "T3 설명 컬럼 손상" "$(grep -m1 'FR-1' "$Q")"
fi

# ── T4 굵게 표기 행도 갱신되고 장식이 벗겨진다 ──
out=$(bash "$SCRIPT" "$Q" FR-2 MERGED 2>&1); code=$?
if [ "$code" -eq 0 ] && [ "$(_status_of "$Q" FR-2)" = "MERGED" ] && ! grep -q '\*\*' "$Q"; then
  ok "T4 **IMPL_DONE** 행 갱신 + 장식 제거"
else
  nope "T4 장식 잔존" "exit=$code line=$(grep -m1 'FR-2' "$Q")"
fi

# ── T5 알 수 없는 라벨 거부 ──
#    이게 없으면 기계화의 의미가 없다 — 통과한 값이 소비자 인식 라벨임을 보장해야 한다.
Q5="$TMP/t5.md"; mk_queue "$Q5"
out=$(bash "$SCRIPT" "$Q5" FR-1 DONE 2>&1); code=$?
if [ "$code" -ne 0 ] && printf '%s' "$out" | grep -q '알 수 없는 라벨'; then
  ok "T5 알 수 없는 라벨(DONE) 거부"
else
  nope "T5 라벨 검증 부재" "exit=$code out=$out"
fi
[ "$(_status_of "$Q5" FR-1)" = "PENDING" ] && ok "T5.b 거부 시 파일 무변경" \
  || nope "T5.b 거부인데 파일 변경됨" "FR-1=$(_status_of "$Q5" FR-1)"

# ── T6 FR-ID 미발견 거부 ──
out=$(bash "$SCRIPT" "$Q5" FR-99 SKIP 2>&1); code=$?
[ "$code" -ne 0 ] && printf '%s' "$out" | grep -q '미발견' \
  && ok "T6 미발견 FR-ID 거부" || nope "T6 미발견 미거부" "exit=$code out=$out"

# ── T7 FR-ID 중복 거부 ──
#    어느 행을 고칠지 모르는 채 하나를 고르면 조용히 틀린 행을 갱신한다.
Q7="$TMP/t7.md"; mk_queue "$Q7"
printf '| FR-1 | 20260101-dup | 중복 행 | PENDING |\n' >> "$Q7"
out=$(bash "$SCRIPT" "$Q7" FR-1 IMPL_DONE 2>&1); code=$?
if [ "$code" -ne 0 ] && printf '%s' "$out" | grep -q '중복'; then
  ok "T7 FR-ID 중복 거부"
else
  nope "T7 중복 미거부 — 틀린 행 갱신 위험" "exit=$code out=$out"
fi

# ── T8 멱등 — 같은 값 재적용이 깨지지 않는다 ──
Q8="$TMP/t8.md"; mk_queue "$Q8"
bash "$SCRIPT" "$Q8" FR-3 SKIP >/dev/null 2>&1
out=$(bash "$SCRIPT" "$Q8" FR-3 SKIP 2>&1); code=$?
if [ "$code" -eq 0 ] && [ "$(_status_of "$Q8" FR-3)" = "SKIP" ]; then
  ok "T8 멱등 — 같은 값 재적용 안전"
else
  nope "T8 멱등 실패" "exit=$code"
fi

# ── T9 행 수 불변 ──
#    표가 깨지면 소비자 전체가 오작동한다. 행 수는 최소한의 구조 지표다.
Q9="$TMP/t9.md"; mk_queue "$Q9"
before=$(wc -l < "$Q9")
bash "$SCRIPT" "$Q9" FR-1 WIP >/dev/null 2>&1
after=$(wc -l < "$Q9")
[ "$before" = "$after" ] && ok "T9 행 수 불변 ($before)" \
  || nope "T9 행 수 변동" "$before → $after"

# ── T10 파일 부재 → 사용 오류(exit 2) ──
bash "$SCRIPT" "$TMP/nope.md" FR-1 SKIP >/dev/null 2>&1; code=$?
[ "$code" -eq 2 ] && ok "T10 파일 부재 exit 2" || nope "T10 exit code" "exit=$code (기대 2)"

# ── T11 인자 부족 → 사용 오류(exit 2) ──
bash "$SCRIPT" "$Q9" FR-1 >/dev/null 2>&1; code=$?
[ "$code" -eq 2 ] && ok "T11 인자 부족 exit 2" || nope "T11 exit code" "exit=$code (기대 2)"

# ── T12 queue-lib 정규화 규칙 단위 검증 ──
#    소비자 4곳이 이 함수 하나에 의존하므로 규칙 자체를 직접 잠근다.
. "$LIB"
_qn_ok=0
[ "$(queue::qnorm '**IMPL_DONE**')" = "IMPL_DONE" ] || _qn_ok=1
[ "$(queue::qnorm '  `SKIP`  ')" = "SKIP" ] || _qn_ok=1
[ "$(queue::qnorm '_PENDING_')" = "PENDING" ] || _qn_ok=1
[ "$(queue::qnorm 'IMPL_DONE')" = "IMPL_DONE" ] || _qn_ok=1
[ "$_qn_ok" -eq 0 ] && ok "T12 queue::qnorm 장식 흡수 (굵게·백틱·기울임·평문)" \
  || nope "T12 qnorm 규칙 불일치"

# T12.b 과잉 정규화 금지 — 라벨 자체를 바꾸면 미완이 완료가 된다
if [ "$(queue::qnorm '**PLAN_DONE**')" = "PLAN_DONE" ] && [ "$(queue::qnorm 'DONE')" = "DONE" ]; then
  ok "T12.b 과잉 정규화 없음 — 라벨 내용 불변"
else
  nope "T12.b 과잉 정규화" "PLAN_DONE=$(queue::qnorm '**PLAN_DONE**') DONE=$(queue::qnorm 'DONE')"
fi

# ── T13 start-all 배선 — 산문 손편집 지시로 되돌아가지 않게 잠근다 ──
#    스크립트만 있고 호출하는 곳이 없으면 유입이 그대로다.
SA="$PLUGIN/commands/start-all.md"
n=$(grep -c 'queue-set-status\.sh' "$SA" 2>/dev/null || echo 0)
if [ "$n" -ge 2 ]; then
  ok "T13 start-all Phase 1·3 Status 갱신이 스크립트 배선 (${n}곳)"
else
  nope "T13 배선 누락" "queue-set-status.sh 참조 ${n}곳 (기대 ≥2)"
fi

# ── T14 소비자 4곳이 정규화 단일 출처를 쓴다 ──
#    한 곳이라도 자기 정규식을 따로 쓰면 이 FID 가 고친 드리프트가 재발한다.
_t14=0
for f in scripts/batch-state.sh scripts/_internal/collect-assumptions.sh scripts/_internal/record-batch-gate.sh; do
  grep -q 'queue-lib\.sh' "$PLUGIN/$f" || { _t14=1; echo "  (미배선: $f)"; }
done
[ "$_t14" -eq 0 ] && ok "T14 소비자 3곳 queue-lib 단일 출처 사용" \
  || nope "T14 정규화 규칙 분산 — 드리프트 재발 위험"

# ── T15~T18: FID 칸을 스크립트로 채운다 (20261009-startall-silent-pass) ──
#   batch PR 게이트·RELEASE_READY·게이트 전파는 queue 의 FID 칸으로 그 FR 의 산출물을 찾는다. 그런데 FID 칸은 모델이 표를
#   손으로 고치게 돼 있었고(start-all.md 는 "게이트가 읽는 값이 아니다" 라고까지 적었다), 비어 있으면 검사가 그 행을 건너뛰었다.
mk_tbd() {
  cat > "$1" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-5 | TBD | 주문 목록 | PENDING |
| FR-6 | TBD | 주문 상세 | PENDING |
| FR-7 | 20260101-c | 주문 취소 | PLAN_DONE |
EOF
}
_fid_of() { awk -F'|' -v want="$2" '/^[[:space:]]*\|/ { v=$2; gsub(/^[ \t]+|[ \t]+$/, "", v); if (v == want) { f=$3; gsub(/^[ \t]+|[ \t]+$/, "", f); print f; exit } }' "$1"; }

Q="$TMP/t15.md"; mk_tbd "$Q"
out=$(bash "$SCRIPT" "$Q" FR-5 PLAN_DONE 20261009-order-list 2>&1); code=$?
[ "$code" -eq 0 ] && [ "$(_fid_of "$Q" FR-5)" = "20261009-order-list" ] && [ "$(_status_of "$Q" FR-5)" = "PLAN_DONE" ] \
  && grep -q '^| FR-5 | 20261009-order-list | 주문 목록 | PLAN_DONE |$' "$Q" && [ "$(_fid_of "$Q" FR-6)" = "TBD" ] \
  && ok "T15 ★ 넷째 인자 FID → 그 행의 FID 칸과 Status 를 함께 갱신(다른 칸·다른 행 불변)" || nope "T15" "code=$code out=$out $(cat "$Q" | tr '\n' ' ')"

Q="$TMP/t16.md"; mk_tbd "$Q"; h1=$(cksum < "$Q")
out=$(bash "$SCRIPT" "$Q" FR-5 PLAN_DONE 'not a fid' 2>&1); c1=$?
out2=$(bash "$SCRIPT" "$Q" FR-5 PLAN_DONE '20261009-x|y' 2>&1); c2=$?
[ "$c1" -ne 0 ] && [ "$c2" -ne 0 ] && [ "$h1" = "$(cksum < "$Q")" ] \
  && ok "T16 FID 형식이 아니면 거부(파일 무변경 — 표 구분자 주입 불가)" || nope "T16" "c1=$c1 c2=$c2"

# IMPL_DONE 은 FID 칸이 채워져 있어야 한다 — 산출물을 찾을 수 없는 완료 행을 만들지 않는다
Q="$TMP/t17.md"; mk_tbd "$Q"; h1=$(cksum < "$Q")
out=$(bash "$SCRIPT" "$Q" FR-6 IMPL_DONE 2>&1); code=$?
[ "$code" -ne 0 ] && [ "$h1" = "$(cksum < "$Q")" ] && printf '%s' "$out" | grep -q 'FID' \
  && ok "T17 ★ FID 칸이 TBD 인 행을 IMPL_DONE 으로 → 거부(FID 를 함께 주라고 안내)" || nope "T17" "code=$code out=$out"
out=$(bash "$SCRIPT" "$Q" FR-6 IMPL_DONE 20261009-order-detail 2>&1); c1=$?
out=$(bash "$SCRIPT" "$Q" FR-7 IMPL_DONE 2>&1); c2=$?
[ "$c1" -eq 0 ] && [ "$c2" -eq 0 ] && [ "$(_status_of "$Q" FR-6)" = "IMPL_DONE" ] && [ "$(_status_of "$Q" FR-7)" = "IMPL_DONE" ] \
  && ok "T17b FID 를 함께 주거나 이미 채워진 행은 IMPL_DONE 통과" || nope "T17b" "c1=$c1 c2=$c2"

# PLAN_DONE 인데 FID 가 아직 TBD — 막지는 않되 알린다(재개 중인 옛 queue 를 깨지 않는다)
Q="$TMP/t18.md"; mk_tbd "$Q"
out=$(bash "$SCRIPT" "$Q" FR-5 PLAN_DONE 2>&1); code=$?
[ "$code" -eq 0 ] && printf '%s' "$out" | grep -q 'FID 칸' \
  && ok "T18 FID 없이 PLAN_DONE → 갱신하되 FID 칸이 비었다고 경고" || nope "T18" "code=$code out=$out"
#   넷째 인자는 FID 칸이 있는 표(4칸)에서만 — 칸 수가 모자라면 엉뚱한 칸을 덮어쓰지 않는다
printf '| FR-9 | 설명 | PENDING |\n' > "$TMP/t18b.md"; h1=$(cksum < "$TMP/t18b.md")
out=$(bash "$SCRIPT" "$TMP/t18b.md" FR-9 PLAN_DONE 20261009-z 2>&1); code=$?
[ "$code" -ne 0 ] && [ "$h1" = "$(cksum < "$TMP/t18b.md")" ] \
  && ok "T18b FID 칸이 없는 표(3칸)에 FID 인자 → 거부(파일 무변경)" || nope "T18b" "code=$code out=$out"

# ── T19: 인자가 5개 이상이면 사용법 오류 — 남는 인자를 조용히 버리지 않는다 ──
mk_queue "$TMP/t19.md"; h19=$(cksum < "$TMP/t19.md")
out=$(bash "$SCRIPT" "$TMP/t19.md" FR-1 PLAN_DONE 20260101-a extra 2>&1); code=$?
[ "$code" -ne 0 ] && printf '%s' "$out" | grep -q 'usage:' && [ "$h19" = "$(cksum < "$TMP/t19.md")" ] \
  && ok "T19 인자 5개 → usage · 파일 무변경" || nope "T19" "code=$code out=$out"
# ── T20: FID 칸 경고는 FID 가 아닐 때만 낸다 ──
#   PLAN_DONE 으로 바꾸는데 FID 칸이 이미 FID 면 경고가 없어야 한다(조건을 꺼도 통과하던 변이 — 20261009 실측).
mk_queue "$TMP/t20.md"
out=$(bash "$SCRIPT" "$TMP/t20.md" FR-1 PLAN_DONE 2>&1); code=$?
[ "$code" -eq 0 ] && ! printf '%s' "$out" | grep -q '경고' \
  && ok "T20a FID 칸이 FID 인 행 → PLAN_DONE 에 경고 없음" || nope "T20a" "code=$code out=$out"
cat > "$TMP/t20b.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | TBD | 아직 FID 없음 | PENDING |
EOF
out=$(bash "$SCRIPT" "$TMP/t20b.md" FR-1 PLAN_DONE 2>&1); code=$?
[ "$code" -eq 0 ] && printf '%s' "$out" | grep -q '경고' && printf '%s' "$out" | grep -q "TBD" \
  && ok "T20b FID 칸이 TBD 인 행 → PLAN_DONE 은 되고 경고가 그 값을 보인다" || nope "T20b" "code=$code out=$out"

finish
