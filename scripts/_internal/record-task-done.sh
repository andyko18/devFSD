#!/usr/bin/env bash
# 태스크 기록 1회 — receipt · dispatch-log 구현 행 · session-progress 줄을 한 번에 남긴다 (20261024-speed-release-fresh-task-record).
# Usage: record-task-done.sh <FID> <task-id> [요약]
# Exit:  receipt 의 rc 그대로(0 이 아니면 dispatch-log·session-progress 는 쓰지 않는다) · 0 = TASK-DONE 1줄.
#   진행 기록이 남지 않으면 경고 1줄 뒤 rc 0 — receipt·dispatch-log 는 이미 남았다.
set -u

FID="${1:?usage: $0 <FID> <task-id> [요약]}"
TASK="${2:?usage: $0 <FID> <task-id> [요약]}"
MEMO="${3:-}"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

bash "$HERE/record-task-receipt.sh" "$FID" "$TASK" >/dev/null || exit $?

# receipt 와 같은 .specops 에 쓴다 — worktree 셸이면 메인 worktree 로 옮긴다(SPECOPS_ROOT 를 준 호출은 그대로)
# shellcheck source=/dev/null
. "$HERE/specops-root.sh" 2>/dev/null && { specops_root_enter "$FID" 2>/dev/null || true; }
SPECOPS="${SPECOPS_ROOT:-.specops}"
LOG="$SPECOPS/$FID/dispatch-log.md"
if [ ! -f "$LOG" ]; then
  cp "$HERE/../../templates/dispatch-log.md" "$LOG" 2>/dev/null || : > "$LOG"
fi
printf '| A | %s | Phase-A | implementer-ko | IMPL_DONE | %s receipt |\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TASK" >> "$LOG" || {
  echo "record-task-done: dispatch-log 기록 실패: $LOG" >&2; exit 1; }

_note="$TASK 완료"; [ -z "$MEMO" ] || _note="$_note — $MEMO"
# append 는 쓰기에 실패해도 rc 0 을 낼 수 있다(mv 실패 뒤에도 성공 문구) — 이 FID 섹션의 그 줄 개수가 늘었는지 파일로 확인한다
#   (파일 전체 grep 은 다른 FID 섹션·같은 태스크의 옛 줄에 속는다)
#   섹션 판정은 session-progress-append.sh 와 같은 규칙 — `## FID` 정확 일치 또는 `## FID ` 로 시작(`## FID · 기능명` 접미 헤더).
#   FID·문구는 ENVIRON 으로 넘긴다(`awk -v` 는 백슬래시를 해석한다).
_cnt() { H="## $FID" N="/implement 진행 ($_note)" awk '/^## /{f=($0==ENVIRON["H"] || index($0, ENVIRON["H"] " ")==1)} f && index($0,ENVIRON["N"]){c++} END{print c+0}' \
  "$SPECOPS/session-progress.md" 2>/dev/null || echo 0; }
_before=$(_cnt)
bash "$HERE/../session-progress-append.sh" "$FID" /implement 진행 "$_note" >/dev/null 2>&1
[ "$(_cnt)" -gt "$_before" ] \
  || echo "record-task-done: 경고 — session-progress 기록 실패 (receipt·dispatch-log 는 남았다)" >&2

echo "TASK-DONE: $FID/$TASK"
