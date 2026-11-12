#!/usr/bin/env bash
# 구현 직전 세션 분리 (20261112) — split-session.sh 의 판정·실행·결과 판독·대화 크기 고지.
#
# 왜 필요한가: 분리는 풀 경로의 기본 동작이다. 판정이 틀리면 lite·batch 가 자식 세션으로 새거나(계약 위반),
#   자식의 실패·보류를 완료로 읽어 주 세션이 검증 안 된 채 PR 게이트로 간다. 실 claude 는 부르지 않는다(stub).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0

SS="$PLUGIN/scripts/split-session.sh"
F=20261112-split-x
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
unset SPECOPS_SPLIT_CHILD SPECOPS_NO_SPLIT SPECOPS_SPLIT_PERMISSION_MODE SPECOPS_SPLIT_MODEL \
      SPECOPS_SPLIT_TIMEOUT_MIN SPECOPS_SPLIT_MAX_BUDGET_USD SPECOPS_SPLIT_WARN_TOKENS SPECOPS_ROOT SPECOPS_CONFIG
export CLAUDE_CONFIG_DIR="$TMP/home"   # 사용자 실제 settings 를 읽지 않게
mkdir -p "$CLAUDE_CONFIG_DIR"

# stub claude — 인자를 기록하고 STUB_MODE 에 따라 stream-json 을 낸다
STUB="$TMP/claude"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_ARGS"
printf 'child=%s\n' "${SPECOPS_SPLIT_CHILD:-}" >> "$STUB_ARGS"
echo '{"type":"system","subtype":"init","session_id":"sid-123"}'
case "${STUB_MODE:-done}" in
  done)   echo '{"type":"result","subtype":"success","session_id":"sid-123","num_turns":7,"total_cost_usd":1.25,"result":"요약\nSPLIT-CHILD-DONE: 20261112-split-x"}' ;;
  held)   echo '{"type":"result","subtype":"success","session_id":"sid-123","num_turns":3,"total_cost_usd":0.5,"result":"SPLIT-CHILD-HELD: 20261112-split-x"}' ;;
  failed) echo '{"type":"result","subtype":"success","session_id":"sid-123","num_turns":2,"total_cost_usd":0.1,"result":"SPLIT-CHILD-FAILED: 20261112-split-x 도구 거부"}' ;;
  nomark) echo '{"type":"result","subtype":"success","session_id":"sid-123","num_turns":2,"total_cost_usd":0.1,"result":"다 했습니다"}' ;;
  otherfid) echo '{"type":"result","subtype":"success","session_id":"sid-123","num_turns":2,"total_cost_usd":0.1,"result":"SPLIT-CHILD-DONE: 20261112-other"}' ;;
  budget) echo '{"type":"result","subtype":"error_max_budget_usd","session_id":"sid-123","num_turns":9,"total_cost_usd":3}'; exit 1 ;;
  multi)  echo '{"type":"result","subtype":"success","session_id":"sid-123","num_turns":4,"total_cost_usd":0.4,"result":"대기"}'
          echo '{"type":"result","subtype":"success","session_id":"sid-123","num_turns":9,"total_cost_usd":1.1,"result":"요약\nSPLIT-CHILD-DONE: 20261112-split-x"}'
          echo '{"type":"result","subtype":"success","session_id":"sid-123","num_turns":0,"total_cost_usd":1.1,"result":""}' ;;
  crash)  exit 3 ;;
  hang)   sleep 600 ;;
esac
EOF
chmod +x "$STUB"
export CLAUDE_BIN="$STUB" STUB_ARGS="$TMP/args.log"

