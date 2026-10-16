#!/usr/bin/env bash
# 기록 스크립트의 .specops 위치 — worktree 에서도 메인 기록에 쓴다 (20261016-hook-worktree-target)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
APPEND="$PLUGIN/scripts/session-progress-append.sh"
REC="$PLUGIN/scripts/_internal/record-task-receipt.sh"
RUNV="$PLUGIN/scripts/_internal/run-verification.sh"
SR="$PLUGIN/scripts/_internal/specops-root.sh"
PRE="$PLUGIN/hooks/pretool-governance.sh"
TD=$(mktemp -d) || exit 1
trap 'rm -rf "$TD"' EXIT
FID=20261016-sr
_g() { git -c user.name=t -c user.email=t@e.com "$@"; }
_tasks_md() {  # $1=경로 — DAG 픽스처. 제목·펜스를 printf 로 만든다: 이 테스트 코드가 tasks.md 에 실릴 때 진짜 DAG 로 읽히지 않게(dag::extract_yaml 은 줄 맨 앞 첫 `## 의존 그래프` 를 집는다)
  { printf '# tasks\n\n## %s\n\n%syaml\n' '의존 그래프' '```'
    printf 'tasks:\n  - id: T1\n    test_command: "bash scripts/tests/test-foo.sh"\n    depends_on: []\n    inputs: []\n    outputs: [src/foo.sh, scripts/tests/test-foo.sh]\n    ac: [AC-1]\n%s\n' '```'; } > "$1"
}

_mk() {  # $1=메인 폴더 $2=마커 파일 — 메인 + .specops/FID(tasks) + worktree .worktrees/FID (worktree 에는 .specops 없음)
  local m=$1 mk=$2
  git init -q "$m" && git -C "$m" symbolic-ref HEAD refs/heads/main
  printf '.specops/\n.worktrees/\n' > "$m/.gitignore"
  mkdir -p "$m/scripts/tests" "$m/src" "$m/.specops/$FID"
  # 테스트 명령은 자기가 돈 폴더와 GIT_DIR 을 마커에 남긴다 — 원래 폴더 · git env 없음 이어야 한다
  printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "$(pwd -P)" "${GIT_DIR:-none}" >> "%s"\nexit 0\n' "$mk" > "$m/scripts/tests/test-foo.sh"
  chmod +x "$m/scripts/tests/test-foo.sh"
  printf 'x\n' > "$m/src/foo.sh"
  (cd "$m" && git add -A && _g commit -qm init)
    _tasks_md "$m/.specops/$FID/tasks.md"
  printf '<!-- active-fid: %s -->\n## %s\n' "$FID" "$FID" > "$m/.specops/session-progress.md"
  git -C "$m" worktree add -q "$m/.worktrees/$FID" -b "feat/$FID" 2>/dev/null
}

# ── Argus식: 프로젝트 = 메인, 셸 = worktree ───────────────────────────────────
M="$TD/a"; MK="$TD/a.marker"; _mk "$M" "$MK"; W="$M/.worktrees/$FID"; WP=$(cd "$W" && pwd -P)

# SR-1 진행 기록
(cd "$W" && bash "$APPEND" "$FID" /verify PASS "sr-1") >/dev/null 2>&1
grep '/verify PASS' "$M/.specops/session-progress.md" | grep -q 'sr-1' && [ ! -e "$W/.specops" ] \
  && ok "SR-1 ★ worktree 에서 진행 기록 → 메인 .specops · worktree 에 .specops 안 생김" || nope "SR-1" "$(ls -a "$W" | tr '\n' ' ')"
# 다음 단언들이 /verify PASS 앵커에 영향받지 않게 진행 기록을 되돌린다
printf '<!-- active-fid: %s -->\n## %s\n- 2026-10-16 10:00 /implement DONE (T1)\n' "$FID" "$FID" > "$M/.specops/session-progress.md"

# SR-2 receipt — 테스트는 worktree 에서 git env 없이 돈다 (SPECOPS_ROOT 없음 = enter 경로)
printf 'y\n' > "$W/src/foo.sh"
: > "$MK"
(cd "$W" && bash "$REC" "$FID" T1) >/dev/null 2>&1
[ -f "$M/.specops/$FID/receipts/T1.json" ] && [ ! -e "$W/.specops" ] && [ "$(cat "$MK")" = "$WP|none" ] \
  && ok "SR-2 ★ worktree 에서 receipt → 메인 .specops · 테스트는 worktree·git env 없음" || nope "SR-2" "marker=$(cat "$MK")"

# SR-6 (AC-1 결합 종단) — SR-2 의 receipt 로 worktree 셸의 커밋이 훅을 통과한다
printf '# spec\n' > "$M/.specops/$FID/spec.md"
(cd "$W" && git add src/foo.sh scripts/tests/test-foo.sh)
TR="$TD/tr.jsonl"
printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"bash scripts/tests/test-foo.sh"}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu1","content":"ok"}]}}' > "$TR"
r=$(jq -nc --arg c "git commit -m 'feat: x (Task: T1)'" --arg w "$W" --arg t "$TR" '{tool_name:"Bash",tool_input:{command:$c},transcript_path:$t,cwd:$w}' \
  | (cd "$M" && CLAUDE_PROJECT_DIR="$M" bash "$PRE" 2>/dev/null))
