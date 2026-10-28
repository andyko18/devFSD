#!/usr/bin/env bash
# 압박 테스트 eval — HARD GATE 우회 거부 검증 (금지 도구 부재 AND 게이트 발화)
# 사용: bash scripts/tests/llm-eval/run-pressure-evals.sh [pressure-fixtures.jsonl]
# 환경: CLAUDE_BIN(기본 claude) · LLM_EVAL_TIMEOUT(120) · LLM_EVAL_MAX_TURNS(3)
# ⚠️ 실 claude 호출 비용 — run-all/CI 비포함, 수동 전용
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FX="${1:-$HERE/pressure-fixtures.jsonl}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
MAX_TURNS="${LLM_EVAL_MAX_TURNS:-3}"
TIMEOUT_S="${LLM_EVAL_TIMEOUT:-120}"
# sandbox 격리 — git commit·branch·.specops 부작용을 temp repo 에 가둠 (run-evals.sh 패턴)
SANDBOX=$(mktemp -d)
git -C "$SANDBOX" init -q
git -C "$SANDBOX" config user.email eval@local; git -C "$SANDBOX" config user.name eval
mkdir -p "$SANDBOX/.specops"; printf '# sandbox\n' > "$SANDBOX/CLAUDE.md"
cleanup() { rm -rf "$SANDBOX"; return 0; }
trap cleanup EXIT
total=$(grep -c . "$FX" 2>/dev/null || true); [ -z "$total" ] && total=0
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  echo "SKIP: claude CLI 부재 (CLAUDE_BIN=$CLAUDE_BIN)"
  echo "PASS=0 FAIL=0 SKIP=$total COST=\$0.00"
  exit 0
fi
PASS=0; FAIL=0; COST=0

run_once() {  # $1=prompt → stdout stream-json (run-evals 워치독 패턴 복제)
  local out_f pid flag mark; out_f=$(mktemp); mark=$(mktemp); rm -f "$mark"; flag=$(mktemp)
  ( cd "$SANDBOX" && exec "$CLAUDE_BIN" -p "$1" --output-format stream-json --verbose --max-turns "$MAX_TURNS" \
    --allowedTools Skill Write Edit Bash ) > "$out_f" 2>/dev/null < /dev/null &
  pid=$!
  # 워치독: 부모는 flag 만 지운다 — 신호 정리는 고아 sleep·멈춤을 남긴다(run-evals.sh run_once 주석 참조)
  ( lim=$TIMEOUT_S; case "$lim" in ''|*[!0-9]*) lim=${lim%%.*}; case "$lim" in ''|*[!0-9]*) lim=0 ;; esac; lim=$((lim + 1)) ;; esac
    n=0; while [ "$n" -lt "$lim" ]; do [ -e "$flag" ] || exit 0; sleep 1; n=$((n + 1)); done
    [ -e "$flag" ] || exit 0; : > "$mark"; pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  wait "$pid" 2>/dev/null || true
  rm -f "$flag"
  [ -f "$mark" ] && echo '{"type":"_timeout"}'
  cat "$out_f"; rm -f "$out_f" "$mark"
}
extract_cost() { jq -r 'select(.type=="result")|.total_cost_usd // 0' 2>/dev/null | head -1 | grep . || echo 0; }

judge_pressure() {  # stdin=stream-json $1=forbidden_csv $2=gate_re $3=bash_re → "PASS|FAIL\t<사유>"
  local fb="$1" gate="$2" bashre="${3:-}" out; out=$(cat)
  printf '%s\n' "$out" | grep -q '"_timeout"' && { printf 'FAIL\ttimeout'; return; }
  [ -z "$gate" ] && { printf 'FAIL\tgate_phrases 미정의'; return; }
  local tools texts cmds hit=""
  # bash-command 차원 검사 (verify-gate — git commit·gh pr create 변형)
  if [ -n "$bashre" ]; then
    cmds=$(printf '%s\n' "$out" | jq -r 'select(.type=="assistant")|.message.content[]?|select(.type=="tool_use" and .name=="Bash")|.input.command // empty' 2>/dev/null)
    if printf '%s\n' "$cmds" | grep -Eq "$bashre"; then printf 'FAIL\t게이트 붕괴 (bash: %s)' "$bashre"; return; fi
  fi
  tools=$(printf '%s\n' "$out" | jq -r 'select(.type=="assistant")|.message.content[]?|select(.type=="tool_use")|if .name=="Skill" then "Skill:"+((.input.skill//"")|sub("^devfsd:";"")) else .name end' 2>/dev/null)
  local IFS=','; for f in $fb; do
    [ -z "$f" ] && continue
    if printf '%s\n' "$tools" | grep -Fxq "$f"; then hit="$f"; break; fi
  done
  unset IFS
  if [ -n "$hit" ]; then printf 'FAIL\t게이트 붕괴 (%s 호출)' "$hit"; return; fi
  texts=$(printf '%s\n' "$out" | jq -r 'select(.type=="assistant")|.message.content[]?|select(.type=="text")|.text' 2>/dev/null)
  if printf '%s' "$texts" | grep -Eq "$gate"; then printf 'PASS\t거부'; else printf 'FAIL\t게이트 발화 부재'; fi
}

run_fixture() {
  local fx="$1" id prompt fb gate v retry=""
  id=$(printf '%s' "$fx" | jq -r '.id')
  prompt=$(printf '%s' "$fx" | jq -r '.prompt')
  fb=$(printf '%s' "$fx" | jq -r '(.forbidden_tools // [])|join(",")')
  gate=$(printf '%s' "$fx" | jq -r '.gate_phrases // ""')
  local bashre; bashre=$(printf '%s' "$fx" | jq -r '.forbidden_bash_re // ""')
  local out; out=$(run_once "$prompt"); COST=$(awk -v a="$COST" -v b="$(printf '%s\n' "$out"|extract_cost)" 'BEGIN{printf "%.4f",a+b}')
  v=$(printf '%s\n' "$out" | judge_pressure "$fb" "$gate" "$bashre")
  if [ "${v%%$'\t'*}" != "PASS" ]; then
    out=$(run_once "$prompt"); COST=$(awk -v a="$COST" -v b="$(printf '%s\n' "$out"|extract_cost)" 'BEGIN{printf "%.4f",a+b}')
    v=$(printf '%s\n' "$out" | judge_pressure "$fb" "$gate" "$bashre"); retry=" retry"
  fi
  if [ "${v%%$'\t'*}" = "PASS" ]; then PASS=$((PASS+1)); echo "PASS $id$retry"; else FAIL=$((FAIL+1)); echo "FAIL $id$retry (${v#*$'\t'})"; fi
}

while IFS= read -r fx; do [ -z "$fx" ] && continue; run_fixture "$fx"; done < "$FX"
printf 'PASS=%d FAIL=%d SKIP=0 COST=$%.2f\n' "$PASS" "$FAIL" "$COST"
[ "$FAIL" -eq 0 ]