# 풀 경로 FID 픽스처(spec·plan·tasks) + 사용자 기본 권한 모드 auto
_mk() {
  local sb; sb=$(mktemp -d "$TMP/sb.XXXXXX") || return 1
  mkdir -p "$sb/.specops/$F"
  printf '# spec\n\n**§유형**: 신규\n**§일괄**: true\n' > "$sb/.specops/$F/spec.md"
  : > "$sb/.specops/$F/plan.md"; : > "$sb/.specops/$F/tasks.md"
  printf '%s' "$sb"
}
_mode() { printf '{"permissions":{"defaultMode":"%s"}}\n' "$1" > "$CLAUDE_CONFIG_DIR/settings.json"; }
_decide() { ( cd "$1" && shift && "$@" bash "$SS" decide "$F" 2>&1 ); }
_mode auto

# ── D: decide ────────────────────────────────────────────────────────────
sb=$(_mk)
out=$(_decide "$sb" env); rc=$?
[ "$rc" = 0 ] && [ "$out" = "SPLIT: yes" ] && ok "D1 풀 경로 FID + 기본 모드 auto → yes" || nope "D1" "rc=$rc out=$out"

_no() {  # <id> <설명> <기대 사유 조각> <준비 명령…>
  local id="$1" desc="$2" want="$3"; shift 3
  local s out rc; s=$(_mk); ( cd "$s" && eval "$1" )
  out=$(_decide "$s" env ${2:-}); rc=$?
  [ "$rc" = 1 ] && printf '%s' "$out" | grep -q "^SPLIT: no (" && printf '%s' "$out" | grep -qF -- "$want" \
    && ok "$id $desc → no" || nope "$id $desc" "rc=$rc out=$out"
}
_no D2 "§batch" "§batch" "printf '**§batch**: B1\n' >> .specops/$F/spec.md"
_no D3 "§lite" "§lite" "printf '**§lite**: true\n' >> .specops/$F/spec.md"
_no D4 "trivial" "trivial" "printf '# s\n\n**§유형**: trivial\n' > .specops/$F/spec.md"
_no D5 "plan.md 없음(lite·basic)" "plan.md" "rm .specops/$F/plan.md"
_no D6 "--no-split 라벨" "no-split" "printf '**§분리**: off\n' >> .specops/$F/spec.md"
_no D7 "config enabled: false" "enabled" "printf 'session_split:\n  enabled: false\n' > .specops/config.yaml"
_no D8 "SPECOPS_NO_SPLIT=1" "SPECOPS_NO_SPLIT" ":" "SPECOPS_NO_SPLIT=1"
_no D9 "자식 세션 안(재귀 차단)" "자식" ":" "SPECOPS_SPLIT_CHILD=1"
_no D10 "claude CLI 없음" "claude" ":" "CLAUDE_BIN=$TMP/none"
_no D11 "tasks.md 없음" "tasks.md" "rm .specops/$F/tasks.md"

_mode default
out=$(_decide "$(_mk)" env); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'permission_mode' && ok "D12 기본 모드가 auto 아님 → no(설정 안내)" || nope "D12" "rc=$rc out=$out"
sb=$(_mk); printf 'session_split:\n  permission_mode: auto   # 명시\nother:\n  permission_mode: bypassPermissions\n' > "$sb/.specops/config.yaml"
out=$(_decide "$sb" env); rc=$?
[ "$rc" = 0 ] && ok "D13 config permission_mode: auto 명시 → yes(다른 블록의 같은 키는 읽지 않는다)" || nope "D13" "rc=$rc out=$out"
out=$(_decide "$(_mk)" env SPECOPS_SPLIT_PERMISSION_MODE=bypassPermissions); rc=$?
[ "$rc" = 1 ] && ok "D14 ★ bypassPermissions 지정 → 거절" || nope "D14" "rc=$rc out=$out"
_mode bypassPermissions
out=$(_decide "$(_mk)" env); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'bypassPermissions' && ok "D15 ★ 사용자 기본이 bypassPermissions → 물려주지 않고 no" || nope "D15" "rc=$rc out=$out"
_mode auto
out=$(cd "$(_mk)" && bash "$SS" decide "../x" 2>&1); rc=$?
[ "$rc" = 2 ] && ok "D16 FID 에 경로 문자 → 사용법 오류(rc 2)" || nope "D16" "rc=$rc out=$out"