[ "$(printf '%s' "$r" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')" = "allow" ] \
  && ok "SR-6 ★ worktree 에서 남긴 receipt(SPECOPS_ROOT 없음) → 훅 allow" || nope "SR-6" "$(printf '%s' "$r" | jq -r '.hookSpecificOutput.permissionDecisionReason' | head -3)"
rm -f "$M/.specops/$FID/spec.md"   # SR-3 의 검증 러너가 AC 계약 검사를 하지 않게 (spec 없는 FID)
(cd "$W" && git reset -q)

# SR-3 검증 러너 — evidence·판정 상태는 메인, 테스트는 worktree
: > "$MK"
out=$(cd "$W" && bash "$RUNV" "$FID" 2>&1)
st=$(jq -r '.verdict // "-"' "$M/.specops/$FID/verification-state.json" 2>/dev/null)
printf '%s' "$out" | grep -q 'VERIFY: PASS' && [ "$st" = "PASS" ] && [ ! -e "$W/.specops" ] \
  && grep -q 'run-verification.sh' "$M/.specops/$FID/evidence.md" && [ "$(head -1 "$MK")" = "$WP|none" ] \
  && ok "SR-3 ★ worktree 에서 검증 러너 → 메인 evidence·판정 상태 PASS · 테스트는 worktree" || nope "SR-3" "st=$st marker=$(head -1 "$MK") out=$(printf '%s' "$out" | tail -2)"

# ── Specops식: 프로젝트 = linked worktree, 자기 .specops · 메인 worktree 에도 다른 .specops ──
R="$TD/b"; MK2="$TD/b.marker"; _mk "$R" "$MK2"; L="$R/.worktrees/$FID"
mkdir -p "$L/.specops/$FID" && cp "$R/.specops/$FID/tasks.md" "$L/.specops/$FID/" && printf '## %s\n' "$FID" > "$L/.specops/session-progress.md"
sum_before=$(cat "$R/.specops/session-progress.md" | git hash-object --stdin)
(cd "$L" && bash "$APPEND" "$FID" /verify PASS "sr-4") >/dev/null 2>&1
printf 'y\n' > "$L/src/foo.sh"
(cd "$L" && bash "$REC" "$FID" T1) >/dev/null 2>&1
grep '/verify PASS' "$L/.specops/session-progress.md" | grep -q 'sr-4' && [ -f "$L/.specops/$FID/receipts/T1.json" ] \
  && [ "$(cat "$R/.specops/session-progress.md" | git hash-object --stdin)" = "$sum_before" ] && [ ! -e "$R/.specops/$FID/receipts" ] \
  && ok "SR-4 ★ 자기 .specops 가 있는 linked worktree → 자기 기록 · 메인 worktree 기록 불변" || nope "SR-4" "-"

# SR-7 같은 형태의 하위 폴더에서 불러도 자기 기록 — 메인 worktree 기록에 쓰지 않는다
mkdir -p "$L/src"
sum_before=$(git hash-object "$R/.specops/session-progress.md")
(cd "$L/src" && bash "$APPEND" "$FID" /verify PASS "sr-7") >/dev/null 2>&1
[ "$(git hash-object "$R/.specops/session-progress.md")" = "$sum_before" ] && ! grep -rqs 'sr-7' "$R/.specops" \
  && ok "SR-7 ★ 자기 .specops 가 있는 linked worktree 의 하위 폴더 → 메인 worktree 기록 불변 (하위 폴더 ./.specops 생성은 이번 FID 이전부터의 동작 — 별건)" \
  || nope "SR-7" "메인 worktree 기록에 sr-7 이 쓰였다 main=$(grep -c 'sr-7' "$R/.specops/session-progress.md") (하위 폴더 ./.specops 생성은 별건)"

# SR-5 이동하지 않는 경우 — 일반 저장소 · GIT_DIR 이 이미 있을 때
P="$TD/plain"; git init -q "$P"
(cd "$P" && bash "$APPEND" 20261016-plain /specify 완료 x) >/dev/null 2>&1
a=$( cd "$W" && GIT_DIR="$M/.git" bash -c "source '$SR'; specops_root_enter; echo rc=\$? pwd=\$(pwd -P)" )
b=$( cd "$W" && SPECOPS_ROOT="$TD/x" bash -c "source '$SR'; specops_root_enter; echo rc=\$? pwd=\$(pwd -P)" )
[ -f "$P/.specops/session-progress.md" ] && [ "$a" = "rc=1 pwd=$WP" ] && [ "$b" = "rc=1 pwd=$WP" ] \
  && ok "SR-5 일반 저장소는 종전대로 ./.specops · GIT_DIR·SPECOPS_ROOT 가 있으면 이동하지 않음" || nope "SR-5" "a=$a b=$b"

