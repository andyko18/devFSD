#!/usr/bin/env bash
# 가정 다이제스트 결정론적 집계 — 20260806 /start-all-auto 분석
#
# 배경: `/start-all-auto` 는 clarify BLOCKING 을 best-guess 로 자동 답하고 `status: ASSUMED`
#   로 기록한다. 사용자가 그 가정들을 보는 **유일한 지점이 batch PR 게이트의 다이제스트**다
#   (다른 모든 확인은 자동 통과). 그런데 집계가 **모델 재량**이라 누락·과소보고를 잡는 층이 0곳
#   이었다 — 누락되면 사용자는 무엇이 자기 대신 결정됐는지 모른 채 batch PR 을 승인한다.
#   무인 모드를 수용 가능하게 만드는 단 하나의 게이트가 내용을 잃는다(5원칙 4 주권).
# 해법: 집계를 스크립트로 옮겨 **과소보고를 구조적으로 불가능**하게 만든다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
COL="$PLUGIN/scripts/_internal/collect-assumptions.sh"

_batch() {  # $1=dir — IMPL_DONE 2 FID
  mkdir -p "$1/.specops/batch-20260806-0900"
  cat > "$1/.specops/batch-20260806-0900/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260806-fr-one | one | IMPL_DONE |
| FR-2 | 20260806-fr-two | two | IMPL_DONE |
| FR-3 | 20260806-fr-thr | three | PLAN_DONE |
EOF
  local f
  for f in 20260806-fr-one 20260806-fr-two 20260806-fr-thr; do
    mkdir -p "$1/.specops/$f"
    printf '**§유형**: 신규\n**§auto**: true\n' > "$1/.specops/$f/spec.md"
  done
}

# T1: ★ 전 IMPL_DONE FID 의 ASSUMED 를 빠짐없이 집계
TD=$(mktemp -d); _batch "$TD"
printf '## Q1 · 저장소 · BLOCKING\nstatus: ASSUMED\n**가정 근거**: 기본값\n\n## Q2 · 포맷 · BLOCKING\nstatus: ASSUMED\n**가정 근거**: 관례\n' \
  > "$TD/.specops/20260806-fr-one/clarifications.md"
printf '## Q1 · 인증 · BLOCKING\nstatus: ASSUMED\n**가정 근거**: 세션\n' \
  > "$TD/.specops/20260806-fr-two/clarifications.md"
out=$(cd "$TD" && bash "$COL" .specops/batch-20260806-0900 2>&1); rc=$?
n=$(printf '%s' "$out" | grep -c 'ASSUMED' || true)
[ "$rc" -eq 0 ] && [ "${n:-0}" -ge 3 ] \
  && ok "T1 전 IMPL_DONE ASSUMED 집계 (${n}건)" || nope "T1" "rc=$rc n=$n"
rm -rf "$TD"

# T2: ★ IMPL_DONE 아닌 FID 는 제외 (batch 범위 밖)
TD=$(mktemp -d); _batch "$TD"
printf '## Q1 · 제외대상 · BLOCKING\nstatus: ASSUMED\n**가정 근거**: x\n' \
  > "$TD/.specops/20260806-fr-thr/clarifications.md"
out=$(cd "$TD" && bash "$COL" .specops/batch-20260806-0900 2>&1)
! printf '%s' "$out" | grep -q '제외대상' \
  && ok "T2 비-IMPL_DONE FID 제외" || nope "T2" "out=$out"
rm -rf "$TD"

# T3: RESOLVED 는 가정이 아니다 (집계 제외)
TD=$(mktemp -d); _batch "$TD"
printf '## Q1 · 확정건 · BLOCKING\nstatus: RESOLVED\n**답변**: 사용자가 정함\n' \
  > "$TD/.specops/20260806-fr-one/clarifications.md"
out=$(cd "$TD" && bash "$COL" .specops/batch-20260806-0900 2>&1)
! printf '%s' "$out" | grep -q '확정건' \
  && ok "T3 RESOLVED 제외" || nope "T3" "out=$out"
