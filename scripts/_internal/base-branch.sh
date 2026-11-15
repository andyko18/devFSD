#!/usr/bin/env bash
# base-branch.sh — 이 저장소의 기본 브랜치를 찾는다 (source 전용 · 20261115)
#
# 왜 필요한가: 스크립트 여러 곳이 기본 브랜치를 `main`·`master` 로만 알았다. 기본 브랜치가 develop·trunk 인 하류 저장소에서
#   ① 기본·quick 경로가 작업 브랜치를 만들지 않고 그 자리에 커밋했고 ② 기준 ref 를 못 찾아 문서만 바꾼 PR 이 막혔고
#   ③ 변경 파일 기반 위험 재판정이 비었다. 한 곳에서 같은 순서로 찾는다:
#     origin/HEAD 가 가리키는 브랜치(원격의 기본 브랜치) → main → master
#   origin/HEAD 가 없는 저장소(clone 이 아니라 `git remote add` 로 붙인 경우)는 `git remote set-head origin -a` 로 만든다.
#
#   specops_default_branch [<dir>]   기본 브랜치 **이름**(develop·main…) · 모르면 rc 1
#   specops_base_candidates [<dir>]  기준 ref 후보를 한 줄에 하나씩(로컬이 먼저) — 존재 여부는 호출자가 확인한다
#   specops_on_default_branch [<dir>] 지금 HEAD 가 기본 브랜치 위거나 분리(detached) 상태면 rc 0 — "여기서 작업 브랜치를 새로 따야 하는가"

specops_default_branch() {
  local d=${1:-} h b
  h=$(git ${d:+-C "$d"} symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null) || h=""
  h=${h#origin/}
  [ -n "$h" ] && { printf '%s' "$h"; return 0; }
  for b in main master; do
    git ${d:+-C "$d"} show-ref --verify --quiet "refs/heads/$b" 2>/dev/null && { printf '%s' "$b"; return 0; }
  done
  for b in main master; do
    git ${d:+-C "$d"} show-ref --verify --quiet "refs/remotes/origin/$b" 2>/dev/null && { printf '%s' "$b"; return 0; }
  done
  return 1
}

specops_base_candidates() {
  local d=${1:-} h
  h=$(git ${d:+-C "$d"} symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null) || h=""
  h=${h#origin/}
  case "$h" in ''|main|master) ;; *) printf '%s\n%s\n' "$h" "origin/$h" ;; esac
  printf 'main\nmaster\norigin/main\norigin/master\n'
}

specops_on_default_branch() {
  local d=${1:-} cur def
  cur=$(git ${d:+-C "$d"} symbolic-ref --short -q HEAD 2>/dev/null) || cur=""
  [ -n "$cur" ] || return 0
  case "$cur" in main|master) return 0 ;; esac
  def=$(specops_default_branch "$d") || return 1
  [ "$cur" = "$def" ]
}
