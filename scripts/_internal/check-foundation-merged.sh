#!/usr/bin/env bash
# check-foundation-merged.sh — /start-all Phase 0 foundation 브랜치 머지 게이트 (20260812)
# Usage: check-foundation-merged.sh
# Exit: 0 = PASS | SKIP | WARN(비필수·미머지)
#       1 = FAIL (필수 KIND + 미머지 feat/<foundation-FID>)
#
# 왜: present 는 manifest 문서만 본다. foundation 은 feat/<FID> + PR, start-all 은
#   feat/batch-* 이중 트랙이라 미머지 상태로 batch 가 들어가면 공통 코드가 base 에 없다.
# 판정(A): §유형=foundation FID → feat/<FID> 가 base 조상 또는 gh MERGED.
#   브랜치 부재 = 머지 후 삭제로 간주(OK). FID 0건 = SKIP.
# KIND: foundation-kind.sh (present 와 공유).
# gh 주입: SPECOPS_BRANCH_GH_STATE (check-branch-deletable 과 동일).
set -u

SPECOPS="${SPECOPS_ROOT:-.specops}"
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
. "$PLUGIN/scripts/_internal/foundation-kind.sh"

_resolve_base() {
  # 기본 브랜치가 develop·trunk 인 저장소 — origin/HEAD 가 가리키는 브랜치가 먼저다(20261115 — base-branch.sh).
  local _d
  # shellcheck source=/dev/null
  . "$PLUGIN/scripts/_internal/base-branch.sh" 2>/dev/null && _d=$(specops_default_branch) \
    && git show-ref --verify --quiet "refs/heads/$_d" 2>/dev/null && { echo "$_d"; return 0; }
  if git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    echo main
    return 0
  fi
  if git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
    echo master
    return 0
  fi
  return 1
}

_list_foundation_fids() {
  local d spec base
  [ -d "$SPECOPS" ] || return 0
  for d in "$SPECOPS"/*/; do
    [ -d "$d" ] || continue
    base=$(basename "$d")
    case "$base" in
      memory|batch-*|archive|audit|.specops) continue ;;
    esac
    printf '%s' "$base" | grep -qE '^[.]' && continue
    spec="${d}spec.md"
    [ -f "$spec" ] || continue
    grep -qE '^\*\*§유형\*\*:[[:space:]]*foundation([[:space:]]|$)' "$spec" 2>/dev/null || continue
    printf '%s\n' "$base"
  done
}

_branch_merged_into() {
  # $1=branch $2=base → 0=머지됨
  local branch="$1" base="$2" gh_state
  if git merge-base --is-ancestor "$branch" "$base" 2>/dev/null; then
    return 0
  fi
  gh_state="${SPECOPS_BRANCH_GH_STATE-}"
  if [ -z "${gh_state}" ] && [ "${SPECOPS_BRANCH_GH_STATE+set}" != "set" ]; then
    if command -v gh >/dev/null 2>&1; then
      gh_state=$(gh pr list --head "$branch" --state all --limit 1 --json state \
        --jq '.[0].state // empty' 2>/dev/null || echo "")
    fi
  fi
  [ "$gh_state" = "MERGED" ] && return 0
  return 1
}

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "FOUNDATION-MERGED: SKIP (git repo 아님)"
  exit 0
}

BASE=$(_resolve_base) || {
  echo "FOUNDATION-MERGED: SKIP (base 브랜치 없음 — main/master)"
  exit 0
}

fids=$(_list_foundation_fids)
if [ -z "$fids" ]; then
  echo "FOUNDATION-MERGED: SKIP (foundation FID 없음)"
  exit 0
fi

unmerged=""
while IFS= read -r fid; do
  [ -n "$fid" ] || continue
  br="feat/$fid"
  git show-ref --verify --quiet "refs/heads/$br" 2>/dev/null || continue
  if _branch_merged_into "$br" "$BASE"; then
    continue
  fi
  if [ -z "$unmerged" ]; then
    unmerged="$br"
  else
    unmerged="$unmerged $br"
  fi
done <<EOF
$fids
EOF

required=0
foundation_kind_is_required && required=1

if [ -z "$unmerged" ]; then
  echo "FOUNDATION-MERGED: PASS"
  exit 0
fi

if [ "$required" -eq 1 ]; then
  echo "FOUNDATION-MERGED: FAIL — 미머지: $unmerged"
  echo "  foundation 브랜치를 $BASE 에 머지(또는 PR MERGED)한 뒤 /start-all 을 재실행하세요."
  echo "  (manifest 만 있고 공통 코드가 base 에 없으면 batch 가 빈 재사용 선언으로 갑니다.)"
  exit 1
fi

echo "FOUNDATION-MERGED: WARN — 미머지: $unmerged (비필수). $BASE 머지 권장"
exit 0
