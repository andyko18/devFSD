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
# WT-9x 이동 표기 4형태 — _gov_cmd_moves_git 의 -C·--work-tree · GIT_DIR= · pushd 분기를 각각 잠근다(변이 M4·M4b·M4c)
for mv in "git -C $M commit -m 'feat: m1 (Task: T1)'" \
          "pushd $M >/dev/null && git commit -m 'feat: m2 (Task: T1)'" \
          "GIT_DIR=$M/.git git commit -m 'feat: m3 (Task: T1)'" \
          "git --work-tree=$M commit -m 'feat: m4 (Task: T1)'"; do
  r=$(_pre "$mv" "$W" "$TR")
  [ "$(_dec "$r")" = "deny" ] && ok "WT-9x cwd=worktree + $mv → deny" || nope "WT-9x" "$mv dec=$(_dec "$r")"
done

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
[ "$(_dec "$r")" = "deny" ] && _why "$r" | grep -qF '자기 기록이 없어' && ! _why "$r" | grep -qF '사본을 지우면' \
  && ok "WT-6 worktree 에 .specops 사본 → 판정 그대로 · 자기 기록 없음 안내" || nope "WT-6" "$(_why "$r" | tail -3)"
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

# ── 이동한 커밋의 문서 면제 (20261016-docs-exempt-moved-target) ──────────────
#   메인 트리에 문서만 staged 일 때 다른 worktree 로 옮겨 하는 코드 커밋이 "문서 전용" 으로 면제되던 구멍.
printf '# readme\n' > "$M/README.md"; (cd "$M" && git add README.md)
printf 'w2\n' > "$W/src/foo.sh"; (cd "$W" && git add src/foo.sh)
n=0; nn=0
for w in "$M" "$W"; do
  for c in "cd $W && git commit -m 'feat: moved'" "git -C $W commit -m 'feat: moved'"; do
    r=$(_pre "$c" "$w" "$TR")
    [ "$(_dec "$r")" = "deny" ] && n=$((n + 1))
    _why "$r" | grep -qF '다른 작업 트리로 옮겨 문서 면제를 적용하지 않았습니다' && nn=$((nn + 1))
  done
done
[ "$n" -eq 4 ] && ok "WT-11 ★ 메인 문서 staged + 다른 worktree 로 옮긴 코드 커밋 4형태 → deny" || nope "WT-11" "deny=$n/4"
r=$(_pre "git commit -m 'feat: plain (Task: T1)'" "$W" "$TR")
[ "$nn" -eq 4 ] && [ "$(_dec "$r")" = "deny" ] && ! _why "$r" | grep -qF '다른 작업 트리로 옮겨' \
  && ok "WT-12 면제를 거둔 deny 에 이유 안내 4/4 · 이동 없는 deny 에는 없음" || nope "WT-12" "note=$nn/4 plain=$(_dec "$r")"
a=$(_dec "$(_pre "cd $M && git commit -m 'docs: a'" "$M" "$TR")"); b=$(_dec "$(_pre "cd $M/src && git commit -m 'docs: b'" "$W" "$TR")")
[ "$a" = "allow" ] && [ "$b" = "allow" ] \
  && ok "WT-13 같은 작업 트리로 옮긴 문서 커밋(자기 폴더·하위 폴더) → 종전 면제" || nope "WT-13" "$a $b"
n0=0; n1=0
#   이어진 상대 이동은 메인에 같은 이름 폴더($M/$FID)를 둔다 — 홉마다 따로 풀면 두 번째 홉이 메인 안 폴더로 풀려
#   "같은 트리" 로 오답한다. 종전 `cd .worktrees && cd x` 는 $M/x 가 없어 "없는 폴더" 로 rc 0 이 나 보호 줄을 잠그지 못했다.
mkdir -p "$M/$FID"
for c in 'cd "" && git commit' 'cd $X && git commit' 'cd ~/x && git commit' 'cd - && git commit' 'popd; git commit' 'cd && git commit' "cd $M/nope && git commit" "GIT_DIR=$W/.git git commit" "git -C $W commit" "pushd $W && git commit" "git --git-dir $W/.git commit" "cd .worktrees && cd $FID && git commit" 'cd "/tmp" && git commit'; do
  (cd "$M" && _gov_cmd_moves_elsewhere "$c") && n0=$((n0 + 1))
done
for c in 'git commit -m x' "cd $M && git commit" "git -C $M commit" 'cd src && git commit' "GIT_DIR=$M/.git git commit" 'git commit -m "cd .worktrees/x"' 'git commit -m "fix -C HEAD"'; do
  (cd "$M" && _gov_cmd_moves_elsewhere "$c"); [ $? -eq 1 ] && n1=$((n1 + 1))   # rc 1 을 명시 — 미정의(127)를 통과로 세지 않는다
done
[ "$n0" -eq 13 ] && [ "$n1" -eq 7 ] \
  && ok "WT-14 이동 위치 확인: 확인 불가·다른 트리·이어진 상대 이동 13종 rc 0 · 옮기지 않음·같은 트리·메시지 속 cd/-C 7종 rc 1" || nope "WT-14" "rc0=$n0/13 rc1=$n1/7"
e1=$(cd "$M" && bash "$PLUGIN/scripts/_internal/scope-explain.sh" "cd $W && git commit -m code" 2>/dev/null)
e2=$(cd "$M" && bash "$PLUGIN/scripts/_internal/scope-explain.sh" "cd $M && git commit -m docs" 2>/dev/null)
printf '%s' "$e1" | grep -q 'EXEMPT=no' && printf '%s' "$e2" | grep -q 'EXEMPT=yes' \
  && ok "WT-15 면제 조회가 실제 판정과 같다(이동 → EXEMPT=no · 같은 트리 → yes)" || nope "WT-15" "$e1 / $e2"
