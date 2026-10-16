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
# 왜 현재 폴더 .specops 를 먼저 보는가: 이 repo 처럼 linked worktree 자체가 프로젝트이고 자기 .specops 를
#   쓰는 형태가 있다 — 메인 worktree 에도 다른 .specops 가 있어 메인 우선이면 남의 기록에 쓴다(실측).
# 부르는 쪽 약속: 이동하면 상대경로 $0 의 뜻이 바뀐다 — 자기 경로는 이 함수를 부르기 **전에** 절대경로로 잡는다.
specops_root_enter() {
  local gd cd main wt
  [ -z "${SPECOPS_ROOT:-}" ] || return 1                                # 부르는 쪽이 위치를 정했다
  [ ! -e .specops ] && [ ! -L .specops ] || return 1
  [ -z "${GIT_DIR:-}${GIT_WORK_TREE:-}" ] || return 1
  gd=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  cd=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  cd=$(cd "$cd" 2>/dev/null && pwd -P) || return 1
  [ "$(cd "$gd" 2>/dev/null && pwd -P)" != "$cd" ] || return 1          # 메인 worktree 자신
  main=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
  [ -n "$main" ] && [ -d "$main/.specops" ] && [ ! -L "$main/.specops" ] || return 1
  wt=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
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
