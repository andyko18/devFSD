#!/usr/bin/env bash
# check-regression-ac.sh — 회귀 AC(AC-R-1/AC-R-2) 게이트 (20260806, /maintain 정밀분석)
# Usage: check-regression-ac.sh <FID>
# Exit: 0 = PASS 또는 해당 없음(skip) · 1 = FAIL(회귀 AC 누락·미채움)
#
# 왜 스크립트인가: "/maintain 의 존재 이유" 인 회귀 안전망이 전부 산문이었다 —
#   specifying-ko "유지보수 → AC-R-1 강제(스키마면 AC-R-2)", 템플릿 "evaluator 가
#   누락 시 verdict=BLOCK". 그런데 검사 구현이 0곳이라 모델이 빠뜨리면 회귀 AC 없이
#   구현이 진행됐다. 결과는 "새 기능이 이상함" 이 아니라 "멀쩡하던 것이 깨짐" 클래스.
#
# 판정 규칙:
#   need AC-R-1 ⇐ spec.md `**§유형**: 유지보수`  (신규·trivial·foundation 면제 — 템플릿 계약)
#   need AC-R-2 ⇐ current-state.md §1 `스키마 override` 마커 (analyzing Step 1 산출)
#     — §유형과 **독립**: trivial 이어도 파괴적 스키마면 강제 (데이터 안전은 라인수 면제 불가)
#   채움 판정: 헤더 존재 + Given/When/Then 의 **템플릿 문구 잔존 없음**.
#     템플릿이 AC-R 섹션을 기본 포함하므로 "헤더 존재" 만으론 템플릿 복사로 뚫린다.
# fail-open: spec.md 부재 → skip.
set -u

FID="${1:?usage: $0 <FID>}"
SPECOPS="${SPECOPS_ROOT:-.specops}"
SPEC="$SPECOPS/$FID/spec.md"
AC="$SPECOPS/$FID/acceptance-criteria.md"
CS="$SPECOPS/$FID/current-state.md"

[ -f "$SPEC" ] || { echo "REGRESSION-AC: SKIP (spec.md 부재)"; exit 0; }

need_r1=0
grep -qE '^\*\*§유형\*\*:[[:space:]]*유지보수' "$SPEC" 2>/dev/null && need_r1=1

# §유형 줄이 아예 없는 spec (20261115) — analyzing 마커가 유지보수(합산 >5줄)면 유지보수로 본다. 라벨을 빠뜨린 것만으로
#   회귀 기준 검사가 SKIP 되던 구멍이다(템플릿에 그 줄이 없었다). 명시 라벨(신규·trivial·foundation)이 있으면 종전 판정 그대로다.
if [ "$need_r1" -eq 0 ] && [ -f "$CS" ] && ! grep -qE '^\*\*§유형\*\*:' "$SPEC" 2>/dev/null \
   && grep -qE '라인 범위 합산.*→[[:space:]]*유지보수' "$CS" 2>/dev/null; then
  need_r1=1
fi

need_r2=0
# ⚠️ **양성 마커**만 본다 — 문자열 존재(`grep -q '스키마 override'`)로 판정하면
#   analyzing-ko 가 "**스키마 override**: 미발동 — …" 이라고 **부정문으로 근거를 남길 때**
#   그것마저 양성으로 읽혀 AC-R-2(데이터 보존)를 근거 없이 요구한다
#   (20260807 실사용 검증 FID 20260807-doctor-ci-check 실측 — 정상 유지보수 FID 가 차단됐다).
#   analyzing-ko:122 가 규정한 양성 형식은 §1 합산 줄의 `→ 유지보수(스키마 override)` 다.
#   "언급 ≠ 해당" — AC 골격 오탐(1호)과 같은 클래스.
[ -f "$CS" ] && grep -qE '유지보수\(스키마 override\)' "$CS" 2>/dev/null && need_r2=1