# WT-16 ★ 셸이 worktree 일 때 상대 경로·--work-tree 만 준 이동 — 셸 위치 기준으로 풀어야 한다(plan-reviewer 1회차 실측: 프로젝트 기준이면 6건 allow)
mkdir -p "$W/src"
n=0
for c in "cd src && git commit -m 'feat: r1'" "cd . && git commit -m 'feat: r2'" "git -C . commit -m 'feat: r3'" "git -C src commit -m 'feat: r4'" "git --work-tree=$M commit -m 'feat: r5'" "GIT_WORK_TREE=$M git commit -m 'feat: r6'"; do
  [ "$(_dec "$(_pre "$c" "$W" "$TR")")" = "deny" ] && n=$((n + 1))
done
a=$(_dec "$(_pre "cd src && git commit -m 'docs: r7'" "$M" "$TR")")
[ "$n" -eq 6 ] && [ "$a" = "allow" ] \
  && ok "WT-16 ★ 셸=worktree 상대 경로·--work-tree 만 6형태 → deny · 셸=프로젝트 상대 경로 문서 커밋 → allow" || nope "WT-16" "deny=$n/6 rel=$a"

# ── 자기 기록 worktree 판정 루트 (20261106-worktree-specops-root · T2 pretool) ─────────────
#   데스크톱 worktree(<프로젝트>/.claude/worktrees/<이름>)는 자기 .specops 에 기록하는데(specops-root.sh)
#   훅은 프로젝트 폴더 .specops 를 읽어 다른 FID 로 판정했다(커밋 우회 21건). 자기 기록이 있을 때만 그쪽으로 판정한다.
# shellcheck source=/dev/null
source "$PLUGIN/scripts/_internal/specops-root.sh"   # specops_root_dir — RR-P 의 기대값(기록 스크립트가 쓰는 곳)
FIDM=20261106-main-old; FIDW=20261106-wt-own; FIDX=20261106-tracked
_mkmain() {  # $1=경로 $2=0 이면 .specops 를 ignore 하지 않는다(Argus 형태) — 메인 + FIDM(검증 STALE)
  git init -q "$1" && git -C "$1" symbolic-ref HEAD refs/heads/main
  if [ "${2:-1}" = 0 ]; then printf '.claude/\n' > "$1/.gitignore"; else printf '.specops/\n.claude/\n' > "$1/.gitignore"; fi
  mkdir -p "$1/scripts/tests" "$1/src" "$1/.specops/$FIDM"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/scripts/tests/test-foo.sh"; chmod +x "$1/scripts/tests/test-foo.sh"
  printf 'x\n' > "$1/src/foo.sh"
  (cd "$1" && git add -A && _g commit -qm init)
  printf '# spec\n' > "$1/.specops/$FIDM/spec.md"; _tasks_md "$1/.specops/$FIDM/tasks.md"
  printf '<!-- active-fid: %s -->\n## %s\n- 2026-11-06 08:00 /verify PASS\n' "$FIDM" "$FIDM" > "$1/.specops/session-progress.md"
}
_mkwt() {  # $1=메인 $2=이름 → worktree 물리 경로(.claude/worktrees/<이름>, 코드 변경 staged)
  local w="$1/.claude/worktrees/$2"
  git -C "$1" worktree add -q "$w" -b "feat/$2" 2>/dev/null
  printf 'y\n' > "$w/src/foo.sh"; (cd "$w" && git add src/foo.sh)
  (cd "$w" && pwd -P)
}
_ownrec() {  # $1=worktree — FIDW 자기 기록(spec·tasks·session-progress)
  mkdir -p "$1/.specops/$FIDW"; printf '# spec\n' > "$1/.specops/$FIDW/spec.md"; _tasks_md "$1/.specops/$FIDW/tasks.md"
  printf '<!-- active-fid: %s -->\n## %s\n- 2026-11-06 15:28 /implement 진행 (T1)\n' "$FIDW" "$FIDW" > "$1/.specops/session-progress.md"
}
_prem() {  # $1=프로젝트 폴더, 나머지 = _in 인자
  local m="$1"; shift
  _in "$@" | (cd "$m" && CLAUDE_PROJECT_DIR="$m" bash "$PRE" 2>/dev/null)
}
M2="$TD/main2"; _mkmain "$M2"; M2P=$(cd "$M2" && pwd -P)
(cd "$M2" && bash "$VS" record "$FIDM" PASS >/dev/null 2>&1); printf 'z\n' > "$M2/src/foo.sh"   # FIDM → STALE (WT-7 방식)
W2P=$(_mkwt "$M2" wt1); _ownrec "$W2P"
(cd "$W2P" && git add scripts/tests/test-foo.sh && bash "$REC" "$FIDW" T1) >/dev/null 2>&1
_pre2() { _prem "$M2" "$@"; }

# RR-0 픽스처 전제
[ -f "$W2P/.specops/$FIDW/receipts/T1.json" ] && ok "RR-0 전제: worktree 자기 기록에 receipt" || nope "RR-0" "receipt 없음"
vs0=$(cd "$M2" && bash "$VS" current "$FIDM" 2>&1)
printf '%s' "$vs0" | grep -q STALE && ok "RR-0b 전제: 메인 FIDM verify = STALE" || nope "RR-0b" "$vs0"
git -C "$W2P" check-ignore -q .specops/x && ok "RR-0c 전제: worktree 에서 .specops ignore" || nope "RR-0c" "ignore 아님"