rm -rf "$TD"

# T4: 자동 결정 화면·인터페이스도 집계 (spec.md §1 — 사용자 미확인 결정)
TD=$(mktemp -d); _batch "$TD"
printf '**§유형**: 신규\n**§auto**: true\n**자동 결정 화면**: login, dashboard\n**자동 결정 인터페이스**: POST /auth\n' \
  > "$TD/.specops/20260806-fr-one/spec.md"
out=$(cd "$TD" && bash "$COL" .specops/batch-20260806-0900 2>&1)
{ printf '%s' "$out" | grep -q '자동 결정 화면' && printf '%s' "$out" | grep -q '자동 결정 인터페이스'; } \
  && ok "T4 자동 결정 화면·IF 집계" || nope "T4" "out=$out"
rm -rf "$TD"

# T5: 가정 0건 → 명시적으로 0 보고 (침묵 금지 — 0 과 미집계는 다르다)
TD=$(mktemp -d); _batch "$TD"
out=$(cd "$TD" && bash "$COL" .specops/batch-20260806-0900 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qE '0건|없음' \
  && ok "T5 가정 0건 → 명시 보고" || nope "T5" "rc=$rc out=$out"
rm -rf "$TD"

# T6: queue 부재 → 오류 (조용한 빈 다이제스트 금지)
TD=$(mktemp -d); mkdir -p "$TD/.specops/batch-x"
(cd "$TD" && bash "$COL" .specops/batch-x >/dev/null 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "T6 queue 부재 → 오류" || nope "T6" "rc=$rc"
rm -rf "$TD"

# T7: start-all-auto 가 집계기를 지시 (모델 수기 집계 금지)
grep -q 'collect-assumptions.sh' "$PLUGIN/commands/start-all-auto.md" \
  && ok "T7 start-all-auto 배선" || nope "T7" "미배선 — 수기 집계 잔존"

# T8: /start-all 도 §auto 가 아니어도 화면·IF 자동결정 집계 경로를 공유
grep -q 'collect-assumptions.sh' "$PLUGIN/commands/start-all.md" \
  && ok "T8 start-all 배선(공유)" || nope "T8" "미배선"

# T-intent: 자동 결정 intent 가 ASSUMED 로 집계된다
#   ★ 픽스처는 collect-assumptions 실제 스키마를 따른다 (plan-review 1회차 I-1):
#   FID 는 queue 행 **2열**, 상태 셀은 `IMPL_DONE`, spec 은 batch-dir 의 **상위**(.specops/<fid>/spec.md)
TD=$(mktemp -d); mkdir -p "$TD/.specops/batch-x" "$TD/.specops/20260917-x"
printf '| FR-1 | 20260917-x | 자동 결정 intent 케이스 | IMPL_DONE |\n' > "$TD/.specops/batch-x/queue.md"
printf '**자동 결정 intent**: 재고 마감 알림 부재\n' > "$TD/.specops/20260917-x/spec.md"
out=$(bash "$PLUGIN/scripts/_internal/collect-assumptions.sh" "$TD/.specops/batch-x" 2>&1)
printf '%s' "$out" | grep -q '자동 결정 intent' \
  && { PASS=$((PASS+1)); echo "PASS T-intent 자동 결정 intent 집계"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T-intent ($out)"; }
rm -rf "$TD"

# T-devdec: 개발 구간에서 묻지 않고 정한 결정도 batch 다이제스트에 모인다 (20261008-dev-no-ask)
#   batch 는 FR 마다 PR 게이트가 없다 — 이 집계가 사용자가 그 결정을 보는 유일한 지점이다.
TD=$(mktemp -d); mkdir -p "$TD/.specops/batch-x" "$TD/.specops/20261008-x"
printf '| FR-1 | 20261008-x | 결정 기록 케이스 | IMPL_DONE |\n' > "$TD/.specops/batch-x/queue.md"
printf '**§유형**: 신규\n' > "$TD/.specops/20261008-x/spec.md"
( cd "$TD" && bash "$PLUGIN/scripts/dev-decision.sh" add 20261008-x backlog "기존 결함은 다음 FID 로" "이번 FID 이전부터" \
  && bash "$PLUGIN/scripts/dev-decision.sh" add 20261008-x order "리뷰 먼저" ) >/dev/null 2>&1
printf -- '- 손으로 쓴 줄은 집계하지 않는다\n' >> "$TD/.specops/20261008-x/dev-decisions.md"
out=$(bash "$PLUGIN/scripts/_internal/collect-assumptions.sh" "$TD/.specops/batch-x" 2>&1)
printf '%s' "$out" | grep -q '개발 중 결정 · \[backlog\] 기존 결함은 다음 FID 로 — 이번 FID 이전부터' \
  && printf '%s' "$out" | grep -q '개발 중 결정 · \[order\] 리뷰 먼저' \
  && printf '%s' "$out" | grep -q '\*\*2건\*\*' && ! printf '%s' "$out" | grep -q '손으로 쓴 줄' \
  && { PASS=$((PASS+1)); echo "PASS T-devdec 개발 중 결정 집계(기록 형식 줄만 · 건수 포함)"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T-devdec ($out)"; }
#   심볼릭 링크로 걸린 기록 파일은 읽지 않는다 — 링크 밖 파일 내용이 다이제스트로 새지 않게
printf -- '- 2026-10-08T00:00:00Z [backlog] 링크 밖 파일의 줄\n' > "$TD/outside.md"
rm -f "$TD/.specops/20261008-x/dev-decisions.md"; ln -s "$TD/outside.md" "$TD/.specops/20261008-x/dev-decisions.md"
out=$(bash "$PLUGIN/scripts/_internal/collect-assumptions.sh" "$TD/.specops/batch-x" 2>&1)
! printf '%s' "$out" | grep -q '링크 밖 파일의 줄' \
  && { PASS=$((PASS+1)); echo "PASS T-devdec.b 심볼릭 링크 기록 파일은 집계하지 않는다"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T-devdec.b ($out)"; }
rm -rf "$TD"

# T-unp: batch 대상에서 빠진 FR 행(해석하지 못한 행)은 다이제스트에 실린다 (20261009-startall-silent-pass)
#   무인 batch 에서 사용자가 보는 지점은 이 다이제스트뿐이다 — queue 머리말에만 있으면 아무도 보지 못한다.
TD=$(mktemp -d); mkdir -p "$TD/.specops/memory"
cat > "$TD/.specops/memory/requirements.md" <<'EOF'
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-5 | 주문 목록 | M1 | must | (TBD) |
| FR 6 | 하이픈 없는 ID | M1 | must | (TBD) |
EOF
( cd "$TD" && bash "$PLUGIN/scripts/_internal/init-batch-queue.sh" .specops/batch-u ) >/dev/null 2>&1
mkdir -p "$TD/.specops/20261009-u5"; printf '**§유형**: 신규\n' > "$TD/.specops/20261009-u5/spec.md"
( cd "$TD" && bash "$PLUGIN/scripts/_internal/queue-set-status.sh" .specops/batch-u/queue.md FR-5 IMPL_DONE 20261009-u5 ) >/dev/null 2>&1
out=$(cd "$TD" && bash "$PLUGIN/scripts/_internal/collect-assumptions.sh" .specops/batch-u 2>&1)
printf '%s' "$out" | grep -q '^## batch 대상에서 빠진 FR 행' && printf '%s' "$out" | grep -q 'FR 6' && printf '%s' "$out" | grep -q '\*\*1건\*\*' \
  && { PASS=$((PASS+1)); echo "PASS T-unp 해석하지 못한 FR 행 → 다이제스트 절 + 건수"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL T-unp ($out)"; }
rm -rf "$TD"

finish
