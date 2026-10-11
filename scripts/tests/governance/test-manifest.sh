#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
HOOKS_JSON="$PLUGIN/hooks/hooks.json"

# T12.a hooks.json: PostToolUse 배열 + posttool-governance 항목
if jq -e '.hooks.PostToolUse[] | .hooks[] | select(.command | contains("posttool-governance.sh"))' "$HOOKS_JSON" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T12.a PostToolUse posttool-governance 등록"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.a"
fi

# T12.b hooks.json: Stop 배열에 stop-governance 항목
if jq -e '.hooks.Stop[] | .hooks[] | select(.command | contains("stop-governance.sh"))' "$HOOKS_JSON" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T12.b Stop stop-governance 등록"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.b"
fi

# T12.c hooks.json: SessionStart session-start.sh · Stop ensure-session-progress.sh 기존 항목 보존
if jq -e '.hooks.SessionStart[] | .hooks[] | select(.command | contains("session-start.sh"))' "$HOOKS_JSON" >/dev/null 2>&1 \
   && jq -e '.hooks.Stop[] | .hooks[] | select(.command | contains("ensure-session-progress.sh"))' "$HOOKS_JSON" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T12.c 기존 hook 보존"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.c"
fi

# T12.d is-hook-enabled: posttool-governance / stop-governance 기본 enabled (exit 0)
run_hook_enabled() { bash "$PLUGIN/scripts/_internal/is-hook-enabled.sh" "$1" >/dev/null 2>&1; }
if run_hook_enabled posttool-governance; then
  PASS=$((PASS+1)); echo "PASS T12.d posttool-governance 기본 enabled"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.d"
fi
if run_hook_enabled stop-governance; then
  PASS=$((PASS+1)); echo "PASS T12.e stop-governance 기본 enabled"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.e"
fi

# T12.f hooks.json JSON 유효성
if jq -e . "$HOOKS_JSON" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T12.f JSON 유효"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.f"
fi

# T12.g hooks.json: PreToolUse 배열 + pretool-governance 항목 배선
if jq -e '.hooks.PreToolUse[] | .hooks[] | select(.command | contains("pretool-governance.sh"))' "$HOOKS_JSON" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T12.g PreToolUse pretool-governance 배선"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.g PreToolUse pretool-governance 배선"
fi

# T12.h ★ PostToolUse matcher 가 모든 posttool 규칙의 trigger_tool 을 덮는다 (20260911-posttool-matcher-narrow)
#   matcher 를 좁히면 새 결합이 생긴다 — 규칙이 새 trigger_tool 을 쓰는데 matcher 를 안 넓히면
#   그 규칙은 **켜져도 안 돈다**(에러 없이 기록만 0). enabled 무관 — 나중에 켜질 규칙도 덮는다.
RULES_JSONL="$PLUGIN/hooks/rules.jsonl"
post_matcher=$(jq -r '[.hooks.PostToolUse[] | select(any(.hooks[]; .command | contains("posttool-governance.sh"))) | (.matcher // "")] | first // ""' "$HOOKS_JSON" 2>/dev/null)
trigger_tools=$(jq -r 'select(.matcher == "posttool") | .trigger_tool // empty' "$RULES_JSONL" 2>/dev/null | sort -u)
missing=""
for t in $trigger_tools; do
  printf '%s\n' "$post_matcher" | tr '|,' '\n\n' | sed 's/^ *//; s/ *$//' | grep -qxF -- "$t" || missing="$missing $t"
done
# 공허 가드: trigger_tool 을 하나도 못 읽었으면 "빠진 것 없음" 은 아무것도 증명하지 않는다
if [ -n "$trigger_tools" ] && [ -z "$missing" ]; then
  PASS=$((PASS+1)); echo "PASS T12.h PostToolUse matcher('$post_matcher') ⊇ trigger_tool($(printf '%s' "$trigger_tools" | tr '\n' ' '))"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.h matcher='$post_matcher' 누락=[${missing# }] trigger_tools=[$(printf '%s' "$trigger_tools" | tr '\n' ' ')]"
fi

# T12.i PostToolUse matcher 는 와일드카드가 아니다 (clarify Q1 — 사용자 결정 2026-09-11)
#   `*`·빈값·생략은 모든 도구 호출마다 posttool 을 띄운다 — 판정에 기여하지 않는 호출이 약 1/7.
#   되돌리려면 이 케이스를 고치는 명시적 결정이 필요하게 한다(성능 개선의 무음 회귀 차단).
case "$post_matcher" in
  ''|'*')
    FAIL=$((FAIL+1)); echo "FAIL T12.i PostToolUse matcher 가 와일드카드('$post_matcher')" ;;
  *)
    PASS=$((PASS+1)); echo "PASS T12.i PostToolUse matcher 명시 목록('$post_matcher')" ;;
esac

# ── hooks.json 등록 정합 (20261008-hooks-json-registration) ───────────────────────────────
#   T12.a/g 는 "command 문자열이 어딘가에 있다" 만 본다. matcher 오타("Bsh")나 async:true 는
#   등록은 남긴 채 **차단 훅을 통째로 무력화**하는데 이전엔 어떤 스위트도 몰랐다(변이 주입 실측).

