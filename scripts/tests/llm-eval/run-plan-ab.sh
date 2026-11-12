#!/usr/bin/env bash
# plan 리뷰 A/B 측정 — inline self-review(A) vs 2중 dispatch(B) 검출률·토큰 비교
# 사용: bash scripts/tests/llm-eval/run-plan-ab.sh [fixtures-dir]
# ⚠️ 실 claude 비용 (fixture×3회) — 수동 전용. 예비 측정 (NFR-3 통계 약함)
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FXDIR="${1:-$HERE/plan-ab-fixtures}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
TIMEOUT_S="${LLM_EVAL_TIMEOUT:-120}"
DOCREV="$(cd "$HERE/../../.." && pwd)/skills/planning-ko/plan-document-reviewer-prompt.md"
[ -f "$DOCREV" ] || echo "WARN: doc-reviewer 프롬프트 부재 ($DOCREV) — 방식 B 첫 dispatch 가 빈 프롬프트로 약화됨" >&2
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  echo "SKIP: claude CLI 부재 (CLAUDE_BIN=$CLAUDE_BIN)"
  echo "A: recall=0/0 비용=\$0.00 / B: recall=0/0 비용=\$0.00"
  exit 0
fi

run_once() {  # $1=prompt → stdout stream-json (워치독 복제)
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
out_cost() { jq -r 'select(.type=="result")|.total_cost_usd // 0' 2>/dev/null | head -1 | grep . || echo 0; }
count_detected() {  # $1=출력텍스트 $2=defects.jsonl $3=plan본문 → 검출수
  # 측정 무결성: locator 가 plan 본문에도 등장하면 claude 인용만으로 매칭될 수 있어 검출 무효 (이중 가드)
  local n=0 loc; while IFS= read -r d; do [ -z "$d" ] && continue
    loc=$(printf '%s' "$d" | jq -r '.locator')
    printf '%s' "$3" | grep -Fq "$loc" && continue   # 본문 등장 locator → 무효
    printf '%s' "$1" | grep -Fq "$loc" && n=$((n+1))
  done < "$2"; echo "$n"
}

A_det=0; A_tot=0; A_cost=0; B_det=0; B_tot=0; B_cost=0
for fx in "$FXDIR"/*/; do
  [ -f "$fx/plan.md" ] && [ -f "$fx/defects.jsonl" ] || continue
  def_n=$(grep -c . "$fx/defects.jsonl"); plan=$(cat "$fx/plan.md")
  # 방식 A — inline self-review
  a_out=$(run_once "다음은 구현 플랜이다. §자체 검토 3관점(① 스펙 커버리지 누락 ② 플레이스홀더(TBD·적절한 처리 등) ③ 타입/명명 일관성)으로 결함을 나열하라.

$plan")
  a_txt=$(printf '%s\n' "$a_out" | out_text); a_c=$(printf '%s\n' "$a_out" | out_cost)
  ad=$(count_detected "$a_txt" "$fx/defects.jsonl" "$plan")
  # 방식 B — 2중 dispatch (claude -p 2회: doc-reviewer + plan-reviewer 근사)
  b1=$(run_once "$(cat "$DOCREV" 2>/dev/null)

검토 대상 플랜:
$plan")
  b2=$(run_once "너는 plan-reviewer 다. TDD 커버리지·플레이스홀더·파일 경계·타입 일관성 4관점으로 아래 플랜의 결함을 나열하라.

$plan")
  b_txt="$(printf '%s\n' "$b1" | out_text)
$(printf '%s\n' "$b2" | out_text)"
  b_c=$(awk -v x="$(printf '%s\n' "$b1"|out_cost)" -v y="$(printf '%s\n' "$b2"|out_cost)" 'BEGIN{printf "%.4f",x+y}')
  bd=$(count_detected "$b_txt" "$fx/defects.jsonl" "$plan")
  printf '%s — 방식 A: recall=%d/%d 비용=$%.2f / 방식 B: recall=%d/%d 비용=$%.2f\n' "$(basename "$fx")" "$ad" "$def_n" "$a_c" "$bd" "$def_n" "$b_c"
  A_det=$((A_det+ad)); A_tot=$((A_tot+def_n)); A_cost=$(awk -v a="$A_cost" -v b="$a_c" 'BEGIN{printf "%.4f",a+b}')
  B_det=$((B_det+bd)); B_tot=$((B_tot+def_n)); B_cost=$(awk -v a="$B_cost" -v b="$b_c" 'BEGIN{printf "%.4f",a+b}')
done
echo "----"
printf '총괄 — 방식 A: recall=%d/%d 비용=$%.2f / 방식 B: recall=%d/%d 비용=$%.2f\n' "$A_det" "$A_tot" "$A_cost" "$B_det" "$B_tot" "$B_cost"
diff_det=$((B_det - A_det))
mult=$(awk -v a="$A_cost" -v b="$B_cost" 'BEGIN{if(a>0)printf "%.1f",b/a;else printf "N/A"}')
printf '결론 — B-A 검출차=+%d / 비용배수=%s배 (유지 가치 판단은 사용자 — 예비 측정, NFR-3 통계 약함)\n' "$diff_det" "$mult"
exit 0