# ── R: run ───────────────────────────────────────────────────────────────
_run() { ( cd "$1" && shift && "$@" bash "$SS" run "$F" 2>&1 ); }
sb=$(_mk); : > "$STUB_ARGS"
out=$(_run "$sb" env STUB_MODE=done); rc=$?
last=$(printf '%s\n' "$out" | tail -n 1)
[ "$rc" = 0 ] && printf '%s' "$last" | grep -q "^SPLIT-RESULT: DONE fid=$F session=sid-123 turns=7 cost_usd=1.25 " \
  && ok "R1 자식 DONE → rc 0 · 마지막 줄에 세션·호출 수·비용" || nope "R1" "rc=$rc last=$last"
[ "$(jq -r .status "$sb/.specops/$F/split/result.json")" = DONE ] && [ "$(cat "$sb/.specops/$F/split/session-id")" = sid-123 ] \
  && ok "R2 result.json·session-id 기록" || nope "R2" "$(cat "$sb/.specops/$F/split/result.json" 2>&1)"
grep -q -- '--output-format stream-json' "$STUB_ARGS" && grep -q '^child=1$' "$STUB_ARGS" \
  && grep -q 'devfsd:implementing-ko' "$STUB_ARGS" && grep -q "SPLIT-CHILD-HELD: $F" "$STUB_ARGS" \
  && ok "R3 자식 호출 — stream-json · SPECOPS_SPLIT_CHILD=1 · 프롬프트에 진입 skill 과 끝 마커 규칙" || nope "R3" "$(cat "$STUB_ARGS")"
! grep -q -- 'dangerously-skip-permissions\|bypassPermissions' "$STUB_ARGS" && ! grep -q -- '--permission-mode' "$STUB_ARGS" \
  && ok "R4 ★ inherit 는 권한 옵션을 넘기지 않는다(skip-permissions 없음)" || nope "R4" "$(cat "$STUB_ARGS")"

out=$(_run "$(_mk)" env STUB_MODE=held); rc=$?
[ "$rc" = 10 ] && printf '%s' "$out" | grep -q '^SPLIT-RESULT: HELD ' && ok "R5 자식 HELD → rc 10" || nope "R5" "rc=$rc out=$out"
out=$(_run "$(_mk)" env STUB_MODE=failed); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^SPLIT-RESULT: FAILED .*도구 거부' && ok "R6 자식 FAILED → rc 1 · 사유 전달" || nope "R6" "rc=$rc out=$out"
out=$(_run "$(_mk)" env STUB_MODE=nomark); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^SPLIT-RESULT: FAILED .*마커' && ok "R7 ★ 끝 마커 없는 정상 종료 → 완료로 읽지 않는다" || nope "R7" "rc=$rc out=$out"
out=$(_run "$(_mk)" env STUB_MODE=otherfid); rc=$?
[ "$rc" = 1 ] && ok "R8 ★ 다른 FID 의 DONE 마커 → 완료로 읽지 않는다" || nope "R8" "rc=$rc out=$out"
out=$(_run "$(_mk)" env STUB_MODE=budget); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'error_max_budget_usd' && ok "R9 예산 초과 종료 → FAILED(subtype 표시)" || nope "R9" "rc=$rc out=$out"
sb=$(_mk); out=$(_run "$sb" env STUB_MODE=crash); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^SPLIT-RESULT: FAILED .*session=sid-123' \
  && ok "R10 result 줄 없이 죽음 → FAILED · init 줄에서 세션 id 회수(재개 가능)" || nope "R10" "rc=$rc out=$out"

out=$(_run "$(_mk)" env STUB_MODE=multi); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^SPLIT-RESULT: DONE .*turns=13 cost_usd=1.1 ' \
  && ok "R10b ★ result 줄이 여럿(알림으로 턴 재개)·마지막 본문이 비어도 마커를 찾는다 · 호출 수는 합" || nope "R10b" "rc=$rc out=$out"