# T12.j PreToolUse: matcher 정확히 'Bash' + pretool-governance 는 동기(async != true)
#   async:true 면 harness 는 훅 결과를 기다리지 않아 deny 가 적용되지 않는다.
pre_matcher=$(jq -r '[.hooks.PreToolUse[] | select(any(.hooks[]; .command | contains("pretool-governance.sh"))) | (.matcher // "")] | first // "<none>"' "$HOOKS_JSON" 2>/dev/null)
pre_async_bad=$(jq -r '[.hooks.PreToolUse[] | .hooks[] | select(.command | contains("pretool-governance.sh")) | select(.async == true)] | length' "$HOOKS_JSON" 2>/dev/null)
pre_cnt=$(jq -r '[.hooks.PreToolUse[] | .hooks[] | select(.command | contains("pretool-governance.sh"))] | length' "$HOOKS_JSON" 2>/dev/null)
if [ "$pre_matcher" = "Bash" ] && [ "${pre_cnt:-0}" -ge 1 ] && [ "${pre_async_bad:-1}" = "0" ]; then
  PASS=$((PASS+1)); echo "PASS T12.j PreToolUse matcher=Bash · pretool-governance 동기"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.j PreToolUse matcher='$pre_matcher' 등록수=${pre_cnt:-?} async위반=${pre_async_bad:-?}"
fi

# T12.k PostToolUse matcher 정확히 'Bash|Skill' (T12.h 는 ⊇ 만 본다 — 정확한 목록을 잠가 무음 변경을 막는다)
if [ "$post_matcher" = "Bash|Skill" ]; then
  PASS=$((PASS+1)); echo "PASS T12.k PostToolUse matcher == 'Bash|Skill'"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.k PostToolUse matcher='$post_matcher' (기대 'Bash|Skill')"
fi

# T12.l 거버넌스 훅(pre·post·stop·session-start) 은 전부 동기(async != true)
gov_total=$(jq -r '[.hooks[][] | .hooks[] | select(.command | test("(pretool|posttool|stop)-governance\\.sh|session-start\\.sh"))] | length' "$HOOKS_JSON" 2>/dev/null)
gov_async=$(jq -r '[.hooks[][] | .hooks[] | select(.command | test("(pretool|posttool|stop)-governance\\.sh|session-start\\.sh")) | select(.async == true)] | length' "$HOOKS_JSON" 2>/dev/null)
if [ "${gov_total:-0}" -ge 4 ] && [ "${gov_async:-1}" = "0" ]; then
  PASS=$((PASS+1)); echo "PASS T12.l 거버넌스 훅 ${gov_total}개 전부 동기"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.l 거버넌스 훅 total=${gov_total:-?} async=${gov_async:-?}"
fi

# T12.m 모든 hook command 가 가리키는 스크립트가 실재한다 (${CLAUDE_PLUGIN_ROOT} → 플러그인 루트)
#   파일명 오타·삭제·rename 누락은 훅이 조용히 실패(command not found)해 강제층이 사라진다.
cmd_total=0; cmd_missing=""
while IFS= read -r c; do
  [ -z "$c" ] && continue
  cmd_total=$((cmd_total+1))
  rel=$(printf '%s' "$c" | sed -n 's/.*\${CLAUDE_PLUGIN_ROOT}\/\([^" ]*\).*/\1/p')
  if [ -z "$rel" ] || [ ! -f "$PLUGIN/$rel" ]; then cmd_missing="$cmd_missing [${rel:-경로추출실패:$c}]"; fi
done < <(jq -r '.hooks[][] | .hooks[] | .command' "$HOOKS_JSON" 2>/dev/null)
if [ "$cmd_total" -ge 8 ] && [ -z "$cmd_missing" ]; then
  PASS=$((PASS+1)); echo "PASS T12.m hook command ${cmd_total}건 스크립트 전부 실재"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.m command=${cmd_total}건 누락=[${cmd_missing# }]"
fi

# T12.n 이벤트 키는 공식 hook 이벤트 이름 집합에 속한다 (오타 키는 harness 가 무시 — 훅이 안 돈다)
valid_events='SessionStart SessionEnd UserPromptSubmit PreToolUse PostToolUse PostToolUseFailure PermissionRequest Notification SubagentStart SubagentStop Stop StopFailure PreCompact PostCompact TeammateIdle TaskCompleted ConfigChange Setup'
bad_events=""; ev_total=0
for ev in $(jq -r '.hooks | keys[]' "$HOOKS_JSON" 2>/dev/null); do
  ev_total=$((ev_total+1))
  case " $valid_events " in *" $ev "*) ;; *) bad_events="$bad_events $ev" ;; esac
done
if [ "$ev_total" -ge 6 ] && [ -z "$bad_events" ]; then
  PASS=$((PASS+1)); echo "PASS T12.n 이벤트 키 ${ev_total}종 전부 유효"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.n 이벤트 ${ev_total}종 무효=[${bad_events# }]"
fi

echo
echo "==== Results: PASS=$PASS FAIL=$FAIL ===="
[ "$FAIL" -eq 0 ]
