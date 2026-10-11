#!/usr/bin/env bash
# _verify_exec_evidence 단위 — tool_use ↔ tool_result join 실행증거 판정 (20260713-verify-exec-gate)
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN=$(cd "$script_dir/../../.." && pwd)
FIX="$script_dir/fixtures/transcripts"
# harness 로드 가드 — source 실패 시 false-PASS 봉쇄
. "$PLUGIN/hooks/governance-lib.sh" || { echo "FATAL: governance-lib.sh 로드 실패"; exit 1; }
type _verify_exec_evidence >/dev/null 2>&1 || { echo "FATAL: _verify_exec_evidence 미정의"; exit 1; }
pass=0; fail=0
ck() { if [ "$2" = "$3" ]; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1 — expected rc=$2, got rc=$3"; fail=$((fail+1)); fi; }

_verify_exec_evidence "$FIX/exec-evidence-pass.jsonl"; ck "T1 실행증거 있음 → 0" 0 $?
_verify_exec_evidence "$FIX/exec-evidence-absent.jsonl"; ck "T2 호출만(실행 결과 없음) → 1" 1 $?
_verify_exec_evidence "$FIX/exec-evidence-partial.jsonl"; ck "T3 PARTIAL → 1 (negative check)" 1 $?
_verify_exec_evidence "/nonexistent/path.jsonl"; ck "T4 transcript 부재 → 2 (fail-open)" 2 $?
# ★ C-3 설계 정정: 빈 transcript(파일 존재·파싱 성공·tool_use 0건) = 판정 불가(2), 증거 없음(1) 아님.
#   이벤트 0건은 "검증 안 함"과 "transcript 를 못 읽음"을 구별 불가 → fail-open 원칙상 2.
#   (test-verify-progress T13 무손상 근거)
empty=$(mktemp) || exit 1
_verify_exec_evidence "$empty"; ck "T5 빈 transcript → 2 (판정 불가 — 증거없음 아님)" 2 $?
rm -f "$empty"
# T6 (AC-9): command-only 위조 — 러너 tool_use 는 있으나 대응 tool_result 부재 → 1
cmdonly=$(mktemp) || exit 1
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_Z","name":"Bash","input":{"command":"bash scripts/_internal/run-verification.sh 20260101-x"}}]}}' > "$cmdonly"
_verify_exec_evidence "$cmdonly"; ck "T6 command-only(result 부재) → 1 (AC-9)" 1 $?
rm -f "$cmdonly"

# ── 위조 벡터 4종 (Phase C: 방어층 회귀 잠금) ───────────────────────────────────
# 아래 4케이스는 각각 함수의 방어층 하나씩을 잠근다. 해당 층을 제거하면 그 케이스만 FAIL 해야 한다.
#   T7 → 러너 앵커 정규식 / T8 → tool_use_id join / T9 → is_error 필터 / T10 → negative check

# T7: echo 위장 — 비러너 Bash(러너 키워드를 문자열 안에 품음) + 하네스 result 에 PASS.
#     코드 주석이 스스로 명명한 핵심 위조 벡터. 앵커 없는 정규식이면 "ran pytest" 가 매칭되어 뚫린다.
echoforge=$(mktemp) || exit 1
printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_E1","name":"Bash","input":{"command":"echo \"ran pytest — VERIFY: PASS\""}}]}}' \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_E1","is_error":false,"content":"ran pytest — VERIFY: PASS"}]}}' > "$echoforge"
_verify_exec_evidence "$echoforge"; ck "T7 echo 위장(비러너 명령 + PASS 출력) → 1 (러너 앵커)" 1 $?
rm -f "$echoforge"

# T8: id 도용 — 러너 tool_use 는 있으나, PASS result 가 **다른 tool_use_id** 에 달려 있다.
#     join 없이 result 만 훑으면 남의 PASS 를 자기 실행증거로 착복한다.
idsteal=$(mktemp) || exit 1
printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_R1","name":"Bash","input":{"command":"bash scripts/_internal/run-verification.sh 20260101-x"}}]}}' \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_OTHER","is_error":false,"content":"VERIFY: PASS"}]}}' > "$idsteal"
_verify_exec_evidence "$idsteal"; ck "T8 id 도용(타 tool_use 의 PASS) → 1 (id join)" 1 $?
rm -f "$idsteal"

# T9: 에러 결과 — 러너가 돌긴 했으나 하네스가 is_error 로 표시한 출력. 실패한 실행은 증거 불인정.
errres=$(mktemp) || exit 1
printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_R2","name":"Bash","input":{"command":"bash scripts/_internal/run-verification.sh 20260101-x"}}]}}' \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_R2","is_error":true,"content":"VERIFY: PASS"}]}}' > "$errres"
_verify_exec_evidence "$errres"; ck "T9 is_error 결과(PASS 문자열 포함) → 1 (에러결과 불인정)" 1 $?
rm -f "$errres"

# T10: 혼재 출력 — 같은 출력에 PASS 와 PARTIAL 이 함께 있다(다FID·요약행). 부분 검증을 전체 통과로 읽으면 안 된다.
#      기존 T3 partial fixture 는 content 에 "PASS" 부분문자열이 없어 negative check 를 잠그지 못한다.
mixed=$(mktemp) || exit 1
printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_R3","name":"Bash","input":{"command":"bash scripts/_internal/run-verification.sh 20260101-x"}}]}}' \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_R3","is_error":false,"content":"AC-1 VERIFY: PASS\nAC-2 VERIFY: PARTIAL — 1개 명령 whitelist 미통과"}]}}' > "$mixed"
_verify_exec_evidence "$mixed"; ck "T10 PASS/PARTIAL 혼재 → 1 (negative check)" 1 $?
rm -f "$mixed"

# ── 멀티라인 command (실전 dogfooding 이 잡은 false-block) ─────────────────────
# Bash tool 의 command 는 흔히 멀티라인이다 (`cd <path>` 다음 줄에 러너). 러너 앵커의 선행자
# 문자클래스에 줄바꿈이 없으면 2번째 줄의 러너가 ^ 에도 [;&|(] 에도 안 걸려 **정직한 실행이
# 미인식 → deny** 된다. 줄바꿈은 셸에서 진짜 명령 구분자이므로 클래스에 포함되어야 옳다.
#   T11 = RED 드라이버(수정 전 rc=1) / T12·T13 = 앵커 의미 회귀 잠금(수정 전후 불변 rc=1)

# T11: 멀티라인 러너 호출 + 대응 tool_result 의 PASS → 0 (실행증거 인정)
mlrun=$(mktemp) || exit 1
printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_M1","name":"Bash","input":{"command":"cd /Users/x/proj\nbash scripts/_internal/run-verification.sh 20260101-x"}}]}}' \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_M1","is_error":false,"content":"VERIFY: PASS"}]}}' > "$mlrun"
_verify_exec_evidence "$mlrun"; ck "T11 멀티라인 러너(cd 후 다음 줄) → 0 (false-block 차단)" 0 $?
rm -f "$mlrun"

# T12: 멀티라인 echo 위장 — 줄바꿈 허용이 "아무 데나 있어도 됨"이 되면 여기서 뚫린다.
mlecho=$(mktemp) || exit 1
printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_M2","name":"Bash","input":{"command":"cd /x\necho \"ran pytest — VERIFY: PASS\""}}]}}' \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_M2","is_error":false,"content":"ran pytest — VERIFY: PASS"}]}}' > "$mlecho"
_verify_exec_evidence "$mlecho"; ck "T12 멀티라인 echo 위장 → 1 (앵커 의미 유지)" 1 $?
rm -f "$mlecho"

