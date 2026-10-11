#!/usr/bin/env bash
# check-review-presence.sh — Phase B/C **수행 존재** 관측 (20260806)
# Usage: check-review-presence.sh <FID>
# Exit: 항상 0 — **warn-only (비차단)**. 관측 결과는 stdout + friction-log.
#
# 왜 필요한가: skill 은 "Phase B/C 생략 금지" 를 여러 곳에서 HARD 로 선언한다
#   (§lite 불변 · risk-profile allowlist · implementing-ko §리뷰 규약). 그런데
#   `check-review-audit.sh` 는 **정합 검사**(reviews ↔ dispatch-log)지 **존재 검사**가 아니다 —
#   리뷰를 0회 하면 검사 대상 자체가 없어 `SKIP` rc=0 으로 통과한다(20260806 실측).
#   즉 "생략 금지" 선언에 대응하는 관측조차 없었다.
#
# 왜 차단이 아니라 warn 인가: 그 fail-open 은 의도된 설계다
#   ("산출물 부재는 SKIP — 무관 repo·초기 FID 월권 0"). presence 를 즉시 하드 차단하면
#   본 repo 기존 FID 20건 중 **7건(35%)이 소급 FAIL** 한다(실측). 1단계는 관측만 하고,
#   빈도를 본 뒤 차단 전환을 판단한다. **전환 시 바꿀 계약이 바로 이 exit 0 이다.**
#
# 관측 대상: `tasks.md` 가 있는 FID(= 구현에 도달). 없으면 초기 FID 라 월권하지 않는다.
# 수행 증거: `reviews/*-B-report.md|*-B-feedback.md` · 동일하게 C. FAIL 라운드의 feedback 도
#   "수행함" 의 증거다(implementing 규약상 FAIL 시 feedback 병기).
set -u

FID="${1:?usage: $0 <FID>}"
SPECOPS="${SPECOPS_ROOT:-.specops}"
DIR="$SPECOPS/$FID"

[ -d "$DIR" ] || exit 0                 # 무관 repo·부재 FID — 월권 0
[ -f "$DIR/tasks.md" ] || exit 0        # 구현 미도달 — 관측 대상 아님

_has() {  # $1=B|C → 수행 증거 유무
  ls "$DIR"/reviews/*-"$1"-report.md >/dev/null 2>&1 && return 0
  ls "$DIR"/reviews/*-"$1"-feedback.md >/dev/null 2>&1 && return 0
  return 1
}

miss=""
_has B || miss="Phase B(spec-reviewer-ko) 미수행"
_has C || miss="${miss}${miss:+ · }Phase C(code-reviewer-ko) 미수행"

if [ -z "$miss" ]; then
  echo "REVIEW-PRESENCE: OK (B·C 수행 흔적 확인)"
  exit 0
fi

# ── §lite 는 하드 차단 (20260806) ────────────────────────────────────────────
# lite 는 clarify·plan 을 **이미 뺀** 모드라 Phase B/C 가 **남은 유일한 리뷰층**이다.
#   여기서도 B/C 가 사라지면 lite = spec → implement → verify (외부 리뷰 0) 가 된다.
#   warn-first 를 택한 이유는 소급 영향이었는데(전체 FID 20건 중 7건 무리뷰),
#   **§lite FID 는 실측 0건**(v1.60 도입 직후)이라 하드화의 소급 비용이 없다 —
#   "가장 필요한 곳"과 "가장 싼 곳"이 일치한다. 비-lite 는 warn 유지(기존 계약 무손상).
if grep -qE '^\*\*§lite\*\*:[[:space:]]*true' "$DIR/spec.md" 2>/dev/null; then
  echo "REVIEW-PRESENCE: FAIL — $miss (§lite 는 B/C 가 남은 유일한 리뷰층이라 생략 불가)"
  echo "  lite 는 clarify·plan 을 이미 축약했다 — Phase B/C 까지 빠지면 외부 리뷰가 0 이 된다."
  echo "  end-loaded 로 FID 말미 B 1회 + C 1회를 수행하고 reviews/<tid>-B-report.md ·"
  echo "  <tid>-C-report.md 를 남긴 뒤 재실행하세요."
  exit 1
fi

echo "REVIEW-PRESENCE: WARN — $miss"
echo "  skill 계약상 Phase B/C 는 생략 금지다(end-loaded 는 시점 통합이지 생략이 아님)."
echo "  현재는 **관측만** 하고 chain 을 막지 않는다(warn-only). 리뷰 산출물은"
echo "  reviews/<tid>-B-report.md · <tid>-C-report.md 규약으로 남긴다."

# friction-log 기록 — 빈도 관측이 전환 판단의 근거다.
#   키는 훅의 log_friction(hooks/governance-lib.sh)과 같다: ts·fid·rule_id·severity·principle·evidence_snippet.
#   읽는 쪽(gbrain-friction.sh `select(.rule_id != null)` · doctor.sh `.rule_id`·`.ts`)이 그 키만 읽는다 —
#   종전 키(rule·recorded_at·evidence)로는 이 기록이 집계에서 통째로 빠졌다(20261011 실측: 하류 31건 누락).
#   transcript_offset 은 쓰지 않는다 — 이 스크립트는 transcript 를 읽지 않는다.
log="$DIR/friction-log.jsonl"
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg ts "$ts" --arg fid "$FID" --arg rule_id "REVIEW-PRESENCE" --arg ev "$miss" \
     --argjson principle 2 \
     '{ts:$ts,fid:$fid,rule_id:$rule_id,severity:"warn",principle:$principle,evidence_snippet:$ev}' \
     >> "$log" 2>/dev/null || true
else
  printf '{"ts":"%s","fid":"%s","rule_id":"REVIEW-PRESENCE","severity":"warn","principle":2,"evidence_snippet":"%s"}\n' \
    "$ts" "$FID" "$miss" >> "$log" 2>/dev/null || true
fi
exit 0
