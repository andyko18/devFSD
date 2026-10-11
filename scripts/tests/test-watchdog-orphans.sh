#!/usr/bin/env bash
# 워치독 고아·잔존 — 5 러너 종료 후 고아 sleep·워치독 0 · 시간초과 판정 보존 · 부하 반복 · 옛 idiom 재유입 가드 (stub 전용, 토큰 0)
# 20260929-run-evals-orphan-sleep AC-1~AC-6
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
LE="$PLUGIN/scripts/tests/llm-eval"
ok()   { echo "PASS $1"; PASS=$((PASS+1)); }
nope() { echo "FAIL $1 — $2"; FAIL=$((FAIL+1)); }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# 실행별 고유 값 — 같은 머신의 동시 실행(병렬 run-all 등)과 pgrep 가 섞이지 않게
BASE=$(( 1000 + ($$ % 400) * 200 ))   # slot 1~6 · +100 오프셋이 다른 실행의 값과 겹치지 않는 간격

printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/fast"; chmod +x "$TMP/fast"
_hang() {  # <초> → 자식 sleep 을 띄우고 멈추는 stub 경로 (stdout)
  printf '#!/usr/bin/env bash\nsleep %s\n' "$1" > "$TMP/hang$1"; chmod +x "$TMP/hang$1"
  printf '%s' "$TMP/hang$1"
}
_count() {  # <pgrep -f 패턴> → 매칭 프로세스 수 (남은 것은 정리)
  local n
  n=$(pgrep -f -- "$1" | grep -c .)
  [ "$n" -gt 0 ] && pkill -f -- "$1" 2>/dev/null
  printf '%s' "$n"
}
# 러너가 반환된 뒤 워치독은 flag 삭제를 1초 안에 보고 스스로 끝나야 한다 — 병렬 run-all 의 CPU 경합을 감안해
#   최대 6초까지 0 이 되길 기다린 뒤 센다(고정 대기는 경합 시 거짓 FAIL). 옛 idiom 의 고아 sleep 은 TIMEOUT 초 동안
#   남으므로 6초 안에 사라지지 않는다 — 판별력 유지.
#   남는 것: 긴 sleep(`sleep <값>`)과 워치독 서브셸(러너의 고유 인자를 argv 로 물려받는다 — 실측)
_leftover() {  # <sleep 값> <러너 고유 인자> → "sleep수/워치독수"
  local k=0
  sleep 1
  while [ "$k" -lt 5 ] && { pgrep -fx "sleep $1" >/dev/null || pgrep -f -- "$2" >/dev/null; }; do sleep 1; k=$((k + 1)); done
  printf '%s/%s' "$(_count "^sleep $1\$")" "$(_count "$2")"
}
_llm() {  # <러너> <인자> <timeout> <CLAUDE_BIN> → 러너 stdout+stderr
  env LLM_EVAL_TIMEOUT="$3" CLAUDE_BIN="$4" bash "$LE/$1" "$2" 2>&1
}

head -1 "$LE/fixtures.jsonl" > "$TMP/fx.jsonl"
head -1 "$LE/pressure-fixtures.jsonl" > "$TMP/pfx.jsonl"
mkdir -p "$TMP/ab" "$TMP/cs"
cp -R "$LE/plan-ab-fixtures/cov-miss" "$TMP/ab/"
cp -R "$LE/chain-stage-fixtures/decompose-covmiss" "$TMP/cs/"