# 라벨 정합 — analyzing 마커(합산 >5 → 유지보수)와 spec §유형 의 다운그레이드 차단.
#   analyzing 이 `→ 유지보수` 를 썼는데 spec 이 trivial 이면 AC-R-1 면제가 근거 없이 열린다.
#   상향(마커 trivial, spec 유지보수)은 더 엄격한 쪽이므로 허용.
if [ -f "$CS" ] \
   && grep -qE '라인 범위 합산.*→[[:space:]]*유지보수' "$CS" 2>/dev/null \
   && grep -qE '^\*\*§유형\*\*:[[:space:]]*trivial' "$SPEC" 2>/dev/null; then
  echo "REGRESSION-AC: FAIL — 라벨 불일치 (analyzing 마커=유지보수, spec §유형=trivial)"
  echo "  합산 >5줄 이면 trivial 면제가 성립하지 않는다 — spec §유형을 유지보수로 정정하고 AC-R-1 을 작성하세요."
  exit 1
fi

if [ "$need_r1" -eq 0 ] && [ "$need_r2" -eq 0 ]; then
  echo "REGRESSION-AC: SKIP (§유형≠유지보수 · 스키마 override 없음)"
  exit 0
fi

if [ ! -f "$AC" ]; then
  echo "REGRESSION-AC: FAIL — acceptance-criteria.md 부재 (회귀 AC 를 쓸 곳이 없다)"
  exit 1
fi

# 섹션 추출 + 채움 판정. 템플릿 잔존 문구(대괄호 placeholder)는 미채움.
_section() {  # $1=AC-R-N → 섹션 본문 (h2/h3 모두 — emit-context #209 헤더 완화와 정합)
  awk -v id="$1" '
    $0 ~ ("^##(#)?[[:space:]]+" id "([[:space:]:]|$)") { f=1; next }
    f && /^##(#)?[[:space:]]/ { exit }
    f { print }
  ' "$AC"
}
_check_ac() {  # $1=AC-R-N $2=설명
  local body
  body=$(_section "$1")
  if [ -z "$body" ]; then
    echo "REGRESSION-AC: FAIL — $1 부재 ($2)"
    return 1
  fi
  # 템플릿 placeholder 잔존 — templates/acceptance-criteria.md 의 원문 대괄호 문구
  if printf '%s' "$body" | grep -qE '\[(구체적|현재와 동일한|기존 회귀 테스트|마이그레이션 적용 전|마이그레이션 테스트|대상 테이블)'; then
    echo "REGRESSION-AC: FAIL — $1 템플릿 placeholder 잔존 (미채움 — 실제 회귀 시나리오로 채우세요)"
    return 1
  fi
  # 최소 구조: Given/When/Then 셋 다
  local g w t
  g=$(printf '%s' "$body" | grep -c '^\*\*Given\*\*') || true
  w=$(printf '%s' "$body" | grep -c '^\*\*When\*\*') || true
  t=$(printf '%s' "$body" | grep -c '^\*\*Then\*\*') || true
  if [ "${g:-0}" -eq 0 ] || [ "${w:-0}" -eq 0 ] || [ "${t:-0}" -eq 0 ]; then
    echo "REGRESSION-AC: FAIL — $1 Given/When/Then 불완전 ($2)"
    return 1
  fi
  return 0
}

fail=0
if [ "$need_r1" -eq 1 ]; then
  _check_ac "AC-R-1" "유지보수 FID 는 기존 동작 보존 AC 필수" || fail=1
fi
if [ "$need_r2" -eq 1 ]; then
  _check_ac "AC-R-2" "파괴적 스키마 변경 — 데이터 보존·역가역성 AC 필수 (라인수 면제 불가)" || fail=1
fi

[ "$fail" -eq 0 ] && { echo "REGRESSION-AC: PASS"; exit 0; }
cat >&2 <<'EOF'
  해법: templates/acceptance-criteria.md 의 '회귀 방지 AC' 섹션을 실제 시나리오로 채우세요.
        AC-R-1 = 기존 동작 보존 (유지보수) · AC-R-2 = 데이터 보존·역가역성 (스키마 override)
EOF
exit 1