# T13: 멀티라인 주석 — 줄 첫 토큰이 '#' 이면 러너는 실행되지 않는다. 인식되면 안 된다.
mlcmt=$(mktemp) || exit 1
printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_M3","name":"Bash","input":{"command":"cd /x\n# bash scripts/_internal/run-verification.sh 20260101-x"}}]}}' \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_M3","is_error":false,"content":"VERIFY: PASS"}]}}' > "$mlcmt"
_verify_exec_evidence "$mlcmt"; ck "T13 멀티라인 주석 처리된 러너 → 1 (미실행)" 1 $?
rm -f "$mlcmt"

# ── run-all.sh 인식 (20260716 false-block — self-maintenance dogfooding 적발) ──
# 플러그인 자기 repo 작업에서 정식 검증 러너는 run-all.sh(전체 스위트)인데, 러너 클래스가
# run-verification.sh·pytest 류만 인식해 run-all 95/95 세션이 deny 됐다(BYPASS 강요 = 신호 희석).
# fix: 러너 클래스에 `bash \S*tests/run-all\.sh` 추가 + run-all.sh 가 성공 시 `VERIFY: PASS`
# (실패 시 `VERIFY: FAIL`) 토큰을 출력해 기존 토큰 계약으로 판정 (게이트 출력검사 로직 무변경).
#   T14 = RED 드라이버 / T15 = 좁은 앵커 잠금(tests/ 경로 밖 run-all 불인정) / T16 = 실패 토큰 대칭

# T14: run-all 실행 + FAIL=0 + PASS 토큰 → 0 (실행증거 인정)
rarun=$(mktemp) || exit 1
printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_RA1","name":"Bash","input":{"command":"bash scripts/tests/run-all.sh 2>&1 | tail -3"}}]}}' \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_RA1","is_error":false,"content":"==== run-all: suites PASS=95 FAIL=0 (total=95) ====\nVERIFY: PASS"}]}}' > "$rarun"
_verify_exec_evidence "$rarun"; ck "T14 run-all.sh 실행 + PASS 토큰 → 0 (false-block 해소)" 0 $?
rm -f "$rarun"

# T15: tests/ 경로 밖 run-all.sh — 러너 클래스는 \S*tests/run-all\.sh 로 좁힌다.
#      downstream repo 의 무관한 ./run-all.sh(배포 스크립트 등)가 우연히 토큰을 출력해도 불인정.
raout=$(mktemp) || exit 1
printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_RA2","name":"Bash","input":{"command":"bash ./run-all.sh"}}]}}' \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_RA2","is_error":false,"content":"VERIFY: PASS"}]}}' > "$raout"
_verify_exec_evidence "$raout"; ck "T15 tests/ 밖 run-all.sh → 1 (좁은 앵커)" 1 $?
rm -f "$raout"

# T16: run-all 실패 — suite FAIL>0 이면 run-all.sh 가 VERIFY: FAIL 을 출력한다. 출력에
#      PASS 문자열이 섞여 있어도(suite 케이스명 등) negative check 가 전체 불인정해야 한다.
rafail=$(mktemp) || exit 1
printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_RA3","name":"Bash","input":{"command":"bash scripts/tests/run-all.sh"}}]}}' \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_RA3","is_error":false,"content":"PASS T1.a something\n==== run-all: suites PASS=94 FAIL=1 (total=95) ====\nVERIFY: FAIL"}]}}' > "$rafail"
_verify_exec_evidence "$rafail"; ck "T16 run-all 실패(FAIL 토큰) → 1 (negative check)" 1 $?
rm -f "$rafail"

# T-fresh: 신선도 게이트 (20260717-exec-evidence-staleness — dogfood test1 FR-3 실측: 세션 초반
#   FR-2 의 VERIFY: PASS 가 윈도우·스코프 없이 세션 끝까지 만능 면제표가 되어, 이후 FID 의
#   미검증 implement 커밋 전부(서브에이전트 포함)를 열었다. friction 무흔적의 실물 원인)
#   규칙: 마지막 실행증거 **이후** 비-.specops Edit/Write/NotebookEdit/MultiEdit 가 있으면 stale → 1.
runner_ev='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_F1","name":"Bash","input":{"command":"bash scripts/_internal/run-verification.sh 20260101-x"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_F1","is_error":false,"content":"VERIFY: PASS"}]}}'
fr=$(mktemp) || exit 1
# T-fresh.a ★ 증거 후 코드 Edit → stale(1)
printf '%s\n' "$runner_ev" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_F2","name":"Edit","input":{"file_path":"src/app.ts","old_string":"a","new_string":"b"}}]}}' > "$fr"
_verify_exec_evidence "$fr"; ck "T-fresh.a ★ 증거 후 코드 Edit → 1 (stale)" 1 $?
# T-fresh.e ★ 증거 후 MultiEdit → stale(1) — R-5는 MultiEdit를 이미 감지하나 $lastedit 누락이 FN이던 구멍
printf '%s\n' "$runner_ev" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_F2e","name":"MultiEdit","input":{"file_path":"src/app.ts","edits":[]}}]}}' > "$fr"
_verify_exec_evidence "$fr"; ck "T-fresh.e ★ 증거 후 MultiEdit → 1 (stale)" 1 $?
# T-fresh.b 증거 후 .specops 아티팩트 Write 만 → 여전히 0 (정직 흐름: evidence.md 마무리)
printf '%s\n' "$runner_ev" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_F3","name":"Write","input":{"file_path":".specops/20260101-x/evidence.md","content":"x"}}]}}' > "$fr"
_verify_exec_evidence "$fr"; ck "T-fresh.b 증거 후 .specops Write → 0 (아티팩트 제외)" 0 $?
# T-fresh.c 코드 Edit 후 증거 (정상 순서: 수정→재검증) → 0
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_F4","name":"Edit","input":{"file_path":"src/app.ts","old_string":"a","new_string":"b"}}]}}' "$runner_ev" > "$fr"
_verify_exec_evidence "$fr"; ck "T-fresh.c Edit 후 증거(재검증 순서) → 0" 0 $?
# T-fresh.d 증거 후 Write(코드) → stale, 이후 재검증 → 다시 0 (최신 증거가 이김)
printf '%s\n' "$runner_ev" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_F5","name":"Write","input":{"file_path":"src/new.ts","content":"x"}}]}}' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_F6","name":"Bash","input":{"command":"bash scripts/_internal/run-verification.sh 20260101-x"}}]}}' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_F6","is_error":false,"content":"VERIFY: PASS"}]}}' > "$fr"
_verify_exec_evidence "$fr"; ck "T-fresh.d 수정 후 재검증 → 0 (최신 증거 우선)" 0 $?
rm -f "$fr"

# ── 백그라운드 실행 증거 인식 (20260807-bg-verify-evidence) ──
# 백그라운드 Bash 는 tool_result 가 실행 출력이 아니라 스텁이다. 실제 출력은 이후 Read 결과에만
# 있으므로, 스텁이 발급한 경로와 정확히 일치하는 Read 를 찾아 증거를 판정한다.
BGP='/private/tmp/claude-501/x/tasks/bg1.output'
BGSTUB="Command running in background with ID: bg1. Output is being written to: $BGP. You will be notified when it completes."

_mk_bg() {  # $1=출력파일 $2=Bash command $3=스텁 문구 $4=Read file_path $5=Read 결과
  printf '%s\n' \
    "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_B1\",\"name\":\"Bash\",\"input\":{\"command\":\"$2\"}}]}}" \
    "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"toolu_B1\",\"is_error\":false,\"content\":\"$3\"}]}}" \
    "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_B2\",\"name\":\"Read\",\"input\":{\"file_path\":\"$4\"}}]}}" \
    "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"toolu_B2\",\"is_error\":false,\"content\":\"$5\"}]}}" > "$1"
}

bgf=$(mktemp)

