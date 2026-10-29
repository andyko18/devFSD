#!/usr/bin/env bash
# check-maintain-baseline.sh — 유지보수 baseline 산출물 게이트 (20260806)
# Usage: check-maintain-baseline.sh <FID>
# Exit: 0 = PASS 또는 해당 없음(skip) · 1 = FAIL(산출물 부재·미채움)
#
# 왜 필요한가 (클래스 A — 선언은 HARD, 구현은 0곳):
#   `analyzing-ko` 의 HARD-GATE 는 "두 산출물(current-state.md + impact-analysis.md)
#   사용자 검토 통과 전 specifying-ko 호출 금지" 인데, **산출물 존재 자체를 검사하는
#   층이 0곳**이었다. 실측: 유지보수 FID 가 analyzing 산출물 0개로 emit-context 를
#   통과해 구현까지 간다.
#
# 2차 피해가 데이터 안전이다:
#   `check-regression-ac` 의 **스키마 override 판정이 current-state.md 를 읽는다**.
#   파일이 없으면 need_r2=0 이 되어 **파괴적 스키마 변경에도 AC-R-2(데이터 보존)가
#   요구되지 않는다** — 안전망이 조용히 꺼진다. 또 AC-R-1("기존 동작 보존")은
#   baseline 없이는 근거가 없다(무엇을 보존하는지 모른다).
#
# 사용자 검토(대화 승인)는 기계화 불가 — **산출물 존재·채움만** 판정한다.
# fail-open: spec.md 부재 → skip. §유형≠유지보수 → skip(신규·trivial·foundation).
set -u

FID="${1:?usage: $0 <FID>}"
SPECOPS="${SPECOPS_ROOT:-.specops}"
SPEC="$SPECOPS/$FID/spec.md"
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
SCAN="$PLUGIN/scripts/_internal/scan-enrich-placeholders.sh"

[ -f "$SPEC" ] || { echo "MAINTAIN-BASELINE: SKIP (spec.md 부재)"; exit 0; }

grep -qE '^\*\*§유형\*\*:[[:space:]]*유지보수' "$SPEC" 2>/dev/null || {
  echo "MAINTAIN-BASELINE: SKIP (§유형≠유지보수)"; exit 0
}

missing=""
for f in current-state.md impact-analysis.md; do
  [ -f "$SPECOPS/$FID/$f" ] || missing="${missing}${missing:+ · }$f"
done

if [ -n "$missing" ]; then
  cat <<EOF
MAINTAIN-BASELINE: FAIL — analyzing 산출물 부재: $missing
  유지보수 FID 는 analyzing-ko 가 baseline(current-state.md)과 외부 영향(impact-analysis.md)을
  먼저 산출해야 한다. 없으면:
    - AC-R-1("기존 동작 보존")의 근거가 없다 — 무엇을 보존하는지 모른다.
    - check-regression-ac 의 **스키마 override 판정이 current-state.md 를 읽으므로**,
      파괴적 스키마 변경에도 AC-R-2(데이터 보존)가 요구되지 않는다.
  해법: devfsd:analyzing-ko 를 선행 실행하세요(/maintain 진입은 이를 자동 수행).
EOF
  exit 1
fi

# 파일만 만들고 안 채운 통과 차단 — placeholder SoT 재사용
if [ -f "$SCAN" ]; then
  if ! scan_out=$(bash "$SCAN" "$SPECOPS/$FID/current-state.md" "$SPECOPS/$FID/impact-analysis.md" 2>/dev/null); then
    echo "MAINTAIN-BASELINE: FAIL — baseline 미채움(템플릿 placeholder 잔존)"
    printf '%s\n' "$scan_out" | sed 's/^/  /'
    echo "  실제 grep·실행 결과로 채우세요 (analyzing-ko Step 1~6)."
    exit 1
  fi
fi

echo "MAINTAIN-BASELINE: PASS"
exit 0
