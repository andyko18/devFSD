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

finish
