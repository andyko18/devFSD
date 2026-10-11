#!/usr/bin/env bash
# T13. 실패 내성 통합 (AC-7)
# posttool-governance.sh + stop-governance.sh 양쪽 모두
# rules.jsonl 부재 / transcript 부재 / stdin JSON 파싱 실패 3 시나리오 × 2 hook = 6 케이스
# 기대: exit 0 + {continue:true} 보장 + (파싱 실패 시) stderr ERROR 로그
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
POSTTOOL="$PLUGIN/hooks/posttool-governance.sh"
STOP="$PLUGIN/hooks/stop-governance.sh"

source "$PLUGIN/scripts/tests/lib/isolated-tree.sh" 2>/dev/null || true
command -v iso::make_tree >/dev/null 2>&1 && command -v iso::fingerprint >/dev/null 2>&1 \
  || { echo "FATAL: isolated-tree 미로드(또는 반쯤 로드)" >&2; exit 1; }
# ISO pathspec = 격리가 깨졌을 때 이 스위트가 쓸 경로
_iso_paths='hooks/rules.jsonl'
_iso_before=$(iso::fingerprint $_iso_paths)

# ---------- PostToolUse 실패 내성 ----------

# T13.a rules.jsonl 부재 시 posttool exit 0 + {continue:true}
#   ★ 격리: 실 hooks/rules.jsonl 을 mv 하지 않는다. 종전엔 trap 이 0건이라 중단 시
#     거버넌스 규칙이 **사라진 채 남았다**(소비자 5종). 사본에선 잔류할 손상이 없다.
#   ★ "출력이 비어 있지 않음" 은 아래 `jq -e '.continue == true'` 에 **포섭된다**
#     (빈 출력이면 jq 가 실패한다 — 실측: 훅 부재 시 rc=127 out= → FAIL).
#     별도 어서션을 두면 독립적으로 발화할 수 없는 vacuous 한 줄이 늘 뿐이다.
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
touch transcript.jsonl
stdin_json=$(jq -nc --arg tp "$tmp/transcript.jsonl" '{ session_id:"s", transcript_path:$tp, hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:"ls"}, tool_response:{} }')
T=$(iso::make_tree "$PLUGIN") || { FAIL=$((FAIL+1)); echo "FAIL T13.a 격리 사본 생성 실패"; T=""; }
if [ -n "$T" ]; then
  trap 'rm -rf "$T"' EXIT
  ISO_POSTTOOL="$T/hooks/posttool-governance.sh"
  # AC-10 ① 훅 경로가 사본에서 파생됐고 사본 하위인가 — 실 훅 호출로의 회귀를 **도달 불가**로 만든다
  _ac10a=0; case "$ISO_POSTTOOL" in "$T"/*) _ac10a=1 ;; esac
  rm -f "$T/hooks/rules.jsonl"
  # AC-10 ② 호출 직전 사본 rules 부재 사전조건 — rm 실패를 잡는다
  _ac10b=0; [ ! -f "$T/hooks/rules.jsonl" ] && _ac10b=1
  out=$(echo "$stdin_json" | bash "$ISO_POSTTOOL" 2>/dev/null); rc=$?
  rm -rf "$T"; trap - EXIT
  if [ "$_ac10a" -eq 1 ] && [ "$_ac10b" -eq 1 ] \
     && [ "$rc" -eq 0 ] && echo "$out" | jq -e '.continue == true' >/dev/null; then
    PASS=$((PASS+1)); echo "PASS T13.a rules.jsonl 부재 → continue:true (사본 격리 · AC-10 ①②)"
  else
    FAIL=$((FAIL+1)); echo "FAIL T13.a (경로사본하위=$_ac10a 사전조건=$_ac10b rc=$rc out=$out)"
  fi
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T13.b transcript 부재 → exit 0 + continue
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
stdin_json='{"session_id":"s","transcript_path":"/tmp/nowhere-12345.jsonl","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{}}'
out=$(echo "$stdin_json" | bash "$POSTTOOL" 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | jq -e '.continue == true' >/dev/null; then
  PASS=$((PASS+1)); echo "PASS T13.b transcript 부재 → continue:true"
else
  FAIL=$((FAIL+1)); echo "FAIL T13.b (rc=$rc out=$out)"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T13.c stdin JSON 파싱 실패 → exit 0 + continue + stderr 로그
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
stderr_out=$(echo 'not-json-at-all' | bash "$POSTTOOL" 2>&1 >/dev/null); rc_exit=$?
out=$(echo 'not-json-at-all' | bash "$POSTTOOL" 2>/dev/null); rc=$?
has_error_log=$(echo "$stderr_out" | grep -c "governance-capture.*ERROR" || true)
if [ "$rc" -eq 0 ] && echo "$out" | jq -e '.continue == true' >/dev/null && [ "$has_error_log" -ge 1 ]; then
  PASS=$((PASS+1)); echo "PASS T13.c stdin 파싱 실패 → continue:true + stderr"
else
  FAIL=$((FAIL+1)); echo "FAIL T13.c (rc=$rc log=$has_error_log)"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# ---------- Stop 실패 내성 ----------

# T13.d Stop rules.jsonl 부재
#   ★ 격리: T13.a 와 동일 근거. **축마다 새 사본**을 뜬다(T13.a 사본 재사용 금지).
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
touch transcript.jsonl
stdin_json=$(jq -nc --arg tp "$tmp/transcript.jsonl" '{ session_id:"s", transcript_path:$tp, hook_event_name:"Stop", stop_hook_active:false }')
T=$(iso::make_tree "$PLUGIN") || { FAIL=$((FAIL+1)); echo "FAIL T13.d 격리 사본 생성 실패"; T=""; }
if [ -n "$T" ]; then
  trap 'rm -rf "$T"' EXIT
  ISO_STOP="$T/hooks/stop-governance.sh"
  # AC-10 ① 훅 경로가 사본에서 파생됐고 사본 하위인가
  _ac10c=0; case "$ISO_STOP" in "$T"/*) _ac10c=1 ;; esac
  rm -f "$T/hooks/rules.jsonl"
  # AC-10 ② 호출 직전 사본 rules 부재 사전조건
  _ac10d=0; [ ! -f "$T/hooks/rules.jsonl" ] && _ac10d=1
  out=$(echo "$stdin_json" | bash "$ISO_STOP" 2>/dev/null); rc=$?
  rm -rf "$T"; trap - EXIT
  if [ "$_ac10c" -eq 1 ] && [ "$_ac10d" -eq 1 ] \
     && [ "$rc" -eq 0 ] && echo "$out" | jq -e '.continue == true' >/dev/null; then
    PASS=$((PASS+1)); echo "PASS T13.d Stop rules 부재 → continue:true (사본 격리 · AC-10 ①②)"
  else
    FAIL=$((FAIL+1)); echo "FAIL T13.d (경로사본하위=$_ac10c 사전조건=$_ac10d rc=$rc out=$out)"
  fi
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T13.e Stop transcript 부재
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
stdin_json='{"session_id":"s","transcript_path":"/tmp/nowhere-67890.jsonl","hook_event_name":"Stop","stop_hook_active":false}'
out=$(echo "$stdin_json" | bash "$STOP" 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | jq -e '.continue == true' >/dev/null; then
  PASS=$((PASS+1)); echo "PASS T13.e Stop transcript 부재 → continue:true"
else
  FAIL=$((FAIL+1)); echo "FAIL T13.e"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T13.f Stop stdin JSON 파싱 실패
#   도입 저장소에서 잰다 — `.specops/` 가 없으면 입력을 보기 전에 빠진다(관할 한정). cwd 에 기대면 CI 에서만 실패한다.
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
stderr_out=$(echo 'garbage' | bash "$STOP" 2>&1 >/dev/null); rc_exit=$?
out=$(echo 'garbage' | bash "$STOP" 2>/dev/null); rc=$?
cd "$PLUGIN"; rm -rf "$tmp"
has_error_log=$(echo "$stderr_out" | grep -c "governance-capture.*ERROR" || true)
if [ "$rc" -eq 0 ] && echo "$out" | jq -e '.continue == true' >/dev/null && [ "$has_error_log" -ge 1 ]; then
  PASS=$((PASS+1)); echo "PASS T13.f Stop stdin 파싱 실패 → continue + stderr"
else
  FAIL=$((FAIL+1)); echo "FAIL T13.f"
fi

# ── T13.g: T13.a·T13.d **자신**이 사본 훅을 부르는가 (호출부 자기잠금) ──
#   `test-validate-structure.sh` 의 T-hg.e 동형.
#   ★ 왜 필요한가: AC-10 ① (`_ac10a`·`_ac10c`) 은 `ISO_POSTTOOL`/`ISO_STOP` **문자열**이
#     `$T/` 하위인지만 본다. 그 값은 **두 줄 위**에서 `"$T/hooks/…"` 로 조립되므로
#     `$T` 가 비어있지 않은 한 항상 참이다 — **대입줄에만 참, 호출줄엔 거짓**이다.
#     실제 회귀면은 `bash "$ISO_…"` 호출줄이고, `POSTTOOL`·`STOP`(`:9-10`)은
#     T13.b/c/e/f 가 쓰느라 **여전히 정의돼 있다**. 호출줄만 실 훅으로 되돌리면
#     **무음 통과**한다(Phase C 리뷰어 실측: `PASS T13.a …` / `PASS=7 FAIL=0`).
#   ★ 상보 관계 — 둘 다 필요하다. 대입줄을 `"$PLUGIN/…"` 으로 되돌리는 변이는
#     T13.g 를 통과하고 AC-10 ① 이 잡는다. 호출줄 변이는 AC-10 ① 을 통과하고
#     T13.g 가 잡는다. 어느 한쪽만으로는 두 면을 덮지 못한다.
#   ★ 왜 정적 축인가: 실 훅은 rules 유무와 무관하게 `rc=0 {"continue":true}` 를 내고
#     stderr 마커도 없다(`posttool-governance.sh:44`·`stop-governance.sh:47`).
#     프로덕션 훅 무수정 조건에서 **출력으로는 A/B 를 가를 수 없고**, 정적 자기잠금이
#     유일한 축이다. 이 FID 가 AC-10 을 "관측" 이 아니라 "구성" 으로 설계한 것과 같은 이유.
#   ★ 자기 경로는 `$0` 이 아니라 **`$PLUGIN` 파생 절대경로**다. 이유는 둘인데 **무게가 다르다**:
#     (1) **핵심** — `$PLUGIN` 은 `${BASH_SOURCE[0]}` 파생이라(`:8`) 격리 사본에서 실행하면
#         **사본 자신의 파일**을 읽는다. 실 트리를 읽으면 사본 변이가 통과해 vacuous 다.
#     (2) **부차** — `$0` 은 호출 형태·cwd 에 따라 상대경로가 될 수 있다. 다만 **지금은
#         깨지지 않는다**: `:98`·`:109` 가 `cd "$PLUGIN"` 하므로 이 시점 cwd 는 $PLUGIN 이고
#         run-all 의 상대 `$0` 도 풀린다(Phase C 재리뷰 실측 — 종전 주석은 이를 과장했다).
#         실제 취약 경로는 **다른 디렉터리에서 상대경로로 호출**하거나 앞 축 뒤에 `cd` 가
#         끼는 미래 변경이다. `$PLUGIN` 파생은 그 둘 모두에 견고하다.
#   ★ awk 는 블록 첫 줄(`^# T13.a ` / `^# T13.d `)부터 **바깥** `fi`(`^fi$`)까지 뜬다.
#     안쪽 판정 `fi` 는 들여쓰여 있어 걸리지 않는다.
#   ★ grep 은 `-F` 고정문자열이다. 이중 인용 ERE 면 bash 가 `$` 를 풀어 끝 앵커가 되고
#     매치 0 이 된다(T6 실측). 또 `bash "$POSTTOOL"` 은 `bash "$ISO_POSTTOOL"` 의
#     부분문자열이 **아니다**(`ISO_` 접두가 끊는다) — 0건 단언이 vacuous 하지 않다.
_SELF="$PLUGIN/scripts/tests/governance/test-failure-modes.sh"
_t13a_blk=$(awk '/^# T13\.a /{f=1} f{print} f && /^fi$/{exit}' "$_SELF" 2>/dev/null)
_t13d_blk=$(awk '/^# T13\.d /{f=1} f{print} f && /^fi$/{exit}' "$_SELF" 2>/dev/null)
_g_iso_p=$(printf '%s\n' "$_t13a_blk" | grep -cF 'bash "$ISO_POSTTOOL"' || true)
_g_raw_p=$(printf '%s\n' "$_t13a_blk" | grep -cF 'bash "$POSTTOOL"' || true)
_g_iso_s=$(printf '%s\n' "$_t13d_blk" | grep -cF 'bash "$ISO_STOP"' || true)
_g_raw_s=$(printf '%s\n' "$_t13d_blk" | grep -cF 'bash "$STOP"' || true)
if [ "$_g_iso_p" -eq 1 ] && [ "$_g_raw_p" -eq 0 ] \
   && [ "$_g_iso_s" -eq 1 ] && [ "$_g_raw_s" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T13.g 호출부 자기잠금 — T13.a·T13.d 가 사본 훅만 호출"
else
  FAIL=$((FAIL+1)); echo "FAIL T13.g 호출부가 실 훅으로 회귀 — T13.a(사본훅=$_g_iso_p 기대1 · 실훅=$_g_raw_p 기대0) T13.d(사본훅=$_g_iso_s 기대1 · 실훅=$_g_raw_s 기대0)"
fi

if [ "$_iso_before" = "$(iso::fingerprint $_iso_paths)" ]; then
  PASS=$((PASS+1)); echo "PASS ISO 실 트리 전후 지문 불변"
else
  FAIL=$((FAIL+1)); echo "FAIL ISO 실 트리가 변이됐다 (이 스위트 또는 동시 실행 중인 다른 프로세스)"
fi

echo
echo "==== Results: PASS=$PASS FAIL=$FAIL ===="
[ "$FAIL" -eq 0 ]