# T17 — 정직 bg 인정 (AC-1)
_mk_bg "$bgf" "bash scripts/tests/run-all.sh" "$BGSTUB" "$BGP" "==== run-all: suites PASS=130 FAIL=0 ====\\nVERIFY: PASS"
_verify_exec_evidence "$bgf"; ck "T17 bg 러너+Read 회수 → 0 (인정)" 0 $?

# T18 — 경로 불일치 거부 (AC-2): 임의 파일 Read 로는 안 열린다
_mk_bg "$bgf" "bash scripts/tests/run-all.sh" "$BGSTUB" "/tmp/other.output" "VERIFY: PASS"
_verify_exec_evidence "$bgf"; ck "T18 Read 경로 불일치 → 1 (임의 파일 불인정)" 1 $?

# T19 — 스텁 출처 구속 (AC-3): 러너 앵커에 안 걸리는 Bash 의 스텁 경로는 쓸 수 없다
_mk_bg "$bgf" "echo hello" "$BGSTUB" "$BGP" "VERIFY: PASS"
_verify_exec_evidence "$bgf"; ck "T19 비러너 Bash 스텁 → 1 (앵커 구속)" 1 $?

# T20 — bg 후 코드 Edit → stale (AC-4): staleness 는 러너 Bash 인덱스 기준
printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_B1","name":"Bash","input":{"command":"bash scripts/tests/run-all.sh"}}]}}' \
  "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"toolu_B1\",\"is_error\":false,\"content\":\"$BGSTUB\"}]}}" \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_BE","name":"Edit","input":{"file_path":"src/app.sh"}}]}}' \
  "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_B2\",\"name\":\"Read\",\"input\":{\"file_path\":\"$BGP\"}}]}}" \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_B2","is_error":false,"content":"VERIFY: PASS"}]}}' > "$bgf"
_verify_exec_evidence "$bgf"; ck "T20 bg 후 코드 Edit → 1 (stale · Bash 인덱스 기준)" 1 $?

# T21 — 스텁 문구 불일치 → rc=1 (rc=2 면 FAIL): 경로 추출 가드 누락 회귀 잠금 (AC-R-2)
#   가드 없이 split 하면 jq 가 rc=5 로 죽어 rc=2(fail-open)가 된다 — 게이트 무음 해제 방향.
_mk_bg "$bgf" "bash scripts/tests/run-all.sh" "Output written to: $BGP" "$BGP" "VERIFY: PASS"
_verify_exec_evidence "$bgf"; ck "T21 스텁 문구 불일치 → 1 (rc=2 fail-open 금지)" 1 $?

# T22 — bg Read 결과 PASS/PARTIAL 혼재 → 1 (FR-2 후반절)
#   기존 부정토큰 술어는 Bash 결과에만 걸려 있어 Read 결과에 자동 적용되지 않는다(T10 의 bg 판).
_mk_bg "$bgf" "bash scripts/tests/run-all.sh" "$BGSTUB" "$BGP" "VERIFY: PASS\\nVERIFY: PARTIAL"
_verify_exec_evidence "$bgf"; ck "T22 bg Read PASS/PARTIAL 혼재 → 1" 1 $?

rm -f "$bgf"

# T23 — verifying-evidence-ko SKILL.md 에 포그라운드 timeout 지침 (AC-6)
_VE_SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/skills/verifying-evidence-ko/SKILL.md"
if grep -qF 'timeout' "$_VE_SKILL" && grep -qF '포그라운드' "$_VE_SKILL"; then
  ck "T23 SKILL.md 포그라운드 timeout 지침" 0 0
else
  ck "T23 SKILL.md 포그라운드 timeout 지침" 0 1
fi

# T24 — bg 안내 경로가 staleness 와 정렬 (Phase C Important 1)
#   안내는 판정과 같은 기준을 써야 한다. bg 기동 후 코드 편집이 있으면 안내대로 Read 해도
#   stale 로 재차단된다 — "Read 하면 인정됩니다" 가 거짓이 되고 BYPASS 스파이럴 조건이 된다.
_stf=$(mktemp)
_STUB2="Command running in background with ID: z. Output is being written to: /tmp/z.out. You will be notified."
jq -nc --arg c 'bash scripts/tests/run-all.sh' '{type:"assistant",message:{content:[{type:"tool_use",id:"b1",name:"Bash",input:{command:$c}}]}}' > "$_stf"
jq -nc --arg o "$_STUB2" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"b1",is_error:false,content:$o}]}}' >> "$_stf"
if [ -n "$(_bg_pending_path "$_stf")" ]; then ck "T24a 편집 없음 → 안내 경로 반환" 0 0; else ck "T24a 편집 없음 → 안내 경로 반환" 0 1; fi
jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"e1",name:"Edit",input:{file_path:"src/app.sh"}}]}}' >> "$_stf"
if [ -z "$(_bg_pending_path "$_stf")" ]; then ck "T24b bg 후 코드편집 → 안내 억제(과약속 금지)" 0 0; else ck "T24b bg 후 코드편집 → 안내 억제(과약속 금지)" 0 1; fi
# T24c — MultiEdit 도 동일 기준 (판정↔안내 정렬)
_stf2=$(mktemp)
jq -nc --arg c 'bash scripts/tests/run-all.sh' '{type:"assistant",message:{content:[{type:"tool_use",id:"b1",name:"Bash",input:{command:$c}}]}}' > "$_stf2"
jq -nc --arg o "$_STUB2" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"b1",is_error:false,content:$o}]}}' >> "$_stf2"
jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"m1",name:"MultiEdit",input:{file_path:"src/app.sh",edits:[]}}]}}' >> "$_stf2"
if [ -z "$(_bg_pending_path "$_stf2")" ]; then ck "T24c bg 후 MultiEdit → 안내 억제" 0 0; else ck "T24c bg 후 MultiEdit → 안내 억제" 0 1; fi
rm -f "$_stf" "$_stf2"