# RR-1 ★ 자기 기록 worktree · 유효 receipt → allow (종전: 메인 FIDM 기준 deny)
r=$(_pre2 "$C1" "$W2P" "$TR")
{ [ -n "$r" ] && printf '%s' "$r" | jq -e . >/dev/null 2>&1 && [ "$(_dec "$r")" = "allow" ]; } \
  && ok "RR-1 ★ 자기 기록 worktree · 유효 receipt → allow (출력 JSON)" || nope "RR-1" "dec=$(_dec "$r") $(_why "$r" | head -3)"
mkdir -p "$W2P/sub"; r=$(_pre2 "$C1" "$W2P/sub" "$TR")
[ "$(_dec "$r")" = "allow" ] && ok "RR-1b 하위 폴더 cwd → allow" || nope "RR-1b" "dec=$(_dec "$r")"

# RR-2 ★ 막을 때는 FIDW 기준
mv "$W2P/.specops/$FIDW/receipts/T1.json" "$TD/T1.json.bk"
r=$(_pre2 "$C1" "$W2P" "$TR"); R2A=$(_why "$r")
[ "$(_dec "$r")" = "deny" ] && printf '%s' "$R2A" | grep -qF "$FIDW" && ! printf '%s' "$R2A" | grep -qF "$FIDM" \
  && ok "RR-2a ★ receipt 없음 → deny · 사유는 $FIDW (메인 FIDM 아님)" || nope "RR-2a" "dec=$(_dec "$r") $(printf '%s' "$R2A" | head -3)"
mv "$TD/T1.json.bk" "$W2P/.specops/$FIDW/receipts/T1.json"
r=$(_pre2 "git commit -m 'feat: audit'" "$W2P" "$TR")
[ "$(_dec "$r")" = "deny" ] && _why "$r" | grep -qF "$FIDW" && ! _why "$r" | grep -qF "$FIDM" \
  && ok "RR-2b ★ Task 줄 없는 코드 커밋 → deny · 사유는 $FIDW" || nope "RR-2b" "dec=$(_dec "$r") $(_why "$r" | head -3)"

# RR-3b BYPASS 기록도 자기 기록 worktree 에
mw0=$(grep -c '"phase":"governance-bypass"' "$W2P/.specops/$FIDW/metrics.jsonl" 2>/dev/null); mm0=$(grep -c '"phase":"governance-bypass"' "$M2P/.specops/$FIDM/metrics.jsonl" 2>/dev/null)
_in "git commit -m 'feat: b'" "$W2P" "$TR" | (cd "$M2" && CLAUDE_PROJECT_DIR="$M2" SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON=test bash "$PRE" >/dev/null 2>&1)
mw1=$(grep -c '"phase":"governance-bypass"' "$W2P/.specops/$FIDW/metrics.jsonl" 2>/dev/null); mm1=$(grep -c '"phase":"governance-bypass"' "$M2P/.specops/$FIDM/metrics.jsonl" 2>/dev/null)
[ "${mw1:-0}" -eq $((${mw0:-0} + 1)) ] && [ "${mm1:-0}" -eq "${mm0:-0}" ] \
  && ok "RR-3b BYPASS 기록은 worktree FID 에 +1 · 메인 FID 불변" || nope "RR-3b" "wt $mw0→$mw1 main $mm0→$mm1"

# RR-4 ★ 자기 기록이 없는 worktree 는 종전 판정(메인 FIDM) — 구멍 없음
_chk4() {  # $1=이름 $2=프로젝트 $3=worktree $4=불포함 FID(선택) — deny · FIDM 포함
  local r; r=$(_prem "$2" "$C1" "$3" "$TR"); R4=$(_why "$r")
  [ "$(_dec "$r")" = "deny" ] && printf '%s' "$R4" | grep -qF "$FIDM" && { [ -z "${4:-}" ] || ! printf '%s' "$R4" | grep -qF "$4"; } \
    && ok "RR-$1 자기 기록 없음 → 종전 판정(deny · $FIDM)" || nope "RR-$1" "dec=$(_dec "$r") $(printf '%s' "$R4" | head -3)"
}
w=$(_mkwt "$M2" w4a); _chk4 4a "$M2" "$w"
w=$(_mkwt "$M2" w4b); mkdir -p "$w/.specops"; : > "$w/.specops/.DS_Store"; _chk4 4b "$M2" "$w"
w=$(_mkwt "$M2" w4bp); mkdir -p "$w/.specops"; printf '<!-- active-fid: %s -->\n## %s\n' "$FIDW" "$FIDW" > "$w/.specops/session-progress.md"; _chk4 4b\' "$M2" "$w"
w=$(_mkwt "$M2" w4c); mkdir -p "$w/.specops/$FIDW"; : > "$w/.specops/$FIDW/.DS_Store"
printf '<!-- active-fid: %s -->\n## %s\n' "$FIDW" "$FIDW" > "$w/.specops/session-progress.md"; _chk4 4c "$M2" "$w"; R4C=$R4
W4C=$w
w=$(_mkwt "$M2" w4d); ln -s "$M2P/.specops" "$w/.specops"; _chk4 4d "$M2" "$w"; W4D=$w
w=$(_mkwt "$M2" w4dp); mkdir -p "$TD/else4d"; _ownrec "$TD/else4d"; mv "$TD/else4d/.specops/"* "$TD/else4d/" 2>/dev/null; ln -s "$TD/else4d" "$w/.specops"; _chk4 4d\' "$M2" "$w"; W4DP=$w
M3="$TD/main3"; _mkmain "$M3" 0; (cd "$M3" && git add .specops/session-progress.md && _g commit -qm sp)
w=$(_mkwt "$M3" w4e); _chk4 4e "$M3" "$w"; W4E=$w; M3P=$(cd "$M3" && pwd -P)
M3F="$TD/main3f"; _mkmain "$M3F" 0
mkdir -p "$M3F/.specops/$FIDX"; printf 'i\n' > "$M3F/.specops/$FIDX/intent.md"
printf '<!-- active-fid: %s -->\n## %s\n' "$FIDX" "$FIDX" > "$M3F/.specops/session-progress.md"
(cd "$M3F" && git add .specops/session-progress.md ".specops/$FIDX/intent.md" && _g commit -qm sp)
printf '<!-- active-fid: %s -->\n## %s\n- 2026-11-06 08:00 /verify PASS\n' "$FIDM" "$FIDM" > "$M3F/.specops/session-progress.md"
w=$(_mkwt "$M3F" w4f); mkdir -p "$w/.specops/$FIDX/receipts"; printf x > "$w/.specops/$FIDX/receipts/T1.json"
_chk4 4f "$M3F" "$w" "$FIDX"; R4F=$R4; W4F=$w; M3FP=$(cd "$M3F" && pwd -P)

