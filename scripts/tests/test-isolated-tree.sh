#!/usr/bin/env bash
# test-isolated-tree.sh — 격리 사본 헬퍼 계약
# ★ 루트 배치 필수 — lib/ 에 두면 test-run-all-glob-completeness T1.a 가 FAIL 한다(실측).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
source "$PLUGIN/scripts/tests/lib/isolated-tree.sh" 2>/dev/null || true
command -v iso::make_tree >/dev/null 2>&1 && command -v iso::make_git_tree >/dev/null 2>&1 \
  && command -v iso::fingerprint >/dev/null 2>&1 \
  || { echo "FATAL: isolated-tree 미로드(또는 반쯤 로드)" >&2; exit 1; }

# 실 트리 지문 (I5 용) — 절대값이 아니라 전후 비교
_iso_paths='scripts/_internal/.hardgate-baseline skills/specifying-ko/SKILL.md commands/start-all.md skills scripts/tests templates'
_iso_before=$(iso::fingerprint $_iso_paths)

# I1: make_tree 가 사본을 만들고 그 안에서 validate-structure 가 ❌ 0건
T=$(iso::make_tree) || { nope "I1" "사본 생성 실패"; finish; exit 1; }
trap 'rm -rf "${T:-}" "${T3:-}" "${G:-}"' EXIT   # 중단 시 tmpdir 누출 방지
_out1=$( cd "$T" && bash scripts/_internal/validate-structure.sh 2>&1 )
n=$( printf '%s' "$_out1" | grep -c '❌' || true )
y=$( printf '%s' "$_out1" | grep -c '✅' || true )
if [ "$n" = "0" ] && [ "${y:-0}" -gt 0 ]; then
  ok "I1 사본에서 validate-structure ❌ 0건 · ✅ ${y}건"
else
  nope "I1" "❌ ${n}건 · ✅ ${y}건 (✅ 0 이면 조기 crash 를 통과시킨 것)"
fi

# I2: 사본을 변이해도 실 트리는 무오염 (격리의 본질)
before=$(cd "$PLUGIN" && git status --porcelain | shasum | cut -c1-12)
mkdir -p "$T/skills/__iso_probe__"
printf -- '---\nname: __iso_probe__\n---\n\n산문에서 HARD GATE 를 선언한다.\n' > "$T/skills/__iso_probe__/SKILL.md"
m=$( cd "$T" && bash scripts/_internal/validate-structure.sh 2>&1 | grep -c '❌' || true )
after=$(cd "$PLUGIN" && git status --porcelain | shasum | cut -c1-12)
[ "$m" -gt 0 ] && [ "$before" = "$after" ] \
  && ok "I2 사본 변이가 사본에만 반영 (사본 ❌${m}건 · 실 트리 불변)" \
  || nope "I2" "사본❌=$m before=$before after=$after"
rm -rf "$T"

# I3: **워킹트리 내용**을 복사한다 (git archive HEAD 가 아님) — AC-2 핵심
#   ★ 실 트리에 프로브를 쓰지 않는다(자기참조 위반). git 사본 안에서 tracked 파일을
#     미커밋 수정하고, 그 안에서 다시 make_tree 를 돌려 수정분이 따라오는지 본다.
G=$(iso::make_git_tree) || { nope "I3" "git 사본 실패"; finish; exit 1; }
printf '\n<!-- iso-worktree-marker -->\n' >> "$G/templates/spec.md"
# ★ `source … &&` 를 넣지 않는다 — 함수는 서브셸에 상속되고, Step 4 시점엔 헬퍼가 아직
#   untracked 라 `$G`(git ls-files 사본)에 그 파일이 없어 source 가 실패하고 && 로 단락된다
#   (실측: T3 빈값 → "HEAD 를 복사하고 있다" 로 원인이 잘못 표기됨).
# ★ 인자 명시 — 없으면 실 트리를 복사해 거짓 PASS 가 된다.
T3=$( iso::make_tree "$G" )
grep -q 'iso-worktree-marker' "$T3/templates/spec.md" 2>/dev/null \
  && ok "I3 미커밋 수정이 사본에 반영 (워킹트리 복사 — archive HEAD 아님)" \
  || nope "I3" "미커밋 수정이 사본에 없다 — HEAD 를 복사하고 있다"
rm -rf "$T3" "$G"

# I4: make_git_tree 는 git repo 를 만든다 + **clean 대조군** (pre-commit vacuous 차단)
#   ★ pwd -P 필수 — toplevel 은 /private/var/…, $G 는 /var/… 로 나와 문자열 비교가 어긋난다.
G=$(iso::make_git_tree) || { nope "I4" "git 사본 실패"; G=""; }
if [ -n "$G" ]; then
  _top=$(cd "$G" && git rev-parse --show-toplevel 2>/dev/null)
  _pwd=$(cd "$G" && pwd -P)
  ( cd "$G" && bash .githooks/pre-commit >/dev/null 2>&1 ); _hrc=$?
  if [ -n "$_top" ] && [ "$_top" = "$_pwd" ] && [ "$_hrc" -eq 0 ]; then
    ok "I4 git 사본이 toplevel==pwd -P 이고 clean 에서 pre-commit rc=0 (대조군)"
  else
    nope "I4" "toplevel='$_top' pwd -P='$_pwd' clean pre-commit rc=$_hrc"
  fi
  rm -rf "$G"
fi

# I6: iso::fingerprint 가 **호출자가 선언한 경로**의 내용 변화를 본다 (고정목록 맹점 차단)
#   ★ 이미 M 인 파일의 **추가 내용 변경**을 쓴다 — porcelain 절반은 이 변화를 못 보므로
#     git diff 절반(=pathspec)이 유일한 탐지 경로다. 고정 5경로에는 .githooks 가 없다(실측).
G=$(iso::make_git_tree) || { nope "I6" "git 사본 실패"; G=""; }
if [ -n "$G" ]; then
  printf '\n# iso-fp-probe-1\n' >> "$G/.githooks/pre-commit"
  _b=$( PLUGIN="$G"; iso::fingerprint .githooks/pre-commit )
  printf '# iso-fp-probe-2\n' >> "$G/.githooks/pre-commit"
  _a=$( PLUGIN="$G"; iso::fingerprint .githooks/pre-commit )
  rm -rf "$G"
  [ "$_b" != "$_a" ] \
    && ok "I6 선언 경로의 내용 변화를 지문이 반영 (pathspec 계약)" \
    || nope "I6" "지문 불변 ($_b) — 고정 목록이면 .githooks 가 사각지대다"
fi

# I5: 실 트리 무오염 — **before/after 지문 비교** (절대값 검사 금지)
#   ★ `porcelain == 0` 을 요구하면 **WIP 가 있는 dev 머신에서 무조건 FAIL** 한다.
#     158 중 1건이 상시 red 면 pre-push 가 무의미해지고 `--no-verify` 관성이 생긴다 —
#     이 repo 가 이미 겪은 실패 모드다(CLAUDE.md). 우리가 볼 것은 "깨끗한가" 가 아니라
#     "이 스위트가 바꿨는가" 다.
[ "$_iso_before" = "$(iso::fingerprint $_iso_paths)" ] \
  && ok "I5 헬퍼 테스트가 실 트리를 변이하지 않았다 (전후 지문 불변)" \
  || nope "I5" "실 트리가 변이됐다 (이 스위트 또는 동시 실행 중인 다른 프로세스)"

finish