# T64 — 확장 러너 6종이 인정된다 (AC-1, FID 20260907-false-deny-anchor-scope)
_t64d=$(mktemp -d)
_mk_run_tx() {  # $1=명령 · $2=tool_result 출력 → transcript 경로를 stdout 으로
  local f="$_t64d/tx-$RANDOM.jsonl"
  jq -nc --arg c "$1" '{type:"assistant",message:{content:[{type:"tool_use",id:"r1",name:"Bash",input:{command:$c}}]}}' > "$f"
  jq -nc --arg o "$2" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"r1",is_error:false,content:$o}]}}' >> "$f"
  printf '%s' "$f"
}
for _c in 'poetry run pytest tests/ -q' 'uv run pytest -q' 'pnpm --dir frontend test chart' \
          'pnpm --filter web test' 'npx vitest run' 'pnpm exec vitest'; do
  _tx=$(_mk_run_tx "$_c" "1 passed
VERIFY: PASS")
  _verify_exec_evidence "$_tx"; ck "T64 확장 러너 인정: $_c" 0 $?
done
rm -rf "$_t64d"

# T25 — 앵커 리터럴 재등장 감지 (변수화 역행 잠금)
#   ★ 종전 T25("리터럴 4사본이 서로 같은가")의 **이관**이지 완화가 아니다.
#   종전 형태는 리터럴이 4개일 때만 성립했고, 변수화로 0개가 되면 조건 자체가 사라진다.
#   조건을 새 shape 에 맞춰 낮추면 잠금이 증발한다 — 잠글 대상을 둘로 나눠 옮겼다:
#     · 계열 간 커버리지 동치 → T70 (AC-3)
#     · 사본 재발생 방지      → 이 검사
#   ★ `-eq 4` 로 조인다 — `-ge 3` 이면 **사이트 1곳이 조용히 사라져도** 통과한다.
#     사이트를 의도적으로 늘리거나 줄이면 이 기대값을 함께 갱신하라는 뜻이다.
_GL="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/hooks/governance-lib.sh"
_anchor_sites() {   # T25·T38 공용 — 같은 명제를 두 번 쓰지 않는다
  _lit_n=$(grep -c 'select(\.cmd | test("' "$_GL" || true)
  _var_n=$(grep -c 'select(\.cmd | test($anchor))' "$_GL" || true)
}
_anchor_sites
if [ "$_lit_n" -eq 0 ] && [ "$_var_n" -eq 4 ]; then
  ck "T25 앵커 리터럴 0 · 변수 참조 4곳 (변수화 역행 잠금)" 0 0
else
  echo "  (리터럴 잔존=$_lit_n · 변수 참조=$_var_n — 리터럴 0 · 참조 정확히 4 여야 함)"
  echo "  → 앵커를 다시 리터럴로 인라인하면 사본이 함께 낡는 결함이 재발한다."
  ck "T25 앵커 리터럴 0 · 변수 참조 4곳 (변수화 역행 잠금)" 0 1
fi


# ── T26~T27: 선언 명령 추출 (FID 20260809-runner-anchor-downstream) ──
#   ★ 라벨은 T26 부터다 — 위에 T1~T25 가 이미 있다.
_mk_tasks() {   # $1=디렉터리, $2..=test_command 값들
  local d="$1"; shift; mkdir -p "$d"
  { echo '## 의존 그래프'; echo '```yaml'; echo 'tasks:'
    local i=0
    for c in "$@"; do i=$((i+1))
      echo "  - id: T$i"; echo "    test_command: \"$c\""; echo "    depends_on: []"
    done
    echo '```'; } > "$d/tasks.md"
}

# T26 — whitelist 통과 명령만 추출된다
_t26=$(mktemp -d)
_mk_tasks "$_t26" "bash scripts/tests/frontend.sh" "grep -q token file.js" "npx vitest run x"
_got=$(_extract_declared_cmds "$_t26/tasks.md")
_n=$(printf '%s' "$_got" | jq 'length' 2>/dev/null || echo -1)
[ "$_n" = "2" ] \
  && ck "T26 whitelist 통과분만 추출 (2/3)" 0 0 \
  || ck "T26 whitelist 통과분만 추출 — 실제 ${_n}건(기대 2)" 0 1
rm -rf "$_t26"

# T27 — tasks.md 부재·test_command 0건이면 빈 배열 (기존 동작 보존)
_t27=$(mktemp -d)
_e=$(_extract_declared_cmds "$_t27/nope.md")
[ "$_e" = "[]" ] && ck "T27 tasks.md 부재 → 빈 배열" 0 0 || ck "T27 tasks.md 부재 → 빈 배열(실제 '$_e')" 0 1
rm -rf "$_t27"


# ── T28~T43: 선언 명령 앵커 분기 ($declhit) ──
#   ★ 헬퍼는 jq 로 만든다 — printf 로 JSON 을 조립하면 heredoc·따옴표 픽스처(T35)에서
#     이스케이프가 어긋나 어서션이 조용히 공허해진다.
_decl_tx() {   # $1=출력파일, $2=명령, $3=결과내용, $4=is_error(기본 false)
  jq -nc --arg c "$2" '{type:"assistant",message:{role:"assistant",content:[
      {type:"tool_use",id:"toolu_D1",name:"Bash",input:{command:$c}}]}}'  > "$1"
  jq -nc --arg o "$3" --argjson e "${4:-false}" '{type:"user",message:{role:"user",content:[
      {type:"tool_result",tool_use_id:"toolu_D1",is_error:$e,content:$o}]}}' >> "$1"
}
_D=$(mktemp -d); _mk_tasks "$_D" "bash scripts/tests/frontend.sh"
: > "$_D/evidence.md"
_tx=$(mktemp)

# T28 — 선언 러너 실행 + 러너 성공 → 인정 (AC-1·AC-11)
#   `PASS 12/12` 는 `VERIFY: PASS` 를 포함하지 않는다 — 이게 downstream 의 실제 모습이고
#   본 FID 의 존재 이유다. 기존 술어를 그대로 쓰면 이 어서션이 영영 통과할 수 없다.
_decl_tx "$_tx" "bash scripts/tests/frontend.sh" "PASS 12/12"
_verify_exec_evidence "$_tx" "$_D"; ck "T28 선언 downstream 러너 → 0 (AC-1·11)" 0 $?

# T29 — 선언되지 않은 명령은 불인정 (AC-2)
_decl_tx "$_tx" "bash scripts/tests/other.sh" "PASS 12/12"
_verify_exec_evidence "$_tx" "$_D"; ck "T29 미선언 명령 → 1 (AC-2)" 1 $?

# T30 — 정규식 취급 금지: `.` 가 임의 문자로 매치되면 안 된다 (AC-8)
_decl_tx "$_tx" "bash scripts/tests/frontendXsh" "PASS 12/12"
_verify_exec_evidence "$_tx" "$_D"; ck "T30 . 를 임의문자로 매치하지 않음 → 1 (AC-8)" 1 $?

# T31 — 선언 명령의 주석 위장 (AC-5)
_decl_tx "$_tx" "# bash scripts/tests/frontend.sh" "PASS 12/12"
_verify_exec_evidence "$_tx" "$_D"; ck "T31 선언 명령 주석 위장 → 1 (AC-5)" 1 $?

# T32 — 선언 명령의 echo 위장 (AC-5)
_decl_tx "$_tx" 'echo "bash scripts/tests/frontend.sh"' "PASS 12/12"
_verify_exec_evidence "$_tx" "$_D"; ck "T32 선언 명령 echo 위장 → 1 (AC-5)" 1 $?

# T33 — 꼬리에 실패 요약이 있으면 불인정 (AC-11·AC-14 부정)
_decl_tx "$_tx" "bash scripts/tests/frontend.sh" "PASS T1 ok
FAIL T2 broken
PASS=11 FAIL=1"
_verify_exec_evidence "$_tx" "$_D"; ck "T33 꼬리 실패 요약 → 1 (AC-11·14)" 1 $?

# T34 — is_error:true 는 불인정 (AC-11 부정) ★ false-open 방지의 본체
#   $res 가 is_error 를 걸러내므로 조인이 빈 문자열이 된다. 빈 문자열엔 실패 토큰이 없어
#   결과 존재 가드가 없으면 **성공으로 오판**한다. 이 어서션이 그 구멍을 잠근다.
_decl_tx "$_tx" "bash scripts/tests/frontend.sh" "boom" true
_verify_exec_evidence "$_tx" "$_D"; ck "T34 is_error:true → 1 (AC-11)" 1 $?

# T35 — heredoc 본문 위장 차단 (AC-12)
#   `evidence.md` 를 heredoc 으로 쓰는 것은 정직한 흐름이다. 술어를 완화한 이상 이 경로가
#   열리면 "문서 작성이 게이트를 연다". `<<` 포함 시 선언 분기를 통째로 skip 한다.
_decl_tx "$_tx" "cat > .specops/x/evidence.md <<DOC
bash scripts/tests/frontend.sh
DOC" "PASS 12/12"
_verify_exec_evidence "$_tx" "$_D"; ck "T35 heredoc 본문 위장 → 1 (AC-12)" 1 $?

# T39 — ★ 규약 성공 요약 `PASS=N FAIL=0` 은 **인정**되어야 한다 (AC-14)
#   templates/dispatch-context.md 가 downstream 러너의 성공 출력을 이 형태로 규정한다.
#   전체 출력 스캔이면 FAIL 문자열 때문에 차단돼 이 FID 가 고치려는 병을 재생산한다.
_decl_tx "$_tx" "bash scripts/tests/frontend.sh" "==== Results: PASS=26 FAIL=0 ===="
_verify_exec_evidence "$_tx" "$_D"; ck "T39 규약 성공요약 FAIL=0 → 0 (AC-14)" 0 $?

