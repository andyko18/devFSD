#!/usr/bin/env bash
# 태스크 단위 커밋 receipt 기록기.
# Usage: record-task-receipt.sh <FID> <task-id>
# test_command 실행이 PASS일 때만 .specops/<FID>/receipts/<task>.json 을 원자적으로 기록한다.
set -u

FID="${1:?usage: $0 <FID> <task-id>}"
TASK="${2:?usage: $0 <FID> <task-id>}"

printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || { echo "record-task-receipt: invalid FID" >&2; exit 1; }
printf '%s' "$TASK" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$' || { echo "record-task-receipt: invalid task" >&2; exit 1; }

PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
# worktree 에서 불려도 메인 worktree 의 .specops 에 쓴다 — 테스트는 아래에서 원래 폴더로 (20261016-hook-worktree-target)
#   SPECOPS_ROOT 를 준 호출은 위치를 이미 정했으므로 이동하지 않는다(_sr_leave 는 그때 아무것도 안 한다).
# shellcheck source=/dev/null
. "$PLUGIN/scripts/_internal/specops-root.sh" 2>/dev/null || true
command -v _sr_leave >/dev/null 2>&1 || _sr_leave() { :; }
specops_root_enter "$FID" 2>/dev/null || true   # SPECOPS_ROOT 가 있으면 함수가 스스로 건너뛴다
SPECOPS="${SPECOPS_ROOT:-.specops}"
# shellcheck source=/dev/null
source "$PLUGIN/scripts/dag/parse-dag.sh"
# shellcheck source=/dev/null
source "$PLUGIN/scripts/_internal/verification-state.sh"

TASKS="$SPECOPS/$FID/tasks.md"
[ -f "$TASKS" ] || { echo "record-task-receipt: tasks.md not found: $TASKS" >&2; exit 1; }
[ ! -L "$SPECOPS" ] || { echo "record-task-receipt: $SPECOPS symlink 거부" >&2; exit 1; }
[ ! -L "$SPECOPS/$FID" ] || { echo "record-task-receipt: FID symlink 거부" >&2; exit 1; }

yaml=$(dag::extract_yaml "$TASKS")
[ -n "$yaml" ] || { echo "record-task-receipt: DAG YAML 없음" >&2; exit 1; }

test_cmd=$(dag::get_task_test_command "$yaml" "$TASK" 2>/dev/null)
[ -n "$test_cmd" ] || { echo "record-task-receipt: test_command 없음 (task=$TASK)" >&2; exit 1; }

outputs=$(dag::get_task_outputs "$yaml" "$TASK" 2>/dev/null)
[ -n "$outputs" ] || { echo "record-task-receipt: outputs 없음 (task=$TASK)" >&2; exit 1; }

# anti-footgun: run-verification 과 동일 계열만 실행 (임의 셸 메타 차단).
_WHITELIST_PAT='^(cd[[:blank:]]+[A-Za-z0-9_.][A-Za-z0-9_/.-]*[[:blank:]]+&&[[:blank:]]+)?((poetry|uv|pdm|rye)[[:blank:]]+run[[:blank:]]+)?(bash[[:blank:]]+(scripts|tests?)/[A-Za-z0-9_/.-]+\.sh([[:blank:]][A-Za-z0-9_/.=-]*)*|(python[[:blank:]]+-m[[:blank:]]+)?pytest([[:blank:]][A-Za-z0-9_/.=-]*)*|(npm|pnpm|yarn)[[:blank:]]+((--dir|--filter|-C|workspace)[[:blank:]]+[A-Za-z0-9_.@][A-Za-z0-9_@/.-]*[[:blank:]]+)*(run[[:blank:]]+)?test(:[A-Za-z0-9._-]+)?([[:blank:]][A-Za-z0-9_/.=-]*)*|go[[:blank:]]+test([[:blank:]][A-Za-z0-9_/.=-]*)*|cargo[[:blank:]]+test([[:blank:]][A-Za-z0-9_/.=-]*)*|npx[[:blank:]]+[A-Za-z0-9_@][A-Za-z0-9_@/.-]*([[:blank:]][A-Za-z0-9_@/.=-]*)*|(pnpm|yarn)[[:blank:]]+exec[[:blank:]]+[A-Za-z0-9_@][A-Za-z0-9_@/.-]*([[:blank:]][A-Za-z0-9_@/.=-]*)*)$'
if [[ ! "$test_cmd" =~ $_WHITELIST_PAT ]] || [[ "$test_cmd" == *..* ]]; then
  echo "record-task-receipt: test_command whitelist 미통과: $test_cmd" >&2
  exit 1
