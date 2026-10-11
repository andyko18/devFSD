#!/usr/bin/env bash
# test-batch-resume-check.sh — 미완 batch 자동 표면화 (FID 20260828-batch-resume-teeth)
#
# 계기: argus batch-20260729 실측. FR 31건이 IMPL_DONE 에서 멈췄고 Phase 3 완료(batch
#   보안·통합·성능 → batch PR)가 실행되지 않은 채 방치됐다. `ACTIVE` 마커는 재개 키인데
#   읽는 곳이 `/start-all` 재호출·PR 게이트뿐이라 **사용자가 먼저 물어야만** 알 수 있었다.
#   `/status`·`reconcile-check` 는 batch 를 아예 모른다(batch 참조 0건).
#   → 재개 키도 주입 경로도 이미 있는데 둘을 잇는 판독기만 없었다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCRIPT="$PLUGIN/scripts/_internal/batch-resume-check.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

mk_batch() {  # <dir> <ACTIVE 여부: yes|no> <IMPL_DONE 수> <PENDING 수>
  local d="$1" active="$2" done_n="$3" pend_n="$4" i
  mkdir -p "$d/.specops/batch-20260828-0900"
  {
    printf '| FR-ID | FID | 설명 | Status |\n|---|---|---|---|\n'
    # ★ `seq 1 0` 은 BSD(macOS) 에서 역순으로 "1 0" 을 낸다(GNU 는 빈 출력) — 0 가드 필수.
    [ "$done_n" -gt 0 ] && for i in $(seq 1 "$done_n"); do printf '| FR-%s | 20260101-d%s | done%s | IMPL_DONE |\n' "$i" "$i" "$i"; done
    [ "$pend_n" -gt 0 ] && for i in $(seq 1 "$pend_n"); do printf '| FR-p%s | TBD | pend%s | PENDING |\n' "$i" "$i"; done
  } > "$d/.specops/batch-20260828-0900/queue.md"
  [ "$active" = yes ] && : > "$d/.specops/batch-20260828-0900/ACTIVE"
  return 0
}

mk_evidence() {  # 인자: (repo dir) (FID) (게이트 short 목록 — 공백구분, 빈 값이면 헤더 0건)
  local d="$1" fid="$2" gates="$3" g hdr
  mkdir -p "$d/.specops/$fid"
  : > "$d/.specops/$fid/evidence.md"
  for g in $gates; do
    case "$g" in
      security)    hdr=security-review ;;
      integration) hdr=integration-test ;;
      performance) hdr=performance-test ;;
      *) continue ;;
    esac
    printf '\n## /%s PASS\n**결과**: PASS\n' "$hdr" >> "$d/.specops/$fid/evidence.md"
  done
  return 0
}

# ── T1 ACTIVE 없음 → 무출력 exit 0 (batch 미사용 repo 월권 0) ──
rm -rf "$TMP/t1"; mkdir -p "$TMP/t1/.specops"
out=$(cd "$TMP/t1" && bash "$SCRIPT" --hook 2>&1); code=$?
if [ "$code" -eq 0 ] && [ -z "$out" ]; then
  ok "T1 ACTIVE 부재 → 무출력 exit 0"
else
  nope "T1 무관 repo 월권" "exit=$code out=$out"
fi

# ── T2 .specops 자체가 없음 → 무출력 (specops 미사용 repo) ──
rm -rf "$TMP/t2"; mkdir -p "$TMP/t2"
out=$(cd "$TMP/t2" && bash "$SCRIPT" --hook 2>&1); code=$?
[ "$code" -eq 0 ] && [ -z "$out" ] && ok "T2 .specops 부재 → 무출력" \
  || nope "T2 specops 미사용 repo 월권" "exit=$code out=$out"

# ── T3 진행 중 batch (일부 완료) → 진행률 보고 ──
#    이게 핵심이다. 사용자가 묻지 않아도 "미완 batch 가 있다" 를 말해야 한다.
rm -rf "$TMP/t3"; mk_batch "$TMP/t3" yes 3 2
out=$(cd "$TMP/t3" && bash "$SCRIPT" --hook 2>&1); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q 'batch-20260828-0900' \
   && printf '%s' "$out" | grep -qE '3/5'; then
  ok "T3 진행 중 batch 진행률 보고 (3/5)"
else
  nope "T3 미완 batch 미표면화" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# ── T4 전건 완료인데 ACTIVE 잔존 → Phase 3 완료 미실행을 지목 ──
#    argus 가 정확히 이 상태였다. 전건 IMPL_DONE 인데 batch PR 이 안 나갔다.
#    "완료됐다" 가 아니라 "다음 단계가 안 돌았다" 를 말해야 재개가 된다.
rm -rf "$TMP/t4"; mk_batch "$TMP/t4" yes 5 0
out=$(cd "$TMP/t4" && bash "$SCRIPT" --hook 2>&1); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q 'Phase 3'; then
  ok "T4 전건 완료 + ACTIVE 잔존 → Phase 3 완료 미실행 지목"