# T40 — ★ 본문 중간의 실패 어휘는 인정을 막지 않는다 (AC-14)
#   실패 처리를 검증하는 스위트는 이름에 실패 어휘가 들어간다(이 파일 자신이 그렇다).
#   ★ 픽스처 주의: 그 줄들을 **꼬리 3줄 밖**에 둔다. 안에 두면 차단되는 것이 정상 동작이며
#     (§7-9 한계), 실제 러너는 요약을 마지막에 찍으므로 이 배치가 현실적이다.
_decl_tx "$_tx" "bash scripts/tests/frontend.sh" "PASS T16 run-all 실패(FAIL 토큰) → 1
PASS T21 스텁 문구 불일치 → 1 (rc=2 fail-open 금지)
PASS T9 is_error 결과 → 1 (에러결과 불인정)
ok 12 tests
done
PASS=30 FAIL=0"
_verify_exec_evidence "$_tx" "$_D"; ck "T40 설명 줄 실패어휘 → 0 (AC-14)" 0 $?

# T41 — ★ 백그라운드 스텁은 불인정 (AC-15) — false-open 잠금
#   러너를 bg 로 띄우면 결과가 스텁이라 실패 토큰이 없다. 막지 않으면 "띄우고 결과를
#   보지도 않은 채 커밋" 이 열린다. 기존 5종은 VERIFY: PASS 양성 요구라 자동 탈락한다.
_decl_tx "$_tx" "bash scripts/tests/frontend.sh" "Command running in background with ID: bash_1
Output is being written to: /tmp/x.log"
_verify_exec_evidence "$_tx" "$_D"; ck "T41 bg 스텁 → 1 (AC-15)" 1 $?

# T42 — 한국어 0-카운트 성공 요약은 인정 (AC-16)
_decl_tx "$_tx" "bash scripts/tests/frontend.sh" "테스트 12건 성공, 실패 0"
_verify_exec_evidence "$_tx" "$_D"; ck "T42 한국어 실패 0 → 0 (AC-16)" 0 $?

# T43 — 한국어 실패 요약은 불인정 (AC-16 부정)
_decl_tx "$_tx" "bash scripts/tests/frontend.sh" "테스트 9건 성공, 실패 3건"
_verify_exec_evidence "$_tx" "$_D"; ck "T43 한국어 실패 3건 → 1 (AC-16)" 1 $?

# T36 — 창 한정: evidence.md 부재면 신규 경로 비활성 (AC-7)
rm -f "$_D/evidence.md"
_decl_tx "$_tx" "bash scripts/tests/frontend.sh" "PASS 12/12"
_verify_exec_evidence "$_tx" "$_D"; ck "T36 implement 창(evidence 부재) → 1 (AC-7)" 1 $?
rm -rf "$_D"

# T37 — 다중 선언 중 **하나만** 실행해도 인정 (AC-10, clarify Q1)
#   전부 요구하면 선언 5~11개인 FID 7건이 현행과 똑같이 막혀 이 FID 가 무효가 된다.
_M=$(mktemp -d); _mk_tasks "$_M" "bash scripts/tests/frontend.sh" "npx vitest run" "cargo test"
: > "$_M/evidence.md"
_decl_tx "$_tx" "npx vitest run" "Tests  12 passed"
_verify_exec_evidence "$_tx" "$_M"; ck "T37 다중 선언 중 1개 실행 → 0 (AC-10)" 0 $?
rm -f "$_tx"; rm -rf "$_M"

# T38 — AC-13: 앵커 배선 무수정 (T25 와 동일 명제 — 헬퍼 공유)
#   ★ 종전엔 "리터럴 3곳 이상 · 고유 1" 이었다. 변수화로 리터럴이 0 이 되므로
#   T25 와 같은 방식으로 이관한다. 두 검사가 같은 헬퍼를 쓰는 이유는,
#   1회차·2회차 리뷰가 드러낸 결함이 정확히 "같은 명제를 여러 곳에 복제해 함께 낡은 것" 이기 때문이다.
_anchor_sites
if [ "$_lit_n" -eq 0 ] && [ "$_var_n" -eq 4 ]; then
  ck "T38 선언 경로 추가 후에도 앵커 배선 유지 — 변수 참조 4곳 (AC-13)" 0 0
else
  echo "  (리터럴 잔존=$_lit_n · 변수 참조=$_var_n — 신규 경로가 기존 배선을 건드렸다)"
  ck "T38 선언 경로 추가 후에도 앵커 배선 유지 — 변수 참조 4곳 (AC-13)" 0 1
fi


# ── T44: whitelist 두 벌 drift 잠금 (AC-R-2) ──
#   선언 경로와 receipt 경로가 같은 whitelist 를 쓰는데 한쪽만 조여지면 게이트가 조용히
#   넓어진다. propagation edge 가 본 잠금이고, 여기서는 배선 실재만 확인한다.
grep -q '_extract_declared_cmds' "$PLUGIN/hooks/governance-lib.sh" \
  && grep -q 'test_command' "$PLUGIN/hooks/governance-lib.sh" \
  && grep -q 'declared-testcmd-anchor' "$PLUGIN/scripts/_internal/propagation-matrix.jsonl" \
  && ck "T44 선언 추출 배선 + propagation 잠금 존재 (AC-R-2)" 0 0 \
  || ck "T44 선언 추출 배선 또는 propagation 잠금 부재 (AC-R-2)" 0 1


# ── T45~T48: 인용 멀티라인·행연속 위장 차단 (Phase C Critical — 20260809) ──
#   heredoc 가드(T35)가 막으려던 "문서 작성이 게이트를 연다" 의 미봉합 변종이다.
#   Bash cmd 의 **따옴표 문자열 내부** 실개행 줄이 선언 명령과 같으면, 실행 없이 열렸다.
#   규칙: 매칭 줄 **앞** 텍스트의 따옴표 개수가 홀수면 그 줄은 문자열 내부 → skip.
#         앞줄이 `\` 로 끝나면 그 줄은 명령 시작이 아니라 인자 연속 → skip.
_D2=$(mktemp -d); _mk_tasks "$_D2" "bash scripts/tests/frontend.sh"
: > "$_D2/evidence.md"
_tx2=$(mktemp)

# T45 — echo 인용 멀티라인 위장 (Phase C 프로브 P1)
_decl_tx "$_tx2" 'echo "검증 노트
bash scripts/tests/frontend.sh
끝" > notes.md' ""
_verify_exec_evidence "$_tx2" "$_D2"; ck "T45 echo 인용 멀티라인 위장 → 1 (Phase C C-1)" 1 $?

# T46 — git commit 메시지 본문 언급 (Phase C 프로브 P2)
_decl_tx "$_tx2" 'git commit -m "fix: 수정

bash scripts/tests/frontend.sh 로 검증함"' ""
_verify_exec_evidence "$_tx2" "$_D2"; ck "T46 commit 메시지 본문 언급 → 1 (Phase C C-1)" 1 $?

# T47 — 백슬래시 행연속 (매칭 줄이 명령 시작이 아님)
_decl_tx "$_tx2" 'true \
bash scripts/tests/frontend.sh' "PASS 12/12"
_verify_exec_evidence "$_tx2" "$_D2"; ck "T47 백슬래시 행연속 → 1 (Phase C C-1)" 1 $?

# T48 — ★ 정직한 멀티라인은 그대로 인정 (과차단 방지 — 이 가드의 대칭 잠금)
#   `cd <path>` 다음 줄에 러너는 실사용 지배 패턴이다(governance-lib:164 주석 근거).
#   인용도 행연속도 없으므로 통과해야 한다.
_decl_tx "$_tx2" 'cd /repo
bash scripts/tests/frontend.sh' "PASS 12/12"
_verify_exec_evidence "$_tx2" "$_D2"; ck "T48 정직한 cd+러너 멀티라인 → 0 (과차단 방지)" 0 $?
rm -f "$_tx2"; rm -rf "$_D2"

