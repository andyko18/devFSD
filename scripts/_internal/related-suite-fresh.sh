#!/usr/bin/env bash
# related-suite-fresh.sh — 관련 스위트 통과 기록이 지금 트리와 지금 변경이 닿는 스위트 전부를 덮는지 판정 (read-only)
#   FID 20261113-commit-gate-related-evidence
#
# Usage: related-suite-fresh.sh [--need]   (cwd = 대상 repo 안)
#   (없음)  판정 — 통과 기록(.specops/.related-suite-pass: 1행 비문서 지문, 이후 통과한 스위트 경로)이
#           지금 지문과 같고 지금 변경이 닿는 스위트를 전부 덮으면 FRESH
#   --need  지금 변경이 닿는 스위트 목록을 출력(판정과 같은 변경 파일 집합)
# Exit:  0 FRESH(stdout `related-suite FRESH (fp=12자, suites=N)`) / --need 는 목록
#        1 STALE(stdout `related-suite STALE (사유)`) / --need 는 stderr `related-suite: 사유`
# 계약: 덮었을 때만 FRESH. 판정할 수 없으면 전부 STALE — 증거로 치는 방향의 오판 경로가 없다.
# git 환경변수는 지우지 않는다(훅이 worktree 대상으로 내보낸 GIT_DIR·GIT_WORK_TREE 를 따른다).
set -u
export GIT_OPTIONAL_LOCKS=0   # 읽기 전용 — git diff 가 인덱스를 고쳐 쓰지 않게

MODE=judge
case "${1:-}" in
  --need) MODE=need ;;
  "") ;;
  *) printf 'related-suite STALE (알 수 없는 인자: %s)\n' "$1"; exit 1 ;;
esac

_stale() {
  if [ "$MODE" = need ]; then printf 'related-suite: %s\n' "$1" >&2; else printf 'related-suite STALE (%s)\n' "$1"; fi
  exit 1
}

[ -z "${SPECOPS_FORCE_FULL:-}" ] || _stale "SPECOPS_FORCE_FULL 지정"

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || _stale "경로 해석 실패"
VS_LIB="$HERE/verification-state.sh"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || _stale "git repo 아님"
RR="$ROOT/scripts/tests/run-related.sh"
[ -f "$RR" ] || _stale "run-related.sh 부재"
MARKER="$ROOT/${SPECOPS_ROOT:-.specops}/.related-suite-pass"
ERR=$(mktemp) || _stale "임시 파일 생성 실패"
trap 'rm -f "$ERR"' EXIT

if [ "$MODE" = judge ]; then
  [ -f "$MARKER" ] || _stale "통과 기록 부재"
  rec=$(head -1 "$MARKER" 2>/dev/null || printf '')
  [ -n "$rec" ] || _stale "통과 기록이 비었거나 읽을 수 없음"
  [ -f "$VS_LIB" ] || _stale "verification-state.sh 부재"
  # 지문 신선도(읽을 수 없는 untracked → 지문 산출 → 비교)는 vs::marker_fresh 한 곳이 판정한다 — full-suite-fresh.sh 와 공유.
  # shellcheck source=/dev/null
  if now=$( { cd "$ROOT" && . "$VS_LIB" && vs::marker_fresh "$MARKER"; } 2>/dev/null ); then :; else
    _stale "${now:-현재 지문 산출 불가}"
  fi
fi

base=""
for _b in refs/remotes/origin/main refs/remotes/origin/master; do
  if git -C "$ROOT" show-ref --verify --quiet "$_b" 2>/dev/null; then base="$_b"; break; fi
done
[ -n "$base" ] || _stale "origin 의 기본 브랜치를 모름"
mb=$(git -C "$ROOT" merge-base "$base" HEAD 2>/dev/null) && [ -n "$mb" ] || _stale "기본 브랜치와 공통 조상 없음"
# 병합 진행 중(MERGE_HEAD)이면 기준을 병합이 들여오는 쪽으로 옮긴다 (20261114) — 병합 커밋을 만들기 전에는 HEAD 가 병합 전이라 공통 조상이 옛 것이고,
#   작업 트리에 들어온 main 쪽 변경이 전부 "내 변경"으로 세어져 닿는 스위트가 부풀었다(137개 · 상한 80 → 증거 무효).
#   병합 커밋 뒤에는 공통 조상이 MERGE_HEAD 와 같아지므로, 커밋 전후의 목록이 같아진다.
#   MERGE_HEAD 가 기본 브랜치의 조상(또는 같음)일 때만 옮긴다 — 그렇지 않으면(다른 브랜치를 병합 중) 종전 판정 그대로다.
if _mh=$(git -C "$ROOT" rev-parse -q --verify MERGE_HEAD 2>/dev/null) && [ -n "$_mh" ] \
   && git -C "$ROOT" merge-base --is-ancestor "$_mh" "$base" 2>/dev/null; then
  mb="$_mh"
fi

d1=$(git -C "$ROOT" -c core.quotepath=false diff --no-renames --name-only "$mb" 2>/dev/null) || _stale "변경 파일 목록 실패"
d2=$(git -C "$ROOT" -c core.quotepath=false ls-files -o --exclude-standard 2>/dev/null) || _stale "변경 파일 목록 실패"
files=$(printf '%s\n%s\n' "$d1" "$d2" | grep -v '^$' | sort -u || true)
[ -n "$files" ] || _stale "변경 파일 없음"

if list=$( cd "$ROOT" && printf '%s\n' "$files" | bash "$RR" --list 2>"$ERR" ); then :; else
  _stale "관련 스위트를 고를 수 없음($(head -1 "$ERR" 2>/dev/null))"
fi
[ -n "$list" ] || _stale "관련 스위트 목록이 비었음"

if [ "$MODE" = need ]; then printf '%s\n' "$list"; exit 0; fi

miss=$(printf '%s\n' "$list" | grep -Fxv -f <(sed 1d "$MARKER") || true)
if [ -n "$miss" ]; then
  n=$(printf '%s\n' "$miss" | wc -l | tr -d ' ')
  shown=$(printf '%s\n' "$miss" | head -3 | paste -sd '|' - | sed 's/|/, /g')
  _stale "스위트 누락 ${n}개 — $shown"
fi

printf 'related-suite FRESH (fp=%s, suites=%s)\n' "$(printf '%s' "$now" | cut -c1-12)" "$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
exit 0
