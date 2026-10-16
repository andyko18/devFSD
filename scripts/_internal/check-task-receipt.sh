#!/usr/bin/env bash
# 태스크 receipt 게이트 판정.
# Usage: check-task-receipt.sh <FID> <task-id>
# Exit: 0=면제 가능 · 1=receipt 있으나 무효(deny) · 2=부재/판정불가(legacy fallthrough)
#       3=quick 범위 초과 · 4=quick 리뷰 미충족 (둘 다 deny — 명세 없는 FID 에서만 난다. 아래 quick 절)
set -u

FID="${1:-}"; TASK="${2:-}"
[ -n "$FID" ] && [ -n "$TASK" ] || { echo "usage: $0 <FID> <task-id>" >&2; exit 2; }

printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || exit 2
printf '%s' "$TASK" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$' || exit 2

PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
# worktree 에서 불려도 메인 worktree 의 .specops 로 판정한다 — git 조회는 export 된 GIT_DIR·GIT_WORK_TREE 로 그 worktree (20261016-judge-scripts-worktree-root)
#   훅은 .specops 가 있는 프로젝트 폴더에서 부르므로 이동하지 않는다(셸이 다른 worktree 면 git env 도 이미 export 돼 있다). SPECOPS_ROOT 를 준 호출도 그대로다.
#   이동하면 상대경로 $0 의 뜻이 바뀐다 — 자기 경로는 그 전에 잡는다. 테스트 명령을 실행하지 않으므로 _sr_leave 는 부르지 않는다.
# shellcheck source=/dev/null
. "$PLUGIN/scripts/_internal/specops-root.sh" 2>/dev/null && specops_root_enter "$FID" 2>/dev/null || true
SPECOPS="${SPECOPS_ROOT:-.specops}"
receipt="$SPECOPS/$FID/receipts/$TASK.json"
[ -f "$receipt" ] || exit 2
[ -L "$receipt" ] && { echo "check-task-receipt: receipt symlink 거부" >&2; exit 1; }

# shellcheck source=/dev/null
source "$PLUGIN/scripts/dag/parse-dag.sh"
# shellcheck source=/dev/null
source "$PLUGIN/scripts/_internal/verification-state.sh"

verdict=$(jq -r '.verdict // empty' "$receipt" 2>/dev/null) || exit 1
rfid=$(jq -r '.fid // empty' "$receipt" 2>/dev/null) || exit 1
rtask=$(jq -r '.task // empty' "$receipt" 2>/dev/null) || exit 1
[ "$verdict" = "PASS" ] || { echo "check-task-receipt: verdict!=PASS" >&2; exit 1; }
[ "$rfid" = "$FID" ] && [ "$rtask" = "$TASK" ] || { echo "check-task-receipt: fid/task mismatch" >&2; exit 1; }

TASKS="$SPECOPS/$FID/tasks.md"
[ -f "$TASKS" ] || { echo "check-task-receipt: tasks.md 부재" >&2; exit 1; }
yaml=$(dag::extract_yaml "$TASKS")
cur_cmd=$(dag::get_task_test_command "$yaml" "$TASK" 2>/dev/null)
[ -n "$cur_cmd" ] || { echo "check-task-receipt: test_command 없음" >&2; exit 1; }
cur_hash=$(printf '%s' "$cur_cmd" | git hash-object --stdin 2>/dev/null) \
  || cur_hash=$(printf '%s' "$cur_cmd" | shasum -a 256 | awk '{print $1}')
rec_hash=$(jq -r '.test_command_hash // empty' "$receipt")
[ "$cur_hash" = "$rec_hash" ] || { echo "check-task-receipt: test_command drift" >&2; exit 1; }

# staged ⊆ outputs (공집합 staged 거부). bash 3.2 호환 — mapfile 미사용.
staged=$(git diff --cached --name-only --no-renames 2>/dev/null || true)
[ -n "$staged" ] || { echo "check-task-receipt: staged empty" >&2; exit 1; }
outs=$(jq -r '.outputs[]?' "$receipt" 2>/dev/null)
[ -n "$outs" ] || { echo "check-task-receipt: outputs empty" >&2; exit 1; }
while IFS= read -r f; do
  [ -z "$f" ] && continue
  printf '%s\n' "$outs" | grep -Fxq -- "$f" \
    || { echo "check-task-receipt: staged outside outputs: $f" >&2; exit 1; }
done <<< "$staged"

# 문서 전용 변경은 receipt 를 무효화하지 않는다 (20260912-verify-stale-docs-scope).
#   receipt 는 verify 창이 닫혔을 때의 유일한 통로다 — 지문 층과 같은 맹점을 함께 푼다.
#   nondoc_hash 부재(구버전 receipt)면 종전 전체 지문 비교로 떨어진다 = 더 엄격한 쪽(fail-safe).
rec_nd=$(jq -r '.nondoc_hash // empty' "$receipt")
if [ -n "$rec_nd" ] && [ "$rec_nd" != "NO_GIT" ]; then
  cur_nd=$(vs::nondoc_fingerprint)
  [ "$rec_nd" != "UNHASHABLE" ] && [ "$cur_nd" != "UNHASHABLE" ] \
    || { echo "check-task-receipt: 지문 산출 불가(UNHASHABLE) — 읽을 수 없는 파일 등" >&2; exit 1; }
  [ "$rec_nd" = "$cur_nd" ] \
    || { echo "check-task-receipt: tree stale" >&2; exit 1; }
else
  rec_tree=$(jq -r '.tree_hash // empty' "$receipt")
  cur_tree=$(vs::workspace_fingerprint)
  [ "$rec_tree" != "UNHASHABLE" ] && [ "$cur_tree" != "UNHASHABLE" ] \
    || { echo "check-task-receipt: 지문 산출 불가(UNHASHABLE) — 읽을 수 없는 파일 등" >&2; exit 1; }
  [ -n "$rec_tree" ] && [ "$rec_tree" = "$cur_tree" ] \
    || { echo "check-task-receipt: tree stale" >&2; exit 1; }
fi

# ── quick 경로 (20261010-quick-fix-path) ─────────────────────────────────────
# 태스크 문서는 있는데 명세가 없는 FID 는 quick 경로다. 영수증이 유효해도 범위 상한과 리뷰를 함께 요구한다 —
#   이 조합은 문서·리뷰 없이 테스트만 통과하면 커밋이 열리는 통로였다(실사용 0건이라 드러나지 않았을 뿐이다).
#   판정 기준이 구조인 이유: 모델이 쓰는 표지로 가르면 표지를 빼는 것으로 피한다. 구조로 가르면 피하는 길이
#   명세 파일을 두는 것뿐이고, 그 경우는 종전의 정식 영수증 경로다(빈 명세 파일로도 피해진다 — 새로 생긴 구멍이
#   아니라 종전 경로 그대로다). 정식 경로는 명세를 먼저 쓰므로 이 가지에 들어오지 않는다.
if [ ! -f "$SPECOPS/$FID/spec.md" ]; then
  bash "$PLUGIN/scripts/_internal/quick-scope.sh" "$FID" "$TASK" >&2
  case $? in
    0) ;;
    4) exit 4 ;;
    *) exit 3 ;;   # 범위 초과 · 판정기 실행 실패(판정 불가는 막는 쪽)
  esac
fi

exit 0