# T49 — whitelist 세 벌 byte-identity 잠금 (Phase C Important 1 · 20260903 3사본 확장)
#   propagation edge 는 `test_command` 문자열 존재만 본다 — 한쪽만 조여지는 drift 를
#   자동으로 못 잡는다. T25 방식으로 **패턴 자체**의 동일성을 잠근다.
#   ★ 20260903: 종전엔 gl·rc 두 벌만 비교해 **run-verification.sh 사본의 drift 가 무음**이었다
#     (FID 20260903-runner-whitelist-prefix — 세 벌이 바이트 동일해야 게이트가 대칭이다).
#     이 잠금은 "사본끼리 어긋남"을 잡고, "셋을 함께 되돌림"은 propagation 원장
#     `runner-whitelist-prefix` 레코드가 잡는다 — 둘은 상보적이다.
_p_gl=$(grep -oE "\^\(cd\[\[:blank:\]\]\+.*\)\\\$" "$PLUGIN/hooks/governance-lib.sh" | head -1)
_p_rc=$(grep -oE "\^\(cd\[\[:blank:\]\]\+.*\)\\\$" "$PLUGIN/scripts/_internal/record-task-receipt.sh" | head -1)
_p_rv=$(grep -oE "\^\(cd\[\[:blank:\]\]\+.*\)\\\$" "$PLUGIN/scripts/_internal/run-verification.sh" | head -1)
if [ -n "$_p_gl" ] && [ "$_p_gl" = "$_p_rc" ] && [ "$_p_gl" = "$_p_rv" ]; then
  ck "T49 whitelist 패턴 byte-identity 3사본 (drift 잠금)" 0 0
else
  echo "  (gl=${#_p_gl} · rc=${#_p_rc} · rv=${#_p_rv} — 세 벌이 어긋났다)"
  ck "T49 whitelist 패턴 byte-identity 3사본 (drift 잠금)" 0 1
fi


# ── T50~T53: 인용 상태 판정 (Phase C 2회차 Critical — 20260809) ──
#   따옴표 **개수 패리티**로 "문자열 내부" 를 판정하던 것이 양방향으로 틀렸다(실측 반증).
#   `\"` 이스케이프·혼합 인용이 카운트를 오염시켜 **false-open** 이 났고(P8·P9·P10),
#   겹따옴표 안 아포스트로피는 **false-block** 을 냈다(P11 — `Don't` 은 흔한 표면).
#   패리티 대신 **인용 상태기계**로 앞 텍스트를 훑어 "문자열이 열린 채인가" 를 판정한다.
_D3=$(mktemp -d); _mk_tasks "$_D3" "bash scripts/tests/frontend.sh"
: > "$_D3/evidence.md"
_tx3=$(mktemp)

# T50 — 이스케이프된 겹따옴표가 든 위장 (패리티는 짝수로 오산했다)
_decl_tx "$_tx3" 'echo "note \" x
bash scripts/tests/frontend.sh
end" > f.md' ""
_verify_exec_evidence "$_tx3" "$_D3"; ck "T50 이스케이프 따옴표 위장 → 1 (Phase C2 C-1)" 1 $?

# T51 — 혼합 인용 위장 (홑 안의 겹따옴표가 카운트를 오염시켰다)
_decl_tx "$_tx3" "echo 'x \"y' \"a
bash scripts/tests/frontend.sh" ""
_verify_exec_evidence "$_tx3" "$_D3"; ck "T51 혼합 인용 위장 → 1 (Phase C2 C-1)" 1 $?

# T52 — commit 메시지 + 이스케이프 따옴표 (T46 의 실전 변종)
_decl_tx "$_tx3" 'git commit -m "fix: \" 인용 처리

bash scripts/tests/frontend.sh 로 검증"' ""
_verify_exec_evidence "$_tx3" "$_D3"; ck "T52 commit+이스케이프 위장 → 1 (Phase C2 C-1)" 1 $?

# T53 — 인용을 포함한 앞줄은 **불인정**(미탐 — 안전 방향, 20260809 Phase C3 계약 변경)
#   종전엔 인용 상태기계로 "문자열이 열렸나" 를 판정했는데, 셸 인용은 정규 파싱이 불가해
#   라운드마다 새 우회가 나왔다(패리티 → 상태기계 → ANSI-C·$()·백틱). 쫓기를 그만두고
#   **선행 줄을 안전 화이트리스트로 좁힌다** — 빈 줄·`cd <경로>`·`set -eu`·`export X=Y` 만.
#   그 밖은 전부 skip 이라 인용·치환·백틱이 무엇을 하든 **구성상 열 수 없다**.
#   대가: 아래처럼 앞줄에 echo 가 섞인 정직한 실행도 미인식된다. 사용자는 러너를 단독
#   실행하면 열린다(현행 BYPASS 와 동등) — 미탐 방향이라 수용한다.
_decl_tx "$_tx3" "echo \"Don't forget\" && cd /repo
bash scripts/tests/frontend.sh" "PASS 12/12"
_verify_exec_evidence "$_tx3" "$_D3"; ck "T53 인용 섞인 앞줄 → 1 (안전 화이트리스트 밖)" 1 $?

# T54~T56 — 셸 인용 컨텍스트 3종 위장 차단 (Phase C3 Critical)
#   상태기계는 ANSI-C·$()·백틱에서 **닫힘으로 오판**해 false-open 했다(실측 3/3).
#   화이트리스트는 이 줄들이 애초에 `cd|set|export` 가 아니라 통째로 막는다.
_decl_tx "$_tx3" "echo \$'note \\'
bash scripts/tests/frontend.sh
end' > f.md" ""
_verify_exec_evidence "$_tx3" "$_D3"; ck "T54 ANSI-C 인용 위장 → 1 (Phase C3 C-1)" 1 $?

_decl_tx "$_tx3" 'echo "$(echo "
bash scripts/tests/frontend.sh
")" > f.md' ""
_verify_exec_evidence "$_tx3" "$_D3"; ck "T55 \$() 중첩 인용 위장 → 1 (Phase C3 C-1)" 1 $?

_decl_tx "$_tx3" 'echo "`echo "
bash scripts/tests/frontend.sh
`" > f.md' ""
_verify_exec_evidence "$_tx3" "$_D3"; ck "T56 백틱 중첩 인용 위장 → 1 (Phase C3 C-1)" 1 $?

# T57 — ★ 안전 접두는 그대로 인정 (과차단 방지 대칭 — 화이트리스트가 공허하지 않음)
_decl_tx "$_tx3" "set -eu
export CI=1
cd /repo

bash scripts/tests/frontend.sh" "PASS 12/12"
_verify_exec_evidence "$_tx3" "$_D3"; ck "T57 set/export/cd 접두 → 0 (과차단 방지)" 0 $?

# T58 — ★ `cd "` 처럼 **열린 따옴표만 있는 앞줄**은 불인정 (화이트리스트 완화 잠금)
#   경로 문자셋에 따옴표를 넣고 싶은 유혹이 있다(`cd "/path with space"` 미탐 때문).
#   넣으면 `cd "` 한 줄이 "안전" 이 되고 다음 줄이 문자열 내부가 되어 게이트가 열린다.
#   이 어서션이 그 완화를 잠근다 — 변이 M13 이 격추함을 실증.
_decl_tx "$_tx3" 'cd "
bash scripts/tests/frontend.sh
" > f.md' ""
_verify_exec_evidence "$_tx3" "$_D3"; ck "T58 cd + 열린 따옴표 앞줄 → 1 (완화 잠금)" 1 $?
rm -f "$_tx3"; rm -rf "$_D3"


