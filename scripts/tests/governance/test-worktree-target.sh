#!/usr/bin/env bash
# 판정 git 대상 — 셸이 있는 같은 저장소 worktree (20261016-hook-worktree-target)
#   훅은 프로젝트 폴더의 .specops·관할을 그대로 쓰고, 입력 cwd 가 같은 저장소의 다른 작업 트리면
#   git 조회만 그 worktree 로 돌린다. 실기록: Argus 가 .worktrees/<FID> 에서 커밋할 때마다 유효 receipt 가
#   "무효" 로 막혀 우회했다(transcript 51건).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
source "$PLUGIN/hooks/governance-lib.sh"
# shellcheck source=/dev/null
source "$PLUGIN/scripts/tests/lib/exec-transcript.sh"   # _tr_for
PRE="$PLUGIN/hooks/pretool-governance.sh"
POST="$PLUGIN/hooks/posttool-governance.sh"
REC="$PLUGIN/scripts/_internal/record-task-receipt.sh"
VS="$PLUGIN/scripts/_internal/verification-state.sh"
FIXT="$PLUGIN/scripts/tests/governance/fixtures/transcripts"

TD=$(mktemp -d) || exit 1
trap 'rm -rf "$TD"' EXIT
FID=20261016-wt
M="$TD/main"
_g() { git -c user.name=t -c user.email=t@e.com "$@"; }
_tasks_md() {  # $1=경로 — DAG 픽스처. 제목·펜스를 printf 로 만든다: 이 테스트 코드가 tasks.md 에 실릴 때 진짜 DAG 로 읽히지 않게(dag::extract_yaml 은 줄 맨 앞 첫 `## 의존 그래프` 를 집는다)
  { printf '# tasks\n\n## %s\n\n%syaml\n' '의존 그래프' '```'
    printf 'tasks:\n  - id: T1\n    test_command: "bash scripts/tests/test-foo.sh"\n    depends_on: []\n    inputs: []\n    outputs: [src/foo.sh, scripts/tests/test-foo.sh]\n    ac: [AC-1]\n%s\n' '```'; } > "$1"
}
git init -q "$M" && git -C "$M" symbolic-ref HEAD refs/heads/main
printf '.specops/\n.worktrees/\n' > "$M/.gitignore"
mkdir -p "$M/scripts/tests" "$M/src" "$M/.specops/$FID"
printf '#!/usr/bin/env bash\nexit 0\n' > "$M/scripts/tests/test-foo.sh"; chmod +x "$M/scripts/tests/test-foo.sh"
printf 'x\n' > "$M/src/foo.sh"
(cd "$M" && git add -A && _g commit -qm init)
printf '# spec\n' > "$M/.specops/$FID/spec.md"
_tasks_md "$M/.specops/$FID/tasks.md"
printf '<!-- active-fid: %s -->\n## %s\n- 2026-10-16 10:00 /implement DONE (T1)\n' "$FID" "$FID" > "$M/.specops/session-progress.md"
W="$M/.worktrees/$FID"
git -C "$M" worktree add -q "$W" -b "feat/$FID" 2>/dev/null
WP=$(cd "$W" && pwd -P)
TR="$TD/tr.jsonl"   # 실행 증거 없는 transcript — 태스크 테스트만 돌았다
printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"bash scripts/tests/test-foo.sh"}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu1","content":"ok"}]}}' > "$TR"

_in() {  # $1=명령 $2=cwd(빈 값이면 필드 없음) $3=transcript
  jq -nc --arg c "$1" --arg w "$2" --arg t "$3" \
    '{tool_name:"Bash",tool_input:{command:$c},transcript_path:$t} + (if $w=="" then {} else {cwd:$w} end)'
}
_pre() { _in "$@" | (cd "$M" && CLAUDE_PROJECT_DIR="$M" bash "$PRE" 2>/dev/null); }
_dec() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null; }
_why() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
C1="git commit -m 'feat: x (Task: T1)'"

# worktree 에 T1 outputs 를 바꾸고 staged → worktree 를 현재 폴더로 receipt (메인 .specops 에 기록)
printf 'y\n' > "$W/src/foo.sh"
(cd "$W" && git add src/foo.sh scripts/tests/test-foo.sh)
(cd "$W" && SPECOPS_ROOT="$M/.specops" bash "$REC" "$FID" T1) >/dev/null 2>&1

