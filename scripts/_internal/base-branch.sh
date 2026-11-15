#!/usr/bin/env bash
# base-branch.sh — 이 저장소의 기본 브랜치를 찾는다 (source 전용 · 20261115)
#
# 왜 필요한가: 스크립트 여러 곳이 기본 브랜치를 `main`·`master` 로만 알았다. 기본 브랜치가 develop·trunk 인 하류 저장소에서
#   ① 기본·quick 경로가 작업 브랜치를 만들지 않고 그 자리에 커밋했고 ② 기준 ref 를 못 찾아 문서만 바꾼 PR 이 막혔고
#   ③ 변경 파일 기반 위험 재판정이 비었다. 한 곳에서 같은 순서로 찾는다:
#     origin/HEAD 가 가리키는 브랜치(원격의 기본 브랜치) → main → master → 로컬 develop·dev·trunk·development
#   origin/HEAD 가 없는 저장소(clone 이 아니라 `git remote add` 로 붙인 경우)는 `git remote set-head origin -a` 로 만든다.
#
#   specops_default_branch [<dir>]   기본 브랜치 **이름**(develop·main…) · 모르면 rc 1
#   specops_base_candidates [<dir>]  기준 ref 후보를 한 줄에 하나씩(로컬이 먼저) — 존재 여부는 호출자가 확인한다
#   specops_prepare_branch_base [<dir>] 작업 브랜치를 따기 전 1회 — origin/HEAD 보정 또는 '기본 브랜치 모름' 알림(`BRANCH-NOTE:` 한 줄)
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
  # origin/HEAD 도 main·master 도 없는 저장소(`git init` + `git remote add` — clone 이 아니라 origin/HEAD 가 없다 · 20261115 실주행):
  #   흔한 기본 브랜치 이름의 로컬 브랜치가 있으면 그것으로 본다. 이름 목록 밖이면 모른다(rc 1) — 유일한 로컬 브랜치라는
  #   이유로는 정하지 않는다(작업 브랜치 하나만 있는 저장소를 기본 브랜치로 오인한다).
  for b in develop dev trunk development; do
    git ${d:+-C "$d"} show-ref --verify --quiet "refs/heads/$b" 2>/dev/null && { printf '%s' "$b"; return 0; }
  done
  return 1
}

# 작업 브랜치를 따기 전에 한 번 부른다 (20261115 실주행) — 알림은 stdout 한 줄(`BRANCH-NOTE:`), 언제나 rc 0.
#   ① origin/HEAD 가 없는데 기본 브랜치를 이름으로 알아냈고 origin/<그 브랜치> 추적 ref 가 있으면 origin/HEAD 를 그리로 맞춘다
#      (`git remote set-head origin <브랜치>` — 네트워크 없음 · clone 이 하는 일과 같다). 기준 ref 를 origin/HEAD → main → master 로
#      찾는 뒤 단계(리뷰 BASE · 게이트의 변경 파일 조회 · 훅의 문서 면제)가 그 뒤로 전부 살아난다.
#   ② 기본 브랜치를 끝내 모르고 지금 브랜치 위에 있으면 그 사실을 알린다 — 종전엔 말없이 그 브랜치에 커밋했다.
specops_prepare_branch_base() {
  local d=${1:-} cur def
  cur=$(git ${d:+-C "$d"} symbolic-ref --short -q HEAD 2>/dev/null) || cur=""
  if def=$(specops_default_branch "$d"); then
    if ! git ${d:+-C "$d"} symbolic-ref -q refs/remotes/origin/HEAD >/dev/null 2>&1 \
       && git ${d:+-C "$d"} show-ref --verify --quiet "refs/remotes/origin/$def" 2>/dev/null \
       && git ${d:+-C "$d"} remote set-head origin "$def" >/dev/null 2>&1; then
      echo "BRANCH-NOTE: origin/HEAD 가 없어 기본 브랜치 $def 로 맞췄다 (git remote set-head origin $def)"
    fi
  elif [ -n "$cur" ]; then
    echo "BRANCH-NOTE: 기본 브랜치를 알 수 없다(origin/HEAD·main·master·develop 없음) — 지금 브랜치 $cur 에서 그대로 진행한다. $cur 가 기본 브랜치면 작업 브랜치를 먼저 딴다(git remote set-head origin -a 로 origin/HEAD 를 만들면 다음부터 자동)"
  fi
  return 0
}

specops_base_candidates() {
  local d=${1:-} h
  h=$(git ${d:+-C "$d"} symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null) || h=""
  h=${h#origin/}
  [ -n "$h" ] || h=$(specops_default_branch "$d") || h=""
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