# T1 (AC-1·AC-2) llm-eval 러너 4종 — 종료 후 고아 sleep·워치독 0 · 시간초과 판정 보존
_check_llm() {  # <id> <러너> <인자> <정상경로 금지 regex(빈값=검사 안 함)> <시간초과 기대 regex> <slot>
  local id="$1" r="$2" a="$3" nofalse="$4" want="$5" slot="$6" v h out left
  v=$((BASE + slot)); h=$((BASE + slot + 100))
  out=$(_llm "$r" "$a" "$v" "$TMP/fast"); left=$(_leftover "$v" "$a")
  if [ "$left" = "0/0" ] && { [ -z "$nofalse" ] || ! printf '%s' "$out" | grep -Eq "$nofalse"; }; then
    ok "$id.a $r 정상 종료 → 고아 sleep·워치독 0 · 거짓 timeout 없음"
  else nope "$id.a" "$r 잔존 sleep/워치독=$left / out=$(printf '%s' "$out" | tail -2 | tr '\n' ' ')"; fi
  out=$(_llm "$r" "$a" 1 "$(_hang "$h")"); left=$(_leftover "$h" "$a")
  if printf '%s' "$out" | grep -Eq "$want" && [ "$left" = "0/0" ]; then
    ok "$id.b $r 시간초과 → 종전 판정 · 멈춘 stub 자손·워치독 정리"
  else nope "$id.b" "$r 기대 /$want/ · 잔존 stub자손/워치독=$left / out=$(printf '%s' "$out" | tail -2 | tr '\n' ' ')"; fi
}
_check_llm T1.1 run-evals.sh          "$TMP/fx.jsonl"  'TIMEOUT'     'TIMEOUT 1s'            1
_check_llm T1.2 run-pressure-evals.sh "$TMP/pfx.jsonl" '\(timeout\)' '\(timeout\)'           2
_check_llm T1.3 run-plan-ab.sh        "$TMP/ab"        ''            '방식 A: recall=0/2'    3
_check_llm T1.4 run-chain-stage.sh    "$TMP/cs"        ''            'decompose: recall=0/1' 4
# T2 (AC-1·AC-2·AC-5) critic-ask — 종료 후 고아 0 · 출력 계약 · 시간초과 provider 자손 정리(exec)
printf '# p\n' > "$TMP/prompt.md"
printf '#!/usr/bin/env bash\ncat >/dev/null\necho 의견OK\n' > "$TMP/ok"; chmod +x "$TMP/ok"
_critic() {  # <timeout> <CRITIC_BIN> → stdout+stderr
  CRITIC_TIMEOUT="$1" CRITIC_BIN="$2" bash "$PLUGIN/scripts/critic-ask.sh" "$TMP/prompt.md" 2>&1
}
v=$((BASE + 5)); h=$((BASE + 105))
out=$(_critic "$v" "$TMP/ok"); left=$(_leftover "$v" "$TMP/prompt.md")
if [ "$left" = "0/0" ] && printf '%s' "$out" | grep -qF 'CRITIC[custom]:' && printf '%s' "$out" | grep -qF '의견OK' \
   && ! printf '%s' "$out" | grep -q 'timeout'; then
  ok "T2.a critic-ask 정상 응답 → 고아 sleep·워치독 0 · CRITIC[custom]: 출력 계약 유지"
else nope "T2.a" "잔존 sleep/워치독=$left / out=$(printf '%s' "$out" | tr '\n' ' ')"; fi
out=$(_critic 1 "$(_hang "$h")"); left=$(_leftover "$h" "$TMP/prompt.md")
printf '%s' "$out" | grep -qF 'CRITIC: FAIL (timeout 1s)' && ok "T2.b critic-ask 시간초과 → CRITIC: FAIL (timeout 1s)" \
  || nope "T2.b" "out=$(printf '%s' "$out" | tr '\n' ' ')"
[ "$left" = "0/0" ] && ok "T2.c critic-ask 시간초과 → 멈춘 provider 의 자식 sleep·워치독 정리 (exec)" \
  || nope "T2.c" "잔존 provider자손/워치독=$left"
# T2.d SIGTERM 중단 — EXIT trap cleanup 이 flag 를 지워 워치독이 스스로 끝나고 멈춘 provider 자손도 남지 않아야 한다
v=$((BASE + 7)); h=$((BASE + 107))
CRITIC_TIMEOUT="$v" CRITIC_BIN="$(_hang "$h")" bash "$PLUGIN/scripts/critic-ask.sh" "$TMP/prompt.md" >/dev/null 2>&1 &
cp_pid=$!
sleep 1; kill -TERM "$cp_pid" 2>/dev/null; wait "$cp_pid" 2>/dev/null
left=$(_leftover "$h" "$TMP/prompt.md")
[ "$left" = "0/0" ] && ok "T2.d critic-ask SIGTERM 중단 → 워치독·멈춘 provider 자식 sleep 잔존 0" \
  || nope "T2.d" "잔존 provider자손/워치독=$left"

