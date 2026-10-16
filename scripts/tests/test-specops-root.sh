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

# SR-5 이동하지 않는 경우 — 일반 저장소 · GIT_DIR 이 이미 있을 때
P="$TD/plain"; git init -q "$P"
(cd "$P" && bash "$APPEND" 20261016-plain /specify 완료 x) >/dev/null 2>&1
a=$( cd "$W" && GIT_DIR="$M/.git" bash -c "source '$SR'; specops_root_enter; echo rc=\$? pwd=\$(pwd -P)" )
b=$( cd "$W" && SPECOPS_ROOT="$TD/x" bash -c "source '$SR'; specops_root_enter; echo rc=\$? pwd=\$(pwd -P)" )
[ -f "$P/.specops/session-progress.md" ] && [ "$a" = "rc=1 pwd=$WP" ] && [ "$b" = "rc=1 pwd=$WP" ] \
  && ok "SR-5 일반 저장소는 종전대로 ./.specops · GIT_DIR·SPECOPS_ROOT 가 있으면 이동하지 않음" || nope "SR-5" "a=$a b=$b"

finish
