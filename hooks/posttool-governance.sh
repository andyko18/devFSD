#!/usr/bin/env bash
# specops-ko governance-capture — PostToolUse entrypoint
# stdin: Claude Code PostToolUse JSON
# stdout: { "continue": true, "additionalContext"?: "..." }
# 실패 내성: 내부 오류 시 exit 0 + stderr 로그. tool 흐름 무중단.
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin_root=$(dirname "$script_dir")

# config guard — disabled 시 조용히 continue
bash "$plugin_root/scripts/_internal/is-hook-enabled.sh" posttool-governance >/dev/null 2>&1 || { echo '{"continue":true}'; exit 0; }

# 실패 시 stderr + 투과
safe_exit() {
  echo "[governance-capture] ERROR: posttool hook: $1" >&2
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

transcript=$(echo "$input" | jq -r '.transcript_path // empty')
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
tool_cmd=$(echo "$input" | jq -r '.tool_input.command // .tool_input.skill // empty')

[ -n "$transcript" ] && [ -f "$transcript" ] || { echo '{"continue":true}'; exit 0; }

rules_path="$plugin_root/hooks/rules.jsonl"
[ -f "$rules_path" ] || { echo '{"continue":true}'; exit 0; }

# Bash 사전 필터 (20260911-posttool-matcher-narrow) — pretool-governance.sh:45-56 동형.
#   이 훅은 동기라 모든 Bash 호출 뒤에 붙는다. 커밋·PR 이 아닌 명령(호출의 대부분)에서 아래
#   is_docs_only_audit_scope 의 git 3~4회와 규칙 루프 jq 를 다 치른 뒤 governance-lib.sh:1084(trigger_pattern grep)에서 버리던 것을 먼저 거른다.
#   ★ 판정 집합 불변: 정규식은 rules.jsonl 단일 소스(posttool·trigger_tool=Bash, enabled 무관 — 상위집합.
#     enabled==true 로 좁혀도 load_rules 가 enabled 만 적재해 판정은 같다 — 스위트가 잠그지 않는 설계 선택),
#     전처리는 apply_lookback_rule(governance-lib.sh:1082-1083)과 **같은 함수**다. 복제하지 않는다.
#   ★ 판정 불가면 조기 종료하지 않는다 — pretool 과 방향이 반대인 이유: 저쪽은 차단층이라 fail-open(allow),
#     이쪽은 감사층이라 기록 보존이 안전하다. jq -s 는 한 줄만 깨져도 통째로 실패하고(load_rules 의 jq -c
#     스트림은 앞 줄을 살린다), 정규식을 합치면 한 규칙의 오류가 전체를 rc=2 로 만든다 — 둘 다 종전 경로로 보낸다.
if [ "$tool_name" = "Bash" ]; then
  bash_trigger_re=$(jq -rs '[.[] | select(.matcher == "posttool" and .trigger_tool == "Bash") | .trigger_pattern | select(. != null)] | join("|")' "$rules_path" 2>/dev/null)
  if [ -n "$bash_trigger_re" ]; then
    scan_cmd=$(_trigger_scan_text "$(_strip_heredoc_bodies "$tool_cmd")")
    grep -Eq "$bash_trigger_re" <<< "$scan_cmd"
    [ "$?" -eq 1 ] && { echo '{"continue":true}'; exit 0; }   # 1=불일치만. 2(정규식 오류)는 통과
  fi
fi
_gov_cmd_moves_git "$(_strip_quoted_strings "$(_strip_heredoc_bodies "$tool_cmd")")" \
  || _gov_apply_git_target "$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)"   # 감사 범위도 셸이 있는 worktree 기준 (20261016-hook-worktree-target)

fid=$(detect_fid)

matches=""
while IFS= read -r rule; do
  [ -z "$rule" ] && continue
  local_id=$(echo "$rule" | jq -r '.id')
  desc=$(echo "$rule" | jq -r '.description')
  principle=$(echo "$rule" | jq -r '.principle')
  result=""
  case "$local_id" in
    R-1|R-2)
      # 감사 스코프 = 방금 일어난 액션의 범위 (R-1: HEAD~1..HEAD, R-2: base...HEAD) —
      # working-tree 기준(is_docs_only_change)은 커밋 직후 .specops 잔여 dirty 에 걸려 감사 침묵 (T8.e)
      if ! is_docs_only_audit_scope "$local_id"; then
        result=$(apply_lookback_rule "$rule" "$transcript" "$tool_name" "$tool_cmd" 2>/dev/null || true)
      fi
      ;;
    R-3)
      # R8: trigger 패턴을 rules.jsonl R-3.trigger_skill_pattern 단일소스에서 읽음
      #   (하드코딩 drift 제거 — rules 만 바꿔도 동작 따라감). 값 부재 시 안전 fallback.
      skill_pat=$(echo "$rule" | jq -r '.trigger_skill_pattern // "^devfsd:"')
      if [ "$tool_name" = "Skill" ] && grep -Eq "$skill_pat" <<< "$tool_cmd"; then
        result=$(apply_skill_declaration_rule "$transcript" "$tool_cmd" 2>/dev/null || true)
      fi
      ;;
  esac
  if [ -n "$result" ]; then
    snippet=$(echo "$result" | jq -r '.evidence_snippet')
    offset=$(echo "$result" | jq -r '.offset')
    # scope_class = 방금 감사한 액션의 커밋 범위 (20260814-friction-scope-posttool).
    #   R-3 등 커밋 범위 축이 없는 규칙은 _audit_scope_class 가 무출력 → 필드 자체가 생략된다.
    #   posttool 은 면제(docs-only) 시 애초에 여기 도달하지 않으므로 실제 값은 code|empty|무출력이다.
    log_friction "$fid" "$local_id" "$principle" "$snippet" "$offset" \
      "$(_audit_scope_class "$local_id")" 2>/dev/null || true
    matches="${matches}[governance] ${local_id}: ${desc}"$'\n'
  fi
done < <(load_rules "$rules_path" "posttool" 2>/dev/null || true)

if [ -n "$matches" ]; then
  # 300자 제한
  context=$(printf '%s' "$matches" | cut -c1-300)
  jq -nc --arg c "$context" '{ continue: true, additionalContext: $c }'
else
  echo '{"continue":true}'
fi