# T3 (AC-3) 옛 워치독 idiom 재유입 가드 — 워치독을 신호로 정리하는 두 형태를 막는다:
#   `( sleep … & wait $! )` (kill watcher 뒤 sleep 고아) · `( trap …; sleep … & sp=$! … )` (trap 설치 창에서 신호 유실 → 부모 멈춤)
_old_idiom() { grep -nE 'sleep "\$\{?[A-Za-z_]+\}?" & (wait \$!|sp=\$!)' "$@" 2>/dev/null; }
printf '%s\n' "  ( sleep \"\$TIMEOUT_S\" & wait \$!; : ) >/dev/null 2>&1 &" > "$TMP/old1.sh"
printf '%s\n' "  ( trap 'kill \"\${sp:-}\"; exit 0' TERM; sleep \"\${to}\" & sp=\$!; wait \"\$sp\" ) &" > "$TMP/old2.sh"
if _old_idiom "$TMP/old1.sh" >/dev/null && _old_idiom "$TMP/old2.sh" >/dev/null; then
  ok "T3.a 가드 자기 검증 — sleep&wait · TERM-trap sp 두 형태 적발"; else nope "T3.a" "옛 형태를 못 잡음"; fi
hits=$(cd "$PLUGIN" && git ls-files '*.sh' '.githooks/*' | while IFS= read -r f; do _old_idiom "$f" | sed "s|^|$f:|"; done)
[ -z "$hits" ] && ok "T3.b 저장소 셸 스크립트 옛 워치독 idiom 0건" || nope "T3.b" "옛 idiom 잔존: $(printf '%s' "$hits" | cut -d: -f1-2 | tr '\n' ' ')"

# 5곳 워치독 블록 동일성 — 한 곳만 고쳐 조용히 drift 하지 않게 폴링·재확인 줄을 고정 문자열로 잠근다
POLL='n=0; while [ "$n" -lt "$lim" ]; do [ -e "$flag" ] || exit 0; sleep 1; n=$((n + 1)); done'
drift=""
for f in scripts/tests/llm-eval/run-evals.sh scripts/tests/llm-eval/run-pressure-evals.sh scripts/tests/llm-eval/run-plan-ab.sh \
         scripts/tests/llm-eval/run-chain-stage.sh scripts/critic-ask.sh; do
  grep -qF -- "$POLL" "$PLUGIN/$f" && grep -qF -- 'rm -f "$flag"' "$PLUGIN/$f" || drift="$drift $f"
done
[ -z "$drift" ] && ok "T3.c 5곳 워치독 폴링 블록·flag 삭제 동일" || nope "T3.c" "블록 불일치:$drift"

# T4 (AC-6) 부하 반복 — 즉시 끝나는 provider 로 20회 연속: 멈춤 없음 · 잔존 0 (신호 정리 방식이 깨진 타이밍)
v=$((BASE + 6))
( i=0; while [ "$i" -lt 20 ]; do _critic "$v" "$TMP/fast" >/dev/null; i=$((i + 1)); done; : > "$TMP/stress.done" ) &
sp_pid=$!
k=0; while [ "$k" -lt 60 ] && [ ! -e "$TMP/stress.done" ]; do sleep 1; k=$((k + 1)); done
if [ -e "$TMP/stress.done" ]; then
  left=$(_leftover "$v" "$TMP/prompt.md")
  [ "$left" = "0/0" ] && ok "T4 critic-ask 20회 연속(즉시 종료 provider) → 멈춤 없음 · 잔존 0" || nope "T4" "잔존 sleep/워치독=$left"
else
  pkill -P "$sp_pid" 2>/dev/null; kill "$sp_pid" 2>/dev/null
  nope "T4" "20회 연속 실행이 60초 안에 끝나지 않음 — 워치독 정리 경로 멈춤"
fi
echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
