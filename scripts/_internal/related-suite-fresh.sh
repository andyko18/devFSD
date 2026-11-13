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
  # 지문 계산(git add -A)은 읽을 수 없는 untracked 파일이 있으면 HEAD 지문으로 퇴행한다 — 비교 전에 막는다
  unreadable=$( cd "$ROOT" && git ls-files -o --exclude-standard -z 2>/dev/null \
    | while IFS= read -r -d '' _f; do [ -r "$_f" ] || { printf x; break; }; done )
  [ -z "$unreadable" ] || _stale "읽을 수 없는 untracked 파일 — 지문 신뢰 불가"
  [ -f "$VS_LIB" ] || _stale "verification-state.sh 부재"
  # shellcheck source=/dev/null
  now=$( { cd "$ROOT" && . "$VS_LIB" && vs::nondoc_fingerprint; } 2>/dev/null ) || now=""
  [ -n "$now" ] && [ "$now" != "NO_GIT" ] && [ "$now" != "UNHASHABLE" ] || _stale "현재 지문 산출 불가"
  [ "$rec" = "$now" ] || _stale "트리 변경 — 지문 불일치"
fi

base=""
for _b in refs/remotes/origin/main refs/remotes/origin/master; do
  if git -C "$ROOT" show-ref --verify --quiet "$_b" 2>/dev/null; then base="$_b"; break; fi
done
[ -n "$base" ] || _stale "origin 의 기본 브랜치를 모름"
mb=$(git -C "$ROOT" merge-base "$base" HEAD 2>/dev/null) && [ -n "$mb" ] || _stale "기본 브랜치와 공통 조상 없음"

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
