#!/usr/bin/env bash
# specops-ko governance-capture — Stop entrypoint
# stdin: Claude Code Stop JSON (stop_hook_active 필드 포함)
# stdout: { "continue": true }  (Stop 은 additionalContext 미사용 — append only)
# 실패 내성: 내부 오류 시 exit 0 + stderr. 멱등: stop_hook_active==true 즉시 투과.
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin_root=$(dirname "$script_dir")

bash "$plugin_root/scripts/_internal/is-hook-enabled.sh" stop-governance >/dev/null 2>&1 || { echo '{"continue":true}'; exit 0; }

safe_exit() {
  echo "[governance-capture] ERROR: stop hook: $1" >&2
  echo '{"continue":true}'
  exit 0
}

# shellcheck disable=SC1091
source "$script_dir/governance-lib.sh" 2>/dev/null || safe_exit "governance-lib.sh source 실패"

# CWD 앵커링 — subdir/worktree 에서 기동돼도 .specops 상대경로(detect_fid·R-5·R-6 trivial-skip)가
# 프로젝트 루트 기준으로 동작. env 부재 시 기존 CWD 유지 (테스트 fixture 호환).
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR:-}" ]; then
  cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || true
fi

# 관할 한정 — `.specops/` 가 없는 저장소에서는 판정도 기록도 하지 않는다(pretool 의 `.specops/` 부재 면제와 같은 경계).
#   기록(log_friction)이 `.specops/` 를 만들면 그 저장소가 관할로 편입돼 다음 커밋부터 R-1 이 막는다.
[ -d ".specops" ] || { echo '{"continue":true}'; exit 0; }

input=$(cat 2>/dev/null || echo "")
# jq 부재를 오진하지 않는다 (pretool 과 동일 계약 — 20260830-silent-failure-surfacing)
command -v jq >/dev/null 2>&1 || safe_exit "jq 미설치 — 거버넌스 비활성 (설치: brew install jq)"
if ! echo "$input" | jq -e . >/dev/null 2>&1; then
  safe_exit "stdin JSON parse 실패"
fi

# 멱등 가드 (NFR-4)
active=$(echo "$input" | jq -r '.stop_hook_active // false')
if [ "$active" = "true" ]; then
  echo '{"continue":true}'
  exit 0
fi

transcript=$(echo "$input" | jq -r '.transcript_path // empty')
[ -n "$transcript" ] && [ -f "$transcript" ] || { echo '{"continue":true}'; exit 0; }

# 셸이 자기 기록을 가진 worktree 면 기록 루트를 그쪽으로 — git 대상은 바꾸지 않는다 (20261106-worktree-specops-root)
_gov_apply_record_root "$(_gov_git_target "$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)" "$PWD" | sed -n 1p)"

fid=$(detect_fid)
rules_path="$plugin_root/hooks/rules.jsonl"
[ -f "$rules_path" ] || { echo '{"continue":true}'; exit 0; }

while IFS= read -r rule; do
  [ -z "$rule" ] && continue
  rule_id=$(echo "$rule" | jq -r '.id')
  principle=$(echo "$rule" | jq -r '.principle')
  result=""
  case "$rule_id" in
    R-4) result=$(apply_assertion_without_test_rule "$rule" "$transcript" 2>/dev/null || true) ;;
    R-5) result=$(apply_advisor_section_rule "$rule" "$transcript" 2>/dev/null || true) ;;
    R-6) result=$(apply_gbrain_absence_rule "$rule" "$transcript" 2>/dev/null || true) ;;
  esac
  if [ -n "$result" ]; then
    snippet=$(echo "$result" | jq -r '.evidence_snippet')
    offset=$(echo "$result" | jq -r '.offset')
    log_friction "$fid" "$rule_id" "$principle" "$snippet" "$offset" 2>/dev/null || true
  fi
done < <(load_rules "$rules_path" "stop" 2>/dev/null || true)

echo '{"continue":true}'