# ── 판정 스크립트 3종 (20261016-judge-scripts-worktree-root) — worktree 에서 불러도 훅 상태와 같은 답 ──
#   훅 상태 = 프로젝트 폴더 + 그 worktree 의 GIT_DIR·GIT_WORK_TREE (_gov_apply_git_target 가 만드는 상태).
CTR="$PLUGIN/scripts/_internal/check-task-receipt.sh"
RR="$PLUGIN/scripts/_internal/release-ready.sh"
RSP="$PLUGIN/scripts/_internal/review-skip-pass.sh"
C="$TD/c"; MK3="$TD/c.marker"; _mk "$C" "$MK3"; CW="$C/.worktrees/$FID"; CWP=$(cd "$CW" && pwd -P)
CGD=$(git -C "$CW" rev-parse --absolute-git-dir)
_hookstate() { (cd "$C" && GIT_DIR="$CGD" GIT_WORK_TREE="$CW" "$@"); }
_rel() { perl -MFile::Spec -e 'print File::Spec->abs2rel($ARGV[0], $ARGV[1])' "$1" "$CWP"; }   # 상대경로 호출 — 이동 전에 자기 위치를 잡는지
printf '# spec\n' > "$C/.specops/$FID/spec.md"
printf 'y\n' > "$CW/src/foo.sh"
(cd "$CW" && bash "$REC" "$FID" T1) >/dev/null 2>&1
(cd "$CW" && git add src/foo.sh)

# SR-8 check-task-receipt — 유효 receipt 는 둘 다 0 · outputs 밖 staged 는 둘 다 1 + 같은 사유
w=$(cd "$CW" && bash "$CTR" "$FID" T1 2>&1); wrc=$?
wr=$(cd "$CW" && bash "$(_rel "$CTR")" "$FID" T1 2>&1); wrrc=$?
h=$(_hookstate bash "$CTR" "$FID" T1 2>&1); hrc=$?
printf 'z\n' > "$CW/extra.txt"; (cd "$CW" && git add extra.txt)
w2=$(cd "$CW" && bash "$CTR" "$FID" T1 2>&1); wrc2=$?
h2=$(_hookstate bash "$CTR" "$FID" T1 2>&1); hrc2=$?
(cd "$CW" && git rm -q --cached extra.txt); rm -f "$CW/extra.txt"
[ "$wrc" = 0 ] && [ "$wrrc" = 0 ] && [ "$hrc" = 0 ] && [ "$wrc2" = 1 ] && [ "$hrc2" = 1 ] && [ -n "$w2" ] && [ "$w2" = "$h2" ] && [ ! -e "$CW/.specops" ] \
  && ok "SR-8 ★ worktree 에서 check-task-receipt → 훅 상태와 같은 rc·사유 (상대경로 호출 포함 · worktree 에 .specops 안 생김)" \
  || nope "SR-8" "rc w=$wrc rel=$wrrc hook=$hrc · outside w=$wrc2 hook=$hrc2 [$w2] vs [$h2] · rel=[$wr]"

# SR-9 release-ready — 출력 전체·rc 가 같다
mkdir -p "$C/.specops/$FID/reviews"
printf 'ok\n' > "$C/.specops/$FID/reviews/T1-B-report.md"; cp "$C/.specops/$FID/reviews/T1-B-report.md" "$C/.specops/$FID/reviews/T1-C-report.md"
# 판정 상태는 worktree 의 git 지문으로 남긴다 — 이동 뒤 git env 를 잃으면 메인 트리 지문으로 STALE 이 되어 출력이 갈라진다
mv "$C/.specops/$FID/spec.md" "$TD/c.spec"   # 검증 러너가 AC 계약 검사를 하지 않게 (SR-3 과 같은 이유)
(cd "$CW" && bash "$RUNV" "$FID") >/dev/null 2>&1
mv "$TD/c.spec" "$C/.specops/$FID/spec.md"
w=$(cd "$CW" && bash "$RR" "$FID" 2>&1); wrc=$?
wr=$(cd "$CW" && bash "$(_rel "$RR")" "$FID" 2>&1); wrrc=$?
h=$(_hookstate bash "$RR" "$FID" 2>&1); hrc=$?
[ "$w" = "$h" ] && [ "$wr" = "$h" ] && [ "$wrc" = "$hrc" ] && [ "$wrrc" = "$hrc" ] && printf '%s' "$h" | grep -qx '  verify=PASS' \
  && ! printf '%s' "$w" | grep -q 'fid-dir-missing' && [ ! -e "$CW/.specops" ] \
  && ok "SR-9 ★ worktree 에서 release-ready → 훅 상태와 출력·rc 동일 (상대경로 호출 포함)" \
  || nope "SR-9" "rc w=$wrc rel=$wrrc hook=$hrc · w=[$(printf '%s' "$w" | head -2 | tr '\n' ' ')] h=[$(printf '%s' "$h" | head -2 | tr '\n' ' ')]"

finish
