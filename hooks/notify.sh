#!/usr/bin/env bash
# specops-ko notify — Notification hook 데스크톱 알림 (idle_prompt·permission_prompt).
# stdin: Claude Code Notification JSON. 부수효과: 알림 발사. 항상 exit 0.
# DRYRUN: SPECOPS_NOTIFY_DRYRUN=1 → 발사 대신 "<title>\t<msg>" stdout (테스트용).
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin_root=$(dirname "$script_dir")

# on/off 토글 (기본 on — config 부재 시 활성)
bash "$plugin_root/scripts/_internal/is-hook-enabled.sh" notify >/dev/null 2>&1 || exit 0

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null || true)
matcher=$(printf '%s' "$input" | jq -r '.matcher // empty' 2>/dev/null || true)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)

case "$matcher" in
  permission_prompt) label="권한 대기" ;;
  *)                 label="입력 대기" ;;
esac

# session-progress 최신 FID·단계 → suffix (cwd 없으면 생략 — pwd fallback 금지, C-1)
# permission_prompt → FID만(AC-2: 권한 대기 · <FID>) / idle_prompt → FID + step
suffix=""
if [ -n "$cwd" ] && [ -f "$cwd/.specops/session-progress.md" ]; then
  parsed=$(awk '
    /^## [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[a-z0-9-]+/ { if(seen)exit; seen=1; line=$2; next }
    seen && /^- / { print line "\t" $4; exit }
  ' "$cwd/.specops/session-progress.md" 2>/dev/null)
  if [ -n "$parsed" ]; then
    fid=$(printf '%s' "$parsed" | cut -f1)
    step=$(printf '%s' "$parsed" | cut -f2)
    if [ "$matcher" = "permission_prompt" ]; then
      suffix=" · $fid"
    else
      suffix=" · $fid $step"
    fi
  fi
fi

msg="$label$suffix"
title="devFSD"

if [ "${SPECOPS_NOTIFY_DRYRUN:-0}" = "1" ]; then
  printf '%s\t%s\n' "$title" "$msg"
  exit 0
fi

if command -v osascript >/dev/null 2>&1; then
  # AppleScript 문자열 escape (백슬래시·따옴표) — msg/title 깨짐 방지
  msg_esc=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
  title_esc=$(printf '%s' "$title" | sed 's/\\/\\\\/g; s/"/\\"/g')
  osascript -e "display notification \"$msg_esc\" with title \"$title_esc\"" >/dev/null 2>&1 || true
elif command -v notify-send >/dev/null 2>&1; then
  notify-send "$title" "$msg" >/dev/null 2>&1 || true
fi
exit 0
