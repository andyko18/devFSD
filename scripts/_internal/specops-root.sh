#!/usr/bin/env bash
# library-only
# 기록 스크립트의 .specops 위치 (20261016-hook-worktree-target).
#
# 왜: 커밋·PR 훅은 프로젝트 폴더의 .specops 를 읽는다. 그런데 FID 를 .worktrees/<FID> 에서 구현하면
#   기록 스크립트가 현재 폴더 기준 .specops 를 찾다 실패하거나 worktree 안에 새로 만들고, 그 기록은 훅이
#   보지 않으며 worktree 를 지우면 사라진다(Argus 실기록 — 사본 rsync 로 버텼다).
# 무엇을: 현재 폴더에 .specops 가 없고 linked worktree 이며 메인 worktree 에 .specops 디렉터리가 있을 때만
#   원래 폴더를 기억하고(_SR_CWD) git 조회가 이 worktree 를 보도록 GIT_DIR·GIT_WORK_TREE 를 export 한 뒤
#   메인 worktree 로 이동한다 — 이후 상대경로 .specops 가 메인 기록이 된다. 테스트 명령은 _sr_leave 로
#   원래 폴더·git env 없음 상태에서 돈다(서브셸 안에서만 부른다).
#   .specops 가 있어도(하류 기본 구조 — memory·session-progress.md·<FID>/intent.md 를 git 추적) 넘긴 FID 의 기록이 이 worktree 에 없고 메인에 있으면 이동한다(20261016-specops-root-tracked-dir).
# 왜 현재 폴더 .specops 를 먼저 보는가: 이 repo 처럼 linked worktree 자체가 프로젝트이고 자기 .specops 를
#   쓰는 형태가 있다 — 메인 worktree 에도 다른 .specops 가 있어 메인 우선이면 남의 기록에 쓴다(실측).
# 부르는 쪽 약속: 이동하면 상대경로 $0 의 뜻이 바뀐다 — 자기 경로는 이 함수를 부르기 **전에** 절대경로로 잡는다.
# 이 worktree 에도 .specops 가 있을 때(하류 기본 구조 — memory·session-progress.md·<FID>/intent.md 를 git 추적) 이동해도 되는가.
#   $1=FID $2=worktree 최상위 $3=메인 worktree. 그 FID 의 기록이 이 worktree 에 없고(git 이 추적하지 않는 파일 0건 —
#   체크아웃된 추적 파일은 기록이 아니다) 메인에 있을 때만 rc 0. FID 가 없거나 형식이 틀리거나 git 조회가 실패하면 rc 1(종전).
#   자기 기록이 있는 worktree(이 repo — .specops 전체 ignore)는 추적하지 않는 파일이 있어 rc 1 이다.
#   한계: worktree 의 .specops/<FID> 에 누가 파일을 하나라도 쓰면(rsync 사본·직접 쓴 리포트) 자기 기록으로 보아 이동하지 않는다.
_sr_fid_only_in_main() {
  local fid=$1 wt=$2 main=$3 untracked
  printf '%s' "$fid" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || return 1
  [ -d "$main/.specops/$fid" ] && [ ! -L "$main/.specops/$fid" ] || return 1
  [ ! -L "$wt/.specops/$fid" ] || return 1
  # --exclude-standard 를 붙이지 않는다 — 이 repo 처럼 .specops 를 통째로 ignore 하면 자기 기록이 목록에서 빠져 메인으로 샌다
  untracked=$(git -C "$wt" ls-files --others -- ".specops/$fid" 2>/dev/null) || return 1
  # macOS Finder 가 만드는 .DS_Store 는 기록이 아니다 — 하나 때문에 종전 동작(추적 사본에 쓰기)으로 돌아가지 않게 뺀다
  untracked=$(printf '%s\n' "$untracked" | grep -Ev '^$|(^|/)\.DS_Store$')
  [ $? -le 1 ] || return 1   # grep 오류(rc 2)는 판정 불가 — 이동하지 않는다
  [ -z "$untracked" ]
}

specops_root_enter() {
  local gd cd main wt here=0
  [ -z "${SPECOPS_ROOT:-}" ] || return 1                                # 부르는 쪽이 위치를 정했다
  [ ! -L .specops ] || return 1                                         # 링크 .specops 는 종전대로 이동하지 않는다
  [ -e .specops ] && here=1
  [ -z "${GIT_DIR:-}${GIT_WORK_TREE:-}" ] || return 1
  wt=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ ! -L "$wt/.specops" ] || return 1
  [ -e "$wt/.specops" ] && here=1                                       # 하위 폴더에서 불러도 worktree 최상위를 본다
  gd=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  cd=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  cd=$(cd "$cd" 2>/dev/null && pwd -P) || return 1
  [ "$(cd "$gd" 2>/dev/null && pwd -P)" != "$cd" ] || return 1          # 메인 worktree 자신
  main=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
  [ -n "$main" ] && [ -d "$main/.specops" ] && [ ! -L "$main/.specops" ] || return 1
  [ "$here" = 0 ] || _sr_fid_only_in_main "${1:-}" "$wt" "$main" || return 1
  _SR_CWD=$PWD
  cd "$main" 2>/dev/null || { unset _SR_CWD; return 1; }
  GIT_DIR=$gd
  GIT_WORK_TREE=$wt
  export GIT_DIR GIT_WORK_TREE
  return 0
}

_sr_leave() {
  [ -n "${_SR_CWD:-}" ] || return 0
  cd "$_SR_CWD" || return 1
  unset GIT_DIR GIT_WORK_TREE
}
