#!/usr/bin/env bash
# batch-progress.sh — 이 FID 가 진행 중인 일괄 묶음의 FR 이면 `<묶음 이름> <끝난 FR 수> <전체 FR 수>` 1줄 (관제판용 · 읽기 전용)
# Usage: batch-progress.sh <FID>      (cwd = .specops 가 있는 폴더)
# Exit: 항상 0 — 일괄이 아니거나 판정할 수 없으면 아무것도 내지 않는다(관제판은 종전 표시로 떨어진다).
#
# 큐 읽기는 queue-lib.sh 의 qnorm 한 곳을 쓴다 — 큐의 Status·FR-ID·FID 칸은 모델이 손으로 고치기도 해서
#   `**IMPL_DONE**`·`` `FR-7` ``·칸 앞뒤 공백 같은 표기 장식이 붙는다(queue-lib.sh 머리 주석의 실측).
#   끝난 FR = IMPL_DONE · MERGED. 전체 = SKIP 을 뺀 FR 행. Status 는 마지막 칸이 아니라 머리줄의 `Status` 칸 위치로 읽는다.
set -u
FID="${1:-}"
printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || exit 0
SPECOPS="${SPECOPS_ROOT:-.specops}"
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/queue-lib.sh"
[ -f "$LIB" ] || exit 0
# shellcheck source=/dev/null
. "$LIB"
for q in "$SPECOPS"/batch-*/queue.md; do
  [ -f "$q" ] || continue
  d="${q%/queue.md}"
  [ -f "$d/ACTIVE" ] || continue
  out=$(awk -F'|' -v fid="$FID" "$QUEUE_AWK_QNORM"'
    /^\|/ {
      id = qnorm($2)
      if (id == "FR-ID") { for (i = 2; i <= NF; i++) if (qnorm($i) == "Status") sc = i; next }
      if (id !~ /^FR-[0-9]/) next
      st = qnorm($(sc ? sc : NF - 1))
      if (qnorm($3) == fid) hit = 1
      if (st == "SKIP") next
      total++
      if (st == "IMPL_DONE" || st == "MERGED") done++
    }
    END { if (hit && total > 0) printf "%d %d\n", done, total }
  ' "$q" 2>/dev/null)
  [ -n "$out" ] || continue
  printf '%s %s\n' "${d##*/}" "$out"
  break
done
exit 0