else
  nope "T4 재개점 미제시" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# ── T5 ACTIVE 제거됨(= PR 완료) → 무출력 ──
#    Step D 가 PR 성공 후 마커를 지운다. 끝난 batch 를 매 세션 떠들면 잡음이다.
rm -rf "$TMP/t5"; mk_batch "$TMP/t5" no 5 0
out=$(cd "$TMP/t5" && bash "$SCRIPT" --hook 2>&1); code=$?
[ "$code" -eq 0 ] && [ -z "$out" ] && ok "T5 완료 batch(ACTIVE 제거) → 무출력" \
  || nope "T5 끝난 batch 잡음" "exit=$code out=$out"

# ── T6 queue.md 부재 → 무출력 (판정 불가는 조용히) ──
rm -rf "$TMP/t6"; mkdir -p "$TMP/t6/.specops/batch-x"; : > "$TMP/t6/.specops/batch-x/ACTIVE"
out=$(cd "$TMP/t6" && bash "$SCRIPT" --hook 2>&1); code=$?
[ "$code" -eq 0 ] && [ -z "$out" ] && ok "T6 queue.md 부재 → 무출력 (판정 불가)" \
  || nope "T6 판정 불가인데 단정" "exit=$code out=$out"

# ── T7 라벨 장식 흡수 — queue-lib 정규화를 쓴다 ──
#    선행 FID(20260828-queue-label-drift)가 고친 것과 같은 유입 경로다. 여기서
#    자기 정규식을 새로 쓰면 그 드리프트가 이 판독기에서 재발한다.
rm -rf "$TMP/t7"; mk_batch "$TMP/t7" yes 0 0
{
  printf '| FR-ID | FID | 설명 | Status |\n|---|---|---|---|\n'
  printf '| FR-1 | 20260101-a | one | **IMPL_DONE** |\n'
  printf '| FR-2 | 20260101-b | two | PENDING |\n'
} > "$TMP/t7/.specops/batch-20260828-0900/queue.md"
out=$(cd "$TMP/t7" && bash "$SCRIPT" --hook 2>&1); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -qE '1/2'; then
  ok "T7 굵게 표기 흡수 (queue-lib 재사용)"
else
  nope "T7 라벨 드리프트 재발" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# ── T8 SKIP 은 분모에서 뺀다 — 시드·공통부는 batch 대상이 아니다 ──
rm -rf "$TMP/t8"; mk_batch "$TMP/t8" yes 2 0
printf '| FR-9 | — | seed | SKIP |\n' >> "$TMP/t8/.specops/batch-20260828-0900/queue.md"
out=$(cd "$TMP/t8" && bash "$SCRIPT" --hook 2>&1); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -qE '2/2'; then
  ok "T8 SKIP 분모 제외 (2/2)"
else
  nope "T8 SKIP 분모 오염" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# ── T9 session-start 배선 — 판독기만 있고 부르는 곳이 없으면 그대로다 ──
if grep -q 'batch-resume-check' "$PLUGIN/hooks/session-start.sh"; then
  ok "T9 session-start.sh 배선"
else
  nope "T9 배선 누락 — 판독기가 호출되지 않는다"
fi

# ── T10 전파 0건 → 누락 줄 출력 (AC-1) ──
#    argus batch-20260729 가 정확히 이 상태였다: 전 FR IMPL_DONE, evidence 에 게이트 0건.
rm -rf "$TMP/t10"; mk_batch "$TMP/t10" yes 2 0
mk_evidence "$TMP/t10" 20260101-d1 ""
mk_evidence "$TMP/t10" 20260101-d2 ""
out=$(cd "$TMP/t10" && bash "$SCRIPT" --hook 2>&1); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q '게이트 전파 누락' \
   && printf '%s' "$out" | grep -q 'security 0/2' \
   && printf '%s' "$out" | grep -q 'record-batch-gate'; then
  ok "T10 전파 0건 → 누락 줄 + 해법 안내"
else
  nope "T10 전파 누락 미표면화" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# ── T11 전파 완료 → 누락 줄 미출력 (AC-2, 벽지화 방지) ──
rm -rf "$TMP/t11"; mk_batch "$TMP/t11" yes 2 0
mk_evidence "$TMP/t11" 20260101-d1 "security integration performance"
mk_evidence "$TMP/t11" 20260101-d2 "security integration performance"
out=$(cd "$TMP/t11" && bash "$SCRIPT" --hook 2>&1); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q 'Phase 3' \
   && ! printf '%s' "$out" | grep -q '게이트 전파 누락'; then
  ok "T11 전파 완료 → 누락 줄 미출력"