# RR-5 ★ 명령이 git 대상을 옮기면 종전(메인) — 자기 기록 worktree 에서도
n=0; nf=0
for mv in "cd $M2P && git commit -m 'feat: m (Task: T1)'" \
          "pushd $M2P >/dev/null && git commit -m 'feat: m (Task: T1)'" \
          "GIT_DIR=$M2P/.git git commit -m 'feat: m (Task: T1)'" \
          "git --work-tree=$M2P commit -m 'feat: m (Task: T1)'" \
          "git -C $M2P commit -m 'feat: m (Task: T1)'"; do
  r=$(_pre2 "$mv" "$W2P" "$TR")
  [ "$(_dec "$r")" = "deny" ] && n=$((n + 1))
  _why "$r" | grep -qF "$FIDM" && ! _why "$r" | grep -qF "$FIDW" && nf=$((nf + 1))
done
[ "$n" -eq 5 ] && [ "$nf" -eq 5 ] && ok "RR-5 ★ 이동 5형태 · cwd=자기 기록 worktree → 종전(deny · $FIDM)" || nope "RR-5" "deny=$n/5 fid=$nf/5"

# RR-6 안내 문구
printf '%s' "$R2A" | grep -qF "판정 기준 worktree: $W2P" && printf '%s' "$R2A" | grep -qF "기록·관할은 $W2P/.specops" \
  && ! printf '%s' "$R2A" | grep -qF "기록·관할은 $M2P/.specops" && ! printf '%s' "$R2A" | grep -qF '사본을 지우면' \
  && printf '%s' "$R4C" | grep -qF '자기 기록이 없어' \
  && ok "RR-6 안내: 자기 기록 worktree 는 판정 루트 명시 · 자기 기록 없으면 '자기 기록이 없어'" || nope "RR-6" "$(printf '%s' "$R2A" | tail -3) // $(printf '%s' "$R4C" | tail -2)"
# RR-6f 추적 session-progress + 추적 안 된 FID 기록 → 안내가 사실대로 (자기 기록이 없다고 말하지 않는다)
printf '%s' "$R4F" | grep -qF 'session-progress.md 가 git 추적' && ! printf '%s' "$R4F" | grep -qF '자기 기록이 없어' \
  && ok "RR-6f 안내: 추적 session-progress + 추적 안 된 기록 → 'git 추적' 사유 · '자기 기록이 없어' 아님" || nope "RR-6f" "$(printf '%s' "$R4F" | tail -2)"
# RR-6L 프로젝트 .specops 가 링크(가드 a 로 루트 안 옮김) + 추적 안 된 session-progress 의 자기 기록 → 'git 추적' 사유를 말하지 않는다
M6L="$TD/main6l"; _mkmain "$M6L"; mv "$M6L/.specops" "$TD/ext6L"; ln -s "$TD/ext6L" "$M6L/.specops"
(cd "$M6L" && bash "$VS" record "$FIDM" PASS >/dev/null 2>&1); printf 'z\n' > "$M6L/src/foo.sh"
w=$(_mkwt "$M6L" w6l); _ownrec "$w"
r=$(_prem "$M6L" "$C1" "$w" "$TR"); R6L=$(_why "$r")
[ "$(_dec "$r")" = "deny" ] && ! git -C "$w" ls-files --error-unmatch -- .specops/session-progress.md >/dev/null 2>&1 \
  && ! printf '%s' "$R6L" | grep -qF 'session-progress.md 가 git 추적' \
  && ok "RR-6L 안내: 프로젝트 .specops 링크 + 추적 안 된 session-progress → deny · 'git 추적' 사유 아님" || nope "RR-6L" "dec=$(_dec "$r") $(printf '%s' "$R6L" | tail -2)"

# RR-8 (NFR-2) 대상이 없으면 git 을 부르지 않는다
REALGIT=$(command -v git); FG="$TD/fakegit"; mkdir -p "$FG"; CNT="$TD/rr.count"
printf '#!/bin/sh\necho x >> "%s"\nexec "%s" "$@"\n' "$CNT" "$REALGIT" > "$FG/git"; chmod +x "$FG/git"
: > "$CNT"; (export PATH="$FG:$PATH"; source "$PLUGIN/hooks/governance-lib.sh"; cd "$M2"; _GOV_TARGET_WT=; : > "$CNT"; _gov_apply_record_root)
c0=$(wc -l < "$CNT" | tr -d ' ')
: > "$CNT"; (export PATH="$FG:$PATH"; source "$PLUGIN/hooks/governance-lib.sh"; cd "$M2"; : > "$CNT"; _gov_apply_record_root "$W2P" >/dev/null 2>&1)
c1=$(wc -l < "$CNT" | tr -d ' ')
[ "$c0" -eq 0 ] && [ "$c1" -ge 1 ] && ok "RR-8 ★ 대상 없으면 git 0회 · 대조군(대상 있음) ≥1회 (c0=$c0 c1=$c1)" || nope "RR-8" "c0=$c0 c1=$c1"

