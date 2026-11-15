#!/usr/bin/env bash
# screen-shot.sh — 화면 목업(또는 URL)을 넓은 폭·좁은 폭 두 장으로 찍는다 (20261109-screen-quality)
# Usage: screen-shot.sh <html 파일|URL> <출력 접두 경로>
#   → <접두>@1280.png (1280×1000) · <접두>@390.png (390×1400) 를 만들고 경로를 한 줄씩 낸다.
# 출력:
#   SCREEN-SHOT: <경로>                       (장마다)
#   SCREEN-SHOT: SKIP (찍지 못함 — <사유>)      (Chrome 을 찾지 못함 — 통과로 위장하지 않는다)
# rc: 0 = 두 장 다 찍음 · 3 = 찍지 못함(SKIP) · 2 = 인자 오류
# 불변식: <접두>.probe.txt 는 직전 촬영과 같은 시점의 결과이거나 없다(시작할 때 지운다).
# 배치 계측: 두 장을 찍은 뒤 ui-probe.cjs 로 가로 잘림·글자 겹침을 재서 <접두>.probe.txt 에 남긴다(찍을 때마다 덮어쓴다).
#   내용은 셋 중 하나 — 경고 줄들 · "배치 경고 0건 …" · "UI-PROBE: SKIP (…)". 계측은 rc 를 바꾸지 않는다. 끄려면 SCREEN_SHOT_PROBE=0.
#   배치 줄 뒤에 접근성 결과가 이어진다 — `접근성 <critical|serious> <규칙>(<N>곳)` 줄과 요소 상세(선택자 · 대비 색 쌍) · "접근성 심각 0건 …" · "접근성 계측 못 함 …" 중 하나.
#   SCREEN-PROBE: <경로>   (계측 파일을 썼을 때 한 줄)
#   SCREEN-SHOT-FULL: <접두>@<폭>.full.png   (계측이 돌았을 때 폭마다 — 화면 전체 높이. 계측 도구가 없으면 없다)
#
# 왜: 설계 목업을 한 번도 렌더해 보지 않고 사용자에게 넘겼다. 다른 디자인 도구는 결과를 보고 다듬는다.
#   목업을 만든 뒤 이 두 장을 Read 로 열어 templates/screen-design-guide.md 의 자가 점검표로 1~2회 다듬는다.
# 브라우저: $SCREEN_SHOT_CHROME → macOS Google Chrome → PATH 의 google-chrome·chromium·chromium-browser → /opt/pw-browsers.
#   촬영 자체는 Playwright·Node 가 필요 없다(Chrome 헤드리스 스크린샷). 배치 계측(아래)만 Node + Playwright 를 쓰며 없으면 SKIP 한 줄로 남기고 촬영 rc 는 바꾸지 않는다. 웹폰트 로딩을 위해 virtual-time-budget 을 준다.
set -u
SRC="${1:-}"; OUT="${2:-}"
[ -n "$SRC" ] && [ -n "$OUT" ] || { echo "usage: $0 <html 파일|URL> <출력 접두 경로>" >&2; exit 2; }
case "$SRC" in
  http://*|https://*|file://*) URL="$SRC" ;;
  *) [ -f "$SRC" ] || { echo "screen-shot: 파일이 없다 — $SRC" >&2; exit 2; }
     URL="file://$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")" ;;
esac
mkdir -p "$(dirname "$OUT")" 2>/dev/null || { echo "screen-shot: 출력 폴더를 만들 수 없다 — $OUT" >&2; exit 2; }
rm -f "${OUT}.probe.txt" 2>/dev/null   # 불변식: probe.txt 는 이번 촬영과 같은 시점의 결과이거나 없다
rm -f "${OUT}@1280.full.png" "${OUT}@390.full.png" 2>/dev/null   # 전체 촬영도 같은 불변식

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
trap 'rm -rf "$TMPD"' EXIT   # 프로필·계측 산출물(전체 높이 PNG 포함)을 남기지 않는다 — 필요한 것은 끝나기 전에 꺼낸다
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
if [ "$rc" -eq 0 ] && [ "${SCREEN_SHOT_PROBE:-1}" != 0 ]; then
  PROBE_TXT="${OUT}.probe.txt"; PROBE_JS="$(cd "$(dirname "$0")" && pwd)/ui-probe.cjs"
  if ! command -v node >/dev/null 2>&1; then raw="UI-PROBE: SKIP (NO_TOOL — node 를 찾지 못했다)"
  else raw=$(node "$PROBE_JS" --out "$TMPD/probe" --widths 390,1280 "$URL" 2>"$TMPD/probe.err"); fi   # stdout 만 — stderr 경고가 판정 줄 앞에 끼지 않게
  first=$(printf '%s\n' "$raw" | grep -m1 '^UI-PROBE: ' || true)
  case "$first" in
    "UI-PROBE: SKIP"*) printf '%s\n' "$first" > "$PROBE_TXT" ;;
    "UI-PROBE: "*) hits=$(printf '%s\n' "$raw" | grep -E '^  - .*배치 (경고|계측 못 함)' || true)
      if [ -n "$hits" ]; then printf '%s\n' "$hits" > "$PROBE_TXT"; else echo "배치 경고 0건 (390·1280 폭 · 화면을 연 상태 기준 · 세로 잘림과 불투명한 층에 덮인 글자는 재지 않는다)" > "$PROBE_TXT"; fi
      # 접근성(대비 포함) — 심각한 위반 줄과 그 요소 상세를 이어 적는다. 위반이 없으면 0건 한 줄, axe-core 가 없으면 못 쟀다고 적는다(0 으로 쓰지 않는다)
      a11y=$(printf '%s\n' "$raw" | awk '/^  - .*접근성 (critical|serious) /{on=1; print; next} /^      · /{ if (on) print; next } { on=0 }')
      case "$first" in
        *"접근성 SKIP"*) echo "접근성 계측 못 함 (axe-core 없음 — 위반 없음이 아니다)" >> "$PROBE_TXT" ;;
        *) if [ -n "$a11y" ]; then printf '%s\n' "$a11y" >> "$PROBE_TXT"
           elif printf '%s\n' "$raw" | grep -q '^  - .*열기 실패'; then echo "접근성 계측 못 함 (화면을 열지 못했다 — 위반 없음이 아니다)" >> "$PROBE_TXT"   # 접근성은 가장 넓은 폭에서만 잰다 — 못 연 화면을 0건으로 쓰지 않는다
           else echo "접근성 심각 0건 (1280 폭 · 대비 포함 WCAG 2.1 AA)" >> "$PROBE_TXT"; fi ;;
      esac ;;
    *) echo "UI-PROBE: SKIP (NO_TOOL — 계측 출력을 읽지 못했다: $(sed -n 1p "$TMPD/probe.err" 2>/dev/null | cut -c1-120))" > "$PROBE_TXT" ;;
  esac
  echo "SCREEN-PROBE: $PROBE_TXT"
  # 화면 전체 — 계측이 찍은 전체 높이 PNG 를 꺼내 둔다(위 두 장은 높이가 고정이라 긴 화면의 아래쪽이 없다)
  for w in 390 1280; do
    full=$(ls "$TMPD/probe"/*@"$w".png 2>/dev/null | sed -n 1p)
    if [ -n "$full" ] && cp "$full" "${OUT}@${w}.full.png" 2>/dev/null; then echo "SCREEN-SHOT-FULL: ${OUT}@${w}.full.png"; fi
  done
fi
exit "$rc"
