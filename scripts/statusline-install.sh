#!/usr/bin/env bash
# specops-ko statusLine 설치 — statusline.sh 절대경로를 .claude/settings.json statusLine 키에 주입.
# 플러그인 statusLine 번들 불가(claude-code-guide) → 본 스크립트가 수동 주입. 멱등.
#
# Usage: statusline-install.sh [--check | --help]
#   (무인자)  설치 수행 (멱등)
#   --check   변경 예정 내용만 표시 — **파일을 만들지도 고치지도 않는다**
#   --help    이 사용법
# Exit: 0 = 성공 / --check 시 이미 동일 · 1 = 오류 또는 --check 시 변경 예정 · 2 = 사용 오류
#
# ★ 인자 처리가 왜 생겼나 (20260829-statusline-check): 종전엔 인자를 **아예 안 봤다**.
#   `--help` 를 줘도 그대로 설치가 실행돼 `.claude/settings.json` 이 바뀌었다(커맨드 전수
#   점검 중 실측 — 확인하려다 설치됨). `.claude/` 는 gitignore 라 `git status` 에도 안 보여서
#   파일을 직접 열기 전엔 알 수 없다. 이 repo 의 다른 도구는 전부 미리보기 경로를 갖는데
#   (design-screen `--check` · release `--dry-run` · mutation-score `--check-conf`)
#   하필 **부작용이 사용자 설정인** 설치기만 없었다.
#   미지 인자는 조용히 설치하지 않고 exit 2 로 거부한다 — 오타가 설정을 바꾸면 안 된다.
set -uo pipefail

MODE=install
case "${1:-}" in
  "")        MODE=install ;;
  --check)   MODE=check ;;
  --help|-h) MODE=help ;;
  *)         echo "error: 알 수 없는 인자 '$1'" >&2
             echo "Usage: $0 [--check | --help]" >&2
             exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  echo "error: 인자는 하나만 받는다" >&2
  echo "Usage: $0 [--check | --help]" >&2
  exit 2
fi
if [ "$MODE" = help ]; then
  cat <<'USAGE'
Usage: statusline-install.sh [--check | --help]
  (무인자)  .claude/settings.json 의 statusLine 을 devFSD statusline.sh 로 설정 (멱등)
  --check   변경 예정 내용만 표시하고 종료 — 파일을 만들지도 고치지도 않는다
            exit 0 = 이미 동일 · exit 1 = 변경 예정
  --help    이 사용법
USAGE
  exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "error: jq 필요" >&2; exit 1; }

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SL="$ROOT/scripts/statusline.sh"
[ -f "$SL" ] || { echo "error: statusline.sh 없음 ($SL)" >&2; exit 1; }

DIR=".claude"; SETTINGS="$DIR/settings.json"

NEW_SL=$(jq -n --arg cmd "$SL" '{type:"command", command:$cmd}')

# --check: 파일시스템 무접촉. mkdir 조차 하지 않는다 — "확인" 이 디렉토리를 만들면
#   그건 이미 부작용이고, 이 옵션이 존재하는 이유를 스스로 깬다(T3·T7 이 잠근다).
if [ "$MODE" = check ]; then
  cur=""
  [ -f "$SETTINGS" ] && cur=$(jq -c '.statusLine // empty' "$SETTINGS" 2>/dev/null || true)
  want=$(printf '%s' "$NEW_SL" | jq -c .)
  if [ "$cur" = "$want" ]; then
    echo "statusLine: 이미 동일 — 변경 없음"
    echo "  현재: $cur"
    exit 0
  fi
  echo "statusLine: 변경 예정"
  echo "  대상 파일: $SETTINGS$([ -f "$SETTINGS" ] || echo ' (신규 생성)')"
  echo "  현재: ${cur:-(없음)}"
  echo "  변경: $want"
  [ -n "$cur" ] && echo "  ※ 기존 값은 $SETTINGS.bak 으로 백업된다"
  exit 1
fi

mkdir -p "$DIR"

if [ -f "$SETTINGS" ]; then
  if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
    cp "$SETTINGS" "$SETTINGS.bak"
    echo "기존 statusLine 백업: $SETTINGS.bak"
  fi
  TMP=$(mktemp)
  if ! jq --argjson sl "$NEW_SL" '.statusLine = $sl' "$SETTINGS" > "$TMP"; then
    echo "error: settings.json 파싱 실패 — 갱신 중단 ($SETTINGS)" >&2
    rm -f "$TMP"
    exit 1
  fi
  mv "$TMP" "$SETTINGS"
else
  jq -n --argjson sl "$NEW_SL" '{statusLine:$sl}' > "$SETTINGS"
fi

echo "✅ statusLine 등록: $SL → $SETTINGS"
echo "   (Claude Code 재시작 또는 다음 메시지부터 상태줄 표시)"
exit 0