else
  nope "T11 완료분까지 반복 출력" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# ── T12 부분 전파 → 누락 축만 나열, 전파된 축은 빠진다 (AC-6) ──
rm -rf "$TMP/t12"; mk_batch "$TMP/t12" yes 2 0
mk_evidence "$TMP/t12" 20260101-d1 "security"
mk_evidence "$TMP/t12" 20260101-d2 "security"
out=$(cd "$TMP/t12" && bash "$SCRIPT" --hook 2>&1); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q 'integration 0/2' \
   && printf '%s' "$out" | grep -q 'performance 0/2' \
   && ! printf '%s' "$out" | grep -q 'security 2/2'; then
  ok "T12 부분 전파 → 누락 축만 나열"
else
  nope "T12 전파된 축까지 나열" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# ── T13 IMPL_DONE FID 의 evidence.md 부재 → 분모에서 제외, 전파 줄 미출력 (AC-3) ──
#    AC-3 Then 원문: "해당 FID 를 분모에서 제외하거나 해당 batch 를 건너뛴다".
#    record-batch-gate.sh:63 도 evidence 없는 FID 를 skip 하므로, 세어 봐야 해소 불가 누락이 된다.
rm -rf "$TMP/t13"; mk_batch "$TMP/t13" yes 2 0
out=$(cd "$TMP/t13" && bash "$SCRIPT" --hook 2>&1); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q 'Phase 3' \
   && ! printf '%s' "$out" | grep -q '게이트 전파 누락'; then
  ok "T13 evidence 부재 FID 는 분모 제외 → 전파 줄 미출력"
else
  nope "T13 근거 없는 수치 출력" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# ── T14 진행 중 batch → 전파 줄 미출력 (Phase 3 이전이라 전파 0건이 정상) ──
#    외부 critic 지적: else 분기에서도 경고하면 해소 불가능한 오경보가 매 세션 반복된다.
#    ★ 아래 mk_evidence 3줄을 지우지 말 것 — evidence 가 있어야 "else 분기라서" 줄이 안 나오는
#      것을 잠근다. 없으면 n_fid=0 가드에 걸려 엉뚱한 이유로 green 이 된다.
rm -rf "$TMP/t14"; mk_batch "$TMP/t14" yes 3 2
mk_evidence "$TMP/t14" 20260101-d1 ""
mk_evidence "$TMP/t14" 20260101-d2 ""
mk_evidence "$TMP/t14" 20260101-d3 ""
out=$(cd "$TMP/t14" && bash "$SCRIPT" --hook 2>&1); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -qE '3/5' \
   && ! printf '%s' "$out" | grep -q '게이트 전파 누락'; then
  ok "T14 진행 중 batch → 전파 줄 미출력"
else
  nope "T14 진행 중 오경보" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi


# ── T15·T16 훅 모드 상세 상한(20261002-batch-resume-hook-cap) ──
#    SessionStart 앞 블록은 상한이 없으면 총량이 harness 한도를 넘어 meta 본문을 프리뷰 밖으로 민다(프로브: batch 10개 = 10,044).
mk_n() {  # <dir> <개수> — 미완 batch N개(ACTIVE, IMPL_DONE 1 + PENDING 1)
  local d="$1" n="$2" i b
  for i in $(seq 1 "$n"); do
    b="$d/.specops/batch-20260828-090$i"; mkdir -p "$b"
    printf '| FR-ID | FID | 설명 | Status |\n|---|---|---|---|\n| FR-1 | 20260101-d%s | d | IMPL_DONE |\n| FR-p1 | TBD | p | PENDING |\n' "$i" > "$b/queue.md"
    : > "$b/ACTIVE"
  done
}
rm -rf "$TMP/t15"; mk_n "$TMP/t15" 5
hook_out=$(cd "$TMP/t15" && bash "$SCRIPT" --hook 2>&1); code=$?
full_out=$(cd "$TMP/t15" && bash "$SCRIPT" 2>&1)
if [ "$code" -eq 0 ] \
   && [ "$(printf '%s\n' "$hook_out" | grep -c '미완 batch — batch-')" -eq 3 ] \
   && [ "$(printf '%s\n' "$hook_out" | grep -c '외 미완 batch 2개')" -eq 1 ] \
   && printf '%s' "$hook_out" | grep -q 'batch-20260828-0903' && ! printf '%s' "$hook_out" | grep -q 'batch-20260828-0904' \
   && [ "$(printf '%s\n' "$full_out" | grep -c '미완 batch — batch-')" -eq 5 ] \
   && ! printf '%s' "$full_out" | grep -q '외 미완 batch'; then
  ok "T15 훅 모드 상세 3개 + '외 미완 batch 2개' 1줄 · 직접 실행은 5개 전부"