# 재개 — 저장된 세션 id 로 --resume, 전달문이 프롬프트에 실린다
: > "$STUB_ARGS"
out=$(cd "$sb" && STUB_MODE=done bash "$SS" run "$F" --resume "사용자 답: 진행" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q -- '--resume sid-123' "$STUB_ARGS" && grep -q '사용자 답: 진행' "$STUB_ARGS" \
  && ok "R11 --resume → 같은 세션 id 로 이어 간다" || nope "R11" "rc=$rc args=$(cat "$STUB_ARGS")"
out=$(cd "$(_mk)" && bash "$SS" run "$F" --resume "x" 2>&1); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'session-id' && ok "R12 세션 id 없이 --resume → FAILED" || nope "R12" "rc=$rc out=$out"

# 설정이 자식 인자로 간다
sb=$(_mk); : > "$STUB_ARGS"
printf 'session_split:\n  permission_mode: acceptEdits\n  model: sonnet\n  max_budget_usd: 9\n' > "$sb/.specops/config.yaml"
out=$(_run "$sb" env STUB_MODE=done); rc=$?
[ "$rc" = 0 ] && grep -q -- '--permission-mode acceptEdits --model sonnet --max-budget-usd 9' "$STUB_ARGS" \
  && ok "R13 config 의 권한 모드·모델·예산이 자식 인자로 전달" || nope "R13" "rc=$rc args=$(cat "$STUB_ARGS")"

# 시간 상한 — 자식이 멈추면 끝내고 TIMEOUT (상한은 분 단위라 워치독을 직접 줄인 사본으로 잰다)
FAST="$TMP/split-fast.sh"
sed -e 's/run_child \$((tmin \* 60))/run_child 2/' -e 's/sleep 5; waited=\$((waited + 5))/sleep 1; waited=$((waited + 1))/' "$SS" > "$FAST"
sb=$(_mk); t0=$(date +%s)
out=$(cd "$sb" && STUB_MODE=hang bash "$FAST" run "$F" 2>&1); rc=$?; el=$(( $(date +%s) - t0 ))
[ "$rc" = 124 ] && printf '%s' "$out" | grep -q '^SPLIT-RESULT: TIMEOUT .*session=sid-123' && [ "$el" -lt 30 ] \
  && ok "R14 상한 초과 → TIMEOUT(rc 124) · 세션 id 보존 · 자식 정리(${el}s)" || nope "R14" "rc=$rc el=$el out=$out"

# ── S: status ────────────────────────────────────────────────────────────
sb=$(_mk); _run "$sb" env STUB_MODE=done >/dev/null
printf '## %s\n\n- 2026-11-12 10:00 /implement 진행 (T1 완료)\n' "$F" > "$sb/.specops/session-progress.md"
out=$(cd "$sb" && bash "$SS" status "$F" 2>&1)
printf '%s' "$out" | grep -q '결과: DONE' && printf '%s' "$out" | grep -q 'T1 완료' && ok "S1 status — 결과와 진행 기록" || nope "S1" "$out"
out=$(cd "$(_mk)" && bash "$SS" status "$F" 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '기록 없음' && ok "S2 status — 자식 기록 없음(rc 0)" || nope "S2" "rc=$rc out=$out"

# ── W: warn-size ─────────────────────────────────────────────────────────
_tr() {  # <파일> <입력> <캐시읽기> <캐시생성>
  printf '{"type":"user","message":{"content":"x"}}\n{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":999999,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s}}}\n{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$2" "$3" "$4" > "$1"
}
_tr "$TMP/big.jsonl" 10 200000 5000
out=$(bash "$SS" warn-size "$TMP/big.jsonl" 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^CONTEXT-LARGE: .*205K .*기준 150K' && ok "W1 205K > 기준 150K → 1줄 고지(rc 0 — 차단 아님)" || nope "W1" "rc=$rc out=$out"
_tr "$TMP/small.jsonl" 10 60000 1000
out=$(bash "$SS" warn-size "$TMP/small.jsonl" 2>&1); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "W2 61K → 침묵(서브에이전트 줄 999999 는 세지 않는다)" || nope "W2" "rc=$rc out=$out"
out=$(SPECOPS_SPLIT_WARN_TOKENS=50000 bash "$SS" warn-size "$TMP/small.jsonl" 2>&1)
printf '%s' "$out" | grep -q '기준 50K' && ok "W3 기준은 설정값(환경변수)" || nope "W3" "$out"
sb=$(_mk); printf 'session_split:\n  warn_context_tokens: 0\n' > "$sb/.specops/config.yaml"
out=$(cd "$sb" && bash "$SS" warn-size "$TMP/big.jsonl" 2>&1)
[ -z "$out" ] && ok "W4 config warn_context_tokens: 0 → 끔" || nope "W4" "$out"
out=$(bash "$SS" warn-size "$TMP/none.jsonl" 2>&1); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "W5 transcript 없음 → 침묵(rc 0)" || nope "W5" "rc=$rc out=$out"
head -c 2000000 /dev/zero | tr '\0' 'x' > "$TMP/raw.jsonl"
out=$(bash "$SS" warn-size "$TMP/raw.jsonl" 2>&1)
printf '%s' "$out" | grep -q '파일 크기 근사' && ok "W6 usage 를 읽지 못하면 파일 크기로 근사" || nope "W6" "$out"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/p1"; cp "$TMP/big.jsonl" "$CLAUDE_CONFIG_DIR/projects/p1/sess-9.jsonl"
out=$(CLAUDE_CODE_SESSION_ID=sess-9 bash "$SS" warn-size 2>&1)
printf '%s' "$out" | grep -q '^CONTEXT-LARGE' && ok "W7 경로 인자 없이 세션 id 로 transcript 를 찾는다" || nope "W7" "$out"

# ── K: 배선 — skill·command 가 스크립트를 실제로 부른다 ───────────────────
grep -q 'split-session.sh decide' "$PLUGIN/skills/decomposing-ko/SKILL.md" && grep -q 'session-split.md' "$PLUGIN/skills/decomposing-ko/SKILL.md" \
  && ok "K1 decomposing-ko 가 분리 판정을 부르고 절차 문서를 가리킨다" || nope "K1" "배선 없음"
grep -q 'split-session.sh run' "$PLUGIN/skills/decomposing-ko/session-split.md" && grep -q 'run-verification.sh' "$PLUGIN/skills/decomposing-ko/session-split.md" \
  && grep -q -- '--resume' "$PLUGIN/skills/decomposing-ko/session-split.md" \
  && ok "K2 절차 문서 — 실행·재개·주 세션 재검증" || nope "K2" "절차 누락"
grep -q 'SPLIT-CHILD-DONE' "$PLUGIN/skills/performance-test-ko/SKILL.md" && ok "K3 performance-test-ko PR 게이트 — 자식은 멈춘다" || nope "K3" "없음"
for c in start maintain; do
  grep -q -- '--no-split' "$PLUGIN/commands/$c.md" && grep -q 'split-session.sh warn-size' "$PLUGIN/commands/$c.md" \
    && ok "K4.$c /$c — --no-split 과 대화 크기 고지" || nope "K4.$c" "없음"
done
grep -q '§분리' "$PLUGIN/skills/specifying-ko/SKILL.md" && ok "K5 specifying-ko 가 --no-split 을 spec 라벨로 남긴다" || nope "K5" "없음"
for c in basic start-lite maintain-lite quick-fix; do
  ! grep -q 'split-session.sh' "$PLUGIN/commands/$c.md" && ok "K6.$c /$c 는 분리를 부르지 않는다" || nope "K6.$c" "분리 배선이 있다"
done

echo ""
finish