# ── T59~T62: env 접두 러너 인식 (FID 20260902-runner-anchor-env-prefix) ──
#   왜: 앵커가 `KEY=VALUE` 접두를 못 읽어 정직한 검증 실행이 deny 됐다(false-deny →
#   BYPASS 관성). T59·T60 = RED 드라이버 / T61 = 기존 인정형 무손상 / T62 = 위조 잠금.

_verify_exec_evidence "$FIX/exec-evidence-envprefix.jsonl"
ck "T59 env 접두 1개 러너 → 0 (false-deny 해소)" 0 $?

_verify_exec_evidence "$FIX/exec-evidence-envprefix-multi.jsonl"
ck "T60 env 접두 다중 + 쌍따옴표 값 → 0" 0 $?

# T61 — 기존 인정 형태 4종 무손상 (무접두 · 파이프 · cd&& · 명령치환)
_t61=$(mktemp); _t61rc=0
for _c in 'bash scripts/tests/run-all.sh' \
          'bash scripts/tests/run-all.sh | tail -20' \
          'cd /x && bash scripts/tests/run-all.sh' \
          'out=$(bash scripts/tests/run-all.sh)'; do
  jq -nc --arg c "$_c" '{type:"assistant",message:{content:[{type:"tool_use",id:"toolu_k",name:"Bash",input:{command:$c}}]}}' > "$_t61"
  jq -nc '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"toolu_k",content:"VERIFY: PASS"}]}}' >> "$_t61"
  _verify_exec_evidence "$_t61" || _t61rc=1
done
rm -f "$_t61"
ck "T61 기존 인정 4형태 무손상 → 0" 0 $_t61rc

# T62 — env 접두 위장 차단: `echo` 는 `=` 가 없어 반복군이 0회 매칭되고 그 자리에서
#   `bash` 를 요구하는데 `echo` 라 불일치한다. 넓히기가 위조를 통과시키지 않는 증거.
_t62=$(mktemp)
jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"toolu_f",name:"Bash",input:{command:"echo SPECOPS=1 bash scripts/tests/run-all.sh"}}]}}' > "$_t62"
jq -nc '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"toolu_f",content:"VERIFY: PASS"}]}}' >> "$_t62"
_verify_exec_evidence "$_t62"; _t62rc=$?
rm -f "$_t62"
ck "T62 env 접두 위장(echo) → 1 (앵커 의미 유지)" 1 $_t62rc

# T63 — 비-bash 러너 + env 접두 (Phase C I-1: 커버리지 공백)
#   왜: 반복군은 6종 러너 대안 전부에 걸리는데 그 **범위**를 잠그는 것이 없었다. 반복군을
#   `bash` 분기 안으로만 옮기면 `CI=true npm test` 류가 조용히 false-deny 로 되돌아가는데
#   스위트 69/69 PASS · 원장 0/4 FAIL 로 아무도 못 본다(Phase C 실측 N5). 하필 이 집단이
#   20260809-runner-anchor-downstream 이 "외부 4개 프로젝트 BYPASS 77건" 근거로 삼은
#   downstream 러너다 — 고치려던 병이 그 집단에서 무음 재발한다.
_t63=$(mktemp); _t63rc=0
for _c in 'CI=true npm test' \
          'SPECOPS=1 pytest -q' \
          'GOFLAGS=-count=1 go test ./...' \
          'RUST_BACKTRACE=1 cargo test'; do
  jq -nc --arg c "$_c" '{type:"assistant",message:{content:[{type:"tool_use",id:"toolu_n",name:"Bash",input:{command:$c}}]}}' > "$_t63"
  jq -nc '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"toolu_n",content:"VERIFY: PASS"}]}}' >> "$_t63"
  _verify_exec_evidence "$_t63" || _t63rc=1
done
rm -f "$_t63"
ck "T63 비-bash 러너 4종 + env 접두 → 0 (범위 잠금)" 0 $_t63rc

# T70 — cross-family 커버리지 동치 (AC-3, FID 20260907-false-deny-anchor-scope)
#   왜 byte-identity 가 아닌가: whitelist(_extract_declared_cmds 의 `local pat=`) 는 `^…$`
#   전체일치이고 앵커는 줄시작 부분일치 + env 접두 반복군이다. 구조가 달라 T49 식 문자열
#   비교를 두 계열 사이에 걸 수 없다. 잠글 대상은 문자열이 아니라 **커버리지** 다.
#   검사 방향은 하나다 — "whitelist 허용 ∧ 앵커 불인정" 이 0건. 역방향(앵커 인정 ∧
#   whitelist 차단)은 정당한 비대칭이라 FAIL 로 세지 않는다.
_ROOT2="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
_FIX_CMDS="$_ROOT2/scripts/tests/fixtures/runner-commands.txt"
_wl_pat=$(grep -oE "\^\(cd\[\[:blank:\]\]\+.*\)\\\$" "$_ROOT2/hooks/governance-lib.sh" | head -1)
# ★ `:-` 로 받아 로컬에 고정한다 — 이 파일은 `set -u` 다. 앵커 변수가 없는(미구현) 트리에서
#   `${#_RUNNER_ANCHOR_PAT}` 를 직접 쓰면 unbound 로 **셸이 즉사**해 ck 가 아예 안 돌고
#   FAIL 줄조차 남지 않는다. 진단 문구와 jq 인자 모두 이 사본을 쓴다.
_anchor="${_RUNNER_ANCHOR_PAT:-}"
# ★ 빈 값 가드 — 둘 중 하나라도 비면 `grep -qE ""` 가 전건 매치하거나 jq test("") 가
#   전건 참이 되어 **T70 이 조용히 껍데기로 격하**된다. 이 FID 가 고치는 병과 동형이다.
if [ -z "$_wl_pat" ] || [ -z "$_anchor" ] || [ ! -r "$_FIX_CMDS" ]; then
  echo "  (whitelist 추출=${#_wl_pat}자 · 앵커 변수=${#_anchor}자 · fixture=$_FIX_CMDS)"
  echo "  → 판정기나 코퍼스를 못 읽으면 동치를 검사할 수 없다. 통과시키지 않는다."
  ck "T70 cross-family 커버리지 동치" 0 1