# RR-9 (NFR-3) git 조회 실패 → 옮기지 않는다
FG9="$TD/fakegit9"; mkdir -p "$FG9"
printf '#!/bin/sh\ncase " $* " in *" ls-files "*"--others"*) exit 1;; esac\nexec "%s" "$@"\n' "$REALGIT" > "$FG9/git"; chmod +x "$FG9/git"
o9=$(export PATH="$FG9:$PATH"; source "$PLUGIN/hooks/governance-lib.sh"; cd "$M2"; _gov_apply_record_root "$W2P"; printf '%s|%s' "$(pwd -P)" "${_GOV_RECORD_ROOT:-}")
[ "$o9" = "$M2P|" ] && ok "RR-9 ★ git 조회 실패 → 옮기지 않음(종전)" || nope "RR-9" "$o9"

# RR-10a 관할 밖 프로젝트 폴더는 자기 기록 worktree 가 있어도 넓히지 않는다
M5="$TD/main5"; _mkmain "$M5"; rm -rf "$M5/.specops"
w=$(_mkwt "$M5" w5); _ownrec "$w"
r=$(_prem "$M5" "git commit -m 'feat: nojur'" "$w" "$TR")
[ -n "$r" ] && [ "$(_dec "$r")" = "allow" ] && [ -z "$(find "$M5" -maxdepth 1 -name .specops)" ] \
  && ok "RR-10a ★ 관할 밖 프로젝트 → allow · 프로젝트 폴더에 .specops 안 생김" || nope "RR-10a" "dec=$(_dec "$r") out=${r:0:60}"

# ── posttool·stop 도 같은 루트에 기록 (T3) ─────────────────────────────────────
STOP="$PLUGIN/hooks/stop-governance.sh"
W5P=$w   # RR-10a 의 관할 밖 프로젝트(M5) 자기 기록 worktree
_lines() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }
FW="$W2P/.specops/$FIDW/friction-log.jsonl"; FM="$M2P/.specops/$FIDM/friction-log.jsonl"
_post2() { _in "$@" | (cd "$M2" && CLAUDE_PROJECT_DIR="$M2" bash "$POST" >/dev/null 2>&1); }

# RR-3 ★ posttool 감사 기록이 worktree FIDW 에
(cd "$W2P" && _g commit -qm 'feat: wt code')   # 방금 커밋(HEAD~1..HEAD)에 코드 변경이 있어야 scope_class=code (WT-8 과 같은 방식)
bw=$(_lines "$FW"); bm=$(_lines "$FM")
_post2 "git commit -m 'feat: audit-post'" "$W2P" "$TR"   # 메시지를 RR-2b 와 달리 — friction dedup(같은 규칙·snippet)
new=$(tail -n +"$((bw + 1))" "$FW" 2>/dev/null | grep '"rule_id":"R-1"'); sc=$(printf '%s\n' "$new" | tail -1 | jq -r '.scope_class // "-"' 2>/dev/null)
[ -n "$new" ] && [ "$sc" = "code" ] && [ "$(_lines "$FM")" -eq "$bm" ] \
  && ok "RR-3 ★ posttool 감사 R-1 기록 → worktree $FIDW (scope_class=code) · 메인 불변" || nope "RR-3" "rec=$(printf '%s' "$new" | grep -c .) sc=$sc main $bm→$(_lines "$FM")"

# RR-5p 이동 5형태 posttool → worktree 줄 수 불변 · 메인 증가
bw=$(_lines "$FW"); bm=$(_lines "$FM"); i=0
for mv in "cd $M2P && git commit -m 'feat: p1 (Task: T1)'" \
          "pushd $M2P >/dev/null && git commit -m 'feat: p2 (Task: T1)'" \
          "GIT_DIR=$M2P/.git git commit -m 'feat: p3 (Task: T1)'" \
          "git --work-tree=$M2P commit -m 'feat: p4 (Task: T1)'" \
          "git -C $M2P commit -m 'feat: p5 (Task: T1)'"; do
  _post2 "$mv" "$W2P" "$TR"
done
[ "$(_lines "$FW")" -eq "$bw" ] && [ "$(_lines "$FM")" -gt "$bm" ] \
  && ok "RR-5p ★ posttool 이동 5형태 → 메인 FIDM 기록 +$(($(_lines "$FM") - bm)) · worktree 불변" || nope "RR-5p" "wt $bw→$(_lines "$FW") main $bm→$(_lines "$FM")"