# WT-1 (AC-1)
r=$(_pre "$C1" "$W" "$TR")
[ "$(_dec "$r")" = "allow" ] && ok "WT-1 ★ cwd=worktree · 유효 receipt → allow" || nope "WT-1" "$(_why "$r" | head -3)"

# WT-2 (AC-7)
mkdir -p "$W/sub"
r=$(_pre "$C1" "$W/sub" "$TR")
[ "$(_dec "$r")" = "allow" ] && ok "WT-2 cwd=worktree 하위 폴더 → allow" || nope "WT-2" "$(_why "$r" | head -3)"

# WT-9 ★ 셸은 worktree 인데 명령이 메인으로 cd 해서 커밋 — 판정 대상을 바꾸지 않는다(종전 = 메인 기준 deny)
r=$(_pre "cd $M && git commit -m 'feat: main (Task: T1)'" "$W" "$TR")
[ "$(_dec "$r")" = "deny" ] && ! _why "$r" | grep -qF '판정 기준 worktree' \
  && ok "WT-9 ★ cwd=worktree + 명령 안 cd 메인 → 종전 판정(deny) · 안내 없음" || nope "WT-9" "dec=$(_dec "$r")"

# WT-10 receipt 뒤 worktree 에 추적 안 하는 파일이 생기면 지문이 바뀐다 — worktree 지문을 실제로 본다
printf 'n\n' > "$W/new-untracked.sh"
r=$(_pre "$C1" "$W" "$TR")
[ "$(_dec "$r")" = "deny" ] && ok "WT-10 receipt 뒤 worktree 에 untracked 추가 → deny (worktree 지문)" || nope "WT-10" "dec=$(_dec "$r")"
rm -f "$W/new-untracked.sh"

# WT-3 (AC-3) — 판정 대상이 바뀌지 않는 다섯 입력 + 바뀌는 입력
git init -q "$TD/other"
n=0
for c in "" "$M" "$M/src" "$TD/other" "$TD/nonexist"; do
  [ -z "$(_gov_git_target "$c" "$M")" ] && n=$((n + 1))
done
[ -z "$(GIT_DIR=/nonexist _gov_git_target "$W" "$M")" ] && n=$((n + 1))   # 이미 GIT_DIR 이 있으면 손대지 않는다
t=$(_gov_git_target "$W/sub" "$M")
[ "$n" -eq 6 ] && [ "${t%%$'\n'*}" = "$WP" ] && [ -d "${t#*$'\n'}" ] \
  && ok "WT-3a 대상 해석: 무변경 6종(GIT_DIR 기존 포함) · worktree 하위 → worktree 최상위" || nope "WT-3a" "n=$n t=$t"
a=$(_dec "$(_pre "$C1" "" "$TR")"); b=$(_dec "$(_pre "$C1" "$M" "$TR")"); c=$(_dec "$(_pre "$C1" "$TD/other" "$TR")")
[ "$a" = "deny" ] && [ "$b" = "$a" ] && [ "$c" = "$a" ] \
  && ok "WT-3b cwd 없음·프로젝트 폴더·다른 저장소 → 종전 판정(메인 트리 기준 deny)" || nope "WT-3b" "$a $b $c"
[ -z "$(_why "$(_pre "$C1" "" "$TR")" | grep -F '판정 기준 worktree')" ] \
  && ok "WT-3c 판정 대상이 그대로면 판정 기준 안내 없음 (AC-8)" || nope "WT-3c" "안내가 나옴"

# WT-4 (AC-2) — outputs 밖 파일 staged: worktree 에 .specops 가 없어도 관할 밖이 아니다
#   ★ 커밋 메시지를 C1 과 다르게 쓴다 — log_friction_sev 는 같은 rule_id·snippet 의 block 기록을 다시 쓰지 않아(dedup),
#   C1 이면 WT-3b 의 기록(scope_class=empty)을 읽는다(plan-reviewer 1회차 실측).
C4="git commit -m 'feat: extra (Task: T1)'"
printf 'z\n' > "$W/extra.sh"; (cd "$W" && git add extra.sh)
r=$(_pre "$C4" "$W" "$TR")
sc=$(grep '"rule_id":"R-1"' "$M/.specops/$FID/friction-log.jsonl" 2>/dev/null | tail -1 | jq -r '.scope_class // "-"')
[ "$(_dec "$r")" = "deny" ] && [ "$sc" = "code" ] && [ ! -e "$W/.specops" ] \
  && ok "WT-4 ★ receipt 밖 코드 → deny · 기록은 메인 .specops · scope_class=code" || nope "WT-4" "dec=$(_dec "$r") sc=$sc"

