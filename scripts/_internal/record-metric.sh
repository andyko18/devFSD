#!/usr/bin/env bash
# 비용·수율 메타데이터 JSONL 기록기. 프롬프트·응답 원문을 받는 옵션은 의도적으로 제공하지 않는다.
# Usage: record-metric.sh --fid <FID> --phase <phase> [schema options]
set -u

SPECOPS="${SPECOPS_ROOT:-.specops}"
fid=""; task=""; phase=""; model=""
wall_ms=null; retry_count=0; fallback=false
verdict=""; finding_severity=""

need_value() {
  [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { echo "record-metric: $1 값 필요" >&2; exit 1; }
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --fid) need_value "$@"; fid="$2"; shift 2 ;;
    --task) need_value "$@"; task="$2"; shift 2 ;;
    --phase) need_value "$@"; phase="$2"; shift 2 ;;
    --model) need_value "$@"; model="$2"; shift 2 ;;
    --wall-ms) need_value "$@"; wall_ms="$2"; shift 2 ;;
    --retry-count) need_value "$@"; retry_count="$2"; shift 2 ;;
    --fallback) need_value "$@"; fallback="$2"; shift 2 ;;
    --verdict) need_value "$@"; verdict="$2"; shift 2 ;;
    --finding-severity) need_value "$@"; finding_severity="$2"; shift 2 ;;
    *) echo "record-metric: unknown option: $1" >&2; exit 1 ;;
  esac
done

printf '%s' "$fid" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || { echo "record-metric: invalid FID" >&2; exit 1; }
printf '%s' "$phase" | grep -qE '^[a-z0-9][a-z0-9_-]*$' || { echo "record-metric: invalid phase" >&2; exit 1; }
# task/model은 식별자만 허용 — 공백·개행 등 자유 텍스트(비밀 원문) 유입 경로를 스키마에서 닫는다.
if [ -n "$task" ]; then
  printf '%s' "$task" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$' \
    || { echo "record-metric: invalid task id" >&2; exit 1; }
fi
if [ -n "$model" ]; then
  printf '%s' "$model" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._/@+-]{0,119}$' \
    || { echo "record-metric: invalid model id" >&2; exit 1; }
fi

# 숫자 검증 대상은 wall_ms 하나뿐이다 — 종전엔 토큰 4필드가 함께 있어 루프였다
# (FID 20260903-metrics-dead-fields 가 그 4필드를 제거). 단일 대상에 for 를 쓰면
# 한 번만 도는 루프라 shellcheck SC2066 이 error 로 잡는다.
[ "$wall_ms" = "null" ] || printf '%s' "$wall_ms" | grep -qE '^[0-9]+$' \
  || { echo "record-metric: numeric value required" >&2; exit 1; }
printf '%s' "$retry_count" | grep -qE '^[0-9]+$' || { echo "record-metric: invalid retry-count" >&2; exit 1; }
case "$fallback" in true|false) ;; *) echo "record-metric: fallback must be true|false" >&2; exit 1 ;; esac
case "$verdict" in ""|NOT_RUN|PASS|PARTIAL|FAIL|WAIVED|STALE) ;; *) echo "record-metric: invalid verdict" >&2; exit 1 ;; esac
case "$finding_severity" in ""|none|low|medium|high|critical) ;; *) echo "record-metric: invalid severity" >&2; exit 1 ;; esac

# worktree 에서도 메인 기록을 쓴다 (fid 확정 뒤 · symlink 검사 앞)
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/specops-root.sh" 2>/dev/null && specops_root_export "$fid"
SPECOPS="${SPECOPS_ROOT:-.specops}"
[ ! -L "$SPECOPS" ] || { echo "record-metric: $SPECOPS symlink 거부" >&2; exit 1; }
[ ! -L "$SPECOPS/$fid" ] || { echo "record-metric: FID symlink 거부" >&2; exit 1; }
mkdir -p "$SPECOPS/$fid" || exit 1
target="$SPECOPS/$fid/metrics.jsonl"
[ ! -L "$target" ] || { echo "record-metric: metrics file symlink 거부" >&2; exit 1; }

ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq -nc \
  --argjson schema_version 2 --arg ts "$ts" --arg fid "$fid" \
  --arg task "$task" --arg phase "$phase" --arg model "$model" \
  --argjson wall_ms "$wall_ms" --argjson retry_count "$retry_count" \
  --argjson fallback "$fallback" \
  --arg verdict "$verdict" --arg severity "$finding_severity" \
  '{schema_version:$schema_version,ts:$ts,fid:$fid,
    task:(if $task=="" then null else $task end),phase:$phase,
    model:(if $model=="" then null else $model end),
    wall_ms:$wall_ms,retry_count:$retry_count,fallback:$fallback,
    verdict:(if $verdict=="" then null else $verdict end),
    finding_severity:(if $severity=="" then null else $severity end)}' >> "$target"
