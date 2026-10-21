#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
FIXTURES="$PLUGIN/scripts/tests/governance/fixtures"
HOOK="$PLUGIN/hooks/posttool-governance.sh"

# T8.a R-1 트리거 → additionalContext + friction-log append
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
cp "$FIXTURES/transcripts/r1-commit-without-verify.jsonl" transcript.jsonl
stdin_json=$(jq -nc --arg tp "$tmp/transcript.jsonl" '{ session_id:"s1", transcript_path:$tp, hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:"git commit -m \"x\""}, tool_response:{} }')
out=$(echo "$stdin_json" | bash "$HOOK" 2>/dev/null); rc=$?
has_r1=$(echo "$out" | jq -e '.continue == true and (.additionalContext | contains("R-1"))' >/dev/null 2>&1 && echo 1 || echo 0)
log_path=".specops/20260424-newest-feature/friction-log.jsonl"
if [ "$rc" -eq 0 ] && [ "$has_r1" -eq 1 ] && [ -f "$log_path" ] && jq -e '.rule_id == "R-1"' "$log_path" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS T8.a R-1 additionalContext + append"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.a (rc=$rc has_r1=$has_r1 log=$(ls $log_path 2>/dev/null))"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T8.b 매칭 없음 → {continue:true} 만
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
sed 's/20260101-x/20260424-newest-feature/g' "$FIXTURES/transcripts/r1-commit-with-verify.jsonl" > transcript.jsonl   # 러너가 **이 샌드박스의 FID** 를 검증한 것으로 — 다른 FID 의 PASS 는 증거가 아니다
stdin_json=$(jq -nc --arg tp "$tmp/transcript.jsonl" '{ session_id:"s1", transcript_path:$tp, hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:"git commit -m \"x\""}, tool_response:{} }')
out=$(echo "$stdin_json" | bash "$HOOK" 2>/dev/null); rc=$?
has_context=$(echo "$out" | jq -e 'has("additionalContext")' >/dev/null 2>&1 && echo 1 || echo 0)
continue_ok=$(echo "$out" | jq -e '.continue == true' >/dev/null 2>&1 && echo 1 || echo 0)
if [ "$rc" -eq 0 ] && [ "$continue_ok" -eq 1 ] && [ "$has_context" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T8.b 매칭 없음 → continue only"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.b (rc=$rc continue=$continue_ok context=$has_context)"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T8.c FID 감지 실패 (session-progress.md 부재) → 전역 .specops/friction-log.jsonl
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
cp "$FIXTURES/transcripts/r1-commit-without-verify.jsonl" transcript.jsonl
stdin_json=$(jq -nc --arg tp "$tmp/transcript.jsonl" '{ session_id:"s1", transcript_path:$tp, hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:"git commit -m \"x\""}, tool_response:{} }')
echo "$stdin_json" | bash "$HOOK" >/dev/null 2>&1
if [ -f ".specops/friction-log.jsonl" ] && jq -e '.fid == null and .rule_id == "R-1"' ".specops/friction-log.jsonl" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS T8.c FID 없음 → 전역 fallback"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.c"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T8.d additionalContext 300자 제한
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
cp "$FIXTURES/transcripts/r1-commit-without-verify.jsonl" transcript.jsonl
stdin_json=$(jq -nc --arg tp "$tmp/transcript.jsonl" '{ session_id:"s1", transcript_path:$tp, hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:"git commit -m \"x\""}, tool_response:{} }')
out=$(echo "$stdin_json" | bash "$HOOK" 2>/dev/null)
ctx_len=$(echo "$out" | jq -r '.additionalContext // ""' | wc -c | tr -d ' ')
if [ "$ctx_len" -le 301 ]; then  # wc -c 는 trailing newline 포함, +1 허용
  PASS=$((PASS+1)); echo "PASS T8.d additionalContext ≤ 300"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.d (len=$ctx_len)"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T8.e ★ 감사 스코프 회귀 (20260718-posttool-audit-silence): 커밋 직후 잔여 dirty 가
#   tracked .specops/session-progress.md 뿐인 실전 상태에서, 방금 커밋(코드)의 감사가 침묵하면 안 된다.
#   구버전은 is_docs_only_change(working-tree)가 .specops/* 면제에 걸려 R-1 감사를 통째로 skip —
#   #214 이후 R-1 posttool warn 전 repo 0건의 실물 원인 (T8.a 는 git repo 부재 fixture 라 못 잡았다).
tmp=$(mktemp -d); cd "$tmp"; git init -q
mkdir -p .specops
cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
echo 'echo v1' > a.sh
git add a.sh .specops/session-progress.md && git -c user.email=t@t -c user.name=t commit -qm init
echo 'echo v2' > a.sh && git add a.sh && git -c user.email=t@t -c user.name=t commit -qm "feat: code"
printf '\n- dirty line\n' >> .specops/session-progress.md   # tracked+modified — 실전 잔여 dirty
cp "$FIXTURES/transcripts/r1-commit-without-verify.jsonl" transcript.jsonl
stdin_json=$(jq -nc --arg tp "$tmp/transcript.jsonl" '{ session_id:"s1", transcript_path:$tp, hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:"git commit -m \"x\""}, tool_response:{} }')
out=$(echo "$stdin_json" | bash "$HOOK" 2>/dev/null); rc=$?
log_path=".specops/20260424-newest-feature/friction-log.jsonl"
if [ "$rc" -eq 0 ] && [ -f "$log_path" ] && jq -e '.rule_id == "R-1"' "$log_path" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T8.e ★ 코드 커밋 + .specops 잔여 dirty → 감사 실행 (침묵 봉합)"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.e 감사 침묵 (rc=$rc log=$(ls $log_path 2>/dev/null))"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T8.f 방금 커밋이 docs-only → 감사 skip 유지 (스코프 의미론 — tree 에 코드 dirt 가 있어도 커밋 기준)
tmp=$(mktemp -d); cd "$tmp"; git init -q
mkdir -p .specops
cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
echo 'echo v1' > a.sh
git add a.sh .specops/session-progress.md && git -c user.email=t@t -c user.name=t commit -qm init
echo docs > README.md && git add README.md && git -c user.email=t@t -c user.name=t commit -qm "docs: readme"
echo 'echo dirty' > b.sh   # untracked 코드 dirt — 커밋 스코프 판정엔 무관해야 함
cp "$FIXTURES/transcripts/r1-commit-without-verify.jsonl" transcript.jsonl
stdin_json=$(jq -nc --arg tp "$tmp/transcript.jsonl" '{ session_id:"s1", transcript_path:$tp, hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:"git commit -m \"x\""}, tool_response:{} }')
out=$(echo "$stdin_json" | bash "$HOOK" 2>/dev/null); rc=$?
log_path=".specops/20260424-newest-feature/friction-log.jsonl"
if [ "$rc" -eq 0 ] && [ ! -f "$log_path" ]; then
  PASS=$((PASS+1)); echo "PASS T8.f docs-only 커밋 → 감사 skip (커밋 기준 스코프)"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.f (rc=$rc log=$(ls $log_path 2>/dev/null))"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T8.g ★ scope_class 배선 (20260814-friction-scope-posttool): posttool 이 남기는 R-1 행에
#   커밋 범위 분류가 들어가야 한다. 없으면 gbrain-friction 집계에서 warn 계열이 영구 `판정불가`.
#   구조상 posttool 행은 docs-only 가 될 수 없으므로(면제면 기록 자체가 없음) 기대값은 code 다.
tmp=$(mktemp -d); cd "$tmp"; git init -q
mkdir -p .specops
cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
echo 'echo v1' > a.sh
git add a.sh .specops/session-progress.md && git -c user.email=t@t -c user.name=t commit -qm init
echo 'echo v2' > a.sh && git add a.sh && git -c user.email=t@t -c user.name=t commit -qm "feat: code"
printf '\n- dirty line\n' >> .specops/session-progress.md
cp "$FIXTURES/transcripts/r1-commit-without-verify.jsonl" transcript.jsonl
stdin_json=$(jq -nc --arg tp "$tmp/transcript.jsonl" '{ session_id:"s1", transcript_path:$tp, hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:"git commit -m \"x\""}, tool_response:{} }')
echo "$stdin_json" | bash "$HOOK" >/dev/null 2>&1
log_path=".specops/20260424-newest-feature/friction-log.jsonl"
got=$(jq -r 'select(.rule_id=="R-1") | .scope_class // "<부재>"' "$log_path" 2>/dev/null | head -1)
if [ "$got" = "code" ]; then
  PASS=$((PASS+1)); echo "PASS T8.g ★ posttool R-1 행에 scope_class=code 기록"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.g scope_class got=$got 기대=code"
fi
cd "$PLUGIN"; rm -rf "$tmp"


# ── Bash 사전 필터 (20260911-posttool-matcher-narrow) ─────────────────────────
#   posttool 은 동기 훅이라 모든 Bash 호출 뒤에 붙는다. 커밋·PR 이 아닌 명령에서
#   git·jq 비용을 다 치른 뒤 버리던 것을, 판정과 **같은 전처리·같은 정규식**으로 먼저 거른다.
#   아래 케이스는 "필터가 판정을 바꾸지 않았다"(T8.i·T8.j·T8.k)와
#   "필터가 실제로 비용을 없앴다"(T8.h)를 따로 잠근다 — 앞의 것만 있으면 필터를 지워도 통과한다.

# git shim — 호출될 때마다 1줄을 남기고 진짜 git 으로 넘긴다.
#   ★ PATH 앞에만 끼운다. 통째로 교체하면 bash·jq 를 못 찾아 훅이 다른 이유로 끝난다.
_real_git=$(command -v git)
_mk_git_shim() {  # $1=shim dir  $2=log file
  mkdir -p "$1"
  printf '#!/bin/sh\necho "$*" >> "%s"\nexec "%s" "$@"\n' "$2" "$_real_git" > "$1/git"
  chmod +x "$1/git"
}
# $1=tool_name $2=command(또는 skill) [$3=훅 경로] → stdout. cwd 는 호출자의 $tmp.
_post() {
  local _h="${3:-$HOOK}" _in
  if [ "$1" = "Skill" ]; then
    _in=$(jq -nc --arg tp "$tmp/transcript.jsonl" --arg s "$2" '{session_id:"s1", transcript_path:$tp, hook_event_name:"PostToolUse", tool_name:"Skill", tool_input:{skill:$s}, tool_response:{}}')
  else
    _in=$(jq -nc --arg tp "$tmp/transcript.jsonl" --arg t "$1" --arg c "$2" '{session_id:"s1", transcript_path:$tp, hook_event_name:"PostToolUse", tool_name:$t, tool_input:{command:$c}, tool_response:{}}')
  fi
  printf '%s' "$_in" | PATH="$tmp/shim:$PATH" bash "$_h" 2>/dev/null
}

# T8.h ★ 비트리거 Bash 는 git 을 부르기 전에 끝난다 (AC-2)
#   음성 3형: 평범한 명령 · 인자에 commit 이 없는 grep · heredoc **본문**에만 git commit(비실행자 cat).
#   기록 없음·출력 동일은 필터가 없어도 성립한다 — **git 호출 0회**가 필터의 유일한 관측 증거다.
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
cp "$FIXTURES/transcripts/r1-commit-without-verify.jsonl" transcript.jsonl
_mk_git_shim "$tmp/shim" "$tmp/git-calls.log"
_heredoc_cmd=$(printf "cat > note.md <<'EOF'\ngit commit -m x\nEOF")
_h_bad=""
for _c in "ls" "grep -rn foo ." "$_heredoc_cmd"; do
  : > "$tmp/git-calls.log"
  _o=$(_post Bash "$_c")
  _n=$(wc -l < "$tmp/git-calls.log" | tr -d ' ')
  _logs=$(find .specops -name friction-log.jsonl 2>/dev/null | wc -l | tr -d ' ')
  if [ "$_o" != '{"continue":true}' ] || [ "$_n" -ne 0 ] || [ "$_logs" -ne 0 ]; then
    _h_bad="$_h_bad [$(printf '%s' "$_c" | head -1): out=$_o git=$_n logs=$_logs]"
  fi
done
if [ -z "$_h_bad" ]; then
  PASS=$((PASS+1)); echo "PASS T8.h ★ 비트리거 Bash 3형 → git 0회 · 기록 0 · continue only"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.h 필터 미작동:$_h_bad"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T8.i ★ 트리거 판정 동치 코퍼스 (AC-3)
#   양성 5형은 **필터 추가 전과 같은 규칙**이 기록돼야 하고, 음성 3형은 기록이 없어야 한다.
#   기대 규칙은 2026-09-11 main 훅(필터 추가 전) 실측값이다 — 필터가 정규식을 좁히면 양성이 떨어진다.
#   heredoc **본문** 음성(AC-3)은 git 호출 0회까지 보는 T8.h 가 담당한다.
_i_bad=""
while IFS='|' read -r _exp _c; do
  [ -n "$_c" ] || continue
  tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
  cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
  cp "$FIXTURES/transcripts/r1-commit-without-verify.jsonl" transcript.jsonl
  _o=$(_post Bash "$_c")
  _got=$(printf '%s' "$_o" | jq -r '.additionalContext // ""' 2>/dev/null | grep -oE 'R-[12]' | sort -u | tr '\n' ' ' | sed 's/ $//')
  [ "$_got" = "$_exp" ] || _i_bad="$_i_bad [$_c: got='$_got' exp='$_exp']"
  cd "$PLUGIN"; rm -rf "$tmp"
done <<'CORPUS'
R-1|git commit -m x
R-1|FOO='a b' git commit -m x
R-1|rtk proxy git commit -m x
R-1|git -C . commit -m x
R-2|gh pr create --title t
|git commit-tree HEAD^{tree}
|echo "git commit -m x"
|ls
CORPUS
if [ -z "$_i_bad" ]; then
  PASS=$((PASS+1)); echo "PASS T8.i ★ 트리거 동치 코퍼스 8형 (양성 5 · 음성 3)"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.i 판정 변화:$_i_bad"
fi

# T8.j ★ 필터를 못 만들면 감사를 건너뛰지 않는다 (AC-4)
#   두 손상형 모두 main 은 R-1 을 기록한다 — load_rules(jq -c)는 스트림이라 깨진 줄 앞의 규칙을 살리고,
#   apply_lookback_rule 은 규칙마다 따로 grep 해 한 규칙의 정규식 오류가 다른 규칙을 막지 않는다.
#   필터는 jq -s(통째 실패)·정규식 합치기(한 개 오류 = 전체 rc=2)라 **더 쉽게 깨진다** — 그때 조기 종료하면
#   main 이 남기던 감사가 사라진다.
source "$PLUGIN/scripts/tests/lib/isolated-tree.sh" 2>/dev/null || true
_j_bad=""
if ! command -v iso::make_tree >/dev/null 2>&1; then
  _j_bad=" isolated-tree 미로드"
else
  for _dmg in broken-json bad-regex; do
    T=$(iso::make_tree "$PLUGIN") || { _j_bad="$_j_bad [$_dmg: 사본 실패]"; continue; }
    case "$_dmg" in
      broken-json) printf '{broken\n' >> "$T/hooks/rules.jsonl" ;;
      bad-regex)   printf '%s\n' '{"id":"R-X","matcher":"posttool","enabled":false,"trigger_tool":"Bash","trigger_pattern":"("}' >> "$T/hooks/rules.jsonl" ;;
    esac
    tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
    cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
    cp "$FIXTURES/transcripts/r1-commit-without-verify.jsonl" transcript.jsonl
    _o=$(_post Bash "git commit -m x" "$T/hooks/posttool-governance.sh")
    printf '%s' "$_o" | jq -e '.additionalContext | contains("R-1")' >/dev/null 2>&1 \
      || _j_bad="$_j_bad [$_dmg: out=$_o]"
    cd "$PLUGIN"; rm -rf "$tmp" "$T"
  done
