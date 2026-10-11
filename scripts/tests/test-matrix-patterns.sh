#!/usr/bin/env bash
# test-matrix-patterns.sh — check-matrix-patterns.sh 의 판별력 (20260831-matrix-pattern-lint)
#
# 왜 별도 파일인가: lint 를 시험하려면 **위반이 있는 원장**이 필요한데, 그걸 실 원장에 넣으면
#   전 커밋이 막힌다. 픽스처 원장(아래 heredoc)으로 lint 를 돌린다 — 픽스처는 이 파일 안에
#   있고 이 파일은 lint 의 **검사 대상이 아니다**(lint 는 원장의 edge 가 가리키는 파일을 본다).
#   즉 자기참조 false-match 가 구조적으로 불가능하다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

LINT="$PLUGIN/scripts/_internal/check-matrix-patterns.sh"
[ -f "$LINT" ] || { nope "M0" "lint 부재"; finish; }

tmp=$(mktemp -d) || exit 1
# shellcheck disable=SC2064
trap "rm -rf '$tmp'" EXIT   # ★ EXIT 단독 (INT/TERM 병기 금지 — handler delay, 20260809 실측)

_lint_run() {  # $1=픽스처 경로 → stdout=출력, return=rc
  local out rc
  out=$(cd "$PLUGIN" && bash "$LINT" "$1" 2>&1); rc=$?
  printf '%s' "$out"
  return "$rc"
}

# ── M1: 주석 전용 패턴 → 위반으로 잡는다 (AC-1) ──
#   governance-lib.sh 의 `task receipt 필수` 는 L989 주석 1줄에만 있다(실측).
printf '%s\n' '{"id":"fx-comment-only","edges":[{"path":"hooks/governance-lib.sh","must_match":"task receipt 필수"}]}' > "$tmp/comment-only.jsonl"
m1=$(_lint_run "$tmp/comment-only.jsonl"); m1_rc=$?
if [ "$m1_rc" -ne 0 ] \
   && printf '%s' "$m1" | grep -q 'fx-comment-only' \
   && printf '%s' "$m1" | grep -q 'governance-lib.sh'; then
  ok "M1 주석 전용 패턴 → 위반 (id·경로 노출, AC-1)"
else
  nope "M1" "rc=$m1_rc / $m1"
fi

# ── M2: 실코드 매치 패턴 → 통과 (AC-1 음성 대조) ──
printf '%s\n' '{"id":"fx-code","edges":[{"path":"hooks/governance-lib.sh","must_match":"_CHECK_TASK_RECEIPT_SH"}]}' > "$tmp/code.jsonl"
m2=$(_lint_run "$tmp/code.jsonl"); m2_rc=$?
if [ "$m2_rc" -eq 0 ] && printf '%s' "$m2" | grep -q 'MATRIX-PATTERN: OK'; then
  ok "M2 실코드 매치 → 통과 (음성 대조)"
else
  nope "M2" "rc=$m2_rc / $m2"
fi

# ── M3: 주석 앵커는 선언으로 인정 (AC-3) ──
#   M1 과 **같은 파일·같은 문구**인데 앵커만 붙였다 — 인정 여부가 패턴 형태로만 갈린다.
printf '%s\n' '{"id":"fx-anchored","edges":[{"path":"hooks/governance-lib.sh","must_match":"^[[:space:]]*#.*task receipt 필수"}]}' > "$tmp/anchored.jsonl"
m3=$(_lint_run "$tmp/anchored.jsonl"); m3_rc=$?
if [ "$m3_rc" -eq 0 ] && printf '%s' "$m3" | grep -q 'MATRIX-PATTERN: OK'; then
  ok "M3 주석 앵커 → 선언으로 인정 (면제 필드 없이, AC-3)"
else
  nope "M3" "rc=$m3_rc / $m3"
fi

# ── M4: 산문(.md) skip + 건수 노출 (AC-2) ──
#   .md 는 전체가 산문이라 "주석 전용" 판정이 정의되지 않는다. 조용히 빼지 않고 숫자로 낸다.
printf '%s\n' '{"id":"fx-md","edges":[{"path":"scripts/README.md","must_match":"propagation-matrix"}]}' > "$tmp/md.jsonl"
#   어서션은 **숫자를 파싱해 비교**한다 — 출력 문구는 런타임 조립이라 통짜 리터럴을 grep 하면
#   사전검사가 dangling-lock 으로 잡는다(그 문자열은 repo 어디에도 없다).
m4=$(_lint_run "$tmp/md.jsonl"); m4_rc=$?
m4_chk=$(printf '%s' "$m4" | sed -n 's/.*검사 \([0-9]*\) .*/\1/p')
m4_skp=$(printf '%s' "$m4" | sed -n 's/.*skip \([0-9]*\).*/\1/p')
if [ "$m4_rc" -eq 0 ] && [ "${m4_chk:-x}" -eq 0 ] 2>/dev/null && [ "${m4_skp:-0}" -eq 1 ] 2>/dev/null; then
  ok "M4 산문(.md) 은 검사 0 · skip 1 — 조용히 빼지 않고 숫자로 낸다 (AC-2)"
else
  nope "M4" "rc=$m4_rc 검사=${m4_chk:-미파싱} skip=${m4_skp:-미파싱} / $m4"
fi

# ── M5: 실 원장이 위반 0 (AC-4 — 무음 2건이 교체됐다) ──
m5=$(_lint_run "$PLUGIN/scripts/_internal/propagation-matrix.jsonl"); m5_rc=$?
if [ "$m5_rc" -eq 0 ] && printf '%s' "$m5" | grep -q 'MATRIX-PATTERN: OK'; then
  ok "M5 실 원장 위반 0 (AC-4)"
