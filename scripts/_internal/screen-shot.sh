#!/usr/bin/env bash
# screen-shot.sh — 화면 목업(또는 URL)을 넓은 폭·좁은 폭 두 장으로 찍는다 (20261109-screen-quality)
# Usage: screen-shot.sh <html 파일|URL> <출력 접두 경로>
#   → <접두>@1280.png (1280×1000) · <접두>@390.png (390×1400) 를 만들고 경로를 한 줄씩 낸다.
# 출력:
#   SCREEN-SHOT: <경로>                       (장마다)
#   SCREEN-SHOT: SKIP (찍지 못함 — <사유>)      (Chrome 을 찾지 못함 — 통과로 위장하지 않는다)
# rc: 0 = 두 장 다 찍음 · 3 = 찍지 못함(SKIP) · 2 = 인자 오류
#
# 왜: 설계 목업을 한 번도 렌더해 보지 않고 사용자에게 넘겼다. 다른 디자인 도구는 결과를 보고 다듬는다.
#   목업을 만든 뒤 이 두 장을 Read 로 열어 templates/screen-design-guide.md 의 자가 점검표로 1~2회 다듬는다.
# 브라우저: $SCREEN_SHOT_CHROME → macOS Google Chrome → PATH 의 google-chrome·chromium·chromium-browser → /opt/pw-browsers.
#   Playwright 나 Node 가 필요 없다(Chrome 헤드리스 스크린샷). 웹폰트 로딩을 위해 virtual-time-budget 을 준다.
set -u
SRC="${1:-}"; OUT="${2:-}"
[ -n "$SRC" ] && [ -n "$OUT" ] || { echo "usage: $0 <html 파일|URL> <출력 접두 경로>" >&2; exit 2; }
case "$SRC" in
  http://*|https://*|file://*) URL="$SRC" ;;
  *) [ -f "$SRC" ] || { echo "screen-shot: 파일이 없다 — $SRC" >&2; exit 2; }
     URL="file://$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")" ;;
esac
mkdir -p "$(dirname "$OUT")" 2>/dev/null || { echo "screen-shot: 출력 폴더를 만들 수 없다 — $OUT" >&2; exit 2; }

CHROME=""
# SCREEN_SHOT_CHROME 를 주면 그것만 쓴다(다른 후보로 넘어가지 않는다 — 사용자 지정·테스트)
if [ -n "${SCREEN_SHOT_CHROME:-}" ]; then
  [ -x "$SCREEN_SHOT_CHROME" ] && CHROME="$SCREEN_SHOT_CHROME"
  [ -n "$CHROME" ] || { echo "SCREEN-SHOT: SKIP (찍지 못함 — SCREEN_SHOT_CHROME 실행 파일이 없다: $SCREEN_SHOT_CHROME)"; exit 3; }
fi
[ -n "$CHROME" ] || for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "$(command -v google-chrome 2>/dev/null)" "$(command -v chromium 2>/dev/null)" "$(command -v chromium-browser 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] && { CHROME="$c"; break; }
done
if [ -z "$CHROME" ]; then
  for c in /opt/pw-browsers/chromium*/chrome-linux/chrome /opt/pw-browsers/chromium; do [ -x "$c" ] && { CHROME="$c"; break; }; done
fi
[ -n "$CHROME" ] || { echo "SCREEN-SHOT: SKIP (찍지 못함 — Chrome·Chromium 을 찾지 못했다. SCREEN_SHOT_CHROME 로 경로를 줄 수 있다. 앱 안 브라우저가 있으면 그것으로 찍는다)"; exit 3; }

# 데스크톱 Chrome 은 헤드리스에서도 창 최소 폭이 500px 이다(실측: --window-size=390 → innerWidth 500).
#   그래서 좁은 폭은 정확한 폭의 iframe 을 가운데 둔 감싸개 페이지를 500 폭으로 찍고, macOS 면 sips 로 가운데를 잘라
#   정확히 그 폭의 이미지를 만든다(sips 가 없으면 500 폭 이미지 그대로 — 좌우 여백이 감싸개다).
MIN_W=500
TMPD=$(mktemp -d 2>/dev/null || echo "/tmp/screen-shot-$$"); mkdir -p "$TMPD"
rc=0
for spec in "1280 1000" "390 1400"; do
  set -- $spec; w=$1; h=$2; png="${OUT}@${w}.png"; target="$URL"; win=$w
  rm -f "$png" 2>/dev/null
  if [ "$w" -lt "$MIN_W" ]; then
    printf '<!DOCTYPE html><html><body style="margin:0;background:#fff"><iframe src="%s" style="display:block;margin:0 auto;border:0;width:%spx;height:%spx"></iframe></body></html>' \
      "$URL" "$w" "$h" > "$TMPD/wrap-$w.html"
    target="file://$TMPD/wrap-$w.html"; win=$MIN_W
  fi
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run --no-default-browser-check \
    --allow-file-access-from-files --user-data-dir="$TMPD/profile-$w" \
    --window-size="${win},${h}" --virtual-time-budget=3000 --screenshot="$png" "$target" >/dev/null 2>&1
  if [ -s "$png" ] && [ "$win" != "$w" ] && command -v sips >/dev/null 2>&1; then
    sips --cropToHeightWidth "$h" "$w" "$png" >/dev/null 2>&1 || true
  fi
  if [ -s "$png" ]; then echo "SCREEN-SHOT: $png"
  else echo "SCREEN-SHOT: SKIP (찍지 못함 — ${w} 폭 촬영 실패: $CHROME)"; rc=3; fi
done
exit "$rc"