fi
if [ -z "$_j_bad" ]; then
  PASS=$((PASS+1)); echo "PASS T8.j ★ 손상 rules 2형(깨진 JSON · 정규식 오류) → 조기 종료 없이 R-1 감사 유지"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.j 감사 소실:$_j_bad"
fi

# T8.k Skill 은 필터 대상이 아니다 — R-3 경로 유지 (AC-R-1 ①)
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
cp "$FIXTURES/transcripts/r3-skill-without-declaration.jsonl" transcript.jsonl
_o=$(_post Skill "specops-ko:planning-ko")
if printf '%s' "$_o" | jq -e '.additionalContext | contains("R-3")' >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T8.k Skill 선언 부재 → R-3 기록 유지"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.k (out=$_o)"
fi
cd "$PLUGIN"; rm -rf "$tmp"

STOP_HOOK="$PLUGIN/hooks/stop-governance.sh"

# T11.a stop_hook_active=true → 즉시 exit 0, append 없음
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
touch transcript.jsonl
stdin_json=$(jq -nc --arg tp "$tmp/transcript.jsonl" '{ session_id:"s1", transcript_path:$tp, hook_event_name:"Stop", stop_hook_active:true }')
out=$(echo "$stdin_json" | bash "$STOP_HOOK" 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | jq -e '.continue == true' >/dev/null && [ ! -f ".specops/friction-log.jsonl" ]; then
  PASS=$((PASS+1)); echo "PASS T11.a stop_hook_active 멱등"
else
  FAIL=$((FAIL+1)); echo "FAIL T11.a"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T11.b R-4 트리거 → friction-log append + continue:true
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
cp "$FIXTURES/transcripts/r4-claim-without-runner.jsonl" transcript.jsonl
stdin_json=$(jq -nc --arg tp "$tmp/transcript.jsonl" '{ session_id:"s1", transcript_path:$tp, hook_event_name:"Stop", stop_hook_active:false }')
out=$(echo "$stdin_json" | bash "$STOP_HOOK" 2>/dev/null); rc=$?
log_path=".specops/20260424-newest-feature/friction-log.jsonl"
if [ "$rc" -eq 0 ] && echo "$out" | jq -e '.continue == true' >/dev/null && [ -f "$log_path" ] && jq -e '.rule_id == "R-4"' "$log_path" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS T11.b R-4 append"
else
  FAIL=$((FAIL+1)); echo "FAIL T11.b (rc=$rc log=$(ls $log_path 2>/dev/null))"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T11.c 매칭 없음 (빈 transcript) → append 없음, continue:true
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
touch transcript.jsonl
stdin_json=$(jq -nc --arg tp "$tmp/transcript.jsonl" '{ session_id:"s1", transcript_path:$tp, hook_event_name:"Stop", stop_hook_active:false }')
out=$(echo "$stdin_json" | bash "$STOP_HOOK" 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | jq -e '.continue == true and (has("additionalContext") | not)' >/dev/null; then
  PASS=$((PASS+1)); echo "PASS T11.c 매칭 없음 continue only"
else
  FAIL=$((FAIL+1)); echo "FAIL T11.c"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T13 관할 한정 — .specops 없는 저장소에는 감사 기록을 만들지 않는다 (pretool 의 `.specops/` 부재 면제와 같은 경계).
#   왜: 감사 기록이 .specops/friction-log.jsonl 을 만들면 그 저장소가 관할로 편입돼 다음 커밋부터 R-1 이 막는다.
tmp=$(mktemp -d); cd "$tmp"
cp "$FIXTURES/transcripts/r1-commit-without-verify.jsonl" transcript.jsonl
stdin_json=$(jq -nc --arg tp "$tmp/transcript.jsonl" '{ session_id:"s1", transcript_path:$tp, hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:"git commit -m \"x\""}, tool_response:{} }')
out=$(echo "$stdin_json" | bash "$HOOK" 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && [ ! -e ".specops" ] && echo "$out" | jq -e '.continue == true and (has("additionalContext") | not)' >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T13.a .specops 부재 → 감사 기록·디렉토리 미생성"
else
  FAIL=$((FAIL+1)); echo "FAIL T13.a (rc=$rc out=$out .specops=$([ -e .specops ] && echo yes || echo no))"
fi
# T13.b CLAUDE_PROJECT_DIR 로 앵커된 뒤에도 같은 판정 — 프로젝트 루트에 .specops 가 없으면 만들지 않는다
mkdir -p sub
out=$(cd sub && echo "$stdin_json" | CLAUDE_PROJECT_DIR="$tmp" bash "$HOOK" 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && [ ! -e ".specops" ] && [ ! -e "sub/.specops" ]; then
  PASS=$((PASS+1)); echo "PASS T13.b 앵커 뒤에도 미생성"
else
  FAIL=$((FAIL+1)); echo "FAIL T13.b (rc=$rc $(find . -name .specops | tr '\n' ' '))"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T8.l ★ 사후 감사도 같은 형태를 커밋으로 알아본다 (20261010-hook-sigpipe-test-eval)
#   왜: 규칙 적용 자리(lib 의 apply_lookback_rule)가 일치를 `printf … | grep -q` 로 읽어, 커밋 뒤에 큰 여러 줄이 붙으면
#   grep 이 먼저 끝나 앞단이 SIGPIPE 로 죽고 "트리거 불일치" 가 됐다 — 감사 기록이 빠졌다(훅은 `set -uo pipefail`).
#   크기는 약 103KB 로 둔다: 파이프 버퍼(64KB)보다 커야 재현되고, Linux 가 exec 인자 1개에 두는 한도(131072바이트)보다는
#   작아야 한다 — 이 문자열이 jq --arg 의 인자로 넘어간다(넘으면 입력이 만들어지지 않아 CI 의 ubuntu 에서만 거짓 결과가 난다).
_l_big=$(_l_i=0; while [ "$_l_i" -lt 2000 ]; do echo "echo line-$_l_i-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"; _l_i=$((_l_i+1)); done)
_l_bad=""
for _l_case in big cont; do
  tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
  cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
  cp "$FIXTURES/transcripts/r1-commit-without-verify.jsonl" transcript.jsonl
  if [ "$_l_case" = big ]; then _l_c="git commit -m x
$_l_big"; else _l_c='git commit -m "x" \
  --no-verify'; fi
  _o=$(_post Bash "$_l_c")
  _got=$(printf '%s' "$_o" | jq -r '.additionalContext // ""' 2>/dev/null | grep -oE 'R-[12]' | sort -u | tr '\n' ' ' | sed 's/ $//')
  [ "$_got" = "R-1" ] || _l_bad="$_l_bad [$_l_case: got='$_got']"
  cd "$PLUGIN"; rm -rf "$tmp"
done
if [ -z "$_l_bad" ]; then
  PASS=$((PASS+1)); echo "PASS T8.l ★ 커밋 뒤 큰 여러 줄(${#_l_big}바이트) · 인용 + 줄 연속 → 사후 감사가 R-1 을 기록"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.l 사후 감사가 커밋을 놓침:$_l_bad"
fi

# T8.m ★ 훅에 "파이프 뒤 grep -q" 가 없다 — 같은 병의 재발 잠금
#   왜: `set -uo pipefail` 아래 `producer | grep -q` 는 grep 이 첫 일치에서 끝날 때 앞단이 SIGPIPE 로 죽으면 일치가 불일치로
#   읽힌다. 이 저장소에서 세 번 나온 병이다(check-screen-quality · session-start · 커밋 전 훅). 일치 여부는 파이프 없이
#   읽는다: `grep -Eq "$re" <<< "$text"`. 주석 줄과 `||` 뒤의 grep 은 보지 않는다. 옵션 묶음에 q 가 든 grep · egrep · fgrep 과
#   --quiet · --silent 를 본다. 한 줄 안에서만 본다 — `|` 뒤에서 줄을 바꾼 grep -q 는 잡지 못한다.
_pipe_grep_q_hits() {  # <파일…> → 걸린 줄마다 "  디렉토리/파일:줄: 원문"
  awk '
    /^[[:space:]]*#/ { next }
    /(^|[^|])\|[[:space:]]*(e|f)?grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+(-[A-Za-z]*q[A-Za-z]*|--quiet|--silent)([[:space:]]|$)/ {
      n = split(FILENAME, p, "/"); printf "  %s:%d: %s\n", p[n-1] "/" p[n], FNR, $0
    }' "$@" 2>/dev/null
}
_m_hits=$(_pipe_grep_q_hits "$PLUGIN"/hooks/*.sh "$PLUGIN/scripts/_internal/file-class.sh")   # 훅 전부 + 훅이 source 하는 파일(같은 pipefail 아래서 돈다)
if [ -z "$_m_hits" ]; then
  PASS=$((PASS+1)); echo "PASS T8.m ★ 훅에 파이프 뒤 grep -q 없음"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.m 훅이 일치를 파이프 뒤 grep -q 로 읽는다 — grep -Eq \"\$re\" <<< \"\$text\" 형태로 바꿀 것:"; printf '%s\n' "$_m_hits" | cut -c1-200
fi

# T8.n 잠금(T8.m)의 판별식이 실제로 가려낸다 — 걸려야 할 줄만 걸린다
#   왜: 판별식이 아무것도 못 잡게 되면(정규식 손상 · awk 구현 차이) T8.m 은 조용히 통과한다. 임시 파일로 양쪽을 다 잰다.
_n_d=$(mktemp -d); mkdir -p "$_n_d/hooks"
cat > "$_n_d/hooks/x.sh" <<'T8N'
# printf '%s' "$a" | grep -q x
printf '%s' "$a" | grep -Eq "$re" || exit 0
[ -f "$f" ] || grep -q x "$f"
grep -Eq "$re" <<< "$a"
printf '%s' "$a" | grep -c x
out=$(producer | egrep --quiet x)
T8N
_n_hits=$(_pipe_grep_q_hits "$_n_d/hooks/x.sh" | sed -E 's/^  hooks\/x\.sh:([0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')
rm -rf "$_n_d"
if [ "$_n_hits" = "2 6" ]; then
  PASS=$((PASS+1)); echo "PASS T8.n 판별식 — 파이프 뒤 grep -q · egrep --quiet 는 걸리고, 주석 줄 · || 뒤 · here-string · grep -c 는 걸리지 않는다"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.n 판별식이 가려내지 못한다 — 걸린 줄='$_n_hits' (기대 '2 6')"
fi

# T8.o ★ 훅 밖 스크립트에도 "파이프 뒤 grep -q" 가 없다 — pipefail 을 켜는 파일 전부 (20261011-script-pipe-grep)
#   왜: 같은 병이 훅 밖에도 있었다. `locale -a | grep -q` 는 입력 3KB 에서도 매번 틀렸다 — 앞단이 줄마다 나눠 쓰면
#   grep 이 끝난 뒤의 쓰기에서 죽는다. 입력이 작다고 안전하지 않다. 대상은 scripts(tests 제외) · skills · evals 의 *.sh 가운데
#   `set … pipefail` 줄이 어디든 있는 파일이다. 파일 단위다 — pipefail 이 함수 안에만 있어도 그 파일 전체를 본다.
#   pipefail 을 켜지 않는 파일과, 그런 파일이 source 로 끌어오는 파일은 보지 못한다.
_PIPEFAIL_RE='^[[:space:]]*set[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*o[[:space:]]+pipefail'
_pipefail_sh_files() {  # <디렉토리…> → pipefail 을 켜는 *.sh (…/scripts/tests/ 아래 제외 · 없는 디렉토리는 건너뛴다)
  find "$@" -name '*.sh' -not -path '*/scripts/tests/*' -exec grep -lE "$_PIPEFAIL_RE" {} + 2>/dev/null | sort
}
_pipefail_sh_hits() {  # <디렉토리…> → 그 파일들에서 걸린 줄
  local f
  while IFS= read -r f; do
    [ -n "$f" ] && _pipe_grep_q_hits "$f"
  done <<< "$(_pipefail_sh_files "$@")"
}
_o_files=$(_pipefail_sh_files "$PLUGIN/scripts" "$PLUGIN/skills" "$PLUGIN/evals")
_o_hits=$(_pipefail_sh_hits "$PLUGIN/scripts" "$PLUGIN/skills" "$PLUGIN/evals")
_o_n=$(grep -c . <<< "$_o_files")
if grep -qxF "$PLUGIN/scripts/release.sh" <<< "$_o_files" && [ -z "$_o_hits" ]; then
  PASS=$((PASS+1)); echo "PASS T8.o ★ pipefail 을 켜는 훅 밖 스크립트 ${_o_n}개에 파이프 뒤 grep -q 없음"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.o 훅 밖 스크립트가 pipefail 아래에서 일치를 파이프 뒤 grep -q 로 읽는다(대상 ${_o_n}개 — 0개면 대상 목록이 깨진 것이다) — grep -Eq \"\$re\" <<< \"\$text\" 형태로 바꿀 것:"; printf '%s\n' "$_o_hits" | cut -c1-200
fi

# T8.p 잠금(T8.o)의 대상 고르기가 실제로 가려낸다 — pipefail 을 켜는 파일만, 테스트 디렉토리는 빼고
#   왜: 대상 목록이 비면 T8.o 는 걸린 줄 0 으로 통과한다. 임시 트리로 양쪽을 다 잰다.
_p_d=$(mktemp -d); mkdir -p "$_p_d/scripts/tests" "$_p_d/skills/x/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'printf "%s" "$a" | grep -q x' > "$_p_d/scripts/a.sh"
printf '%s\n' '#!/usr/bin/env bash' 'set -u' 'printf "%s" "$a" | grep -q x' > "$_p_d/scripts/b.sh"
printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail' 'printf "%s" "$a" | grep -q x' > "$_p_d/scripts/tests/c.sh"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s" "$a" | grep -q x' 'f() (' '  set -o pipefail' ')' > "$_p_d/scripts/d.sh"
printf '%s\n' '#!/usr/bin/env bash' 'set -e -o pipefail' '# printf "%s" "$a" | grep -q x' 'grep -q x <<< "$a"' > "$_p_d/skills/x/scripts/e.sh"
_p_files=$(_pipefail_sh_files "$_p_d/scripts" "$_p_d/skills" "$_p_d/evals" | sed "s|^$_p_d/||" | tr '\n' ' ' | sed 's/ $//')
_p_hits=$(_pipefail_sh_hits "$_p_d/scripts" "$_p_d/skills" "$_p_d/evals" | sed -E 's/^  ([^:]+:[0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/ $//')
rm -rf "$_p_d"
if [ "$_p_files" = "scripts/a.sh scripts/d.sh skills/x/scripts/e.sh" ] && [ "$_p_hits" = "scripts/a.sh:3 scripts/d.sh:2" ]; then
  PASS=$((PASS+1)); echo "PASS T8.p 대상 고르기 — pipefail 을 켜는 파일(함수 안 · 옵션을 나눠 쓴 형태 포함)만 대상이고, pipefail 없는 파일 · 테스트 디렉토리 · 없는 디렉토리는 빠진다"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.p 대상 고르기가 가려내지 못한다 — 대상='$_p_files' (기대 'scripts/a.sh scripts/d.sh skills/x/scripts/e.sh') · 걸린 줄='$_p_hits' (기대 'scripts/a.sh:3 scripts/d.sh:2')"
fi

# T8.q ★ 제품 스크립트의 awk 정규식에 구간 반복({n,m})이 없다 — mawk 호환 (20261021-root-skip-tests)
#   왜: mawk 1.3.4(Ubuntu 24.04 기본 awk)는 구간 반복을 지원하지 않아 `/^#{2,3} AC-/` 가 한 줄도 맞지 않는다 —
#   check-ac-format 은 모든 AC 를 "헤더형 0건" 으로, plan-to-tasks 는 태스크를 못 찾았다. CI 리눅스 러너는 gawk 라
#   이 회귀는 CI 에서 보이지 않는다. 대상은 hooks · scripts(tests 제외) · skills · evals 의 *.sh 에서 awk 정규식
#   리터럴(`~ /…/` · sub/gsub/match/split 의 `/…/` · 줄 머리 패턴 `/…/ {`)이다. grep -E · sed -E · bash =~ 는 보지 않는다.
_AWK_IV_RE='(~|match\(|sub\(|gsub\(|split\()[^;]*/[^/]*\{[0-9]+(,[0-9]*)?\}[^/]*/|^[[:space:]]*/[^/]*\{[0-9]+(,[0-9]*)?\}[^/]*/[[:space:]]*\{'
_awk_iv_hits() {  # <디렉토리…> → 걸린 줄 (…/scripts/tests/ 아래 제외 · 주석 줄 제외 · 없는 디렉토리는 건너뛴다)
  find "$@" -name '*.sh' -not -path '*/scripts/tests/*' -exec grep -nE "$_AWK_IV_RE" {} + 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | sort
}
_q_hits=$(_awk_iv_hits "$PLUGIN/hooks" "$PLUGIN/scripts" "$PLUGIN/skills" "$PLUGIN/evals")
if [ -z "$_q_hits" ]; then
  PASS=$((PASS+1)); echo "PASS T8.q ★ 제품 스크립트의 awk 정규식에 구간 반복({n,m}) 없음 (mawk 호환)"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.q awk 정규식이 구간 반복({n,m})을 쓴다 — mawk 에서 매칭 0건. 대안(##|###)·\\.\\.+·length() 로 바꿀 것:"; printf '%s\n' "$_q_hits" | cut -c1-200
fi

# T8.r 잠금(T8.q)의 판별식이 실제로 가려낸다 — awk 리터럴만, grep -E·sed -E·주석·테스트 디렉토리는 빼고
_r_d=$(mktemp -d); mkdir -p "$_r_d/scripts/tests" "$_r_d/skills/x"
printf '%s\n' 'awk '"'"'' '/^#{2,3} AC-/ { n++ }' '  if (s ~ /^\.{2,}$/) x=1' '  sub(/^#{1,3}[ \t]+/, "", t)' "'" > "$_r_d/scripts/a.sh"
printf '%s\n' 'grep -qE "^[0-9]{8}-x$" <<< "$f"' 'sed -E "s/a{2}/b/"' '# awk 예: /^#{2,3} / { }' 'if [[ $f =~ ^[0-9]{8}$ ]]; then :; fi' > "$_r_d/skills/x/b.sh"
printf '%s\n' '/^#{2,3} AC-/ { n++ }' > "$_r_d/scripts/tests/c.sh"
_r_hits=$(_awk_iv_hits "$_r_d/hooks" "$_r_d/scripts" "$_r_d/skills" | sed -E "s|^$_r_d/||; s|^([^:]+:[0-9]+):.*|\1|" | tr '\n' ' ' | sed 's/ $//')
rm -rf "$_r_d"
if [ "$_r_hits" = "scripts/a.sh:2 scripts/a.sh:3 scripts/a.sh:4" ]; then
  PASS=$((PASS+1)); echo "PASS T8.r 판별식 — awk 리터럴(줄 머리 패턴 · ~ · sub)만 잡고 grep -E · sed -E · bash =~ · 주석 · 테스트 디렉토리는 빠진다"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.r 판별식이 가려내지 못한다 — 걸린 줄='$_r_hits' (기대 'scripts/a.sh:2 scripts/a.sh:3 scripts/a.sh:4')"
fi

echo
echo "==== Results: PASS=$PASS FAIL=$FAIL ===="
[ "$FAIL" -eq 0 ]
