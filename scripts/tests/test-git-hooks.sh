#!/usr/bin/env bash
# 2단 git hook 게이트 — pre-commit(빠른 정합 ~5s) / pre-push(run-all 전체 — 병렬 ~7분, 머신 부하가 값을 흔든다. 동일 트리면 마커 skip)
# 계기: 44cd095 revert 가 run-all 없이 나가 main 이 하루 red.
#       Claude Code PreToolUse 훅은 Cursor 등 다른 도구의 커밋에 발화하지 않는다 —
#       git hook 은 도구 무관하게 걸리는 유일한 층이다.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

PRE_COMMIT="$PLUGIN/.githooks/pre-commit"
PRE_PUSH="$PLUGIN/.githooks/pre-push"
INSTALLER="$PLUGIN/scripts/_internal/install-git-hooks.sh"

source "$PLUGIN/scripts/tests/lib/isolated-tree.sh" 2>/dev/null || true
command -v iso::make_tree >/dev/null 2>&1 && command -v iso::make_git_tree >/dev/null 2>&1 \
  && command -v iso::fingerprint >/dev/null 2>&1 \
  || { echo "FATAL: isolated-tree 미로드(또는 반쯤 로드)" >&2; exit 1; }

# ★ 자가점검 (AC-10): 이 스위트가 실 트리를 변이하지 않음을 스스로 단언한다.
#   trap 은 **중단** 안전을 담당하고, 이 어서션은 **정상 실행 중** 무변이를 담당한다 —
#   역할이 겹치지 않는다.
# ★ porcelain 만으로는 **이미 M 인 tracked 파일의 내용 변화**를 못 본다(실측: ' M x' 상태에서
#   v1→v2 로 바꿔도 sha 동일 7e3de7179805). T2 구현 중엔 두 스위트가 정확히 M 상태다.
#   git diff HEAD 를 병기해 내용까지 지문에 넣는다.
_iso_paths='scripts/_internal/.hardgate-baseline skills/specifying-ko/SKILL.md commands/start-all.md skills scripts/tests'
_iso_before=$(iso::fingerprint $_iso_paths)

# GH-1: 훅 파일 존재 + 실행권한
[ -f "$PRE_COMMIT" ] && [ -x "$PRE_COMMIT" ] \
  && ok "GH-1 .githooks/pre-commit 존재+실행권한" \
  || nope "GH-1" "부재 또는 비실행"

[ -f "$PRE_PUSH" ] && [ -x "$PRE_PUSH" ] \
  && ok "GH-2 .githooks/pre-push 존재+실행권한" \
  || nope "GH-2" "부재 또는 비실행"

# GH-3: pre-commit 은 빠른 게이트 2종 — 정적 구성 + **실측 소요**로 확인한다.
#       (문구 grep 은 안내문 안의 run-all 언급과 실제 호출을 구분하지 못한다.
#        전체 스위트를 돌지 '않음'은 시간으로 증명하는 게 맞다.)
if [ -x "$PRE_COMMIT" ]; then
  grep -q 'validate-structure.sh' "$PRE_COMMIT" && grep -q 'check-propagation.sh' "$PRE_COMMIT" \
    && gate_ok=1 || gate_ok=0
  _s=$(date +%s)
  (cd "$PLUGIN" && bash "$PRE_COMMIT" >/dev/null 2>&1) || true
  _e=$(date +%s)
  _d=$((_e - _s))
  [ "$gate_ok" -eq 1 ] && [ "$_d" -lt 60 ] \
    && ok "GH-3 pre-commit = 빠른 게이트 2종 (${_d}s < 60s — run-all 미실행)" \
    || nope "GH-3" "gate_ok=$gate_ok 소요=${_d}s"
else
  nope "GH-3" "pre-commit 부재"
fi

# GH-4: pre-push 는 전체 스위트 + 재귀 가드
if [ -f "$PRE_PUSH" ]; then
  grep -q 'run-all.sh' "$PRE_PUSH" \
    && grep -q 'SPECOPS_RUN_ALL' "$PRE_PUSH" \
    && ok "GH-4 pre-push = run-all + 재귀 가드" \
    || nope "GH-4" "run-all 또는 SPECOPS_RUN_ALL 가드 부재"
else
  nope "GH-4" "pre-push 부재"
fi

# GH-5: 주권 탈출구 안내 — 차단 문구에 --no-verify 명시 (5원칙 4)
if [ -f "$PRE_COMMIT" ] && [ -f "$PRE_PUSH" ]; then
  grep -q -- '--no-verify' "$PRE_COMMIT" && grep -q -- '--no-verify' "$PRE_PUSH" \
    && ok "GH-5 두 훅 모두 --no-verify 주권 안내" \
    || nope "GH-5" "탈출구 안내 부재"
else
  nope "GH-5" "훅 부재"
fi

# GH-6: 비-specops repo 면제 — 게이트 스크립트 없는 트리에서 exit 0 (월권 금지, 5원칙 4)
if [ -x "$PRE_COMMIT" ]; then
  TD=$(mktemp -d)
  (cd "$TD" && git init -q && printf 'x\n' > a.txt && git add a.txt)
  (cd "$TD" && bash "$PRE_COMMIT" >/dev/null 2>&1); rc=$?
  [ "$rc" -eq 0 ] && ok "GH-6 비-specops repo 면제 (exit 0)" || nope "GH-6" "rc=$rc"
  rm -rf "$TD"
else
  nope "GH-6" "pre-commit 부재"
fi

# GH-7: 현재 트리 정상 → pre-commit exit 0
if [ -x "$PRE_COMMIT" ]; then
  (cd "$PLUGIN" && bash "$PRE_COMMIT" >/dev/null 2>&1); rc=$?
  [ "$rc" -eq 0 ] && ok "GH-7 정상 트리 → exit 0" || nope "GH-7" "rc=$rc"
else
  nope "GH-7" "pre-commit 부재"
fi

# GH-8: 실제 드리프트 차단 실증 — 44cd095(파손 리비전)의 start-all.md 복원 시 exit 1
#       (이 커밋이 run-all 없이 나가 T1.e 를 하루 red 로 남긴 그 변경이다)
# ★ 격리 사본에서 한다 — 종전엔 실 commands/start-all.md 를 파손 리비전으로 덮어썼고,
#   그 창에 다른 프로세스가 파일을 읽으면 431→300줄에 앵커 10개 소실로 보였다
#   (20260906 실측: check-propagation FAIL (14/208), 원인 규명에 여러 단계 소요).
# ★ iso::make_git_tree 를 쓴다 — git repo 가 아니면 pre-commit 이 관할 판정에서
#   빠져나가 rc=0(면제)을 내고 "차단됐다" 판정이 조용히 거짓이 된다(실측).
if [ -x "$PRE_COMMIT" ] && (cd "$PLUGIN" && git cat-file -e 44cd095:commands/start-all.md 2>/dev/null); then
  G=$(iso::make_git_tree) || G=""
  if [ -z "$G" ]; then
    nope "GH-8" "격리 git 사본 생성 실패"
  else
    trap 'rm -rf "$G"' EXIT
    (cd "$PLUGIN" && git show 44cd095:commands/start-all.md) > "$G/commands/start-all.md"
    (cd "$G" && bash .githooks/pre-commit >/dev/null 2>&1); rc=$?
    rm -rf "$G"; trap - EXIT
    [ "$rc" -ne 0 ] && ok "GH-8 44cd095 파손 리비전 → pre-commit 차단" || nope "GH-8" "rc=$rc (차단 실패)"
  fi
else
  skip "GH-8 (44cd095 미도달 — shallow clone)"
fi

