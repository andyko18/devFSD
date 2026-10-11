#!/usr/bin/env bash
# 비용·수율 계측 기반 — 제한된 메타데이터 스키마와 안전한 JSONL append
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
REC="$PLUGIN/scripts/_internal/record-metric.sh"

TD=$(mktemp -d) || exit 1
trap 'rm -rf "$TD"' EXIT
mkdir -p "$TD/.specops/20260803-metrics"

(cd "$TD" && bash "$REC" \
  --fid 20260803-metrics --task T2 --phase verify --model claude-test \
  --wall-ms 1234 --retry-count 1 --fallback true \
  --verdict PASS --finding-severity high)
LOG="$TD/.specops/20260803-metrics/metrics.jsonl"

# M1 — 유지 필드 보존 + schema_version 2 (AC-3 · AC-R-1)
if [ -f "$LOG" ] && jq -e '
  .schema_version == 2 and .fid == "20260803-metrics" and .task == "T2"
  and .phase == "verify" and .model == "claude-test"
  and .wall_ms == 1234 and .retry_count == 1 and .fallback == true
  and .verdict == "PASS" and .finding_severity == "high"
' "$LOG" >/dev/null; then
  ok "M1 유지 필드 보존 + schema_version 2"
else
  nope "M1" "log=$(cat "$LOG" 2>/dev/null)"
fi

# M1b — 죽은 필드 3종 키가 아예 없다 (AC-1)
#   FID 20260903-metrics-dead-fields: tokens 4필드는 bash 가 관측 불가라 150/150 null 이었고,
#   fixed 는 배선 0, timeout 은 상수 false 였다. 빈 칸은 "측정 중" 이라는 착시를 준다.
if jq -e 'has("tokens") or has("timeout") or has("fixed") | not' "$LOG" >/dev/null; then
  ok "M1b 죽은 필드 키 부재 (tokens·timeout·fixed)"
else
  nope "M1b" "잔존 키=$(jq -r 'keys_unsorted|join(",")' "$LOG" 2>/dev/null)"
fi

# M1c — 유지 키 집합이 정확히 일치 (AC-R-1 — 과잉 제거 방지)
_want='schema_version,ts,fid,task,phase,model,wall_ms,retry_count,fallback,verdict,finding_severity'
_got=$(jq -r 'keys_unsorted|join(",")' "$LOG" 2>/dev/null)
if [ "$_got" = "$_want" ]; then
  ok "M1c 유지 키 집합 정확 일치 (11키)"
else
  nope "M1c" "want=$_want got=$_got"
fi

# M1d — 제거된 플래그는 조용히 무시되지 않고 비0 종료 (AC-2)
#   조용히 무시하면 호출자가 값이 기록된 줄 안다 — 그게 이 FID 가 고치는 병이다.
#   ★ 값은 반드시 **유효한 것**을 쓴다 — 잘못된 값(예: --input-tokens x)은 구 구현에서도
#     값 검증에 걸려 비0 이라 구/신을 가리지 못한다(판별력 0). 유효값이어야 "플래그가
#     사라졌는가" 만 시험한다. (실측: 무효값 판은 구 구현에서도 PASS 했다.)
#   ★ 시행 횟수를 함께 세어 단언한다 — heredoc 이 비면 `_bad=0` 이라 **아무것도 시험하지
#     않고 PASS** 가 난다(Phase C 가 heredoc 을 비워 실증). 하네스 고장과 SUT 속성을
#     구분하려면 "몇 건을 실제로 돌렸는가" 가 판정에 들어가야 한다.
_bad=0; _ran=0
while IFS='|' read -r _f _v; do
  [ -n "$_f" ] || continue
  _ran=$((_ran+1))
  if (cd "$TD" && bash "$REC" --fid 20260803-metrics --phase verify "$_f" "$_v" >/dev/null 2>&1); then
    _bad=$((_bad+1)); echo "  (수락됨: $_f $_v)"
  fi
done <<'EOF_FLAGS'
--input-tokens|100
--timeout|false
--fixed|true
EOF_FLAGS
if [ "$_ran" -eq 3 ] && [ "$_bad" -eq 0 ]; then
  ok "M1d 제거된 플래그 3종 거부 (시행 ${_ran}/3)"
else
  nope "M1d" "시행=${_ran}/3 수락=${_bad}"
fi

