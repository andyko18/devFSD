#!/usr/bin/env bash
# full-suite-fresh.sh — 직전 전체 스위트 통과 마커가 현재 비문서 트리와 같은지 판정 (read-only)
#   FID 20261005-dedupe-test-runs
#
# Usage: full-suite-fresh.sh [--any-worktree]   (cwd = 대상 repo 안)
#   --any-worktree: 자기 마커가 STALE 이면 같은 저장소의 다른 worktree 마커 중 첫 줄이 지금 지문과 같은 것을 찾는다
#     (지문은 내용 기반 — 같은 비문서 내용이면 worktree 가 달라도 같다 · 소비자: release.sh pre-flight · 20261024-speed-release-fresh-task-record)
# Exit:  0 FRESH — stdout 1줄 `full-suite FRESH (fp=지문 앞 12자)` (다른 worktree 마커면 `, worktree=<경로>` 덧붙음)
#        1 STALE — stdout 1줄 `full-suite STALE (사유)`
#
# 소비자: .githooks/pre-push(push 전 스위트 skip) · verifying-evidence-ko(verify 의 전체 스위트 생략).
# 판정 계약은 pre-push 의 종전 인라인 판정을 그대로 옮긴 것이다 — **생략 방향 오판 경로가 없어야 한다**:
#   마커 부재·읽기 실패·빈 첫 줄·지문 NO_GIT·지문 UNHASHABLE(읽을 수 없는 파일)·지문 불일치·SPECOPS_FORCE_FULL(값 무관, 비어있지 않음)·
#   verification-state.sh 부재는 전부 STALE(=재실행)이다. 판정이 애매하면 STALE 이다.
# 마커는 run-all.sh 가 전체 PASS 시 **스위트 실행 전** 비문서 지문으로 기록한다(run-all.sh 의 _FSP_* 주석).
set -u

_stale() { printf 'full-suite STALE (%s)\n' "$1"; exit 1; }

ANY=0
case "${1:-}" in
  --any-worktree) ANY=1 ;;
  "") ;;
  *) _stale "알 수 없는 인자: $1" ;;
esac

[ -z "${SPECOPS_FORCE_FULL:-}" ] || _stale "SPECOPS_FORCE_FULL 지정"

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || _stale "경로 해석 실패"
VS_LIB="$HERE/verification-state.sh"
[ -f "$VS_LIB" ] || _stale "verification-state.sh 부재"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || _stale "git repo 아님"
MARKER="$ROOT/${SPECOPS_ROOT:-.specops}/.full-suite-pass"
own=""; rec=""
if [ ! -f "$MARKER" ]; then
  own="마커 부재"
else
  rec=$(head -1 "$MARKER" 2>/dev/null || printf '')
  [ -n "$rec" ] || own="마커가 비었거나 읽을 수 없음"
fi
# 옵션이 없으면 종전 순서 그대로 여기서 끝난다
[ "$ANY" = 1 ] || [ -z "$own" ] || _stale "$own"

# 지문 계산(git add -A)은 읽을 수 없는 untracked 파일이 있으면 통째로 실패하고 HEAD 지문으로 퇴행한다
# (verification-state.sh 의 기존 한계) — 생략 방향 오판이라 헬퍼가 따로 STALE 로 막는다.
unreadable=$( cd "$ROOT" && git ls-files -o --exclude-standard -z 2>/dev/null \
  | while IFS= read -r -d '' _f; do [ -r "$_f" ] || { printf x; break; }; done )
[ -z "$unreadable" ] || _stale "읽을 수 없는 untracked 파일 — 지문 신뢰 불가"

# shellcheck source=/dev/null
now=$( { cd "$ROOT" && . "$VS_LIB" && vs::nondoc_fingerprint; } 2>/dev/null ) || now=""
[ -n "$now" ] && [ "$now" != "NO_GIT" ] && [ "$now" != "UNHASHABLE" ] || _stale "현재 지문 산출 불가"
_fp12=$(printf '%s' "$now" | cut -c1-12)
if [ -z "$own" ] && [ "$rec" = "$now" ]; then
  printf 'full-suite FRESH (fp=%s)\n' "$_fp12"
  exit 0
fi
[ "$ANY" = 1 ] || _stale "트리 변경 — 지문 불일치"

# 다른 worktree 의 마커 — 첫 줄이 지금 지문과 **완전히 같을 때만** 인정한다
_self=$(cd "$ROOT" && pwd -P)
while IFS= read -r _wt; do
  [ -n "$_wt" ] || continue
  [ "$(cd "$_wt" 2>/dev/null && pwd -P)" != "$_self" ] || continue
  _m="$_wt/${SPECOPS_ROOT:-.specops}/.full-suite-pass"
  [ -f "$_m" ] || continue
  [ "$(head -1 "$_m" 2>/dev/null || printf '')" = "$now" ] || continue
  printf 'full-suite FRESH (fp=%s, worktree=%s)\n' "$_fp12" "$_wt"
  exit 0
done <<< "$(git -C "$ROOT" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')"
_stale "${own:-트리 변경 — 지문 불일치} · 다른 worktree 에도 같은 지문 마커 없음"
