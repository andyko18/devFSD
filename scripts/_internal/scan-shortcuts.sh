#!/usr/bin/env bash
# scan-shortcuts.sh — `shortcut:` 의도적 단순화 주석을 부채 장부 1장으로 모은다
# Usage: scan-shortcuts.sh [ROOT]   (기본 .)  · read-only · 항상 rc 0 (보고 도구 — 게이트 아님)
#
# 규약: 의도적으로 모서리를 자른 코드(전역 락·O(n²) 스캔·단순 휴리스틱)에 주석을 남긴다 —
#   `# shortcut: <상한> → <업그레이드 조건>`   (`//`·`/*`·`--` 접두 가능, `→` 대신 `->` 도 인정)
#   조건이 없는 주석은 `no-trigger` 로 표시한다 — "나중에" 가 조용히 "영원히" 가 되는 것을 드러내는 신호다.
# 스캔 범위: git 추적 파일(없으면 find). `*.md` 는 규약을 설명하는 산문이 장부를 오염시키므로 제외하고,
#   `.specops/`·node_modules·dist·build 도 제외한다. 주석 접두가 앞서야 매치한다(산문 속 언급은 무시).
set -u
ROOT="${1:-.}"
[ -d "$ROOT" ] || { echo "scan-shortcuts: 디렉터리 아님 — $ROOT" >&2; exit 0; }
cd "$ROOT" || exit 0

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  files=$(git ls-files 2>/dev/null)
else
  files=$(find . -type f -not -path './.git/*' 2>/dev/null | sed 's|^\./||')
fi
files=$(printf '%s\n' "$files" | grep -v -E '(^|/)(node_modules|dist|build|\.specops)/|\.md$' )

n=0; nt=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # 줄 번호와 함께 주석 접두 + shortcut: 만 매치 (바이너리 -I 제외)
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    ln=${hit%%:*}; body=${hit#*:}
    note=$(printf '%s' "$body" | sed -E 's/^.*(#|\/\/|\/\*|--) ?shortcut: ?//; s/[[:space:]]*\*\/[[:space:]]*$//')
    n=$((n+1))
    case "$note" in
      *"→"*|*"->"*) printf '%s:%s  %s\n' "$f" "$ln" "$note" ;;
      *) nt=$((nt+1)); printf '%s:%s  %s  [no-trigger]\n' "$f" "$ln" "$note" ;;
    esac
  done < <(grep -n -I -E '(#|//|/\*|--) ?shortcut: ' "$f" 2>/dev/null)
done <<< "$files"

if [ "$n" -eq 0 ]; then
  echo "No shortcut: debt. Clean ledger."
else
  echo "$n markers, $nt with no trigger."
fi
exit 0