# GH-9: 설치 스크립트가 core.hooksPath 를 .githooks 로 설정
if [ -f "$INSTALLER" ]; then
  TD=$(mktemp -d)
  (cd "$TD" && git init -q && mkdir -p .githooks)
  (cd "$TD" && bash "$INSTALLER" >/dev/null 2>&1)
  hp=$(cd "$TD" && git config core.hooksPath || true)
  [ "$hp" = ".githooks" ] && ok "GH-9 installer → core.hooksPath=.githooks" \
    || nope "GH-9" "hooksPath=$hp"
  rm -rf "$TD"
else
  nope "GH-9" "install-git-hooks.sh 부재"
fi

# GH-9b: 관할 한정 — .githooks/ 없는 repo 는 설치 거부 (없는 경로를 가리키게 두지 않는다)
if [ -f "$INSTALLER" ]; then
  TD=$(mktemp -d)
  (cd "$TD" && git init -q)
  (cd "$TD" && bash "$INSTALLER" >/dev/null 2>&1); rc=$?
  hp=$(cd "$TD" && git config core.hooksPath || true)
  [ "$rc" -ne 0 ] && [ -z "$hp" ] \
    && ok "GH-9b .githooks 부재 repo → 설치 거부" \
    || nope "GH-9b" "rc=$rc hooksPath=$hp"
  rm -rf "$TD"
else
  nope "GH-9b" "install-git-hooks.sh 부재"
fi

# GH-10: 설치 안내가 문서화됐는가 (clone 마다 1회 필요 — core.hooksPath 는 버전관리 대상이 아님)
grep -q 'install-git-hooks' "$PLUGIN/CLAUDE.md" && grep -q 'install-git-hooks' "$PLUGIN/scripts/README.md" \
  && ok "GH-10 CLAUDE.md·scripts/README 설치 안내" \
  || nope "GH-10" "설치 안내 문서 부재"

# ─────────────────────────────────────────────────────────────
# GH-env.*: 훅 환경이 export 한 GIT_DIR 등이 run-all 로 새지 않는다 (20261007-prepush-gitdir)
#   링크 worktree 의 pre-push 는 GIT_DIR 를 **절대경로**로 내보내, run-all 안 픽스처의 `cd $tmp && git init/commit` 이
#   임시 repo 가 아니라 공유 실저장소에 실행됐다(2026-10-06 사고 — core.worktree·user.name 주입·로컬 main 이동·잡 브랜치 19개).
#   sandbox: decoy repo 를 GIT_DIR 로 export 한 채 훅을 돌리고, 스텁 run-all 이 보는 git-dir 이 sandbox 자신이어야 한다.
_ge=$(mktemp -d); mkdir -p "$_ge/sb/.githooks" "$_ge/sb/scripts/tests" "$_ge/decoy"
( cd "$_ge/decoy" && git init -q ) 2>/dev/null
( cd "$_ge/sb" && git init -q ) 2>/dev/null
cp "$PRE_PUSH" "$_ge/sb/.githooks/pre-push"
cat > "$_ge/sb/scripts/tests/run-all.sh" <<'STUB'
#!/usr/bin/env bash
{ echo "GITDIR=$(git rev-parse --git-dir 2>/dev/null)"; echo "ENV_GIT_DIR=${GIT_DIR-UNSET}"; echo "ENV_WT=${GIT_WORK_TREE-UNSET}"; echo "ENV_IDX=${GIT_INDEX_FILE-UNSET}"; } > "$STUBOUT"
echo "==== run-all: suites PASS=1 FAIL=0 (total=1) ===="
STUB
chmod +x "$_ge/sb/scripts/tests/run-all.sh"
_sha=$(cd "$_ge/sb" && git hash-object -w --stdin </dev/null 2>/dev/null)
(cd "$_ge/sb" && env -u SPECOPS_RUN_ALL STUBOUT="$_ge/out" GIT_DIR="$_ge/decoy/.git" GIT_WORK_TREE="$_ge/decoy" GIT_INDEX_FILE="$_ge/decoy/.git/index" \
   bash .githooks/pre-push <<< "refs/heads/x $_sha refs/heads/x 0000000000000000000000000000000000000000" >/dev/null 2>&1)
if [ -f "$_ge/out" ] && [ "$(grep '^GITDIR=' "$_ge/out")" = "GITDIR=.git" ] && grep -qx 'ENV_GIT_DIR=UNSET' "$_ge/out" \
   && grep -qx 'ENV_WT=UNSET' "$_ge/out" && grep -qx 'ENV_IDX=UNSET' "$_ge/out"; then
  ok "GH-env.1 훅의 GIT_DIR·GIT_WORK_TREE·GIT_INDEX_FILE 이 run-all 로 새지 않는다"
else
  nope "GH-env.1 훅 환경 git 변수 누수" "$(cat "$_ge/out" 2>/dev/null | tr '\n' ' ')"
fi
# GH-env.2 run-all.sh 자신도 직접 방어한다(release.sh pre-flight·수동 실행 등 훅 밖 경로)
grep -qE '^unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE' "$PLUGIN/scripts/tests/run-all.sh" \
  && ok "GH-env.2 run-all.sh 선두 unset" || nope "GH-env.2" "run-all.sh 에 unset 부재"
rm -rf "$_ge"

# GH-env.3 실 `git push` 종단: 링크 worktree 에서 push 하면 훅이 절대경로 GIT_DIR 를 받는다 — 스텁 run-all 의
#   픽스처(`cd $tmp && git init && git config user.name`)가 공유 저장소 config 를 오염시키지 않아야 한다(전부 sandbox).
_gp=$(mktemp -d)
( cd "$_gp" && git init -q --bare remote.git && git init -q main && cd main && git config user.email t@t && git config user.name orig \
  && mkdir -p .githooks scripts/tests && cp "$PRE_PUSH" .githooks/pre-push \
  && printf '#!/usr/bin/env bash\ntmp=$(mktemp -d); cd "$tmp" && git init -q && git config user.name POLLUTED && git config user.email p@p\necho "==== run-all: suites PASS=1 FAIL=0 (total=1) ===="\n' > scripts/tests/run-all.sh \
  && chmod +x scripts/tests/run-all.sh .githooks/pre-push && git config core.hooksPath .githooks && git add -A && git commit -q -m init \
  && git branch -M main && git remote add origin "$_gp/remote.git" && git worktree add -q "$_gp/wt" -b feat ) >/dev/null 2>&1
# run-all 안에서 이 스위트가 돌 때 SPECOPS_RUN_ALL=1 이 상속돼 훅의 재귀 가드가 스텁에 도달하기 전에 끝낸다 — 가드를 빼야 검증이 공허하지 않다
( cd "$_gp/wt" && env -u SPECOPS_RUN_ALL git push -q origin feat ) >/dev/null 2>&1
_un=$(git -C "$_gp/main" config --get user.name 2>/dev/null); _wt=$(git -C "$_gp/main" config --get core.worktree 2>/dev/null)
if [ -d "$_gp/wt" ] && [ "$_un" = "orig" ] && [ -z "$_wt" ]; then
  ok "GH-env.3 링크 worktree 실 push — 스텁 픽스처가 공유 저장소 config 를 오염시키지 않는다"
else
  nope "GH-env.3 링크 worktree push 오염" "user.name=$_un core.worktree=$_wt wt=$([ -d "$_gp/wt" ] && echo 있음 || echo 없음)"
fi
rm -rf "$_gp"