# WT-5 (AC-8)
_why "$r" | grep -qF "판정 기준 worktree: $WP" && _why "$r" | grep -qF "GIT_WORK_TREE=$WP" \
  && _why "$r" | grep -qF "verification-state.sh current $FID" && ! _why "$r" | grep -qF '.specops 사본' \
  && ok "WT-5 deny 사유에 판정 기준 worktree · 같은 값을 보는 조회법 · 사본 없으면 사본 안내 없음" || nope "WT-5" "$(_why "$r" | tail -3)"

# WT-6 (AC-6)
mkdir -p "$W/.specops" && printf 'copy\n' > "$W/.specops/session-progress.md"
r=$(_pre "$C4" "$W" "$TR")
[ "$(_dec "$r")" = "deny" ] && _why "$r" | grep -qF '.specops 사본' \
  && ok "WT-6 worktree 에 .specops 사본 → 판정 그대로 · 사본 안내" || nope "WT-6" "$(_why "$r" | tail -3)"
rm -rf "$W/.specops"
(cd "$W" && git reset -q extra.sh) && rm -f "$W/extra.sh"

# WT-7 (AC-5) — strict FID 의 PR: release-ready 의 verify 축이 worktree 기준
(cd "$W" && git add src/foo.sh scripts/tests/test-foo.sh && _g commit -qm 'feat: x')
(cd "$W" && SPECOPS_ROOT="$M/.specops" bash "$VS" record "$FID" PASS) >/dev/null 2>&1
printf '<!-- active-fid: %s -->\n## %s\n- 2026-10-16 10:05 /verify PASS (x)\n- 2026-10-16 10:00 /implement DONE (T1)\n' "$FID" "$FID" > "$M/.specops/session-progress.md"
printf '{"effective":"strict"}\n' > "$M/.specops/$FID/risk-profile.json"
TRP=$(_tr_for "$M" "$FIXT/exec-evidence-pass.jsonl")
CPR="gh pr create --base main --head feat/$FID --title t --body b"
rw=$(_why "$(_pre "$CPR" "$W" "$TRP")"); rm_=$(_why "$(_pre "$CPR" "" "$TRP")")
printf '%s' "$rw" | grep -q 'verify=PASS' && ! printf '%s' "$rw" | grep -q 'verify=STALE' && printf '%s' "$rm_" | grep -q 'verify=STALE' \
  && ok "WT-7 PR 판정: cwd=worktree 면 verify=PASS · cwd 없으면 종전(verify=STALE)" || nope "WT-7" "wt=$(printf '%s' "$rw" | grep -m1 'verify=') main=$(printf '%s' "$rm_" | grep -m1 'verify=')"
rm -f "$M/.specops/$FID/risk-profile.json"

# WT-8 (AC-R-1 · posttool 감사) — 감사 scope_class 도 worktree 의 방금 커밋 범위
before=0; [ -f "$M/.specops/$FID/friction-log.jsonl" ] && before=$(wc -l < "$M/.specops/$FID/friction-log.jsonl" | tr -d ' ')
_in "git commit -m 'feat: x'" "$W" "$TR" | (cd "$M" && CLAUDE_PROJECT_DIR="$M" bash "$POST" >/dev/null 2>&1)
new=$(tail -n +"$((before + 1))" "$M/.specops/$FID/friction-log.jsonl" 2>/dev/null | grep '"rule_id":"R-1"')
sc=$(printf '%s\n' "$new" | tail -1 | jq -r '.scope_class // "-"' 2>/dev/null)
[ -n "$new" ] && [ "$sc" = "code" ] && ok "WT-8 posttool 감사 기록이 남고 scope_class = worktree HEAD~1..HEAD (code)" || nope "WT-8" "rec=$(printf '%s' "$new" | grep -c .) sc=$sc"

finish