else
  nope "M5" "rc=$m5_rc / $m5"
fi

# ── M6: 게이팅 계약 — 실 원장의 검사/skip 건수가 실측 분포와 일치 (AC-2) ──
#   숫자를 박지 않는다(원장이 늘면 stale). **검사+skip+미분류 = 전체 edge 수** 항등만 단언한다.
tot=$(jq -rs 'map(.edges|length)|add' "$PLUGIN/scripts/_internal/propagation-matrix.jsonl")
n_chk=$(printf '%s' "$m5" | sed -n 's/.*검사 \([0-9]*\) .*/\1/p')
n_skp=$(printf '%s' "$m5" | sed -n 's/.*skip \([0-9]*\).*/\1/p')
n_unc=$(printf '%s' "$m5" | sed -n 's/.*미분류 \([0-9]*\).*/\1/p')
#   ★ 미분류 파티션을 항등에 **포함**한다. 빼면 정당한 새 확장자 1건이 원장에 오르는 순간
#     M6 가 FAIL 하고 pre-push 가 막힌다 — lint 에서 치운 false-block 을 스위트로 옮기는 꼴이다.
#     불변식("조용히 빠뜨린 edge 0")은 그대로고 파티션만 3분할을 따라간다.
if [ -n "${n_chk:-}" ] && [ -n "${n_skp:-}" ] && [ -n "${n_unc:-}" ] \
   && [ $((n_chk + n_skp + n_unc)) -eq "${tot:-0}" ]; then
  ok "M6 검사+skip+미분류 = 전체 edge 수 ($n_chk + $n_skp + $n_unc = $tot) — 조용히 빠뜨린 edge 0 (AC-2)"
else
  nope "M6" "검사=$n_chk skip=$n_skp 미분류=$n_unc 전체=$tot — 합이 안 맞으면 어딘가 조용히 누락됐다"
fi

# ── M7: 미분류 확장자 → 조용히 산문 skip 하지 않고 별도 카운터로 표면화 (Phase C) ──
#   게이팅이 코드 allowlist 방향이면 `.jsonl` 같은 미지 확장자가 "산문 skip" 으로 무음 분류되고
#   **어떤 어서션도 깨지지 않는다**(M6 항등조차 성립). 산문 allowlist 로 뒤집었으니 여기서는
#   미분류 1 로 **드러나야** 한다. 차단(FAIL)이 아니라 rc=0 + 노출이 계약이다.
printf '%s\n' '{"id":"fx-unclassified","edges":[{"path":"scripts/_internal/propagation-matrix.jsonl","must_match":"must_match"}]}' > "$tmp/unclassified.jsonl"
m7=$(_lint_run "$tmp/unclassified.jsonl"); m7_rc=$?
#   숫자를 **파싱해 비교**한다 — 출력 문구는 런타임 조립이라 통짜 리터럴 grep 은 금지(M4 동일).
m7_chk=$(printf '%s' "$m7" | sed -n 's/.*검사 \([0-9]*\) .*/\1/p')
m7_skp=$(printf '%s' "$m7" | sed -n 's/.*skip \([0-9]*\).*/\1/p')
m7_unc=$(printf '%s' "$m7" | sed -n 's/.*미분류 \([0-9]*\).*/\1/p')
if [ "$m7_rc" -eq 0 ] \
   && [ "${m7_chk:-x}" -eq 0 ] 2>/dev/null \
   && [ "${m7_skp:-x}" -eq 0 ] 2>/dev/null \
   && [ "${m7_unc:-0}" -eq 1 ] 2>/dev/null; then
  ok "M7 미분류 확장자 → 산문 skip 으로 삼키지 않고 미분류 1 로 표면화 (Phase C)"
else
  nope "M7" "rc=$m7_rc 검사=${m7_chk:-미파싱} skip=${m7_skp:-미파싱} 미분류=${m7_unc:-미파싱} / $m7"
fi

# ── M8: 주석 계열 판정 — 확장자 없는 훅이 검사 대상으로 남는다 (Phase C) ──
#   M1~M6 은 `.sh` 만 덮는다. 확장자가 없어 **경로로만** 분류되는 `.githooks/*` 가 3분류
#   재작성 후에도 미분류로 미끄러지지 않는지 본다. `^cp_out=` 는 훅의 실코드 줄이다(주석 아님).
printf '%s\n' '{"id":"fx-hook","edges":[{"path":".githooks/pre-commit","must_match":"^cp_out="}]}' > "$tmp/hook.jsonl"
m8=$(_lint_run "$tmp/hook.jsonl"); m8_rc=$?
m8_chk=$(printf '%s' "$m8" | sed -n 's/.*검사 \([0-9]*\) .*/\1/p')
m8_skp=$(printf '%s' "$m8" | sed -n 's/.*skip \([0-9]*\).*/\1/p')
m8_unc=$(printf '%s' "$m8" | sed -n 's/.*미분류 \([0-9]*\).*/\1/p')
if [ "$m8_rc" -eq 0 ] \
   && [ "${m8_chk:-0}" -eq 1 ] 2>/dev/null \
   && [ "${m8_skp:-x}" -eq 0 ] 2>/dev/null \
   && [ "${m8_unc:-x}" -eq 0 ] 2>/dev/null; then
  ok "M8 확장자 없는 훅(.githooks/*) → 주석 계열로 분류돼 검사 1 (Phase C)"
else
  nope "M8" "rc=$m8_rc 검사=${m8_chk:-미파싱} skip=${m8_skp:-미파싱} 미분류=${m8_unc:-미파싱} / $m8"
fi

finish