# GH-env.4 ★ 모든 스위트가 선두에서 git 저장소 변수를 지운다 (20261011-suite-gitdir-isolation)
#   왜: pre-push·run-all 은 지우지만(GH-env.1·2) 스위트를 run-all 없이 직접 돌리면(영수증·검증 러너·변이 측정·수동 실행)
#   훅이 내보낸 GIT_DIR 이 픽스처로 샌다. 2026-10-06 에 test-release 의 push 가 그렇게 실 origin 으로 나갔고,
#   희생용 복제본 실측에서 191개 스위트 중 32개가 저장소를 바꿨다(그중 11개는 통과로 끝났다).
#   규칙은 "모든 test-*.sh" 다 — git 을 쓰는 스위트만 고르면 스크립트를 거쳐 git 에 닿는 스위트를 놓친다.
#   판별: 첫 코드 줄(주석·빈 줄 제외 — 보통 `set -u`) 다음의 첫 코드 줄이 들여쓰기 없는 unset 이고 아래 7개를 모두 지운다.
#   한계: 줄이 있는지만 본다 — 그 뒤에서 변수를 다시 내보내는 스위트는 GH-env.6 의 표본 밖이면 보지 못한다.
_GIT_ENV_VARS="GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES"
_suite_lacks_git_unset() {  # <파일…> → 방어 줄이 제자리에 없는 파일(줄마다)
  awk -v vars="$_GIT_ENV_VARS" '
    function flush() { if (cur != "" && !good) print cur }
    FNR == 1 { flush(); cur = FILENAME; state = 0; good = 0 }
    state == 2 || /^[[:space:]]*(#|$)/ { next }
    state == 0 { state = 1; next }
    { state = 2; good = ($0 ~ /^unset[[:space:]]/); n = split(vars, v, " ")
      for (i = 1; good && i <= n; i++) if ($0 !~ ("(^|[[:space:]])" v[i] "([[:space:]]|$)")) good = 0 }
    END { flush() }' "$@"
}
_e4_arr=()
while IFS= read -r _e4_f; do [ -n "$_e4_f" ] && _e4_arr+=("$_e4_f"); done <<< "$(find "$PLUGIN/scripts/tests" -type f -name 'test-*.sh' | sort)"
_e4_n=${#_e4_arr[@]}
_e4_bad=""; _e4_known=0
if [ "$_e4_n" -gt 0 ]; then
  _e4_bad=$(_suite_lacks_git_unset "${_e4_arr[@]}")
  for _e4_f in "${_e4_arr[@]}"; do [ "$_e4_f" = "$PLUGIN/scripts/tests/test-release.sh" ] && _e4_known=1; done
fi
if [ "$_e4_n" -gt 0 ] && [ "$_e4_known" = 1 ] && [ -z "$_e4_bad" ]; then
  ok "GH-env.4 ★ 스위트 ${_e4_n}개 전부가 선두에서 git 저장소 변수 7개를 지운다"
else
  nope "GH-env.4 선두에서 git 저장소 변수를 지우지 않는 스위트" "대상 ${_e4_n}개(0개거나 test-release.sh 가 없으면 대상 목록이 깨진 것이다) 중 $(grep -c . <<< "$_e4_bad")개 — 첫 코드 줄(set -u) 바로 뒤에 'unset $_GIT_ENV_VARS' 를 둘 것: $(printf '%s\n' "$_e4_bad" | sed "s|^$PLUGIN/||" | head -5 | tr '\n' ' ')"
fi

# GH-env.5 잠금(GH-env.4)의 판별식이 실제로 가려낸다 — 맞는 형태만 통과한다
#   왜: 판별식이 아무것도 못 잡게 되면(awk 구현 차이·정규식 손상) GH-env.4 는 조용히 통과한다. 임시 파일로 양쪽을 다 잰다.
_e5=$(mktemp -d)
( cd "$_e5" || exit 1
  printf '%s\n' '#!/usr/bin/env bash' '# 머리 주석' 'set -u' "unset $_GIT_ENV_VARS   # 격리" 'PASS=0' > a.sh
  printf '%s\n' '#!/usr/bin/env bash' 'set -u' 'PASS=0' > b.sh
  printf '%s\n' '#!/usr/bin/env bash' 'set -u' 'PASS=0' "unset $_GIT_ENV_VARS" > c.sh
  printf '%s\n' '#!/usr/bin/env bash' 'set -u' "  unset $_GIT_ENV_VARS" > d.sh
  printf '%s\n' '#!/usr/bin/env bash' 'set -u' 'unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX' > e.sh
  printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail' '# 사이의 주석' '' "unset $_GIT_ENV_VARS" 'PASS=0' > f.sh
)
_e5_bad=$(_suite_lacks_git_unset "$_e5/a.sh" "$_e5/b.sh" "$_e5/c.sh" "$_e5/d.sh" "$_e5/e.sh" "$_e5/f.sh" | sed 's|.*/||' | tr '\n' ' ' | sed 's/ $//')
rm -rf "$_e5"
if [ "$_e5_bad" = "b.sh c.sh d.sh e.sh" ]; then
  ok "GH-env.5 판별식 — 줄이 없음·다른 코드 뒤·들여쓴 줄·변수 5개는 걸리고, 맞는 형태(사이에 주석·빈 줄 허용)는 걸리지 않는다"
else
  nope "GH-env.5 판별식이 가려내지 못한다" "걸린 파일='$_e5_bad' (기대 'b.sh c.sh d.sh e.sh')"
fi

# GH-env.6 행동: 훅 환경(GIT_DIR 절대경로)에서 스위트를 직접 실행해도 그 저장소와 원격이 그대로다
#   표본은 사고의 두 스위트다 — test-git-branch-create(실저장소에 브랜치를 만들고 HEAD 를 옮겼다)와
#   test-release(그 브랜치를 origin 으로 push 했다). 전부 sandbox 저장소·sandbox bare 원격이다.
#   SPECOPS_RUN_ALL=1 — test-release 의 T10.b 가 실제 pre-flight(run-all)로 가지 않게 한다(아래 GH-ci 의 하드 규칙과 같은 이유).
_e6=$(mktemp -d)
( cd "$_e6" && git init -q --bare remote.git && git init -q repo && cd repo && git config user.email t@t && git config user.name orig \
  && git commit -q --allow-empty -m base && git branch -M main && git remote add origin "$_e6/remote.git" && git push -q origin main ) >/dev/null 2>&1
_e6_snap() {
  { git --git-dir="$_e6/repo/.git" for-each-ref --format='%(refname) %(objectname)'
    git --git-dir="$_e6/repo/.git" symbolic-ref HEAD
    cat "$_e6/repo/.git/config"
    git --git-dir="$_e6/remote.git" for-each-ref --format='원격 %(refname) %(objectname)'; } 2>/dev/null
}
_e6_before=$(_e6_snap)
for _e6_s in test-git-branch-create.sh test-release.sh; do
  ( cd "$_e6/repo" && SPECOPS_RUN_ALL=1 GH_TOKEN=invalid-for-test GIT_DIR="$_e6/repo/.git" bash "$PLUGIN/scripts/tests/$_e6_s" ) >/dev/null 2>&1
done
_e6_after=$(_e6_snap)
_e6_diff=$(diff <(printf '%s\n' "$_e6_before") <(printf '%s\n' "$_e6_after") | grep -E '^[<>]' | head -4 | cut -c1-90 | tr '\n' ' ')
rm -rf "$_e6"
if [ -n "$_e6_before" ] && [ "$_e6_before" = "$_e6_after" ]; then
  ok "GH-env.6 훅 환경에서 스위트 직접 실행(test-git-branch-create · test-release) — 저장소의 참조·HEAD·설정과 원격이 그대로다"
else
  nope "GH-env.6 스위트 직접 실행이 GIT_DIR 저장소를 바꿨다" "$_e6_diff"
fi

# GH-ci.*: pre-push CI 상태 경고 (FID 20260807-doctor-ci-check)
#
# ⚠️ 하드 규칙: 아래 어서션은 어떤 경로로도 run-all.sh 에 도달하면 안 된다.
#    (증상이 "스위트가 수분대가 됨" 하나뿐이라 리뷰에서 안 보인다)
#    실행되는 pre-push 경로는 면제 4종뿐이고, 배선 검사는 소스 grep 이다.
# ─────────────────────────────────────────────────────────────
CI_SH="$PLUGIN/scripts/_internal/check-ci-status.sh"
CI_RCS=""   # GH-ci.6 이 집계할 전 경로 종료코드(.5·.5b 는 test-timing-serial.sh 가 자체 확인)

# gh stub 디렉터리 생성 — $1=stub 본문 → stdout=디렉터리 경로
_ci_stub() {
  local d; d=$(mktemp -d)
  printf '%s\n' "$1" > "$d/gh"
  chmod +x "$d/gh"
  printf '%s' "$d"
}

# GH-ci.3: gh 부재 → 무출력 exit 0 (AC-3)
#   PATH 를 통째로 교체하므로 bash·jq·git 심링크가 필수다 — 없으면 `bash: command not found`
#   (rc=127)가 나서 구현과 무관하게 영구 FAIL 이 된다.
if [ -f "$CI_SH" ]; then
  D=$(mktemp -d)
  ln -s "$(command -v bash)" "$D/bash" 2>/dev/null
  ln -s "$(command -v jq)" "$D/jq" 2>/dev/null
  ln -s "$(command -v git)" "$D/git" 2>/dev/null
  out=$(cd "$PLUGIN" && PATH="$D" bash "$CI_SH" 2>&1); rc=$?
  CI_RCS="$CI_RCS $rc"
  [ "$rc" -eq 0 ] && [ -z "$out" ] \
    && ok "GH-ci.3 gh 부재 → 무출력 exit 0" \
    || nope "GH-ci.3" "rc=$rc out=[$out]"
  rm -rf "$D"
else
  nope "GH-ci.3" "check-ci-status.sh 부재"
fi

# GH-ci.4: gh 비-0 종료(미인증·오프라인) → 무출력 exit 0 (AC-4)
if [ -f "$CI_SH" ]; then
  D=$(_ci_stub '#!/usr/bin/env bash
echo "gh: not authenticated" >&2
exit 1')
  out=$(cd "$PLUGIN" && PATH="$D:$PATH" bash "$CI_SH" 2>&1); rc=$?
  CI_RCS="$CI_RCS $rc"
  [ "$rc" -eq 0 ] && [ -z "$out" ] \
    && ok "GH-ci.4 gh 실패 → 무출력 exit 0" \
    || nope "GH-ci.4" "rc=$rc out=[$out]"
  rm -rf "$D"
else
  nope "GH-ci.4" "check-ci-status.sh 부재"
fi

# GH-ci.4b: origin 부재 repo → gh 를 부르지 않고 무출력 exit 0 (FR-4 "origin 부재")
#   계약서에 전용 AC 가 없는 FR 경로다(specify 단계 공백). FR 이 must 이므로 여기서 잠근다.
if [ -f "$CI_SH" ]; then
  D=$(mktemp -d); SENT0="$D/called"
  printf '#!/usr/bin/env bash\ntouch "%s"\n' "$SENT0" > "$D/gh"; chmod +x "$D/gh"
  TD=$(mktemp -d); (cd "$TD" && git init -q)
  out=$(cd "$TD" && PATH="$D:$PATH" bash "$CI_SH" 2>&1); rc=$?
  CI_RCS="$CI_RCS $rc"
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -f "$SENT0" ] \
    && ok "GH-ci.4b origin 부재 → gh 미호출·무출력 exit 0" \
    || nope "GH-ci.4b" "rc=$rc out=[$out] gh=$([ -f "$SENT0" ] && echo 호출됨 || echo 미호출)"
  rm -rf "$TD" "$D"
else
  nope "GH-ci.4b" "check-ci-status.sh 부재"
fi

# GH-ci.5·GH-ci.5b(워치독 1s 타임아웃 < 3s)는 시간 임계 단언이라 test-timing-serial.sh 로 이동했다(직렬 — 큰 스위트째 직렬로 묶지 않으려고).


# GH-ci.1: CI 실패 → 결론·SHA·URL 을 담은 경고 (AC-1)
if [ -f "$CI_SH" ]; then
  D=$(_ci_stub '#!/usr/bin/env bash
cat <<JSON
[{"conclusion":"failure","headSha":"abc123def4567890fedcba","url":"https://example.test/runs/42"}]
JSON')
  out=$(cd "$PLUGIN" && PATH="$D:$PATH" bash "$CI_SH" 2>&1); rc=$?
  CI_RCS="$CI_RCS $rc"
  if [ "$rc" -eq 0 ] \
     && printf '%s' "$out" | grep -q 'failure' \
     && printf '%s' "$out" | grep -q 'abc123def456' \
     && printf '%s' "$out" | grep -q 'https://example.test/runs/42'; then
    ok "GH-ci.1 CI red → 결론·SHA·URL 경고"
  else
    nope "GH-ci.1" "rc=$rc out=[$out]"
  fi
  rm -rf "$D"
else
  nope "GH-ci.1" "check-ci-status.sh 부재"
fi

# GH-ci.2: CI 성공 → stdout·stderr 모두 비어 있음 (AC-2, 잡음 금지)
if [ -f "$CI_SH" ]; then
  D=$(_ci_stub '#!/usr/bin/env bash
cat <<JSON
[{"conclusion":"success","headSha":"0123456789abcdef","url":"https://example.test/runs/43"}]
JSON')
  out=$(cd "$PLUGIN" && PATH="$D:$PATH" bash "$CI_SH" 2>&1); rc=$?
  CI_RCS="$CI_RCS $rc"
  [ "$rc" -eq 0 ] && [ -z "$out" ] \
    && ok "GH-ci.2 CI green → 무출력" \
    || nope "GH-ci.2" "rc=$rc out=[$out]"
  rm -rf "$D"
else
  nope "GH-ci.2" "check-ci-status.sh 부재"
fi

# GH-ci.1b: conclusion 부재 응답에서 **필드 시프트가 없다** (Phase C 적발)
#   탭은 bash IFS whitespace 라 빈 필드가 collapse 된다 — 빈 sentinel 이면 sha 가 결론 칸으로,
#   url 이 커밋 칸으로 밀려 경고문이 오염됐다(실측: `결론: deadbeef00112233`).
#   현재 계약은 "-" sentinel → **파싱 실패로 보고 조용히 skip**(spec §7 안전 방향).
if [ -f "$CI_SH" ]; then
  D=$(_ci_stub '#!/usr/bin/env bash
cat <<JSON
[{"headSha":"deadbeef00112233","url":"https://example.test/runs/45"}]
JSON')
  out=$(cd "$PLUGIN" && PATH="$D:$PATH" bash "$CI_SH" 2>&1); rc=$?
  CI_RCS="$CI_RCS $rc"
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    ok "GH-ci.1b conclusion 부재 → 필드 시프트 없이 조용히 skip"
  else
    nope "GH-ci.1b" "rc=$rc out=[$out]"
  fi
  rm -rf "$D"
else
  nope "GH-ci.1b" "check-ci-status.sh 부재"
fi

# GH-ci.6: 전 경로 종료코드가 예외 없이 0 (AC-6)
#   위 6개 시나리오(.3 .4 .4b .1 .2 .1b)가 CI_RCS 에 rc 를 적재해 뒀다(.5·.5b 는 test-timing-serial.sh 로 이동). 0 아닌 값이 하나라도 있으면 FAIL.
if [ -n "$CI_RCS" ]; then
  _bad=0
  for _rc in $CI_RCS; do [ "$_rc" -eq 0 ] || _bad=1; done
  _n=$(printf '%s' "$CI_RCS" | wc -w | tr -d ' ')
  [ "$_bad" -eq 0 ] && [ "$_n" -ge 6 ] \
    && ok "GH-ci.6 전 경로 exit 0 (${_n}경로)" \
    || nope "GH-ci.6" "rcs=[$CI_RCS] n=$_n"
else
  nope "GH-ci.6" "수집된 rc 없음"
fi

# GH-ci.9: 읽기 전용 — 경고가 실제로 나가는 경로에서도 파일을 쓰지 않는다 (AC-9)
#   origin 이 있는 임시 repo 를 만들어 red 응답을 주입한다(경고 경로 = 가장 많이 도는 코드).
#   한계: cwd 트리만 해시한다 — $TMPDIR·$HOME 쓰기는 미탐(Phase C Suggestion 2).
if [ -f "$CI_SH" ]; then
  D=$(_ci_stub '#!/usr/bin/env bash
cat <<JSON
[{"conclusion":"failure","headSha":"deadbeefcafe0001","url":"https://example.test/runs/44"}]
JSON')
  TD=$(mktemp -d)
  (cd "$TD" && git init -q && git remote add origin https://example.test/x.git && printf 'x\n' > a.txt)
  before=$(cd "$TD" && find . -type f | sort | xargs shasum 2>/dev/null | shasum)
  (cd "$TD" && PATH="$D:$PATH" bash "$CI_SH" >/dev/null 2>&1)
  after=$(cd "$TD" && find . -type f | sort | xargs shasum 2>/dev/null | shasum)
  [ "$before" = "$after" ] \
    && ok "GH-ci.9 읽기 전용 (경고 경로에서 파일 무변경)" \
    || nope "GH-ci.9" "트리 해시 변화"
  rm -rf "$TD" "$D"
else
  nope "GH-ci.9" "check-ci-status.sh 부재"
fi

# GH-ci.7: 배선 위치 — 면제 4종 뒤 · run-all 앞 (AC-7)
if [ -f "$PRE_PUSH" ]; then
  ln_exempt=$(grep -n 'has_update' "$PRE_PUSH" | tail -1 | cut -d: -f1)
  ln_ci=$(grep -n 'check-ci-status.sh' "$PRE_PUSH" | tail -1 | cut -d: -f1)
  ln_run=$(grep -n 'RUN_ALL.*--quiet' "$PRE_PUSH" | head -1 | cut -d: -f1)
  if [ -n "$ln_exempt" ] && [ -n "$ln_ci" ] && [ -n "$ln_run" ] \
     && [ "$ln_ci" -gt "$ln_exempt" ] && [ "$ln_ci" -lt "$ln_run" ]; then
    ok "GH-ci.7 배선 위치 (면제:${ln_exempt} < ci:${ln_ci} < run-all:${ln_run})"
  else
    nope "GH-ci.7" "면제=$ln_exempt ci=$ln_ci run-all=$ln_run"
  fi
else
  nope "GH-ci.7" "pre-push 부재"
fi

# GH-ci.8: 판정 로직 단일 소스 — 훅 본문에 gh 호출·파싱 없음 (AC-8)
if [ -f "$PRE_PUSH" ]; then
  if grep -qE '(^|[^-[:alnum:]_])gh[[:space:]]+run' "$PRE_PUSH" \
     || grep -q 'conclusion' "$PRE_PUSH"; then
    nope "GH-ci.8" "훅 본문에 gh 판정 로직 인라인"
  else
    grep -q 'check-ci-status.sh' "$PRE_PUSH" \
      && ok "GH-ci.8 판정 SoT 위임 (훅에 gh 로직 없음)" \
      || nope "GH-ci.8" "check-ci-status.sh 호출 부재"
  fi
else
  nope "GH-ci.8" "pre-push 부재"
fi

# GH-ci.R1: 면제 4경로에서 gh 미호출 + run-all 미실행 (AC-R-1)
#   sentinel = "gh 안 불렸다" / 경과시간 = "run-all 안 돌았다" (GH-3 관용구)
if [ -x "$PRE_PUSH" ]; then
  D=$(mktemp -d); SENT="$D/called"
  printf '#!/usr/bin/env bash\ntouch "%s"\n' "$SENT" > "$D/gh"; chmod +x "$D/gh"

  TD_nogit=$(mktemp -d)                                    # ① 비-git
  TD_norepo=$(mktemp -d); (cd "$TD_norepo" && git init -q) # ② 비-specops repo
  ZERO='refs/heads/main 0000000000000000000000000000000000000000 refs/heads/main 0000000000000000000000000000000000000000'

  _s=$(date +%s)
  (cd "$TD_nogit"  && PATH="$D:$PATH" bash "$PRE_PUSH" </dev/null >/dev/null 2>&1); r1=$?
  (cd "$TD_norepo" && PATH="$D:$PATH" bash "$PRE_PUSH" </dev/null >/dev/null 2>&1); r2=$?
  (cd "$PLUGIN" && PATH="$D:$PATH" SPECOPS_RUN_ALL=1 bash "$PRE_PUSH" </dev/null >/dev/null 2>&1); r3=$?
  (cd "$PLUGIN" && PATH="$D:$PATH" bash "$PRE_PUSH" <<< "$ZERO" >/dev/null 2>&1); r4=$?
  _e=$(date +%s); _d=$((_e - _s))

  if [ ! -f "$SENT" ] && [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$r3" -eq 0 ] && [ "$r4" -eq 0 ] && [ "$_d" -lt 20 ]; then
    ok "GH-ci.R1 면제 4경로 무오염 (gh 미호출 · ${_d}s < 20s = run-all 미실행)"
  else
    nope "GH-ci.R1" "sentinel=$([ -f "$SENT" ] && echo 호출됨 || echo 부재) rc=$r1/$r2/$r3/$r4 소요=${_d}s"
  fi
  rm -rf "$D" "$TD_nogit" "$TD_norepo"
else
  nope "GH-ci.R1" "pre-push 부재"
fi

# GH-ci.doc: gh 선택 의존이 문서화됐는가 (GH-10 과 동형 — 의존 고지는 문서가 유일한 층)
#   CLAUDE.md 측은 'gh' 로 grep 하면 안 된다 — 기존 문장("gh pr create" 등)에 이미 매치해
#   편집 전부터 green 인 vacuous 검사가 된다. 고유 문구로 잠근다.
grep -q 'check-ci-status' "$PLUGIN/scripts/README.md" && grep -q 'CI 상태 경고' "$PLUGIN/CLAUDE.md" \
  && ok "GH-ci.doc CLAUDE.md·scripts/README gh 의존 고지" \
  || nope "GH-ci.doc" "문서 고지 부재"

# ── 20260908 full-suite 마커 (생산측) ────────────────────────────────
RUNALL="$PLUGIN/scripts/tests/run-all.sh"
# ★ regex 는 삽입 코드와 문자 단위로 맞춘다. 마커 경로는 코드에서
#   `${SPECOPS_ROOT:-.specops}/.full-suite-pass` 라 `.specops/.full-suite-pass` 로는 **매칭되지 않는다**.
MARKER_LIT='full-suite-pass'
_g() { grep -qE "$1" "$2"; }   # -E 필수 — 아래 교대(|) 패턴이 BRE 에서 불일치

_g "$MARKER_LIT" "$RUNALL"                        && ok "T20.a run-all 마커 경로 선언"      || nope "T20.a run-all 마커 경로 선언"
_g '_FSP_TREE=.*nondoc_fingerprint' "$RUNALL"  && ok "T20.b 지문 캡처가 nondoc_fingerprint" || nope "T20.b 지문 캡처가 nondoc_fingerprint"
_g 'printf .*_FSP_TREE.*>.*_FSP_MARKER' "$RUNALL" && ok "T20.c 성공 시 기록"                || nope "T20.c 성공 시 기록"
_g 'rm -f .*_FSP_MARKER' "$RUNALL"                && ok "T20.d FAIL 시 마커 제거"           || nope "T20.d FAIL 시 마커 제거"
! _g 'mkdir -p .*_FSP_MARKER' "$RUNALL" && _g '\[ -d .*_FSP_MARKER' "$RUNALL" && ok "T20.e 마커 디렉터리를 만들지 않음(있을 때만 기록 — 관할 편입 금지)" || nope "T20.e 마커 디렉터리를 만들지 않음"
# VERIFY 토큰 불변 — R-1/R-2 실행-근거 게이트가 transcript 에서 파싱한다
_g '^echo "VERIFY: PASS"' "$RUNALL"               && ok "T20.f VERIFY: PASS 토큰 보존"      || nope "T20.f VERIFY: PASS 토큰 보존"
_g '^  echo "VERIFY: FAIL"' "$RUNALL"             && ok "T20.g VERIFY: FAIL 토큰 보존"      || nope "T20.g VERIFY: FAIL 토큰 보존"

# ★ AC-1 "실행 **시작 시점**의 지문" 은 grep 만으로 증명되지 않는다 — T20.b 는 캡처가
#   루프 **뒤**에 있어도 통과하고, T20.h 도 (스위트가 트리를 안 더럽히면) 구분하지 못한다.
#   루프 뒤 캡처는 fail-**open** 방향이다: 트리를 더럽힌 스위트의 종료 지문이 마커가 되어
#   pre-push 가 그 더러운 트리를 skip 한다. 줄번호 대소로 잠근다(T21.i 와 동형).
# ★ 패턴은 **캡처 대입**(`$(`)에 고정한다 — `_FSP_TREE=` 만 보면 :22 의 초기화
#   `_FSP_TREE=NO_GIT` 에 첫매치해, 초기화는 두고 캡처 블록만 루프 뒤로 옮기는
#   분할 변이(C1b)가 통과한다. 그 변이는 실제 fail-open 이다(Phase C 행위 실증:
#   marker==더럽힌 종료지문). 실측: 원본 fsp=26 PASS · C1b fsp=97 FAIL.
_ln_fsp=$(grep -n '_FSP_TREE=\$(' "$RUNALL" | head -1 | cut -d: -f1)
_ln_loop=$(grep -n '^for suite in' "$RUNALL" | head -1 | cut -d: -f1)
if [ -n "$_ln_fsp" ] && [ -n "$_ln_loop" ] && [ "$_ln_fsp" -lt "$_ln_loop" ]; then
  ok "T20.b1 지문 캡처가 스위트 루프보다 앞"
else
  nope "T20.b1 지문 캡처가 스위트 루프보다 앞" "fsp=${_ln_fsp:-없음} loop=${_ln_loop:-없음}"
fi

# ── 생산측 행위 검증 (AC-1·AC-2·AC-7) ────────────────────────────────
# 정적 grep 만으로는 "그 줄이 FAIL 경로에 있는지" 를 증명하지 못한다.
# 사본에서 스위트를 다 걷어내고 더미 1개만 남겨 run-all 을 **수 초**에 돌린다.
_t20_dead() { nope "$1" "fixture 미성립"; }
_p=$(iso::make_git_tree) || _p=""
if [ -z "$_p" ] || [ ! -d "$_p" ]; then
  nope "T20.h fixture 생성"
  _t20_dead "T20.i1 run-all 실패 → exit 1"
  _t20_dead "T20.i run-all 실패 → 마커 삭제"
  _t20_dead "T20.j 마지막 줄이 VERIFY: PASS"
  _t20_dead "T20.k 지문 UNHASHABLE → 마커 미기록"
  _t20_dead "T20.k2 읽을 수 있게 되면 마커 재기록 (양성 대조)"
else
trap 'rm -rf "$_p"' EXIT
find "$_p/scripts/tests" -name 'test-*.sh' -delete 2>/dev/null
printf '#!/usr/bin/env bash\nexit ${DUMMY_RC:-0}\n' > "$_p/scripts/tests/test-dummy.sh"
chmod +x "$_p/scripts/tests/test-dummy.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$_p/scripts/_internal/validate-structure.sh"

# ★ 스위트 정리가 조용히 실패하면 중첩 run-all 이 이 스위트를 **재귀 실행**한다(fork bomb).
#   개수를 단언해 그 사고를 FAIL 로 바꾼다 — 사본이 정리 안 됐으면 run-all 을 아예 돌리지 않는다.
_p_ntests=$(find "$_p/scripts/tests" -name 'test-*.sh' | wc -l | tr -d ' ')
if [ "$_p_ntests" != "1" ]; then
  nope "T20.h fixture 스위트 정리" "test-*.sh ${_p_ntests}개 (중첩 run-all 방지 — 1개여야 한다)"
  _t20_dead "T20.i1 run-all 실패 → exit 1"
  _t20_dead "T20.i run-all 실패 → 마커 삭제"
  _t20_dead "T20.j 마지막 줄이 VERIFY: PASS"
  _t20_dead "T20.k 지문 UNHASHABLE → 마커 미기록"
  _t20_dead "T20.k2 읽을 수 있게 되면 마커 재기록 (양성 대조)"
else

_p_fp() { ( cd "$_p" && bash -c '. scripts/_internal/verification-state.sh; vs::nondoc_fingerprint' ); }

# .specops/ 부재 → 성공해도 디렉터리를 만들지 않는다(관할 편입 금지 — 20261021)
rm -rf "$_p/.specops"
( cd "$_p" && DUMMY_RC=0 bash scripts/tests/run-all.sh >/dev/null 2>&1 ); _p_rc=$?
{ [ "$_p_rc" -eq 0 ] && [ ! -e "$_p/.specops" ]; } && ok "T20.h0 .specops 부재 → run-all 성공 · 디렉터리 미생성" || nope "T20.h0 .specops 부재 → 디렉터리 미생성" "rc=$_p_rc · $(ls -a "$_p" | tr '\n' ' ')"
mkdir -p "$_p/.specops"

# 성공 → 마커가 지문과 일치
( cd "$_p" && DUMMY_RC=0 bash scripts/tests/run-all.sh >/dev/null 2>&1 )
if [ "$(cat "$_p/.specops/.full-suite-pass" 2>/dev/null)" = "$(_p_fp)" ]; then
  ok "T20.h run-all 성공 → 마커==지문"
else nope "T20.h run-all 성공 → 마커==지문"; fi

# 실패 → 마커 삭제 (낡은 통과가 새 실패를 덮지 않는다 — clarify Q1)
# ★ 마커를 **다시 심고** 시작한다 — T20.h 가 남긴 것에 의존하면 공허 통과 여지가 있고,
#   AC-7 검증 방법("마커를 미리 심고")과도 어긋난다.
# ★ mkdir -p 가 **필수**다: `.specops/` 는 .gitignore 라 사본에 없다. 없으면 이 seed 리다이렉트가
#   조용히 실패해 T20.i 가 "삭제됐다" 가 아니라 "애초에 없다" 로 공허 통과한다(AC-7 미검증).
mkdir -p "$_p/.specops"
_p_fp > "$_p/.specops/.full-suite-pass"
( cd "$_p" && DUMMY_RC=1 bash scripts/tests/run-all.sh >/dev/null 2>&1 ); _p_rc=$?
[ "$_p_rc" -eq 1 ] && ok "T20.i1 run-all 실패 → exit 1" || nope "T20.i1 run-all 실패 → exit 1" "rc=$_p_rc"
[ ! -f "$_p/.specops/.full-suite-pass" ] && ok "T20.i run-all 실패 → 마커 삭제" || nope "T20.i run-all 실패 → 마커 삭제"

# stdout 토큰 불변 (R4 — 거버넌스 파싱 대상)
_p_out=$( cd "$_p" && DUMMY_RC=0 bash scripts/tests/run-all.sh 2>&1 | tail -1 )
[ "$_p_out" = "VERIFY: PASS" ] && ok "T20.j 마지막 줄이 VERIFY: PASS" || nope "T20.j 마지막 줄이 VERIFY: PASS ($_p_out)"

# 지문이 UNHASHABLE(읽을 수 없는 tracked 파일)이면 마커를 쓰지 않는다 (20261005-fingerprint-add-failclosed)
#   NO_GIT 과 같은 취급이다 — 대조 불가한 값으로 skip 이 열리면 안 된다. root 는 chmod 000 이 읽히므로 skip.
_chmod_inert() { local f; f=$(mktemp) || return 0; chmod 000 "$f"; if [ -r "$f" ]; then rm -f "$f"; return 0; fi; rm -f "$f"; return 1; }   # root·ACL·비-POSIX FS 에서는 chmod 000 이 파일을 막지 못한다
if _chmod_inert; then
  skip "T20.k 읽을 수 없는 파일 → 마커 미기록 (chmod 000 이 파일을 막지 못한다 — root·ACL 등)"
else
  rm -f "$_p/.specops/.full-suite-pass"
  chmod 000 "$_p/README.md"
  ( cd "$_p" && DUMMY_RC=0 bash scripts/tests/run-all.sh >/dev/null 2>&1 )
  [ ! -f "$_p/.specops/.full-suite-pass" ] && ok "T20.k 지문 UNHASHABLE → 마커 미기록" || nope "T20.k 지문 UNHASHABLE → 마커 미기록"
  chmod 644 "$_p/README.md"
  # 양성 대조 — 읽을 수 있게 되면 다시 기록된다 (T20.k 가 "항상 미기록" 으로 공허 통과하지 않게)
  ( cd "$_p" && DUMMY_RC=0 bash scripts/tests/run-all.sh >/dev/null 2>&1 )
  [ "$(cat "$_p/.specops/.full-suite-pass" 2>/dev/null)" = "$(_p_fp)" ] \
    && ok "T20.k2 읽을 수 있게 되면 마커 재기록 (양성 대조)" || nope "T20.k2 읽을 수 있게 되면 마커 재기록"
fi

fi
rm -rf "$_p"; trap - EXIT
fi

# ── 20260908 full-suite 마커 (소비측) ────────────────────────────────
PREPUSH="$PLUGIN/.githooks/pre-push"
READMES="$PLUGIN/scripts/README.md"
INSTALLSH="$PLUGIN/scripts/_internal/install-git-hooks.sh"

_g "$MARKER_LIT" "$PREPUSH"                    && ok "T21.a pre-push 마커 대조"    || nope "T21.a pre-push 마커 대조"
_g 'SPECOPS_FORCE_FULL' "$PREPUSH"             && ok "T21.b 강제 실행 env"         || nope "T21.b 강제 실행 env"
_g '동일 트리.*통과|이미 통과.*건너' "$PREPUSH" && ok "T21.c skip 고지에 사유"      || nope "T21.c skip 고지에 사유"
_g 'SPECOPS_FORCE_FULL=1' "$PREPUSH"           && ok "T21.d skip 고지에 강제 방법" || nope "T21.d skip 고지에 강제 방법"

# 낡은 수치 잔존 금지 — **3파일 전수**. 실측으로 **6곳**이다:
#   pre-push:2(~340s) · pre-push:31(~330s) · pre-push:37(~5.5분) · README:266(~330s) · README:270(~330s) · install:34(~330s)
for _f in "$PREPUSH" "$READMES" "$INSTALLSH"; do
  if grep -qE '~(330|340)s|5\.5분' "$_f"; then
    nope "T21.h 낡은 수치 잔존: $(basename "$_f")"
  else
    ok "T21.h 낡은 수치 제거: $(basename "$_f")"
  fi
done

# 삽입 순서 계약 — 마커 대조가 면제 4종 뒤인가 (줄번호 대소, 개수 비의존)
_ln_recur=$(grep -n 'SPECOPS_RUN_ALL' "$PREPUSH" | head -1 | cut -d: -f1)
_ln_ci=$(grep -n 'check-ci-status' "$PREPUSH" | head -1 | cut -d: -f1)
_ln_marker=$(grep -n 'full-suite-pass' "$PREPUSH" | head -1 | cut -d: -f1)
if [ -n "$_ln_marker" ] && [ -n "$_ln_ci" ] && [ -n "$_ln_recur" ] \
   && [ "$_ln_marker" -gt "$_ln_ci" ] && [ "$_ln_ci" -gt "$_ln_recur" ]; then
  ok "T21.i 마커 대조가 면제 4종 뒤"
else
  nope "T21.i 마커 대조가 면제 4종 뒤" "marker=${_ln_marker:-없음} ci=${_ln_ci:-없음} recur=${_ln_recur:-없음}"
fi

# ── 20261005 판정 단일화 — pre-push 는 신선도 헬퍼를 부른다 (verify 단계와 공유) ──
_g 'full-suite-fresh\.sh' "$PREPUSH" && ok "T23.a pre-push 가 신선도 헬퍼를 호출" || nope "T23.a pre-push 가 신선도 헬퍼를 호출"
if grep -q 'vs::nondoc_fingerprint' "$PREPUSH"; then
  nope "T23.b pre-push 인라인 지문 판정 잔존 (헬퍼와 이중화)"
else
  ok "T23.b pre-push 인라인 지문 판정 제거"
fi

# ── fail-closed 경로 (AC-4·AC-9) ─────────────────────────────────────
# ★ fixture 미성립 시 **케이스 수·라벨을 고정**한다. if/else 구조가 이미 선형 실행을 막으므로
#   가드 없이도 "T22.b 만 공허 통과" 는 생기지 않는다(1 FAIL + 나머지 10건 **부재**).
#   문제는 그 '부재' 다 — AC-R-1 의 라벨 대조가 누락을 세려면 케이스가 이름을 갖고 FAIL 해야 한다.
#   T20.h 의 _t20_dead 와 동형. (Phase C M-2 가 원 주석의 과장을 지적해 취지로 정정)
_t22_dead() { nope "$1" "fixture 미성립"; }
_fc=$(iso::make_git_tree) || _fc=""
if [ -z "$_fc" ] || [ ! -d "$_fc" ]; then
  nope "T22 fixture 생성"
  _t22_dead "T22.a 마커 부재 → 전체 실행"
  _t22_dead "T22.b 지문 일치 → skip"
  _t22_dead "T22.b1 skip 고지 — 사유 출력"
  _t22_dead "T22.b2 skip 고지 — 강제 방법 출력"
  _t22_dead "T22.c 비문서 변경 → 불일치 → 전체 실행"
  _t22_dead "T22.c2 문서 변경 → 지문 불변 → skip"
  _t22_dead "T22.d 마커 손상 → 전체 실행"
  _t22_dead "T22.e 빈 마커 → 전체 실행"
  _t22_dead "T22.f 권한 없음 → 전체 실행"
  _t22_dead "T22.g NO_GIT → 전체 실행"
  _t22_dead "T22.h FORCE_FULL → 전체 실행"
  _t22_dead "T23.c 헬퍼 부재 → 전체 실행 (fail-closed)"
  _t22_dead "T23.d 지문 UNHASHABLE + 마커 UNHASHABLE → 전체 실행"
else
trap 'rm -rf "$_fc"' EXIT

cat > "$_fc/scripts/tests/run-all.sh" <<'STUB'
#!/usr/bin/env bash
touch "${SPECOPS_ROOT:-.specops}/.ran"
exit 0
STUB
chmod +x "$_fc/scripts/tests/run-all.sh"
mkdir -p "$_fc/.specops"

# ★ SPECOPS_RUN_ALL= 로 재귀 가드를 비운다 (가드는 = "1" 비교라 빈값이면 통과).
#   이 스위트가 run-all 아래서 돌면 run-all.sh:10 의 export 를 상속해 pre-push:18 이
#   **마커 로직 앞에서** exit 0 하고 T22.* 가 전건 SKIPPED 로 무너진다.
_fc_run() {
  ( cd "$_fc" && mkdir -p .specops && rm -f .specops/.ran \
    && printf 'refs/heads/main aaa111 refs/heads/main bbb222\n' \
       | env SPECOPS_RUN_ALL= "$@" bash .githooks/pre-push >/dev/null 2>&1
    [ -f .specops/.ran ] && echo RAN || echo SKIPPED )
}
_fc_fp() { ( cd "$_fc" && bash -c '. scripts/_internal/verification-state.sh; vs::nondoc_fingerprint' ); }
_fc_case() { # $1=id $2=desc $3=기대(RAN|SKIPPED) $4...=env
  local _id="$1" _d="$2" _want="$3"; shift 3
  local _got; _got=$(_fc_run "$@")
  [ "$_got" = "$_want" ] && ok "$_id $_d" || nope "$_id $_d" "기대=$_want 실제=$_got"
}

# ① 마커 부재 → 전체 실행
rm -f "$_fc/.specops/.full-suite-pass"
_fc_case T22.a "마커 부재 → 전체 실행" RAN

# ② 지문 일치 → skip  ★ 이게 통과해야 나머지가 의미를 갖는다
_fc_fp > "$_fc/.specops/.full-suite-pass"
_fc_case T22.b "지문 일치 → skip" SKIPPED
# skip 고지를 **런타임으로** 잠근다 (T21.c/d 는 소스 grep 이라 실제 출력은 안 본다 — AC-3·AC-8).
# T22.b 의 SKIPPED 는 "부작용 파일 부재" 라 어떤 조기 exit 와도 구분되지 않는다 —
# 마커 고유 문구를 stderr 에서 확인하는 b1·b2 가 그 공허 통과를 막는 유일한 층이다.
_fc_err=$( cd "$_fc" && printf 'refs/heads/main a refs/heads/main b\n' \
  | env SPECOPS_RUN_ALL= bash .githooks/pre-push 2>&1 >/dev/null )
printf '%s' "$_fc_err" | grep -qE '동일 트리.*통과|이미 통과.*건너' \
  && ok "T22.b1 skip 고지 — 사유 출력" || nope "T22.b1 skip 고지 — 사유 출력"
printf '%s' "$_fc_err" | grep -q 'SPECOPS_FORCE_FULL=1' \
  && ok "T22.b2 skip 고지 — 강제 방법 출력" || nope "T22.b2 skip 고지 — 강제 방법 출력"

# ③ **비문서** 1바이트 변경 → 불일치 → 전체 실행
# ★ 종전엔 README.md 를 고쳤는데, 마커가 비문서 지문으로 바뀐 뒤로는 문서 변경이 지문을
#   바꾸지 않아 이 케이스의 의미가 **역전**된다(SKIPPED 가 정답). 비문서로 교체한다.
printf '\n# fc mutate\n' >> "$_fc/scripts/tests/run-all.sh"
_fc_case T22.c "비문서 변경 → 불일치 → 전체 실행" RAN

# ③-2 문서 변경 → 지문 불변 → skip (M-2 를 잠그는 양성 대조)
#   이 케이스가 없으면 "문서 한 줄이 전체 스위트를 다시 돌리지 않는다" 가 무잠금이다.
_fc_fp > "$_fc/.specops/.full-suite-pass"
printf '\n<!-- doc mutate -->\n' >> "$_fc/README.md"
_fc_case T22.c2 "문서 변경 → 지문 불변 → skip" SKIPPED

# ④ 마커 내용 손상 → 전체 실행 (③ 로 트리가 이미 바뀌었으니 **재기록 후** 손상해야 성립)
_fc_fp > "$_fc/.specops/.full-suite-pass"
printf 'not-a-tree-hash\n' > "$_fc/.specops/.full-suite-pass"
_fc_case T22.d "마커 손상 → 전체 실행" RAN

# ⑤ 빈 마커 → 전체 실행 (AC-4 ② 읽기 실패 축 — 결정적)
: > "$_fc/.specops/.full-suite-pass"
_fc_case T22.e "빈 마커 → 전체 실행" RAN

# ⑥ 읽기 권한 없음 → 전체 실행 (root 면 읽히므로 skip)
_fc_fp > "$_fc/.specops/.full-suite-pass"
chmod 000 "$_fc/.specops/.full-suite-pass" 2>/dev/null
if [ "$(id -u)" = "0" ]; then
  skip "T22.f 권한 없음 → 전체 실행 (root 는 읽힌다)"
else
  _fc_case T22.f "권한 없음 → 전체 실행" RAN
fi
chmod 644 "$_fc/.specops/.full-suite-pass" 2>/dev/null

# ⑦ NO_GIT → 전체 실행 (TMPDIR 파괴로 vs:: 의 mktemp 를 실패시킨다)
_fc_fp > "$_fc/.specops/.full-suite-pass"
_fc_case T22.g "NO_GIT → 전체 실행" RAN TMPDIR=/nonexistent/zz

# ⑧ SPECOPS_FORCE_FULL=1 → 지문 일치해도 전체 실행
_fc_fp > "$_fc/.specops/.full-suite-pass"
_fc_case T22.h "FORCE_FULL → 전체 실행" RAN SPECOPS_FORCE_FULL=1

# ⑩ 지문 UNHASHABLE(읽을 수 없는 tracked 파일) → 마커가 같은 문자열이어도 전체 실행 (20261005-fingerprint-add-failclosed)
#   헬퍼의 UNHASHABLE 가드가 없으면 현재 지문 == 마커 == UNHASHABLE 이라 일치로 읽혀 skip 된다. root 는 읽혀서 skip.
_chmod_inert() { local f; f=$(mktemp) || return 0; chmod 000 "$f"; if [ -r "$f" ]; then rm -f "$f"; return 0; fi; rm -f "$f"; return 1; }   # root·ACL·비-POSIX FS 에서는 chmod 000 이 파일을 막지 못한다
if _chmod_inert; then
  skip "T23.d 읽을 수 없는 파일 — chmod 000 이 파일을 막지 못한다(root·ACL 등)"
else
  chmod 000 "$_fc/README.md"
  printf 'UNHASHABLE\n' > "$_fc/.specops/.full-suite-pass"
  _fc_case T23.d "지문 UNHASHABLE + 마커 UNHASHABLE → 전체 실행" RAN
  chmod 644 "$_fc/README.md"
fi

# ⑨ 헬퍼 부재 → 전체 실행 (판정이 헬퍼로 옮겨졌으므로 부재 경로가 새로 생겼다 — 마커가 일치해도 생략하면 안 된다)
rm -f "$_fc/scripts/_internal/full-suite-fresh.sh"
_fc_fp > "$_fc/.specops/.full-suite-pass"
_fc_case T23.c "헬퍼 부재 → 전체 실행 (fail-closed)" RAN

rm -rf "$_fc"; trap - EXIT
fi

# ★ 자가점검 (AC-10): 이 스위트가 실 트리를 변이하지 않았음을 스스로 단언한다.
_iso_after=$(iso::fingerprint $_iso_paths)
[ "$_iso_before" = "$_iso_after" ] \
  && ok "ISO 실 트리 무변이 (실행 전후 git status 불변)" \
  || nope "ISO" "실 트리가 변이됐다 (이 스위트 또는 동시 실행 중인 다른 프로세스) — before=$_iso_before after=$_iso_after"

finish
