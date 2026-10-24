#!/usr/bin/env bash
# full-suite-fresh.sh — 직전 전체 스위트 통과 마커가 현재 비문서 트리와 같은지 판정 (read-only)
#   FID 20261005-dedupe-test-runs
#
# Usage: full-suite-fresh.sh [--release]   (cwd = 대상 repo 안)
#   --release: 발행 판정 — 추적 파일이 커밋 그대로일 때 HEAD 트리 해시와 같은 통과 기록(마커 둘째 줄 `tree:<해시>`)을
#     같은 저장소의 어느 worktree(자기 포함)에서든 찾는다. 문서까지 포함하고 추적하지 않는 파일은 보지 않는다
#     (소비자: release.sh pre-flight · 20261024-speed-release-fresh-task-record). 옵션 없는 판정은 그대로다.
# Exit:  0 FRESH — stdout 1줄 `full-suite FRESH (fp=지문 앞 12자)` · --release 는 `full-suite FRESH (tree=앞 12자, worktree=<경로>)`
#        1 STALE — stdout 1줄 `full-suite STALE (사유)`
#
# 소비자: .githooks/pre-push(push 전 스위트 skip) · verifying-evidence-ko(verify 의 전체 스위트 생략).
# 판정 계약은 pre-push 의 종전 인라인 판정을 그대로 옮긴 것이다 — **생략 방향 오판 경로가 없어야 한다**:
#   마커 부재·읽기 실패·빈 첫 줄·지문 NO_GIT·지문 UNHASHABLE(읽을 수 없는 파일)·지문 불일치·SPECOPS_FORCE_FULL(값 무관, 비어있지 않음)·
#   verification-state.sh 부재는 전부 STALE(=재실행)이다. 판정이 애매하면 STALE 이다.
# 마커는 run-all.sh 가 전체 PASS 시 **스위트 실행 전** 비문서 지문으로 기록한다(run-all.sh 의 _FSP_* 주석).
set -u

_stale() { printf 'full-suite STALE (%s)\n' "$1"; exit 1; }

MODE=nondoc
case "${1:-}" in
  --release) MODE=release ;;
  "") ;;
  *) _stale "알 수 없는 인자: $1" ;;
esac

[ -z "${SPECOPS_FORCE_FULL:-}" ] || _stale "SPECOPS_FORCE_FULL 지정"

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || _stale "경로 해석 실패"
VS_LIB="$HERE/verification-state.sh"
[ -f "$VS_LIB" ] || _stale "verification-state.sh 부재"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || _stale "git repo 아님"
MARKER="$ROOT/${SPECOPS_ROOT:-.specops}/.full-suite-pass"

if [ "$MODE" = release ]; then
  # 발행되는 것은 커밋 트리다 — 추적 파일이 커밋과 다르면 그 트리를 판정할 수 없다
  [ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ] || _stale "추적 파일 변경 — 커밋 트리 판정 불가"
  head_tree=$(git -C "$ROOT" rev-parse -q --verify 'HEAD^{tree}' 2>/dev/null) || _stale "HEAD 트리 없음"
  [ -n "$head_tree" ] || _stale "HEAD 트리 없음"
  while IFS= read -r _wt; do
    [ -n "$_wt" ] || continue
    _m="$_wt/${SPECOPS_ROOT:-.specops}/.full-suite-pass"
    [ -f "$_m" ] || continue
    [ "$(sed -n 2p "$_m" 2>/dev/null)" = "tree:$head_tree" ] || continue
    printf 'full-suite FRESH (tree=%s, worktree=%s)\n' "$(printf '%s' "$head_tree" | cut -c1-12)" "$_wt"
    exit 0
  done <<< "$(git -C "$ROOT" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')"
  _stale "같은 커밋 트리의 통과 기록 없음"
fi
[ -f "$MARKER" ] || _stale "마커 부재"

rec=$(head -1 "$MARKER" 2>/dev/null || printf '')
[ -n "$rec" ] || _stale "마커가 비었거나 읽을 수 없음"

# 지문 계산(git add -A)은 읽을 수 없는 untracked 파일이 있으면 통째로 실패하고 HEAD 지문으로 퇴행한다
# (verification-state.sh 의 기존 한계) — 생략 방향 오판이라 헬퍼가 따로 STALE 로 막는다.
unreadable=$( cd "$ROOT" && git ls-files -o --exclude-standard -z 2>/dev/null \
  | while IFS= read -r -d '' _f; do [ -r "$_f" ] || { printf x; break; }; done )
[ -z "$unreadable" ] || _stale "읽을 수 없는 untracked 파일 — 지문 신뢰 불가"

# shellcheck source=/dev/null
now=$( { cd "$ROOT" && . "$VS_LIB" && vs::nondoc_fingerprint; } 2>/dev/null ) || now=""
[ -n "$now" ] && [ "$now" != "NO_GIT" ] && [ "$now" != "UNHASHABLE" ] || _stale "현재 지문 산출 불가"
[ "$rec" = "$now" ] || _stale "트리 변경 — 지문 불일치"

printf 'full-suite FRESH (fp=%s)\n' "$(printf '%s' "$now" | cut -c1-12)"
exit 0