else
  _viol=0; _viol_list=""; _skipped=0; _checked=0
  while IFS= read -r _line; do
    case "$_line" in
      '#!skip'*) _skipped=$((_skipped+1)); echo "  (skip) ${_line#\#!skip }"; continue ;;
      ''|'#'*) continue ;;
    esac
    printf '%s' "$_line" | grep -qE "$_wl_pat" || continue        # whitelist 차단 → 대상 아님
    _checked=$((_checked+1))
    if ! printf '%s' "$_line" | jq -e --arg re "$_anchor" -Rr 'test($re)' >/dev/null 2>&1; then
      _viol=$((_viol+1)); _viol_list="$_viol_list
    - $_line"
    fi
  done < "$_FIX_CMDS"
  # 코퍼스가 통째로 비거나 whitelist 가 전건 차단하면 위반 0 이 자동 성립한다 — 그 통과는 무의미하다.
  #
  # ★ 왜 건수에 하한·상한을 거는가: `_checked`·`_skipped` 를 **찍기만 하면** 잠금이 우회된다.
  #   ① 비대칭 러너가 새로 나왔을 때 앵커를 넓히는 대신 `#!skip` 한 줄을 붙이면 T70 은 계속 green 이고
  #      사유는 한 번 출력되고 아무도 안 읽는다. ② 코퍼스가 17줄 줄어 1건만 남아도 위반 0 이라 통과한다.
  #   같은 파일 T25 가 `-ge 3` 대신 `-eq 4` 를 고른 이유("사이트 1곳이 조용히 사라져도 통과한다")가
  #   그대로 적용된다. 비대칭 경계인 이유:
  #     · `_checked -ge 18` — 코퍼스는 자유롭게 **늘 수** 있어야 한다(fixture 헤더의 "한 줄 추가"
  #       무마찰 계약). 줄어드는 것만 막는다. 18 = 현 코퍼스의 whitelist 통과 건수.
  #     · `_skipped -le 3`  — 새 무음 제외를 막는다. 미뤄둔 bash 계열 FID 가 착지하면 0 으로 **내려가고**
  #       그때도 통과한다. 3 = 현재 의도적 제외 건수.
  # ★ M-3(Phase C): 두 경계를 **한 곳**에서 선언한다. 조건절과 메시지에 각각 리터럴로 쓰면
  #   "두 숫자를 함께 고쳐라" 는 지시가 네 곳을 고치라는 뜻이 되고, 그때 한 곳이 빠진다.
  _T70_MIN_CHECKED=18   # fixture 유효 코퍼스 하한 (늘어나는 것은 자유, 줄면 FAIL)
  _T70_MAX_SKIP=3       # `#!skip` 상한 (bash 계열 FID 착지 시 0 으로 내려가도 통과)
  #   경계를 의도적으로 바꿀 땐 이 두 숫자를 함께 고치라는 뜻이다.
  if [ "$_checked" -eq 0 ]; then
    echo "  (검사 대상 0건 — fixture 가 비었거나 whitelist 가 전건 차단했다)"
    ck "T70 cross-family 커버리지 동치" 0 1
  elif [ "$_viol" -ne 0 ]; then
    echo "  ★ whitelist 는 실행을 허용하는데 앵커가 실행 사실을 인정하지 않는다 ($_viol 건):$_viol_list"
    echo "  → 정직하게 테스트를 돌린 사용자가 커밋에서 막힌다. 두 정규식의 커버리지를 맞추라."
    ck "T70 cross-family 커버리지 동치" 0 1
  elif [ "$_checked" -lt "$_T70_MIN_CHECKED" ] || [ "$_skipped" -gt "$_T70_MAX_SKIP" ]; then
    echo "  (검사 ${_checked}건 [하한 ${_T70_MIN_CHECKED}] · 의도적 제외 ${_skipped}건 [상한 ${_T70_MAX_SKIP}])"
    echo "  → 위반 0 이지만 코퍼스가 줄었거나 제외가 늘었다. 앵커를 넓히는 대신 #!skip 으로"
    echo "     덮으면 이 잠금이 껍데기가 된다. 경계를 바꿀 근거가 있으면 위 두 숫자를 함께 고쳐라."
    ck "T70 cross-family 커버리지 동치" 0 1
  else
    ck "T70 cross-family 커버리지 동치 (검사 ${_checked}건 · 위반 0 · 의도적 제외 ${_skipped}건)" 0 0
  fi
fi

# ── 파일 클래스 구분 (20260912-verify-stale-docs-scope) ──────────────────────
# 편집 이벤트 집계가 문서·저장소 밖 경로를 "코드 편집" 으로 세면, 문서 한 줄 수정이
# 실행증거를 stale 로 뒤집어 커밋을 막는다. 판정(_verify_exec_evidence)과
# 진단(_verify_stale_cause)이 **같은 기준**을 써야 deny 문안이 거짓 원인을 말하지 않는다.
# ★ 양성 대조군 쌍 필수: 문서/저장소밖 = 무효화 안 함 ∧ 런타임 = 무효화.
_cls=$(mktemp) || exit 1

# T-cls.a 문서 편집은 실행증거를 무효화하지 않는다 (AC-3)
printf '%s\n' "$runner_ev" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_D1","name":"Edit","input":{"file_path":"CHANGELOG.md","old_string":"a","new_string":"b"}}]}}' > "$_cls"
_verify_exec_evidence "$_cls"; ck "T-cls.a 문서 Edit → 0 (무효화 안 함)" 0 $?

# T-cls.b 런타임 .md 편집은 여전히 stale (양성 대조 — R-1 확대 방지)
printf '%s\n' "$runner_ev" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_D2","name":"Edit","input":{"file_path":"skills/foo/SKILL.md","old_string":"a","new_string":"b"}}]}}' > "$_cls"
_verify_exec_evidence "$_cls"; ck "T-cls.b 런타임 SKILL.md Edit → 1 (stale 유지)" 1 $?

# T-cls.c 저장소 밖 절대경로 편집은 무효화하지 않는다 (AC-4)
printf '%s\n' "$runner_ev" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_D3","name":"Edit","input":{"file_path":"/somewhere/else/plans/x.md","old_string":"a","new_string":"b"}}]}}' > "$_cls"
_verify_exec_evidence "$_cls"; ck "T-cls.c 저장소 밖 절대경로 Edit → 0" 0 $?

# T-cls.d 진단이 판정과 같은 기준 — 저장소 밖을 원인으로 지목하지 않는다 (AC-4 후반)
_cause=$(_verify_stale_cause "$_cls")
if [ -z "$_cause" ]; then ck "T-cls.d 진단이 저장소 밖을 지목하지 않음" 0 0
else ck "T-cls.d 진단이 저장소 밖을 지목하지 않음 (got: $_cause)" 0 1; fi

# T-cls.e 진단이 런타임 경로는 지목한다 (양성 대조)
printf '%s\n' "$runner_ev" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_D4","name":"Edit","input":{"file_path":"hooks/x.sh","old_string":"a","new_string":"b"}}]}}' > "$_cls"
_cause=$(_verify_stale_cause "$_cls")
case "$_cause" in
  stale*) ck "T-cls.e 진단이 런타임 경로를 지목" 0 0 ;;
  *)      ck "T-cls.e 진단이 런타임 경로를 지목 (got: '$_cause')" 0 1 ;;
esac
rm -f "$_cls"

# ── 편집 이벤트 **입력 스키마 변이** (Phase C C-1) ───────────────────────────
# NotebookEdit 의 입력 필드는 `notebook_path` 라 `.input.file_path` 가 없다. 종전 구현은 그런
# "경로 미상" 을 **저장소 밖과 같은 답**(세지 않음)으로 처리해 R-1 면제가 조용히 넓어졌다
# (실측: BASE rc=1 → HEAD rc=0). 경로를 모를 때는 **코드로 세는 것**이 fail-safe 다.
# ★ 저장소 밖(T-cls.c)은 rc=0 을 유지해야 한다 — 둘 다 코드로 만드는 수정은 AC-4 를 깨는 오답이다.
_sch=$(mktemp) || exit 1

printf '%s\n' "$runner_ev" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_N1","name":"Edit","input":{}}]}}' > "$_sch"
_verify_exec_evidence "$_sch"; ck "T-sch.a file_path 필드 부재 → 1 (경로 미상=코드, fail-safe)" 1 $?

printf '%s\n' "$runner_ev" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_N2","name":"NotebookEdit","input":{"notebook_path":"analysis.ipynb"}}]}}' > "$_sch"
_verify_exec_evidence "$_sch"; ck "T-sch.b NotebookEdit(notebook_path) → 1 (stale)" 1 $?

printf '%s\n' "$runner_ev" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_N3","name":"Edit","input":{"file_path":""}}]}}' > "$_sch"
_verify_exec_evidence "$_sch"; ck "T-sch.c file_path 빈 문자열 → 1 (경로 미상=코드)" 1 $?

# T-sch.d 진단도 같은 기준 — 경로 미상이면 지목은 하되 판정과 어긋나지 않아야 한다
printf '%s\n' "$runner_ev" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_N4","name":"NotebookEdit","input":{"notebook_path":"analysis.ipynb"}}]}}' > "$_sch"
_cause=$(_verify_stale_cause "$_sch")
case "$_cause" in
  stale*) ck "T-sch.d 진단이 경로 미상 편집을 지목" 0 0 ;;
  *)      ck "T-sch.d 진단이 경로 미상 편집을 지목 (got: '$_cause')" 0 1 ;;
esac
rm -f "$_sch"

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
