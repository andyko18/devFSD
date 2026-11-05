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

# SR-10 review-skip-pass — 메인 기록에 쓴다 (상대경로로 부른다 — 이동 전에 HERE 를 잡는지)
printf 'review_mode: end-loaded\n' >> "$C/.specops/$FID/tasks.md"
out=$(cd "$CW" && bash "$(_rel "$RSP")" "$FID" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$out" = "review-skip-pass: OK $FID" ] && [ -f "$C/.specops/$FID/review-skip.md" ] \
  && grep -q '/request-review' "$C/.specops/session-progress.md" && grep -q '/receive-review' "$C/.specops/session-progress.md" && [ ! -e "$CW/.specops" ] \
  && ok "SR-10 ★ worktree 에서 review-skip-pass → 메인 review-skip.md · 진행 기록 두 줄 · worktree 에 .specops 안 생김" \
  || nope "SR-10" "rc=$rc out=[$out]"

# SR-11 이동하지 않아야 하는 호출 — (a) 자기 .specops 가 있는 linked worktree (b) SPECOPS_ROOT 지정
printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$L/.specops/$FID/evidence.md"
printf '# spec\n' > "$L/.specops/$FID/spec.md"; printf 'review_mode: end-loaded\n' >> "$L/.specops/$FID/tasks.md"
mkdir -p "$L/.specops/$FID/reviews"; printf 'ok\n' > "$L/.specops/$FID/reviews/T1-B-report.md"; cp "$L/.specops/$FID/reviews/T1-B-report.md" "$L/.specops/$FID/reviews/T1-C-report.md"
(cd "$L" && git add src/foo.sh)
sum_before=$(git hash-object "$R/.specops/session-progress.md")
a1=$(cd "$L" && bash "$CTR" "$FID" T1 2>&1); a1rc=$?
a2=$(cd "$L" && bash "$RR" "$FID" 2>&1)
a3=$(cd "$L" && bash "$RSP" "$FID" 2>&1); a3rc=$?
(cd "$L" && git reset -q)
mkdir -p "$TD/empty"
b=$(cd "$CW" && SPECOPS_ROOT="$TD/empty" bash "$RR" "$FID" 2>&1); brc=$?
[ "$a1rc" = 0 ] && ! printf '%s' "$a2" | grep -q 'legacy-no-verify-artifact' && [ "$a3rc" = 0 ] && [ -f "$L/.specops/$FID/review-skip.md" ] \
  && [ ! -e "$R/.specops/$FID/review-skip.md" ] && [ "$(git hash-object "$R/.specops/session-progress.md")" = "$sum_before" ] \
  && [ "$brc" = 2 ] && printf '%s' "$b" | grep -q 'reason=fid-dir-missing' \
  && ok "SR-11 자기 .specops 가 있는 linked worktree 는 자기 기록으로 판정·메인 worktree 기록 불변 · SPECOPS_ROOT 지정은 이동하지 않음" \
  || nope "SR-11" "a1=${a1rc}[$a1] a2=[$(printf '%s' "$a2" | head -2 | tr '\n' ' ')] a3=${a3rc}[$a3] b=${brc}[$b]"

# ── 하류 기본 구조 (20261016-specops-root-tracked-dir) — .specops/memory·session-progress.md 를 git 추적하는 repo ──
#   /init-project 로 만든 repo 는 worktree 에도 .specops 가 체크아웃된다. 그 FID 의 기록이 worktree 에 없으면 메인으로 간다.
#   .specops/.gitignore 는 init 템플릿 그대로(new — <FID>/intent.md 도 추적)와 구 템플릿(old — FID 폴더 통째 ignore) 둘 다 본다.
TFID=20261016-trk
_mk_tracked() {  # $1=메인 폴더 $2=new|old $3=마커 파일
  local m=$1 kind=$2 mk=$3
  git init -q "$m" && git -C "$m" symbolic-ref HEAD refs/heads/main
  mkdir -p "$m/scripts/tests" "$m/src" "$m/.specops/memory"
  printf '.worktrees/\n' > "$m/.gitignore"
  if [ "$kind" = new ]; then
    bash -c 'source "$1" && _specops_gitignore_template' _ "$PLUGIN/scripts/_internal/init-project/phases-artifacts.sh" > "$m/.specops/.gitignore"
    mkdir -p "$m/.specops/$TFID" && printf '# intent\n' > "$m/.specops/$TFID/intent.md"
  else
    printf '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*/\nsession-progress.md.bak\n' > "$m/.specops/.gitignore"
  fi
  printf '# constitution\n' > "$m/.specops/memory/constitution.md"
  printf '<!-- active-fid: %s -->\n## %s\n' "$TFID" "$TFID" > "$m/.specops/session-progress.md"
  # 테스트 명령은 자기가 돈 폴더·GIT_DIR 을 마커에 남기고, worktree 의 .specops/memory 를 상대경로로 읽는다(하류 테스트가 그렇게 읽는다)
  printf '#!/usr/bin/env bash\n[ -f .specops/memory/constitution.md ] || exit 1\nprintf "%%s|%%s\\n" "$(pwd -P)" "${GIT_DIR:-none}" >> "%s"\nexit 0\n' "$mk" > "$m/scripts/tests/test-foo.sh"
  chmod +x "$m/scripts/tests/test-foo.sh"
  printf 'x\n' > "$m/src/foo.sh"
  (cd "$m" && git add -A && _g commit -qm init)
  mkdir -p "$m/.specops/$TFID"
  { printf '# tasks\n\n## %s\n\n%syaml\n' '의존 그래프' '```'
    printf 'tasks:\n  - id: T1\n    test_command: "bash scripts/tests/test-foo.sh"\n    depends_on: []\n    inputs: []\n    outputs: [src/foo.sh, scripts/tests/test-foo.sh]\n    ac: [AC-1]\n%s\n' '```'; } > "$m/.specops/$TFID/tasks.md"
  git -C "$m" worktree add -q "$m/.worktrees/$TFID" -b "feat/$TFID" 2>/dev/null
}
_enter_at() {  # $1=부를 폴더 $2=FID — rc·cwd·GIT_WORK_TREE 를 한 줄로
  ( cd "$1" && unset GIT_DIR GIT_WORK_TREE SPECOPS_ROOT && source "$SR" && specops_root_enter "$2"; echo "rc=$? pwd=$(pwd -P) wt=${GIT_WORK_TREE:-none}" )
}
TN="$TD/tn"; _mk_tracked "$TN" new "$TD/tn.marker"; TNW="$TN/.worktrees/$TFID"; TNP=$(cd "$TN" && pwd -P)
TO="$TD/to"; _mk_tracked "$TO" old "$TD/to.marker"; TOW="$TO/.worktrees/$TFID"; TOP=$(cd "$TO" && pwd -P)
TNWP=$(cd "$TNW" && pwd -P); TOWP=$(cd "$TOW" && pwd -P)   # git 이 내는 worktree 경로는 실경로다

# SR-12 하류 기본 구조(새·구 템플릿)의 worktree 최상위·하위 폴더 → 메인으로 이동 (macOS .DS_Store 는 기록으로 치지 않는다)
printf 'x' > "$TNW/.specops/$TFID/.DS_Store"
a=$(_enter_at "$TNW" "$TFID"); b=$(_enter_at "$TNW/src" "$TFID"); c=$(_enter_at "$TOW" "$TFID"); d=$(_enter_at "$TOW/src" "$TFID")
rm -f "$TNW/.specops/$TFID/.DS_Store"
[ -d "$TNW/.specops/$TFID" ] && [ ! -e "$TOW/.specops/$TFID" ] \
  && [ "$a" = "rc=0 pwd=$TNP wt=$TNWP" ] && [ "$b" = "rc=0 pwd=$TNP wt=$TNWP" ] && [ "$c" = "rc=0 pwd=$TOP wt=$TOWP" ] && [ "$d" = "rc=0 pwd=$TOP wt=$TOWP" ] \
  && ok "SR-12 ★ .specops 를 git 추적하는 worktree(새 템플릿 — intent.md 추적 · 구 템플릿) 최상위·하위 폴더 → 메인으로 이동" \
  || nope "SR-12" "new=[$a] [$b] old=[$c] [$d]"

# SR-13 이동하지 않아야 할 때 — FID 없음·형식 틀림·메인에 없는 FID·worktree 에 그 FID 의 기록(추적 안 하는 파일)이 있음
e1=$(_enter_at "$TNW" ""); e2=$(_enter_at "$TNW" "memory"); e3=$(_enter_at "$TNW" "20261016-none")   # memory 는 메인에 실재하는 비-FID 이름 — 형식 검사가 지킨다
printf 'local\n' > "$TNW/.specops/$TFID/tasks.md"
e4=$(_enter_at "$TNW" "$TFID"); rm -f "$TNW/.specops/$TFID/tasks.md"
mkdir -p "$TD/lnk-target" && ln -s "$TD/lnk-target" "$TN/.specops/20261016-lnk"   # 메인의 FID 폴더가 링크
e5=$(_enter_at "$TNW" "20261016-lnk")
x="rc=1 pwd=$TNWP wt=none"
[ "$e1" = "$x" ] && [ "$e2" = "$x" ] && [ "$e3" = "$x" ] && [ "$e4" = "$x" ] && [ "$e5" = "$x" ] \
  && ok "SR-13 FID 없음·형식 틀림·메인에 없는 FID·worktree 에 자기 기록·메인 FID 폴더가 링크면 이동하지 않음" \
  || nope "SR-13" "[$e1] [$e2] [$e3] [$e4] [$e5]"

# SR-14 기록 스크립트 — 진행 기록·receipt 가 메인에 남고 worktree 의 추적 .specops 는 그대로 (새 템플릿)
: > "$TD/tn.marker"
(cd "$TNW" && bash "$APPEND" "$TFID" /implement DONE "sr-14") >/dev/null 2>&1
printf 'y\n' > "$TNW/src/foo.sh"
(cd "$TNW" && bash "$REC" "$TFID" T1) >/dev/null 2>&1
TNWM=$(cd "$TNW" && pwd -P)
grep -q 'sr-14' "$TN/.specops/session-progress.md" && ! grep -q 'sr-14' "$TNW/.specops/session-progress.md" \
  && [ -f "$TN/.specops/$TFID/receipts/T1.json" ] && [ "$(head -1 "$TD/tn.marker")" = "$TNWM|none" ] \
  && [ -z "$(git -C "$TNW" status --porcelain -- .specops)" ] \
  && ok "SR-14 ★ 추적 .specops worktree 에서 진행 기록·receipt → 메인 · 테스트는 worktree(memory 상대경로) · worktree .specops 불변" \
  || nope "SR-14" "main=$(grep -c sr-14 "$TN/.specops/session-progress.md") wt=$(grep -c sr-14 "$TNW/.specops/session-progress.md") marker=$(head -1 "$TD/tn.marker") status=[$(git -C "$TNW" status --porcelain -- .specops | tr '\n' ' ')]"

# SR-14b review-saved mark — 표지가 메인에 남고 worktree 의 추적 .specops 는 그대로
(cd "$TNW" && bash "$PLUGIN/scripts/_internal/review-saved.sh" mark "$TFID" B) >/dev/null 2>&1; rsrc=$?
[ "$rsrc" = 0 ] && [ -f "$TN/.specops/$TFID/reviews/.dispatched-B" ] && [ ! -e "$TNW/.specops/$TFID/reviews/.dispatched-B" ] \
  && [ -z "$(git -C "$TNW" status --porcelain -- .specops)" ] \
  && ok "SR-14b ★ 추적 .specops worktree 에서 review-saved mark → 메인 표지 · worktree .specops 불변" \
  || nope "SR-14b" "rc=$rsrc main=$([ -f "$TN/.specops/$TFID/reviews/.dispatched-B" ] && echo y || echo n) wt=$([ -e "$TNW/.specops/$TFID/reviews/.dispatched-B" ] && echo y || echo n) status=[$(git -C "$TNW" status --porcelain -- .specops | tr '\n' ' ')]"
rm -f "$TN/.specops/$TFID/reviews/.dispatched-B"

# SR-15 검증 러너·receipt 판정 — 메인 판정 상태 PASS · receipt rc 0 · worktree .specops 불변
out=$(cd "$TNW" && bash "$RUNV" "$TFID" 2>&1)
st=$(jq -r '.verdict // "-"' "$TN/.specops/$TFID/verification-state.json" 2>/dev/null)
printf '# spec\n' > "$TN/.specops/$TFID/spec.md"
(cd "$TNW" && git add src/foo.sh)
(cd "$TNW" && bash "$PLUGIN/scripts/_internal/check-task-receipt.sh" "$TFID" T1) >/dev/null 2>&1; crc=$?
(cd "$TNW" && git reset -q)
printf '%s' "$out" | grep -q 'VERIFY: PASS' && [ "$st" = PASS ] && [ "$crc" = 0 ] && [ -z "$(git -C "$TNW" status --porcelain -- .specops)" ] \
  && ok "SR-15 ★ 추적 .specops worktree 에서 검증 러너 → 메인 판정 상태 PASS · check-task-receipt rc 0 · worktree .specops 불변" \
  || nope "SR-15" "st=$st crc=$crc out=$(printf '%s' "$out" | tail -1) status=[$(git -C "$TNW" status --porcelain -- .specops | tr '\n' ' ')]"

# SR-16 판정 스크립트 — release-ready 가 메인 기록으로 판정 · review-skip-pass 가 메인에 쓴다 · worktree .specops 불변
mkdir -p "$TN/.specops/$TFID/reviews"
printf 'ok\n' > "$TN/.specops/$TFID/reviews/T1-B-report.md"; cp "$TN/.specops/$TFID/reviews/T1-B-report.md" "$TN/.specops/$TFID/reviews/T1-C-report.md"
printf 'review_mode: end-loaded\n' >> "$TN/.specops/$TFID/tasks.md"
rr=$(cd "$TNW" && bash "$PLUGIN/scripts/_internal/release-ready.sh" "$TFID" 2>&1)
rs=$(cd "$TNW" && bash "$PLUGIN/scripts/_internal/review-skip-pass.sh" "$TFID" 2>&1); rsrc=$?
printf '%s' "$rr" | grep -q '^RELEASE_READY: ' && ! printf '%s' "$rr" | grep -qE 'fid-dir-missing|legacy-no-verify-artifact' \
  && [ "$rsrc" = 0 ] && [ "$rs" = "review-skip-pass: OK $TFID" ] && [ -f "$TN/.specops/$TFID/review-skip.md" ] \
  && [ -z "$(git -C "$TNW" status --porcelain -- .specops)" ] \
  && ok "SR-16 ★ 추적 .specops worktree 에서 release-ready·review-skip-pass → 메인 기록으로 판정·기록 · worktree .specops 불변" \
  || nope "SR-16" "rr=[$(printf '%s' "$rr" | head -2 | tr '\n' ' ')] rs=${rsrc}[$rs] status=[$(git -C "$TNW" status --porcelain -- .specops | tr '\n' ' ')]"

# ── 해석 함수 (20261105-specops-root-unify) ──
. "$SR"
unset SPECOPS_ROOT
M2="$TD/r"; MK2="$TD/r.marker"; _mk "$M2" "$MK2"; W2="$M2/.worktrees/$FID"
MP=$(cd "$M2" && pwd -P); W2P=$(cd "$W2" && pwd -P)
# SR-17 (a) 메인에만 있음 → 메인 .specops · DIR 인자(다른 cwd·하위 폴더)도 같은 답 · export 는 SPECOPS_ROOT 만(GIT_DIR·GIT_WORK_TREE 없음·cwd 불변)
got=$(cd "$W2" && specops_root_dir "$FID")
got_far=$(cd "$TD" && specops_root_dir "$FID" "$W2")
got_sub=$(cd "$TD" && specops_root_dir "$FID" "$W2/src")
exp=$(cd "$W2" && specops_root_export "$FID" && printf '%s|%s|%s|%s' "${SPECOPS_ROOT:-none}" "${GIT_DIR:-none}" "${GIT_WORK_TREE:-none}" "$(pwd -P)")
[ "$got" = "$MP/.specops" ] && [ "$got_far" = "$MP/.specops" ] && [ "$got_sub" = "$MP/.specops" ] && [ "$exp" = "$MP/.specops|none|none|$W2P" ] \
  && ok "SR-17 ★ 메인에만 있는 FID → 메인 .specops · DIR 인자 · export 는 SPECOPS_ROOT 만" || nope "SR-17" "got=$got far=$got_far sub=$got_sub exp=$exp"
# SR-18 (b) worktree 에 실제 기록 파일(비추적) → 현재 worktree · export 는 아무것도 안 함. 논리 경로($W2) — 훅의 종전 $cwd/.specops 와 같다
mkdir -p "$W2/.specops/$FID" && : > "$W2/.specops/$FID/own.md"
got=$(cd "$W2" && specops_root_dir "$FID")
exp=$(cd "$W2" && specops_root_export "$FID" && printf '%s' "${SPECOPS_ROOT:-none}")
[ "$got" = "$W2/.specops" ] && [ "$exp" = none ] && ok "SR-18 worktree 에 자기 기록 → 현재 worktree .specops" || nope "SR-18" "got=$got exp=$exp"
rm -rf "$W2/.specops"
# SR-19 (c) SPECOPS_ROOT 지정은 그대로(export 도 불변) · 빈 문자열은 미지정 · (d) 진짜 비 git 폴더 → DIR/.specops · DIR 인자 폴백
got=$(cd "$W2" && SPECOPS_ROOT=/x/y specops_root_dir "$FID")
nogit="$TD/nongit"; mkdir -p "$nogit"; got2=$(cd "$nogit" && specops_root_dir "$FID")
ex=$(cd "$W2" && export SPECOPS_ROOT=/x/y && specops_root_export "$FID" && printf '%s' "$SPECOPS_ROOT")
ex_empty=$(cd "$W2" && SPECOPS_ROOT= specops_root_dir "$FID")
got3=$(cd "$TD" && specops_root_dir "$FID" "$nogit")
[ "$got" = "/x/y" ] && [ "$got2" = "$nogit/.specops" ] && [ "$ex" = "/x/y" ] && [ "$ex_empty" = "$MP/.specops" ] && [ "$got3" = "$nogit/.specops" ] \
  && ok "SR-19 SPECOPS_ROOT 지정 그대로 · 빈값은 미지정 · 비 git 은 DIR/.specops" || nope "SR-19" "got=$got got2=$got2 ex=$ex ex_empty=$ex_empty got3=$got3"
# SR-20 메인 자신 · 메인에 .specops 없음 · worktree 의 .specops 링크 · 메인의 .specops 링크 → export 안 함 (링크는 종전대로 해석하지 않는다)
r1=$(cd "$M2" && specops_root_export "$FID" && printf '%s' "${SPECOPS_ROOT:-none}")
mkdir -p "$TD/nm" && git init -q "$TD/nm" && (cd "$TD/nm" && _g commit -q --allow-empty -m i) && git -C "$TD/nm" worktree add -q "$TD/nm/w" -b w 2>/dev/null
r2=$(cd "$TD/nm/w" && specops_root_export "$FID" && printf '%s' "${SPECOPS_ROOT:-none}")
LNK="$TD/lk"; _mk "$LNK" "$TD/lk.marker"; LW="$LNK/.worktrees/$FID"; mkdir -p "$TD/lk-target"; ln -s "$TD/lk-target" "$LW/.specops"
r3=$(cd "$LW" && specops_root_export "$FID" && printf '%s' "${SPECOPS_ROOT:-none}"); d3=$(cd "$LW" && specops_root_dir "$FID")
LK2="$TD/lk2"; _mk "$LK2" "$TD/lk2.marker"; LW2="$LK2/.worktrees/$FID"; mv "$LK2/.specops" "$TD/lk2-real"; ln -s "$TD/lk2-real" "$LK2/.specops"
r4=$(cd "$LW2" && specops_root_export "$FID" && printf '%s' "${SPECOPS_ROOT:-none}")
[ "$r1" = none ] && [ "$r2" = none ] && [ "$r3" = none ] && [ "$d3" = "$LW/.specops" ] && [ "$r4" = none ] \
  && ok "SR-20 메인 자신 · 메인에 .specops 없음 · .specops 링크(worktree·메인) → export 안 함" || nope "SR-20" "r1=$r1 r2=$r2 r3=$r3 d3=$d3 r4=$r4"
# SR-20b 추적 파일만 있는 메인 자신 — linked 판정이 없으면 _sr_fid_only_in_main 이 rc 0 이 되는 픽스처 (plan 의 r1 은 비추적 파일이라 이 변이를 못 잡는다)
TM="$TD/tm"; git init -q "$TM" && git -C "$TM" symbolic-ref HEAD refs/heads/main; mkdir -p "$TM/.specops/$FID"; printf 'i\n' > "$TM/.specops/$FID/intent.md"; (cd "$TM" && git add -A && _g commit -qm i)
r5=$(cd "$TM" && specops_root_export "$FID" && printf '%s' "${SPECOPS_ROOT:-none}")
mkdir -p "$TM/sub"; r5s=$(cd "$TM/sub" && specops_root_export "$FID" && printf '%s' "${SPECOPS_ROOT:-none}")   # 하위 폴더 — 최상위 .git 지름길을 거치지 않아 linked 판정 줄이 실제로 걸린다
[ "$r5" = none ] && [ "$r5s" = none ] && ok "SR-20b ★ 추적 파일만 있는 메인 자신(최상위·하위 폴더) → export 안 함" || nope "SR-20b" "r5=$r5 r5s=$r5s"
# SR-17e 하류 추적 .specops worktree (SR-12 의 TN/TO) — 새·구 템플릿 → 메인 · 거기에 비추적 기록이 생기면 자기 위치 (추적 파일을 기록으로 오인하는 변이를 잡는다)
dn=$(cd "$TNW" && specops_root_dir "$TFID"); do_=$(cd "$TOW" && specops_root_dir "$TFID")
printf 'local\n' > "$TNW/.specops/$TFID/tasks.md"; dn2=$(cd "$TNW" && specops_root_dir "$TFID"); rm -f "$TNW/.specops/$TFID/tasks.md"
[ "$dn" = "$TNP/.specops" ] && [ "$do_" = "$TOP/.specops" ] && [ "$dn2" = "$TNW/.specops" ] \
  && ok "SR-17e ★ 추적 .specops worktree(새·구 템플릿) → 메인 · 비추적 기록이 있으면 자기 위치" || nope "SR-17e" "dn=$dn do=$do_ dn2=$dn2"
# SR-20c 형식 틀린 FID(옵션 문자열·경로 조각)는 판정에 들어가지 않는다 → 메인에 기록이 있어도 리다이렉트 안 함(DIR/.specops) · 빈 FID 는 .specops 가 아예 없을 때만 메인 · 있으면 자기 위치
c1=$(cd "$W2" && specops_root_dir "--plan"); c2=$(cd "$W2" && specops_root_dir "../x"); c3=$(cd "$W2" && specops_root_dir "20261016-SR")
c4=$(cd "$W2" && specops_root_export "--plan" && printf '%s' "${SPECOPS_ROOT:-none}")
e1=$(cd "$W2" && specops_root_dir ""); e2=$(cd "$TNW" && specops_root_dir "")
[ "$c1" = "$W2/.specops" ] && [ "$c2" = "$W2/.specops" ] && [ "$c3" = "$W2/.specops" ] && [ "$c4" = none ] && [ "$e1" = "$MP/.specops" ] && [ "$e2" = "$TNW/.specops" ] \
  && ok "SR-20c ★ 형식 틀린 FID → 리다이렉트 안 함 · 빈 FID 는 worktree 에 .specops 없을 때만 메인" || nope "SR-20c" "c1=$c1 c2=$c2 c3=$c3 c4=$c4 e1=$e1 e2=$e2"
# SR-32 NFR-2 git 호출 횟수 — PATH 앞의 가짜 git(횟수를 세고 실 git 으로 exec): 일반 저장소 최상위 0회 · 링크 worktree(추적 .specops) 3회 이내(0회가 아님 — 계수기 생존 대조)
REALGIT=$(command -v git); FG="$TD/fakegit"; mkdir -p "$FG"; CNT="$TD/git.count"
printf '#!/bin/sh\necho x >> "%s"\nexec "%s" "$@"\n' "$CNT" "$REALGIT" > "$FG/git"; chmod +x "$FG/git"
_gcalls() {  # DIR FID → git 호출 횟수
  : > "$CNT"; ( export PATH="$FG:$PATH"; cd "$TD" && specops_root_dir "$2" "$1" >/dev/null ); wc -l < "$CNT" | tr -d ' '
}
n_top=$(_gcalls "$M2" "$FID"); n_wt=$(_gcalls "$TNW" "$TFID"); n_wt2=$(_gcalls "$W2" "$FID")
[ "$n_top" = 0 ] && [ "$n_wt" -ge 1 ] && [ "$n_wt" -le 3 ] && [ "$n_wt2" -ge 1 ] && [ "$n_wt2" -le 3 ] \
  && ok "SR-32 ★ git 호출: 일반 저장소 최상위 0회 · 링크 worktree ≤3회 (top=$n_top wt=$n_wt wt2=$n_wt2)" || nope "SR-32" "top=$n_top wt=$n_wt wt2=$n_wt2"

# ── T2 진입점: stage-timing · emit-context (20261105-specops-root-unify) ──
EFID=20260902-rules
mkdir -p "$M2/.specops/$EFID" "$M2/.specops/memory"
cp "$PLUGIN"/scripts/tests/dag/fixtures/emit-context/ok-fid/*.md "$M2/.specops/$EFID/"
printf '# api\n' > "$M2/.specops/memory/api-spec.md"
_nowt() { [ ! -e "$W2/.specops" ]; }
# SR-25 stage-timing — 출력에 FID 는 없다. 원장 경로가 메인이다
out=$(cd "$W2" && bash "$PLUGIN/scripts/stage-timing.sh" 2>&1); RC=$?
[ "$RC" = 0 ] && printf '%s\n' "$out" | grep -qF "원장: $MP/.specops/session-progress.md " && _nowt && ok "SR-25 ★ stage-timing → 메인 원장" || nope "SR-25" "RC=$RC out=$(printf '%s' "$out" | head -4)"
# SR-28 emit-context(a) — worktree: 메인 dispatch · §6 은 상대 표기(enter 방식 — 이동 뒤 상대경로가 메인을 가리킨다). worktree 에는 api-spec 이 없으니 실렸다는 것이 메인을 읽었다는 증거
out=$(cd "$W2" && bash "$PLUGIN/scripts/dag/emit-context.sh" "$EFID" 2>/dev/null); RC=$?
c="$M2/.specops/$EFID/dispatch/T1-context.md"
[ "$RC" = 0 ] && [ "$(printf '%s' "$out" | tail -1)" = "EMIT: 2 files" ] && [ -f "$c" ] && [ -f "$M2/.specops/$EFID/dispatch/T2-context.md" ] \
  && grep -qxF -- '- `.specops/memory/api-spec.md`' "$c" && [ ! -e "$W2/.specops/memory/api-spec.md" ] && _nowt \
  && ok "SR-28 ★ emit-context → 메인 dispatch · §6 설계 계약에 api-spec(상대 표기)" || nope "SR-28" "RC=$RC out=$out"
# SR-28m(d) 메인 체크아웃 — 종전 상대 표기 그대로(AC-R-1)
rm -rf "$M2/.specops/$EFID/dispatch"
out=$(cd "$M2" && bash "$PLUGIN/scripts/dag/emit-context.sh" "$EFID" 2>/dev/null); RC=$?
[ "$RC" = 0 ] && grep -qxF -- '- `.specops/memory/api-spec.md`' "$c" && ! grep -qF "$MP" "$c" && ok "SR-28m 메인 체크아웃의 emit-context 는 종전 상대 표기(AC-R-1)" || nope "SR-28m" "RC=$RC"
# SR-28b(b) 게이트 불변식 — 접미사 id(T1a, 날짜 20261007 이후)는 worktree 에서도 task-ids 게이트가 막는다(export 방식이면 게이트가 조용히 SKIP). 메인 체크아웃에서 SPECOPS_ROOT 를 줘도 마찬가지(c)
BFID=20261105-sr-ids
mkdir -p "$M2/.specops/$BFID"; cp "$PLUGIN"/scripts/tests/dag/fixtures/emit-context/ok-fid/*.md "$M2/.specops/$BFID/"
sed -i.bak 's/id: T1$/id: T1a/' "$M2/.specops/$BFID/tasks.md"; rm -f "$M2/.specops/$BFID/tasks.md.bak"
err=$(cd "$W2" && bash "$PLUGIN/scripts/dag/emit-context.sh" "$BFID" 2>&1 >/dev/null); RC=$?
cp -R "$M2/.specops" "$TD/sr-copy"
err2=$(cd "$M2" && SPECOPS_ROOT="$TD/sr-copy" bash "$PLUGIN/scripts/dag/emit-context.sh" "$BFID" 2>&1 >/dev/null); RC2=$?
[ "$RC" = 1 ] && printf '%s\n' "$err" | grep -q '^TASK-IDS: FAIL' && [ ! -d "$M2/.specops/$BFID/dispatch" ] && _nowt \
  && [ "$RC2" = 1 ] && printf '%s\n' "$err2" | grep -q '^TASK-IDS: FAIL' \
  && ok "SR-28b ★ worktree 의 접미사 id → TASK-IDS FAIL·dispatch 0 · 외부 SPECOPS_ROOT 도 위치를 못 옮김" || nope "SR-28b" "RC=$RC RC2=$RC2 err=$(printf '%s' "$err" | head -2) err2=$(printf '%s' "$err2" | head -2)"
# SR-28s(e) screens/ — worktree 에만 있는 screens 가 §6 에 실린다(이동하면 상대 screens 가 메인 기준이 되어 조용히 빠진다)
mkdir -p "$W2/screens"; : > "$W2/screens/home.md"
rm -rf "$M2/.specops/$EFID/dispatch"
(cd "$W2" && bash "$PLUGIN/scripts/dag/emit-context.sh" "$EFID") >/dev/null 2>&1; RC=$?
[ "$RC" = 0 ] && [ ! -e "$M2/screens" ] && grep -qxF -- '- `screens/`' "$c" && ok "SR-28s ★ worktree 에만 있는 screens/ → §6 에 실림" || nope "SR-28s" "RC=$RC"
rm -rf "$W2/screens" "$M2/.specops/$EFID/dispatch"
# SR-28f(f) SCRIPT_DIR — worktree 에서 상대경로로 불러도 worktree 자신의 scripts/ 게이트가 돈다(스텁 게이트가 마커를 남긴다)
mkdir -p "$W2/scripts"; cp -R "$PLUGIN/scripts/dag" "$PLUGIN/scripts/_internal" "$W2/scripts/"
GM="$TD/gate.marker"; : > "$GM"
printf '#!/usr/bin/env bash\necho ran >> "%s"\nexit 0\n' "$GM" > "$W2/scripts/_internal/check-fid-size.sh"
(cd "$W2" && bash scripts/dag/emit-context.sh "$EFID") >/dev/null 2>&1; RC=$?
[ "$RC" = 0 ] && [ -s "$GM" ] && ok "SR-28f ★ 상대경로 호출 → worktree 자신의 게이트 실행" || nope "SR-28f" "RC=$RC marker=$(cat "$GM")"
rm -rf "$W2/scripts/dag" "$W2/scripts/_internal" "$M2/.specops/$EFID/dispatch"

# ── T3 진입점: gbrain-collect · plan-to-tasks (20261105-specops-root-unify) ──
mkdir -p "$M2/.specops/$FID/handoffs"
printf '## Decided\n- 메인-핸드오프-결정\n' > "$M2/.specops/$FID/handoffs/T1.md"
printf '### Task 1: 메인-플랜-첫째\n\n- [ ] **Step 1**: a\n\n### Task 2: 메인-플랜-둘째\n\n- [ ] **Step 1**: b\n' > "$M2/.specops/$FID/plan.md"
# SR-26 gbrain-collect — 출력에 FID 는 없다. 메인 핸드오프의 고유 토큰으로 전체 비교
out=$(cd "$W2" && bash "$PLUGIN/scripts/gbrain-collect.sh" "$FID" 2>&1); RC=$?
[ "$RC" = 0 ] && [ "$out" = "$(printf '## T1.md\n- 메인-핸드오프-결정')" ] && _nowt && ok "SR-26 ★ gbrain-collect → 메인 핸드오프" || nope "SR-26" "RC=$RC out=$out"
# SR-27 plan-to-tasks (+ --plan 명시 경로는 SPECOPS_ROOT 를 무시하고 그 경로를 읽는다)
out=$(cd "$W2" && bash "$PLUGIN/scripts/dag/plan-to-tasks.sh" "$FID" 2>&1); RC=$?
mkdir -p "$W2/pp" && printf '### Task 1: 워크트리-플랜\n\n- [ ] **Step 1**: a\n' > "$W2/pp/plan.md"
out2=$(cd "$W2" && bash "$PLUGIN/scripts/dag/plan-to-tasks.sh" --plan pp/plan.md 2>&1); RC2=$?
rm -rf "$W2/pp"
[ "$RC" = 0 ] && printf '%s' "$out" | grep -qF '메인-플랜-첫째' && printf '%s' "$out" | grep -qF '메인-플랜-둘째' && [ "$RC2" = 0 ] && printf '%s' "$out2" | grep -qF '워크트리-플랜' && ! printf '%s' "$out2" | grep -qF '메인-플랜' && _nowt \
  && ok "SR-27 ★ plan-to-tasks → 메인 plan.md · --plan 경로 회귀" || nope "SR-27" "RC=$RC RC2=$RC2 out=$(printf '%s' "$out" | head -3) out2=$(printf '%s' "$out2" | head -3)"

# ── T4 진입점: dev-decision · show-fid-status (20261105-specops-root-unify) ──
# SR-21 dev-decision add·show
(cd "$W2" && bash "$PLUGIN/scripts/dev-decision.sh" add "$FID" order "정함-sr21" "근거") >/dev/null 2>&1; RC=$?
out=$(cd "$W2" && bash "$PLUGIN/scripts/dev-decision.sh" show "$FID" 2>&1); src=$?
[ "$RC" = 0 ] && [ "$src" = 0 ] && grep -qF '[order] 정함-sr21 — 근거' "$M2/.specops/$FID/dev-decisions.md" && printf '%s' "$out" | grep -qF '[order] 정함-sr21 — 근거' && _nowt \
  && ok "SR-21 ★ worktree 에서 dev-decision add·show → 메인" || nope "SR-21" "RC=$RC src=$src out=$out"
# SR-24 show-fid-status — 메인에만 있는 plan.md·tasks.md 가 ✅ (stderr 의 FID 는 증거가 아니다)
out=$(cd "$W2" && bash "$PLUGIN/scripts/show-fid-status.sh" "$FID" 2>&1); RC=$?
printf '%s\n' "$out" | head -1 | grep -qx "=== FID: $FID ===" && [ "$RC" = 0 ] && printf '%s\n' "$out" | grep -qx '  ✅ plan.md' && printf '%s\n' "$out" | grep -qx '  ✅ tasks.md' && _nowt \
  && ok "SR-24 ★ show-fid-status → 메인 산출물 현황" || nope "SR-24" "RC=$RC out=$(printf '%s' "$out" | head -3)"
# SR-30 이동하지 않아야 할 때 — 자기 기록 worktree($L)는 자기 .specops · 추적 .specops worktree($TNW)는 메인에 쓰고 추적 파일 불변
(cd "$L" && bash "$PLUGIN/scripts/dev-decision.sh" add "$FID" order "own-sr30" "x") >/dev/null 2>&1; RC=$?
(cd "$TNW" && bash "$PLUGIN/scripts/dev-decision.sh" add "$TFID" order "trk-sr30" "x") >/dev/null 2>&1; RC2=$?
[ "$RC" = 0 ] && grep -q 'own-sr30' "$L/.specops/$FID/dev-decisions.md" && [ ! -e "$R/.specops/$FID/dev-decisions.md" ] \
  && [ "$RC2" = 0 ] && grep -q 'trk-sr30' "$TN/.specops/$TFID/dev-decisions.md" && [ -z "$(git -C "$TNW" status --porcelain -- .specops)" ] \
  && ok "SR-30 ★ 자기 기록 worktree → 자기 .specops · 추적 worktree → 메인(추적 파일 불변)" || nope "SR-30" "RC=$RC RC2=$RC2"
# SR-31 인자 없는/틀린 호출은 종전 그대로 — set -u 아래 prelude 가 'unbound variable' 로 죽지 않는다 (worktree 에서)
bad=""
for c in "dev-decision.sh" "gbrain-collect.sh" "dag/plan-to-tasks.sh" "dag/emit-context.sh" "_internal/record-metric.sh" "_internal/risk-profile.sh"; do
  o=$(cd "$W2" && bash "$PLUGIN/scripts/$c" 2>&1); rc=$?
  { [ "$rc" = 1 ] && ! printf '%s' "$o" | grep -q 'unbound variable'; } || bad="$bad $c(rc=$rc)"
done
[ -z "$bad" ] && ok "SR-31 인자 없는 호출 → rc 1 · unbound variable 없음" || nope "SR-31" "$bad"

# ── T5 진입점: record-metric · risk-profile (20261105-specops-root-unify) ──
# SR-22 record-metric — rc 만으로는 prelude 없이도 0 이다: 메인의 새 metrics.jsonl + worktree 에 .specops 없음 이 판별이다
(cd "$W2" && bash "$PLUGIN/scripts/_internal/record-metric.sh" --fid "$FID" --phase sr22-phase) >/dev/null 2>&1; RC=$?
[ "$RC" = 0 ] && [ "$(jq -r '[.fid,.phase]|join(" ")' "$M2/.specops/$FID/metrics.jsonl" | tail -1)" = "$FID sr22-phase" ] && _nowt && ok "SR-22 ★ record-metric → 메인 metrics.jsonl" || nope "SR-22" "RC=$RC"
# SR-23 risk-profile compute·show
out=$(cd "$W2" && bash "$PLUGIN/scripts/_internal/risk-profile.sh" compute "$FID" 2>&1); RC=$?
sh=$(cd "$W2" && bash "$PLUGIN/scripts/_internal/risk-profile.sh" show "$FID" 2>&1); shrc=$?
[ "$RC" = 0 ] && printf '%s' "$out" | grep -q '^RISK_PROFILE: computed=' && [ "$(jq -r .effective "$M2/.specops/$FID/risk-profile.json")" = standard ] && [ "$shrc" = 0 ] && [ "$sh" = "standard (computed=standard, mode=live)" ] && _nowt \
  && ok "SR-23 ★ risk-profile compute·show → 메인 risk-profile.json" || nope "SR-23" "RC=$RC out=$out sh=$sh"
# SR-24b risk-profile 을 source 로만 쓰는 호출자(quick-scope.sh)에는 부작용이 없다 — 환경·cwd 불변
sb=$(cd "$W2" && bash -c 'source "$1" >/dev/null 2>&1; printf "%s|%s|%s" "${SPECOPS_ROOT:-none}" "${GIT_DIR:-none}" "$(pwd -P)"' _ "$PLUGIN/scripts/_internal/risk-profile.sh")
[ "$sb" = "none|none|$W2P" ] && ok "SR-24b risk-profile source 는 SPECOPS_ROOT·GIT_DIR·cwd 를 바꾸지 않는다" || nope "SR-24b" "sb=$sb"
# SR-23t 하류 추적 구조 — spec §참조가 추적 문서(api-spec.md)를 인용한 FID 는 메인·worktree 실행의 computed 가 같다.
#   절대경로 SPECOPS_ROOT 에서 git ls-files 가 'outside repository' rc 128 로 실패하면 인용 가림이 꺼져 worktree 에서만 strict 가 나온다.
printf '# api\n' > "$TN/.specops/memory/api-spec.md" && git -C "$TN" add -f .specops/memory/api-spec.md && _g -C "$TN" commit -qm api-spec   # 추적 문서 — 커밋해 '변경 파일' 신호가 되지 않게
printf '# 스펙\n**§유형**: trivial\n**§lite**: true\n## 1. 개요\n저장 버튼 문구를 바꾼다.\n## 10. 참조\n- IF 설계서 — `.specops/memory/api-spec.md`\n' > "$TN/.specops/$TFID/spec.md"
tm=$(cd "$TN" && bash "$PLUGIN/scripts/_internal/risk-profile.sh" compute "$TFID" 2>&1); tmrc=$?
rm -f "$TN/.specops/$TFID/risk-profile.json"   # worktree 실행이 메인에 다시 써야 한다
tw=$(cd "$TNW" && bash "$PLUGIN/scripts/_internal/risk-profile.sh" compute "$TFID" 2>&1); twrc=$?
cm=$(printf '%s' "$tm" | grep -o 'computed=[a-z]*' | head -1); cw=$(printf '%s' "$tw" | grep -o 'computed=[a-z]*' | head -1)
[ "$tmrc" = 0 ] && [ "$twrc" = 0 ] && [ -n "$cm" ] && [ "$cm" = "$cw" ] && [ "$cm" != computed=strict ] && [ -f "$TN/.specops/$TFID/risk-profile.json" ] && [ ! -e "$TNW/.specops/$TFID/risk-profile.json" ] \
  && ok "SR-23t ★ 추적 구조 인용 FID → 메인·worktree 실행의 $cm 가 같다 (strict 아님)" || nope "SR-23t" "main=${tmrc}[$cm] wt=${twrc}[$cw]"

finish
