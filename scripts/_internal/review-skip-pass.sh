#!/usr/bin/env bash
# review-skip-pass.sh — end-loaded 로 Phase B/C 를 끝낸 FID 의 requesting·receiving-code-review 기계적 통과
#   FID 20261005-skill-progressive-disclosure
#
# Usage: review-skip-pass.sh <FID>        (cwd = 대상 repo 루트 또는 그 linked worktree — 자기 .specops 가 없는 worktree 면 메인 worktree 기록으로 판정)
# Exit:  0 통과 — review-skip.md 와 session-progress 두 줄을 남겼다 (stdout 1줄)
#        1 조건 불충족·판정 불가 — 검사 단계에서는 **아무것도 쓰지 않는다**, 사유 1줄을 stderr 로 낸다(종전 skill 경로가 이어받는다).
#          쓰기 단계의 부분 실패(두 번째 append 실패)만 review-skip.md 가 남을 수 있다 — skill 이 덮어쓰는 정상 경로다
#
# 왜 필요한가: end-loaded FID 에서 requesting-code-review-ko(Step 0 skip)·receiving-code-review-ko(review-skip 통과)는
#   판단 없이 같은 산출물만 남긴다. 두 skill 본문(약 16.8KB)을 매번 싣는 대신 이 스크립트가 같은 일을 한다.
# 판정은 requesting-code-review-ko Step 0 의 skip 조건과 같다: review_mode 가 end-loaded 이고, tasks.md 의
#   모든 task id 에 B/C 리포트가 있다. 리포트의 verdict·dispatch-log 의 B/C 행(skill 도 '권장' 으로만 본다)은 대조하지 않는다.
#   여기에 §batch(batch 는 종전 skill 경로)·review-request.md/review-skip.md 기존재(이어받기)를 더해 **애매하면 rc 1** 이다.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
# worktree 에서 불려도 메인 worktree 의 .specops 로 판정한다 — git 조회는 export 된 GIT_DIR·GIT_WORK_TREE 로 그 worktree (20261016-judge-scripts-worktree-root)
#   훅은 .specops 가 있는 프로젝트 폴더에서 부르므로 이동하지 않는다(셸이 다른 worktree 면 git env 도 이미 export 돼 있다). SPECOPS_ROOT 를 준 호출도 그대로다.
#   이동하면 상대경로 $0 의 뜻이 바뀐다 — 자기 경로는 그 전에 잡는다. 테스트 명령을 실행하지 않으므로 _sr_leave 는 부르지 않는다.
# shellcheck source=/dev/null
. "$HERE/specops-root.sh" 2>/dev/null && specops_root_enter "${1:-}" 2>/dev/null || true
SPECOPS="${SPECOPS_ROOT:-.specops}"
APPEND="$HERE/../session-progress-append.sh"
FID="${1:-}"

_no() { printf 'review-skip-pass: %s — 종전 skill 경로(requesting-code-review-ko)로 진행\n' "$1" >&2; exit 1; }

printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || _no "FID 인자 오류"
# session-progress-append.sh 는 cwd 의 .specops 에만 쓴다 — SPECOPS_ROOT 가 그 디렉터리가 아니면 review-skip.md 와 session-progress 가
#   갈라진 채 rc 0 이 될 수 있다. 같은 디렉터리일 때만 진행한다(운영은 SPECOPS_ROOT 미설정이라 항상 같다).
[ -d "$SPECOPS" ] && [ -d ".specops" ] && [ "$(cd "$SPECOPS" && pwd -P)" = "$(cd .specops && pwd -P)" ] \
  || _no "SPECOPS_ROOT 가 cwd 의 .specops 와 다르다"
D="$SPECOPS/$FID"
[ -d "$D" ] || _no "FID 디렉터리 부재"
TASKS="$D/tasks.md"
[ -f "$TASKS" ] || _no "tasks.md 부재"
[ -f "$D/spec.md" ] || _no "spec.md 부재"
# review_mode 는 **화이트리스트**다 — `^review_mode:` 줄이 정확히 하나이고 값이 end-loaded 일 때만 통과한다.
#   skill 은 필드 부재를 end-loaded 로 취급하지만 부재는 레거시·수기 편집 FID 의 신호일 수 있어 스크립트는 더 엄격하게 rc 1 로 보낸다
#   (decomposing-ko 가 항상 쓰므로 정상 FID 는 막히지 않는다 — 이 repo 의 .specops tasks.md 110건 실측 전부 end-loaded 한 줄).
#   인라인 주석(`review_mode: per-task   # 레거시`, templates/tasks.md 표준 형태)·따옴표는 제거 후 비교하고 중복 줄은 거부한다.
mode_lines=$(grep -cE '^review_mode:' "$TASKS" 2>/dev/null)
[ "${mode_lines:-0}" -eq 1 ] || _no "review_mode 줄이 없거나 둘 이상"
mode=$(grep -E '^review_mode:' "$TASKS" | head -1 \
  | sed -E "s/^review_mode:[[:space:]]*//; s/[[:space:]]*#.*\$//; s/^[\"']//; s/[\"'][[:space:]]*\$//; s/[[:space:]]*\$//")
[ "$mode" = "end-loaded" ] || _no "review_mode=${mode:-빈값} (end-loaded 만 통과)"
grep -qE '^\*\*§batch\*\*:' "$D/spec.md" && _no "§batch FID"
[ ! -f "$D/review-request.md" ] || _no "review-request.md 이미 존재"
[ ! -f "$D/review-skip.md" ] || _no "review-skip.md 이미 존재"

# task id 목록 — batch-state.sh 의 end-loaded skip 검증과 같은 추출이다
tids=$(grep -E '^[[:space:]]*-[[:space:]]*id:[[:space:]]*' "$TASKS" 2>/dev/null \
  | sed -E 's/^[[:space:]]*-[[:space:]]*id:[[:space:]]*//; s/[[:space:]]*$//')
[ -n "$tids" ] || _no "tasks.md 에 task id 없음"
for tid in $tids; do
  [ -f "$D/reviews/${tid}-B-report.md" ] && [ -f "$D/reviews/${tid}-C-report.md" ] \
    || _no "리뷰 리포트 누락: $tid"
done
[ -f "$APPEND" ] || _no "session-progress-append.sh 부재"

# 쓰기 — review-skip.md 먼저, 실패하면 되돌린다
printf 'end-loaded: Phase B/C already covered full FID diff\n' > "$D/review-skip.md" || _no "review-skip.md 쓰기 실패"
if ! bash "$APPEND" "$FID" /request-review 완료 "review-skip.md (end-loaded)" >/dev/null 2>&1; then
  rm -f "$D/review-skip.md"; _no "session-progress 기록 실패"
fi
bash "$APPEND" "$FID" /receive-review 완료 "review-skip 통과 (end-loaded B/C 가 전체 FID diff 를 이미 리뷰)" >/dev/null 2>&1 \
  || _no "session-progress 두 번째 기록 실패(review-skip.md 는 남았다)"
printf 'review-skip-pass: OK %s\n' "$FID"
exit 0