else
  nope "T15 훅 모드 상한" "exit=$code hook=$(printf '%s' "$hook_out" | tr '\n' ' ') full_n=$(printf '%s\n' "$full_out" | grep -c '미완 batch — batch-')"
fi

rm -rf "$TMP/t16"; mk_n "$TMP/t16" 3
hook3=$(cd "$TMP/t16" && bash "$SCRIPT" --hook 2>&1); full3=$(cd "$TMP/t16" && bash "$SCRIPT" 2>&1)
if [ -n "$hook3" ] && [ "$hook3" = "$full3" ] && ! printf '%s' "$hook3" | grep -q '외 미완 batch'; then
  ok "T16 batch 3개 이하는 훅 출력이 직접 실행과 동일(상한 줄 없음)"
else
  nope "T16 3개 이하 불변" "hook=$(printf '%s' "$hook3" | tr '\n' ' ')"
fi

# ── T17 완료형 3개 — 개수(3) 안이어도 바이트 예산이 접는다 (Phase C Critical: 완료형 3개 = 총 10,411) ──
#    완료형 상세는 3줄 + 절대경로 2회라 진행형의 ~3배다. 훅은 첫 batch 만 상세(예산은 2번째부터 적용) + 건수 줄,
#    직접 실행은 3개 전부 + 게이트 전파 줄 3개. SPECOPS_ROOT 절대경로는 session-start.sh 의 호출 형태 그대로다.
rm -rf "$TMP/t17"
for i in 1 2 3; do
  b="$TMP/t17/.specops/batch-20260828-090$i"; mkdir -p "$b"
  printf '| FR-ID | FID | 설명 | Status |\n|---|---|---|---|\n| FR-1 | 20260101-e%s | d | IMPL_DONE |\n' "$i" > "$b/queue.md"
  : > "$b/ACTIVE"
  mk_evidence "$TMP/t17" "20260101-e$i" ""
done
hook17=$(cd "$TMP/t17" && SPECOPS_ROOT="$TMP/t17/.specops" bash "$SCRIPT" --hook 2>&1); code=$?
full17=$(cd "$TMP/t17" && SPECOPS_ROOT="$TMP/t17/.specops" bash "$SCRIPT" 2>&1)
h17=$(printf '%s\n' "$hook17" | grep -c '미완 batch — batch-')
if [ "$code" -eq 0 ] && [ "$h17" -ge 1 ] && [ "$h17" -le 2 ] \
   && [ "$(printf '%s\n' "$hook17" | grep -c "외 미완 batch $((3 - h17))개")" -eq 1 ] \
   && printf '%s' "$hook17" | grep -q 'batch-20260828-0901' \
   && [ "$(printf '%s\n' "$full17" | grep -c '미완 batch — batch-')" -eq 3 ] \
   && [ "$(printf '%s\n' "$full17" | grep -c '게이트 전파 누락')" -eq 3 ] \
   && ! printf '%s' "$full17" | grep -q '외 미완 batch'; then
  ok "T17 완료형 3개 → 훅 상세 ${h17}개 + '외 미완 batch $((3 - h17))개' · 직접 실행은 3개 전부"
else
  nope "T17 완료형 바이트 예산" "exit=$code 훅상세=$h17 hook=$(printf '%s' "$hook17" | cut -c1-60 | tr '\n' ' ') full_n=$(printf '%s\n' "$full17" | grep -c '미완 batch — batch-')"
fi

# ── T18 보류(HELD) FR 이 있으면 재개 안내에 그 사실이 나온다 — Phase 3 는 PLAN_DONE 만 순회해 HELD 는 저절로 되살아나지 않는다 ──
rm -rf "$TMP/t18"; mk_batch "$TMP/t18" yes 1 1
printf '| FR-h1 | 20260101-h1 | held1 | HELD |\n| FR-h2 | 20260101-h2 | held2 | HELD |\n' >> "$TMP/t18/.specops/batch-20260828-0900/queue.md"
out18=$(cd "$TMP/t18" && bash "$SCRIPT" 2>&1)
rm -rf "$TMP/t18b"; mk_batch "$TMP/t18b" yes 1 1
out18b=$(cd "$TMP/t18b" && bash "$SCRIPT" 2>&1)
if printf '%s' "$out18" | grep -q '보류(HELD) 2건은 자동으로 다시 돌지 않는다' && ! printf '%s' "$out18b" | grep -q '보류(HELD)'; then
  ok "T18 HELD 2건 → 재개 안내에 보류 줄 · HELD 없으면 줄 없음"
else
  nope "T18 보류 안내" "held=$(printf '%s' "$out18" | tr '\n' ' ') none=$(printf '%s' "$out18b" | tr '\n' ' ')"
fi

finish