# RR-7 stop
TR7="$TD/tr7.jsonl"; cp "$FIXT/r4-claim-without-runner.jsonl" "$TR7"
_stop2() {  # $1=프로젝트 $2=cwd
  jq -nc --arg tp "$TR7" --arg w "$2" '{session_id:"s",transcript_path:$tp,hook_event_name:"Stop",stop_hook_active:false,cwd:$w}' \
    | (cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$STOP" 2>/dev/null)
}
_r4() { grep -c '"rule_id":"R-4"' "$1" 2>/dev/null || true; }
bw=$(_r4 "$FW"); bm=$(_lines "$FM")
_stop2 "$M2" "$W2P" >/dev/null
[ "$(_r4 "$FW")" -eq $((bw + 1)) ] && [ "$(_lines "$FM")" -eq "$bm" ] \
  && ok "RR-7a ★ stop cwd=자기 기록 worktree → $FIDW R-4 +1 · 메인 불변" || nope "RR-7a" "wt R-4 $bw→$(_r4 "$FW") main $bm→$(_lines "$FM")"
W4A=$(cd "$M2/.claude/worktrees/w4a" && pwd -P); bm=$(_r4 "$FM")
_stop2 "$M2" "$W4A" >/dev/null
[ "$(_r4 "$FM")" -eq $((bm + 1)) ] && [ ! -e "$W4A/.specops" ] \
  && ok "RR-7b stop cwd=자기 기록 없는 worktree → 메인 FIDM R-4 +1 · worktree .specops 없음" || nope "RR-7b" "main R-4 $bm→$(_r4 "$FM")"
M4="$TD/main4"; git init -q "$M4" && git -C "$M4" symbolic-ref HEAD refs/heads/main; : > "$M4/f"; (cd "$M4" && git add f && _g commit -qm i)
git -C "$M4" worktree add -q "$M4/.claude/worktrees/w" -b feat/w4 2>/dev/null
o=$(_stop2 "$M4" "$M4/.claude/worktrees/w")
[ "$(printf '%s' "$o" | jq -c . 2>/dev/null)" = '{"continue":true}' ] && [ -z "$(find "$M4" -name .specops)" ] \
  && ok "RR-7c 관할 밖(.specops 없음) → continue · .specops 안 생김" || nope "RR-7c" "out=$o"
o=$(printf 'not json' | (cd "$M2" && CLAUDE_PROJECT_DIR="$M2" bash "$STOP" 2>/dev/null)); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$o" | grep -q '"continue":true' && ok "RR-7d 잘못된 JSON → continue · rc 0" || nope "RR-7d" "rc=$rc out=$o"

# RR-10b 메인 .specops 없음 + 자기 기록 worktree → posttool·stop 기록 없음
F5="$W5P/.specops/$FIDW/friction-log.jsonl"; b5=$(_lines "$F5")
_in "git commit -m 'feat: nojur'" "$W5P" "$TR" | (cd "$M5" && CLAUDE_PROJECT_DIR="$M5" bash "$POST" >/dev/null 2>&1)
_stop2 "$M5" "$W5P" >/dev/null
[ "$(_lines "$F5")" -eq "$b5" ] && [ -z "$(find "$M5" -maxdepth 1 -name .specops)" ] \
  && ok "RR-10b ★ 관할 밖 프로젝트 → posttool·stop 이 worktree 에 기록 안 함 · 프로젝트에 .specops 안 생김" || nope "RR-10b" "wt $b5→$(_lines "$F5")"

# RR-B 배치 마커 가드 (20261106-hook-root-batch-freecomment) — 브랜치 feat/X ↔ 마커 .specops/X/ACTIVE (X=batch-…)
_mkbatch() {  # $1=프로젝트 루트(.specops 가 있는 곳). 마커 디렉터리 이름 = batch-p, 브랜치 = feat/batch-p
  mkdir -p "$1/.specops/batch-p" "$1/.specops/memory"
  printf '| FR-ID | FID | 설명 | Status |\n|---|---|---|---|\n| FR-4 | 20260721-login | 로그인 | DONE |\n' > "$1/.specops/batch-p/queue.md"
  printf '| FR-4 | a | M1 | must | s | f |\n' > "$1/.specops/memory/requirements.md"
  : > "$1/.specops/batch-p/ACTIVE"
}
GHPR="gh pr create --fill"
_stale() {  # $1=메인 — FIDM 을 STALE 로 (WT-7 방식)
  (cd "$1" && bash "$VS" record "$FIDM" PASS >/dev/null 2>&1); printf 'z\n' > "$1/src/foo.sh"
}
_wtrec() {  # $1=worktree — receipt 작성
  (cd "$1" && git add scripts/tests/test-foo.sh && bash "$REC" "$FIDW" T1) >/dev/null 2>&1
}
# RR-B0 픽스처 전제
M6="$TD/main6"; _mkmain "$M6"; _mkbatch "$M6"; W6P=$(_mkwt "$M6" batch-p); _ownrec "$W6P"
b6=$(git -C "$W6P" symbolic-ref --short HEAD 2>/dev/null)
[ "$b6" = "feat/batch-p" ] && [ -f "$M6/.specops/${b6#feat/}/ACTIVE" ] && [ ! -e "$W6P/.specops/batch-p" ] \
  && ok "RR-B0 전제: 브랜치 $b6 ↔ 메인 마커 존재 · worktree 쪽 마커 없음" || nope "RR-B0" "br=$b6"
# RR-B1 ★ 혼합 배치(마커=메인, 자기 기록=worktree) → 배치 게이트 작동
r=$(_prem "$M6" "$GHPR" "$W6P" "$TR"); w=$(_why "$r")
[ -n "$r" ] && [ "$(_dec "$r")" = deny ] && printf '%s' "$w" | grep -q 'BATCH-GATE' && printf '%s' "$w" | grep -q 'FR-4' \
  && ! printf '%s' "$w" | grep -q '자기 기록이 없어' && printf '%s' "$w" | grep -q '배치 마커' \
  && ok "RR-B1 ★ 혼합 배치 → BATCH-GATE deny (메인 queue FR-4) · 안내가 배치 마커를 말함" || nope "RR-B1" "dec=$(_dec "$r") why=$w"
# RR-B2 마커가 worktree 쪽 → 종전
M7="$TD/main7"; _mkmain "$M7"; W7P=$(_mkwt "$M7" batch-p); _ownrec "$W7P"; _mkbatch "$W7P"
r=$(_prem "$M7" "$GHPR" "$W7P" "$TR"); w=$(_why "$r")
[ -n "$r" ] && [ "$(_dec "$r")" = deny ] && printf '%s' "$w" | grep -q 'BATCH-GATE' && printf '%s' "$w" | grep -q 'FR-4' \
  && ok "RR-B2 마커가 worktree 쪽 → BATCH-GATE deny (종전)" || nope "RR-B2" "dec=$(_dec "$r") why=$w"
# RR-B3 브랜치 불일치 → 옮겨 판정(과차단 없음)
M8="$TD/main8"; _mkmain "$M8"; _mkbatch "$M8"; _stale "$M8"; W8P=$(_mkwt "$M8" wt8); _ownrec "$W8P"; _wtrec "$W8P"
r=$(_prem "$M8" "$C1" "$W8P" "$TR")
[ -n "$r" ] && [ "$(_dec "$r")" = allow ] && ok "RR-B3 브랜치 feat/wt8 ≠ feat/batch-p → 옮겨 receipt 로 allow" || nope "RR-B3" "dec=$(_dec "$r") why=$(_why "$r")"
# RR-B3b feat/ 접두 없는 브랜치
M9="$TD/main9"; _mkmain "$M9"; _mkbatch "$M9"; _stale "$M9"
git -C "$M9" worktree add -q "$M9/.claude/worktrees/w9" -b batch-p 2>/dev/null
printf 'y\n' > "$M9/.claude/worktrees/w9/src/foo.sh"; (cd "$M9/.claude/worktrees/w9" && git add src/foo.sh)
W9P=$(cd "$M9/.claude/worktrees/w9" && pwd -P); _ownrec "$W9P"; _wtrec "$W9P"
r=$(_prem "$M9" "$C1" "$W9P" "$TR")
[ -n "$r" ] && [ "$(_dec "$r")" = allow ] && ok "RR-B3b feat/ 없는 브랜치 batch-p → 옮겨 판정 allow" || nope "RR-B3b" "dec=$(_dec "$r") why=$(_why "$r")"
# RR-B4 detached HEAD → 가드 불작용
W10P=$(_mkwt "$M8" wt10); _ownrec "$W10P"; git -C "$W10P" checkout -q --detach; _wtrec "$W10P"
r=$(_prem "$M8" "$C1" "$W10P" "$TR")
[ -n "$r" ] && [ "$(_dec "$r")" = allow ] && ok "RR-B4 detached HEAD → 가드 불작용 · 종전 allow" || nope "RR-B4" "dec=$(_dec "$r") why=$(_why "$r")"
# RR-B5 의도한 변경 고정 — 혼합 배치 worktree 의 일반 커밋은 메인 기준 판정
_stale "$M6"; _wtrec "$W6P"
r=$(_prem "$M6" "$C1" "$W6P" "$TR"); w=$(_why "$r")
[ -n "$r" ] && [ "$(_dec "$r")" = deny ] && printf '%s' "$w" | grep -q "$FIDM" && ! printf '%s' "$w" | grep -q "$FIDW" \
  && ok "RR-B5 혼합 배치 worktree 일반 커밋 → 메인 FIDM 기준 deny (의도된 변경)" || nope "RR-B5" "dec=$(_dec "$r") why=$w"

# FC 자유 코멘트·진행 기록 귀속 고정 (AC-4 · 코드 무변경) — 실제 훅을 별도 프로세스로 돌린다
FCH="$PLUGIN/hooks/freecomment-capture.sh"; ENS="$PLUGIN/hooks/ensure-session-progress.sh"
_fc_tr() {  # $1=편집 파일 경로(훅이 보는 문자열 그대로) → transcript 경로
  local t="$TD/fc-$RANDOM.jsonl"
  printf '%s\n' \
    '{"type":"user","message":{"role":"user","content":"버그 고쳐줘"}}' \
    "$(jq -nc --arg f "$1" '{type:"assistant",message:{content:[{type:"tool_use",id:"e1",name:"Edit",input:{file_path:$f}}]}}')" > "$t"
  printf '%s' "$t"
}
_fc_in() { jq -nc --arg c "$1" --arg t "$2" '{cwd:$c,transcript_path:$t,stop_hook_active:false}'; }
_fc_run() { local out; out=$(_fc_in "$2" "$3" | (cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$FCH" 2>/dev/null)); printf '%s' "$out" | grep -q '"continue":true'; }  # rc 0 = 훅이 돌았다
# 순서 의존: FC-1 → FC-2 는 한 메인 MF 를 공유한다(FC-2 가 메인에 pending 을 만든다) — 순서를 바꾸지 말 것.
MF="$TD/mainF"; _mkmain "$MF"
# FC-1 자유 코멘트는 cwd(worktree) 자기 기록에 귀속
WFP=$(_mkwt "$MF" wtf); _ownrec "$WFP"
tr=$(_fc_tr "$WFP/src/foo.sh")
if _fc_run "$MF" "$WFP" "$tr"; then
  tail -1 "$WFP/.specops/pending-capture.jsonl" 2>/dev/null | jq -e '.fid == "'"$FIDW"'" and .files == ["src/foo.sh"]' >/dev/null 2>&1 \
    && [ ! -e "$MF/.specops/pending-capture.jsonl" ] \
    && ok "FC-1 자유 코멘트 → worktree 자기 기록에 귀속 · 메인 무기록" || nope "FC-1" "wt=$(tail -1 "$WFP/.specops/pending-capture.jsonl" 2>&1) main=$(ls "$MF/.specops" 2>&1)"
else nope "FC-1" "훅 미실행(rc≠0)"; fi
# FC-2 worktree 에 .specops 가 없으면 훅은 프로젝트 폴더의 변경만 본다 — 현재 동작의 고정 (메인을 더티로: 훅이 거기서 git diff HEAD)
WGP=$(_mkwt "$MF" wtg); printf 'q\n' > "$MF/src/foo.sh"
tr=$(_fc_tr "$MF/src/foo.sh")
if _fc_run "$MF" "$WGP" "$tr"; then
  tail -1 "$MF/.specops/pending-capture.jsonl" 2>/dev/null | jq -e '.files == ["src/foo.sh"] and .fid == "'"$FIDM"'"' >/dev/null 2>&1 \
    && [ ! -e "$WGP/.specops" ] \
    && ok "FC-2 worktree .specops 없음 → 프로젝트 폴더에 귀속 · worktree 무흔적" || nope "FC-2" "main=$(tail -1 "$MF/.specops/pending-capture.jsonl" 2>&1) wtspecops=$(ls -d "$WGP/.specops" 2>&1)"
else nope "FC-2" "훅 미실행(rc≠0)"; fi
# FC-3 ensure 는 worktree 자기 .specops 에 만든다
WHP=$(_mkwt "$MF" wth); mkdir -p "$WHP/.specops"
before=$(cksum < "$MF/.specops/session-progress.md")
(cd "$WHP" && CLAUDE_PROJECT_DIR="$MF" bash "$ENS") >/dev/null 2>&1
[ -f "$WHP/.specops/session-progress.md" ] && [ "$(cksum < "$MF/.specops/session-progress.md")" = "$before" ] \
  && ok "FC-3 ensure → worktree 자기 .specops 에 생성 · 메인 불변" || nope "FC-3" "wt=$(ls "$WHP/.specops" 2>&1)"
# FC-4 ensure 가 관할을 넓히지 않는다
WIP=$(_mkwt "$MF" wti); mkdir "$TD/nospec"
(cd "$WIP" && CLAUDE_PROJECT_DIR="$TD/nospec" bash "$ENS") >/dev/null 2>&1
[ ! -e "$WIP/.specops" ] && [ ! -e "$TD/nospec/.specops" ] \
  && ok "FC-4 .specops 없는 worktree·프로젝트 → ensure 가 만들지 않음" || nope "FC-4" "wt=$(ls -d "$WIP/.specops" 2>&1) proj=$(ls -d "$TD/nospec/.specops" 2>&1)"
# FC-4b 양성 대조 — 프로젝트 폴더에 .specops 가 있으면 폴백이 거기에 만든다
MJ="$TD/mainJ"; mkdir -p "$MJ/.specops"
(cd "$WIP" && CLAUDE_PROJECT_DIR="$MJ" bash "$ENS") >/dev/null 2>&1
[ -f "$MJ/.specops/session-progress.md" ] && [ ! -e "$WIP/.specops" ] \
  && ok "FC-4b 양성 대조 — 폴백이 프로젝트 폴더에 생성 · worktree 무흔적" || nope "FC-4b" "proj=$(ls "$MJ/.specops" 2>&1) wt=$(ls -d "$WIP/.specops" 2>&1)"

# RR-P 패리티 — 훅이 고르는 판정 루트 = 기록 스크립트(specops_root_dir)가 쓰는 곳 (성공지표 M-1)
_par() {  # $1=이름 $2=프로젝트 $3=입력 cwd
  local H FIDL S
  H=$( (source "$PLUGIN/hooks/governance-lib.sh"; cd "$2"; _gov_apply_git_target "$3"; _gov_apply_record_root; pwd -P) )
  FIDL=$(cd "$H" && detect_fid)
  S=$(cd "$3" && unset GIT_DIR GIT_WORK_TREE; cd "$(git rev-parse --show-toplevel)"; specops_root_dir "$FIDL")   # 하위 폴더 cwd 도 최상위 기준 — 비리다이렉트 기본값이 $PWD/.specops 라 하위 폴더에서 호출하면 sub/.specops 를 낸다(기존 동작·범위 밖)
  [ "$(cd "$H/.specops" && pwd -P)" = "$(cd "$S" && pwd -P)" ] && ok "RR-P $1 패리티 (훅=$H · 기록=$S)" || nope "RR-P $1" "H=$H S=$S"
}
_par "W2P" "$M2" "$W2P"; _par "W2P/sub" "$M2" "$W2P/sub"
_par "4a" "$M2" "$(cd "$M2/.claude/worktrees/w4a" && pwd -P)"; _par "4b" "$M2" "$(cd "$M2/.claude/worktrees/w4b" && pwd -P)"
_par "4b'" "$M2" "$(cd "$M2/.claude/worktrees/w4bp" && pwd -P)"; _par "4c" "$M2" "$W4C"; _par "4d" "$M2" "$W4D"
_par "4e" "$M3" "$W4E"
_par "프로젝트=W2P 자신" "$W2P" "$W2P"; _par "메인 cwd" "$M2" "$M2P"; _par "프로젝트=W2P · cwd=메인" "$W2P" "$M2P"
for t in "4d'(의도된 불일치: 링크 .specops — 가드 a)|$M2|$W4DP|$M2P" "4f(의도된 불일치: 추적 session-progress — 가드 c)|$M3F|$W4F|$M3FP"; do
  IFS='|' read -r nm pj cw want <<< "$t"
  H=$( (source "$PLUGIN/hooks/governance-lib.sh"; cd "$pj"; _gov_apply_git_target "$cw"; _gov_apply_record_root; pwd -P) )
  [ "$H" = "$want" ] && ok "RR-P $nm → 프로젝트 폴더 고정" || nope "RR-P $nm" "H=$H want=$want"
done

finish
