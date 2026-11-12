#!/usr/bin/env bash
# chain-stage eval — decompose 단계 미커버 must AC 탐지율 측정 (plan-ab 패턴, A 방식)
# 사용: bash scripts/tests/llm-eval/run-chain-stage.sh [fixtures-dir]
# ⚠️ 실 claude 비용 (fixture×1회) — 수동 전용. 예비 측정 (통계 약함, gbrain v6-baseline)
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FXDIR="${1:-$HERE/chain-stage-fixtures}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
TIMEOUT_S="${LLM_EVAL_TIMEOUT:-120}"
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  echo "SKIP: claude CLI 부재 (CLAUDE_BIN=$CLAUDE_BIN)"
  echo "decompose: recall=0/0 비용=\$0.00"
  exit 0
fi

run_once() {  # $1=prompt → stdout stream-json (plan-ab 워치독 복제)
  local of pid flag; of=$(mktemp); flag=$(mktemp)
  # 잡 컨트롤(set -m)로 실행기를 자기 프로세스 그룹의 리더로 띄운다 — 시간초과 때 `kill -- -$pid` 로 전 자손을 한 번에 끝낸다.
  #   종전 `pkill -P` → `kill` 두 단계는 그 사이에 본체가 띄운 새 자식을 놓쳤다(20261112-flaky-tests-stabilize 실측 12회 중 8회 잔존).
  set -m
  "$CLAUDE_BIN" -p "$1" --output-format stream-json --verbose --max-turns 2 > "$of" 2>/dev/null < /dev/null &
  pid=$!
  set +m
  # 워치독: 부모는 flag 만 지운다 — 신호 정리는 고아 sleep·멈춤을 남긴다(run-evals.sh run_once 주석 참조)
  ( lim=$TIMEOUT_S; case "$lim" in ''|*[!0-9]*) lim=${lim%%.*}; case "$lim" in ''|*[!0-9]*) lim=0 ;; esac; lim=$((lim + 1)) ;; esac
    n=0; while [ "$n" -lt "$lim" ]; do [ -e "$flag" ] || exit 0; sleep 1; n=$((n + 1)); done
    [ -e "$flag" ] || exit 0; kill -TERM -- "-$pid" 2>/dev/null; pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  wait "$pid" 2>/dev/null || true
  rm -f "$flag"
  cat "$of"; rm -f "$of"
}
out_text() { jq -r 'select(.type=="assistant")|.message.content[]?|select(.type=="text")|.text' 2>/dev/null; }
count_detected() {  # $1=출력텍스트 $2=defects.jsonl $3=plan본문 → 검출수 (이중가드: plan 본문 등장 locator 무효, AC.md 제외)
  local n=0 loc; while IFS= read -r d; do [ -z "$d" ] && continue
    loc=$(printf '%s' "$d" | jq -r '.locator')
    printf '%s' "$3" | grep -Eq -- "${loc}([^0-9]|$)" && continue   # plan.md 본문 등장 → 무효(인용 차단). 뒤 숫자경계로 AC-7≠AC-70 구분
    printf '%s' "$1" | grep -Eq -- "${loc}([^0-9]|$)" && n=$((n+1))
  done < "$2"; echo "$n"
}

DET=0; TOT=0; COST=0
for fx in "$FXDIR"/*/; do
  [ -f "$fx/plan.md" ] && [ -f "$fx/acceptance-criteria.md" ] && [ -f "$fx/defects.jsonl" ] || continue
  def_n=$(grep -c . "$fx/defects.jsonl"); plan=$(cat "$fx/plan.md"); ac=$(cat "$fx/acceptance-criteria.md")
  out=$(run_once "너는 decomposing-ko 다. 아래 구현 플랜(plan.md)과 인수기준(acceptance-criteria.md)을 받아, 각 must AC 를 어느 태스크가 충족하는지 매핑하고 **어느 태스크에도 매핑되지 않은 미커버 must AC ID 만 나열하라**. 매핑된 AC 는 출력하지 마라.

## plan.md
$plan

## acceptance-criteria.md
$ac")
  txt=$(printf '%s\n' "$out" | out_text)
  c=$(printf '%s\n' "$out" | jq -r 'select(.type=="result")|.total_cost_usd // 0' 2>/dev/null | head -1 | grep . || echo 0)
  det=$(count_detected "$txt" "$fx/defects.jsonl" "$plan")
  printf '%s — decompose: recall=%d/%d 비용=$%.2f\n' "$(basename "$fx")" "$det" "$def_n" "$c"
  DET=$((DET+det)); TOT=$((TOT+def_n)); COST=$(awk -v a="$COST" -v b="$c" 'BEGIN{printf "%.4f",a+b}')
done
# bash 3.2 builtin printf 는 '--' 로 시작하는 포맷을 invalid-option 으로 거부 → 구분선 분리(plan-ab 선례)
printf '%s\n' '----'
printf '총괄 — decompose: recall=%d/%d 비용=$%.2f (예비 측정 — N회 재현 전 단정 금지)\n' "$DET" "$TOT" "$COST"
exit 0
