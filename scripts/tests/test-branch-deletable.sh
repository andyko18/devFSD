#!/usr/bin/env bash
# 브랜치 삭제 안전 판정 — 20260806 패턴 A 타겟 스캔
#
# 결함: finishing-a-development-branch-ko 의 핵심 HARD GATE 가
#   `[ "$MERGE_CONFIRMED_BY_GH" = "true" ]` 인데, 이 변수를 **모델이 스스로 세팅**한다.
#   gh 가 실제로 MERGED 를 반환했는지 검증하는 층이 0곳이고, `git branch -D`·
#   `git worktree remove`·`git push --delete` 는 pretool 훅 관할 밖이다.
#   → 미머지 브랜치가 `-D` 로 삭제되면 **커밋이 소실**된다(비가역).
# 판정을 증거 기반으로 옮긴다: ① main 조상 여부(git) ② gh MERGED(squash/rebase 대응).
# 삭제는 비가역이므로 **판정 불가는 fail-CLOSED**(다른 게이트의 fail-open 과 반대).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-branch-deletable.sh"

_repo() {  # $1=dir — main + feat 브랜치 fixture
  local d="$1"
  mkdir -p "$d"; cd "$d" || return 1
  git init -q -b main
  git config user.email t@t.com; git config user.name T
  printf 'base\n' > a.txt; git add a.txt; git commit -qm init
}

# T1: 완전 머지된 브랜치 → 삭제 허용 (git 증거만으로 충분)
TD=$(mktemp -d); ( _repo "$TD" >/dev/null 2>&1
  git checkout -qb feat/done; printf 'x\n' >> a.txt; git commit -qam work
  git checkout -q main; git merge -q --no-ff feat/done -m merge )
out=$(cd "$TD" && bash "$CHK" feat/done 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'merged' \
  && ok "T1 완전 머지 → 삭제 허용" || nope "T1" "rc=$rc out=$out"
rm -rf "$TD"

# T2: ★ 미머지 브랜치 → 삭제 금지 (커밋 소실 차단)
TD=$(mktemp -d); ( _repo "$TD" >/dev/null 2>&1
  git checkout -qb feat/wip; printf 'y\n' >> a.txt; git commit -qam wip
  git checkout -q main )
out=$(cd "$TD" && bash "$CHK" feat/wip 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qE '미머지|금지' \
  && ok "T2 미머지 → 삭제 금지" || nope "T2" "rc=$rc out=$out"
rm -rf "$TD"

# T3: 존재하지 않는 브랜치 → 오류(2) — 조용한 통과 금지
TD=$(mktemp -d); ( _repo "$TD" >/dev/null 2>&1 )
(cd "$TD" && bash "$CHK" feat/nope >/dev/null 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "T3 부재 브랜치 → rc=2" || nope "T3" "rc=$rc"
rm -rf "$TD"

# T4: 인자 없음 → 사용법(2)
(bash "$CHK" >/dev/null 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "T4 인자 없음 → rc=2" || nope "T4" "rc=$rc"

# T5: main·현재 브랜치 삭제 시도 → 거부 (자기 발등 방지)
TD=$(mktemp -d); ( _repo "$TD" >/dev/null 2>&1 )
(cd "$TD" && bash "$CHK" main >/dev/null 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "T5 main 삭제 시도 → 거부" || nope "T5" "rc=$rc"
rm -rf "$TD"

# T6: ★ squash merge 시뮬 — 내용은 main 에 있으나 조상 아님. gh 증거 없으면 금지(fail-CLOSED)
TD=$(mktemp -d); ( _repo "$TD" >/dev/null 2>&1
  git checkout -qb feat/squash; printf 'z\n' >> a.txt; git commit -qam feature
  git checkout -q main
  printf 'z\n' >> a.txt; git commit -qam "squashed feature"  # 동일 내용, 별개 커밋
)
out=$(cd "$TD" && SPECOPS_BRANCH_GH_STATE="" bash "$CHK" feat/squash 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qE '증거|gh' \
  && ok "T6 squash + gh 증거 없음 → 금지(fail-CLOSED)" || nope "T6" "rc=$rc out=$out"
rm -rf "$TD"

# T7: squash + gh MERGED 증거 주입 → 삭제 허용
TD=$(mktemp -d); ( _repo "$TD" >/dev/null 2>&1
  git checkout -qb feat/squash2; printf 'w\n' >> a.txt; git commit -qam feature
  git checkout -q main )
out=$(cd "$TD" && SPECOPS_BRANCH_GH_STATE=MERGED bash "$CHK" feat/squash2 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'MERGED' \
  && ok "T7 gh MERGED 증거 → 허용" || nope "T7" "rc=$rc out=$out"
rm -rf "$TD"

# T8: gh 상태가 OPEN → 금지 (증거가 있어도 머지 아님)
TD=$(mktemp -d); ( _repo "$TD" >/dev/null 2>&1
  git checkout -qb feat/open; printf 'v\n' >> a.txt; git commit -qam feature
  git checkout -q main )
(cd "$TD" && SPECOPS_BRANCH_GH_STATE=OPEN bash "$CHK" feat/open >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T8 gh OPEN → 금지" || nope "T8" "rc=$rc"
rm -rf "$TD"

# T9: skill 본문이 판정기를 SoT 로 지목 (자기세팅 변수 대체)
S="$PLUGIN/skills/finishing-a-development-branch-ko/SKILL.md"
grep -q 'check-branch-deletable.sh' "$S" \
  && ok "T9 skill 판정기 지목" || nope "T9" "MERGE_CONFIRMED_BY_GH 자기세팅 잔존"

finish