fi

read -r -a _parts <<< "$test_cmd"
(
  _sr_leave || exit 1
  if [[ "$test_cmd" =~ ^cd[[:blank:]]+([^[:blank:]]+)[[:blank:]]+\&\&[[:blank:]]+(.*)$ ]]; then
    _sub_dir="${BASH_REMATCH[1]}"; read -r -a _sub_parts <<< "${BASH_REMATCH[2]}"
    ( cd "$_sub_dir" && "${_sub_parts[@]}" ) >/dev/null 2>&1
  elif [ "${_parts[0]}" = "bash" ]; then
    bash "${_parts[@]:1}" >/dev/null 2>&1
  else
    "${_parts[@]}" >/dev/null 2>&1
  fi
)
ec=$?
if [ "$ec" -ne 0 ]; then
  echo "record-task-receipt: test FAIL (exit=$ec): $test_cmd" >&2
  exit 1
fi

cmd_hash=$(printf '%s' "$test_cmd" | git hash-object --stdin 2>/dev/null) \
  || cmd_hash=$(printf '%s' "$test_cmd" | shasum -a 256 | awk '{print $1}')
tree=$(vs::workspace_fingerprint)
# 비문서 지문을 함께 남긴다 — 문서 전용 변경이 receipt 를 무효화하지 않게 한다
#   (20260912-verify-stale-docs-scope). 소비측은 이 필드가 없으면 종전 tree_hash 비교로 떨어진다.
nondoc=$(vs::nondoc_fingerprint)
# 읽을 수 없는 파일 등으로 지문을 믿을 수 없으면 receipt 를 만들지 않는다 — 만들면 이후 어떤 변경도 STALE 로 못 잡는다
#   (20261005-fingerprint-add-failclosed). 확인: git add -A -n 으로 permission 오류를 찾아 권한을 고친다.
if [ "$tree" = "UNHASHABLE" ] || [ "$nondoc" = "UNHASHABLE" ]; then
  echo "record-task-receipt: 지문 산출 불가(UNHASHABLE) — 읽을 수 없는 파일 등으로 git add 가 실패했다. git add -A -n 으로 원인(permission 오류 등)을 찾아 고치세요" >&2
  exit 1
fi
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$SPECOPS/$FID/receipts" || exit 1
target="$SPECOPS/$FID/receipts/$TASK.json"
tmp="$SPECOPS/$FID/receipts/.$TASK.$$.tmp"
[ ! -L "$target" ] || { echo "record-task-receipt: receipt symlink 거부" >&2; exit 1; }

outputs_json=$(printf '%s\n' "$outputs" | jq -Rsc 'split("\n")|map(select(length>0))')

# TDD RED 관측 (20260806) — **비차단**. receipt 는 GREEN(test PASS)만 증명하므로,
#   "구현 전에 실패했는가" 를 별도 관측해 필드로 남긴다(공허한 테스트 감사 경로).
#   판정 불가(transcript 부재·명령 미발견)가 흔해 커밋을 막지 않는다 — 차단 전환 시
#   바꿀 지점이 여기다.
_RED_SH="$PLUGIN/scripts/_internal/check-tdd-red.sh"
tdd_red="unknown"
if [ -f "$_RED_SH" ]; then
  if red_out=$(bash "$_RED_SH" "$FID" "$TASK" 2>&1); then
    tdd_red="observed"
  else
    case $? in
      1) tdd_red="absent"; printf '%s\n' "$red_out" >&2 ;;
      *) tdd_red="unknown" ;;
    esac
  fi
fi

jq -n \
  --argjson schema_version 1 --arg fid "$FID" --arg task "$TASK" \
  --arg tree_hash "$tree" --arg nondoc_hash "$nondoc" --arg test_command "$test_cmd" \
  --arg test_command_hash "$cmd_hash" --argjson outputs "$outputs_json" \
  --arg verdict PASS --arg recorded_at "$ts" --arg runner "record-task-receipt.sh" \
  --arg tdd_red "$tdd_red" \
  '{schema_version:$schema_version,fid:$fid,task:$task,tree_hash:$tree_hash,nondoc_hash:$nondoc_hash,
    test_command:$test_command,test_command_hash:$test_command_hash,
    outputs:$outputs,verdict:$verdict,tdd_red:$tdd_red,
    recorded_at:$recorded_at,runner:$runner}' \
  > "$tmp" || { rm -f "$tmp"; exit 1; }
mv "$tmp" "$target"
echo "RECEIPT: PASS $FID/$TASK"
exit 0