# 원문을 받을 수 있는 임의 필드는 거부한다.
if (cd "$TD" && bash "$REC" --fid 20260803-metrics --phase verify --prompt "secret" >/dev/null 2>&1); then
  nope "M2" "미등록 prompt 필드가 수락됨"
else
  ok "M2 미등록·원문 필드 거부"
fi

# 숫자/enum 검증 실패는 append 전에 중단한다.
before=$(wc -l < "$LOG" | tr -d ' ')
if (cd "$TD" && bash "$REC" --fid 20260803-metrics --phase verify --wall-ms nope >/dev/null 2>&1); then
  nope "M3" "잘못된 숫자가 수락됨"
else
  after=$(wc -l < "$LOG" | tr -d ' ')
  [ "$before" = "$after" ] && ok "M3 잘못된 값은 무기록" || nope "M3" "before=$before after=$after"
fi

# path escape와 symlink write-through를 거부한다.
if (cd "$TD" && bash "$REC" --fid ../escape --phase verify >/dev/null 2>&1); then
  nope "M4a" "잘못된 FID 수락"
else
  ok "M4a 잘못된 FID 거부"
fi
mkdir -p "$TD/outside"
ln -s "$TD/outside" "$TD/.specops/20260803-link"
if (cd "$TD" && bash "$REC" --fid 20260803-link --phase verify >/dev/null 2>&1); then
  nope "M4b" "FID symlink 수락"
else
  ok "M4b FID symlink 거부"
fi

# task/model은 식별자만 허용한다 (자유 텍스트·원문 거부).
before=$(wc -l < "$LOG" | tr -d ' ')
if (cd "$TD" && bash "$REC" --fid 20260803-metrics --phase verify --task "secret prompt" >/dev/null 2>&1); then
  nope "M4c" "공백 포함 task가 수락됨"
else
  after=$(wc -l < "$LOG" | tr -d ' ')
  [ "$before" = "$after" ] && ok "M4c task 자유 텍스트 거부" || nope "M4c" "before=$before after=$after"
fi

# BYPASS 수율 계측 — 거버넌스 헬퍼가 phase=governance-bypass만 남기고 사유 원문은 받지 않는다.
source "$PLUGIN/hooks/governance-lib.sh"
mkdir -p "$TD/.specops/20260803-bypass"
(cd "$TD" && _record_bypass_metric 20260803-bypass)
BLOG="$TD/.specops/20260803-bypass/metrics.jsonl"
#   ★ 종전엔 `(.tokens.input == null)` 로 "원문 미기록" 을 단언했으나, tokens 키가
#     스키마에서 사라진 뒤로는 **항상 참**이다 — jq 는 없는 키를 null 로 체이닝한다
#     (실증: `echo '{"a":1}' | jq -e '.tokens.input == null'` → rc=0).
#     `has()` 로 키 부재를 직접 단언해야 실패할 수 있는 assertion 이 된다.
if [ -f "$BLOG" ] && jq -e '
  .phase == "governance-bypass" and .fallback == true
  and .verdict == null and (has("tokens") | not)
' "$BLOG" >/dev/null; then
  ok "M5 BYPASS 계측(식별자만)"
else
  nope "M5" "blog=$(cat "$BLOG" 2>/dev/null)"
fi
(cd "$TD" && _record_bypass_metric "")
(cd "$TD" && _record_bypass_metric "../escape")
[ "$(wc -l < "$BLOG" | tr -d ' ')" = "1" ] && ok "M5b 빈/잘못된 FID no-op" || nope "M5b" "lines=$(wc -l < "$BLOG")"

# M6: evaluator-degradation phase 기록 + 스킬/커맨드 배선
(cd "$TD" && bash "$REC" \
  --fid 20260803-metrics --task T1 --phase evaluator-degradation \
  --fallback true --model claude-sonnet-override)
if jq -e 'select(.phase=="evaluator-degradation" and .fallback==true and .model=="claude-sonnet-override")' \
     "$LOG" >/dev/null; then
  ok "M6a evaluator-degradation JSONL"
else
  nope "M6a" "log=$(cat "$LOG")"
fi
grep -q 'evaluator-degradation' "$PLUGIN/skills/implementing-ko/SKILL.md" \
  && grep -q 'evaluator-degradation' "$PLUGIN/commands/start-all.md" \
  && ok "M6b implementing-ko·start-all 배선" \
  || nope "M6b" "doc wiring missing"

finish
