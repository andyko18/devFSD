#!/usr/bin/env bash
# collect-assumptions.sh — batch PR 게이트용 가정 다이제스트 결정론적 집계 (20260806)
# Usage: collect-assumptions.sh <batch-dir>
# Exit: 0 = 집계 완료(가정 0건 포함) · 1 = 사용 오류(queue 부재 등)
#
# 왜 스크립트인가: `/start-all-auto` 는 clarify BLOCKING 을 best-guess 로 자동 답하고
#   `status: ASSUMED` 로 기록한다. 사용자가 그 가정들을 보는 **유일한 지점이 batch PR
#   게이트의 다이제스트**다 — 나머지 확인은 전부 자동 통과한다. 그런데 집계가 **모델 재량**
#   이라 누락·과소보고를 잡는 층이 0곳이었다. 누락되면 사용자는 무엇이 자기 대신
#   결정됐는지 모른 채 batch PR 을 승인한다 — 무인 모드를 수용 가능하게 만드는 단 하나의
#   게이트가 내용을 잃는다(5원칙 4 주권).
#   집계를 스크립트로 옮겨 **과소보고를 구조적으로 불가능**하게 만든다.
#
# 집계 범위: queue.md 의 **IMPL_DONE FID** 만(batch 에 실제 포함된 것).
#   ① clarifications.md 의 `status: ASSUMED` Q-block
#   ② spec.md §1 의 `**자동 결정 화면**` · `**자동 결정 인터페이스**` · `**자동 결정 intent**` (사용자 미확인 결정)
#   ③ dev-decisions.md 의 기록 줄 — 개발 구간에서 묻지 않고 정한 것(20261008 · dev-decision.sh 가 쓴 형식만)
#   ④ queue.md 머리말의 `해석하지 못한 FR 행` 줄 — batch 대상에서 빠진 FR 행(20261009 · init-batch-queue.sh 가 쓴다)
# 가정 0건도 **명시 보고**한다 — "0건" 과 "집계 안 함" 은 다르다.
set -u

BATCH_DIR="${1:?usage: $0 <batch-dir>}"
QUEUE="$BATCH_DIR/queue.md"
[ -f "$QUEUE" ] || { echo "collect-assumptions: queue.md 부재 ($BATCH_DIR)" >&2; exit 1; }

SPECOPS=$(dirname "$BATCH_DIR")
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/queue-lib.sh"

# Status 정규화 (20260828-queue-label-drift) — 모델이 `**IMPL_DONE**` 로 손편집하면
#   종전 `|IMPL_DONE|` 리터럴 매칭이 전건 불일치해 **대상 0건**이 됐다.
fids=$(awk -F'|' "$QUEUE_AWK_QNORM"'
{
  st = ""
  for (i = NF; i >= 1; i--) { if (qnorm($i) != "") { st = qnorm($i); break } }
  if (st ~ /^IMPL_DONE$/) print qnorm($3)
}' "$QUEUE" | grep -E '^[0-9]{8}-[a-z0-9-]+$' || true)

echo "# 가정 다이제스트 — $(basename "$BATCH_DIR")"
echo ""
echo '> `/start-all-auto` 무인 진행 중 **사용자 확인 없이** 확정된 항목 전체.'   # 작은따옴표 — 큰따옴표 안의 백틱은 명령으로 실행됐다(20261115)
echo "> 집계기: collect-assumptions.sh (수기 집계 금지 — 과소보고 차단)"
echo ""

total=0

# batch 대상에서 빠진 FR 행 (20261009) — init-batch-queue.sh 가 queue 머리말에 남긴 줄을 그대로 옮긴다.
#   requirements 에 FR 처럼 적혔지만 ID 형식이 다르거나 들여쓰여 읽지 못한 행이다. 무인 batch 에서 사용자가 보는 지점은 이 다이제스트뿐이라,
#   여기 없으면 "적었는데 구현되지 않은 기능" 이 아무에게도 보이지 않는다.
unp_line=$(grep -m1 -E '^> \*\*해석하지 못한 FR 행\*\*' "$QUEUE" 2>/dev/null | sed -E 's/^> //' || true)
if [ -n "$unp_line" ]; then
  echo "## batch 대상에서 빠진 FR 행"
  echo "- $unp_line"
  echo ""
  total=$((total + 1))
fi

for fid in $fids; do
  section=""

  clar="$SPECOPS/$fid/clarifications.md"
  if [ -f "$clar" ]; then
    # `## Q...` 블록 중 status: ASSUMED 인 것만
    blocks=$(awk '
      /^##[[:space:]]/ { if (hdr != "" && asm) print hdr "\t" reason; hdr=$0; asm=0; reason=""; next }
      /^[[:space:]]*status:[[:space:]]*ASSUMED/ { asm=1 }
      /^\*\*가정 근거\*\*:/ { r=$0; sub(/^\*\*가정 근거\*\*:[[:space:]]*/, "", r); reason=r }
      END { if (hdr != "" && asm) print hdr "\t" reason }
    ' "$clar")
    while IFS=$'\t' read -r h r; do
      [ -n "$h" ] || continue
      hh=$(printf '%s' "$h" | sed 's/^##[[:space:]]*//')
      section="${section}- ASSUMED · ${hh}${r:+ — 근거: $r}"$'\n'
      total=$((total + 1))
    done <<EOF
$blocks
EOF
  fi

  spec="$SPECOPS/$fid/spec.md"
  if [ -f "$spec" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      section="${section}- ASSUMED · ${line}"$'\n'
      total=$((total + 1))
    done <<EOF
$(grep -E '^\*\*자동 결정 (화면|인터페이스|intent)\*\*:' "$spec" 2>/dev/null | sed 's/^\*\*//; s/\*\*//' || true)
EOF
  fi

  dd="$SPECOPS/$fid/dev-decisions.md"
  if [ -f "$dd" ] && [ ! -L "$dd" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      section="${section}- 개발 중 결정 · ${line}"$'\n'
      total=$((total + 1))
    done <<EOF
$(grep -E '^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z \[(fixed|backlog|order|retry|skip|approval)\] ' "$dd" 2>/dev/null | sed -E 's/^- [^ ]+ //' || true)
EOF
  fi

  if [ -n "$section" ]; then
    echo "## $fid"
    printf '%s' "$section"
    echo ""
  fi
done

if [ "$total" -eq 0 ]; then
  echo "## 집계 결과"
  echo ""
  echo "자동 확정 항목 **0건** — 사용자 확인 없이 결정된 사항이 없습니다."
  echo "(0건과 '집계 안 함' 은 다르다 — 본 줄이 있으면 집계가 수행된 것이다.)"
else
  echo "## 집계 결과"
  echo ""
  echo "자동 확정 항목 **${total}건** — 위 내용을 확인한 뒤 batch PR 을 승인하세요."
fi
exit 0
