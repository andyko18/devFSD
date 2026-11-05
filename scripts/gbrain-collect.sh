#!/usr/bin/env bash
# FID 산출물 결정적 수집기 — handoffs Decided/Risks + evidence 결과 요약 (읽기 전용)
# 사용: bash scripts/gbrain-collect.sh <FID>
# 출력: 수집 텍스트 / 수집물 0 → "COLLECT: EMPTY" (exit 0). FID 디렉토리 부재만 exit 1 (사용 오류)
set -uo pipefail
FID="${1:?FID required}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_internal/specops-root.sh" 2>/dev/null && specops_root_export "$FID"
DIR="${SPECOPS_ROOT:-.specops}/$FID"
if [ ! -d "$DIR" ]; then
  echo "ERROR: $DIR 부재 (사용 오류 — FID 확인)" >&2
  exit 1
fi
found=0
for h in "$DIR"/handoffs/*.md; do
  [ -f "$h" ] || continue
  body=$(awk '/^## /{sec=$2} (sec=="Decided"||sec=="Risks") && /^- /{print}' "$h" | grep -vE -- '^- \(없음\)[[:space:]]*$' || true)
  [ -z "$body" ] && continue
  found=1
  echo "## $(basename "$h")"
  printf '%s\n' "$body"
done
if [ -f "$DIR/evidence.md" ]; then
  ev=$(grep -E '^\*\*결과\*\*:|PASS=|FAIL' "$DIR/evidence.md" | head -5 || true)
  if [ -n "$ev" ]; then
    found=1
    echo "## evidence.md"
    printf '%s\n' "$ev"
  fi
fi
[ "$found" = "0" ] && echo "COLLECT: EMPTY"
exit 0
