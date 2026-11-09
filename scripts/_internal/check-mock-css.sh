#!/usr/bin/env bash
# check-mock-css.sh — 목업 클래스가 앱 CSS 에 얼마나 살아남았나 (경고 전용 · 20261109-mock-css-transplant)
# Usage: check-mock-css.sh [저장소 루트(기본 .)]
# 출력 1줄(+경고면 빠진 클래스 목록):
#   MOCK-CSS: OK <pct>% (<살아남음>/<목업 정의>)
#   MOCK-CSS: WARN <pct>% (<k>/<n>) — 빠진 것: <클래스 최대 12개>
#   MOCK-CSS: SKIP (<사유>)            — 목업 없음 · 앱 CSS 없음 · Tailwind · 목업에 클래스 정의 없음
# rc: 0 = 판정(OK·WARN·SKIP 모두 — 막지 않는다) · 2 = 인자 오류(없는 폴더)
#
# 왜: 디자인 진단(2026-11-09)에서 같은 날 만든 두 앱이 목업 클래스 생존율 8%(stock-mng — 입력·버튼 14/14 가
#   브라우저 기본 모양)와 91%(media)로 갈렸다. 목업의 스타일을 앱으로 옮기라는 지시·검사가 체인에 없었다.
# 무엇을 세나: screens/*.html 의 <style> 안에서 **정의된** 클래스(선택자의 `.이름`) 중, 앱 CSS 파일
#   (*.css·*.scss·*.sass·*.less — node_modules·.next·dist·build·out·coverage·.git·.specops·screens 제외)에서도
#   정의된 것의 비율. 이름 일치만 본다 — 같은 이름에 다른 스타일이면 못 잡고, CSS-in-JS(styled-components 등)는
#   보지 못한다(그때 앱 CSS 없음 SKIP 또는 낮은 비율로 나온다 — 문구가 그렇다고 말한다).
# Tailwind 앱은 유틸리티 클래스라 목업 이름과 원래 다르다 → 생존율로 판정하지 않고 SKIP.
set -u
ROOT="${1:-.}"
[ -d "$ROOT" ] || { echo "check-mock-css: 폴더가 없다 — $ROOT" >&2; exit 2; }
WARN_BELOW=50   # 이 비율(%) 미만이면 WARN

_classes() {  # stdin = CSS 텍스트 → 정의된 클래스 이름(정렬·중복 제거). 숫자로 시작(.5s)·파일 확장자(.png)는 제외
  grep -oE '\.[A-Za-z_-][A-Za-z0-9_-]*' \
    | sed 's/^\.//' \
    | grep -vxE 'png|jpe?g|gif|svg|webp|avif|ico|woff2?|ttf|otf|eot|css|js|mjs|html' \
    | LC_ALL=C sort -u
}

shopt -s nullglob
mocks=("$ROOT"/screens/*.html)
shopt -u nullglob
[ "${#mocks[@]}" -gt 0 ] || { echo "MOCK-CSS: SKIP (목업 없음 — screens/*.html 이 없다)"; exit 0; }

mock_cls=$(for f in "${mocks[@]}"; do
  awk 'BEGIN{IGNORECASE=1} /<style[^>]*>/{f=1; sub(/.*<style[^>]*>/,"")} f{ if (/<\/style>/) { sub(/<\/style>.*/,""); print; f=0 } else print }' "$f"
done | sed 's/{[^}]*}//g' | _classes)
[ -n "$mock_cls" ] || { echo "MOCK-CSS: SKIP (목업에 클래스 정의 없음)"; exit 0; }

app_css=$(find "$ROOT" \( -name node_modules -o -name .next -o -name dist -o -name build -o -name out -o -name coverage \
  -o -name .git -o -name .specops -o -name screens \) -prune -o -type f \( -name '*.css' -o -name '*.scss' -o -name '*.sass' -o -name '*.less' \) -print 2>/dev/null)
[ -n "$app_css" ] || { echo "MOCK-CSS: SKIP (앱 CSS 없음 — *.css·*.scss 파일이 없다. CSS-in-JS 면 이 검사가 보지 못한다)"; exit 0; }

if printf '%s\n' "$app_css" | while IFS= read -r f; do grep -qE '@tailwind|@import[[:space:]]+["'"'"']tailwindcss' "$f" 2>/dev/null && exit 0; done; then
  echo "MOCK-CSS: SKIP (Tailwind — 유틸리티 클래스라 목업 이름과 원래 다르다. 목업 토큰이 tailwind 설정으로 옮겨졌는지는 사람이 본다)"; exit 0
fi
find "$ROOT" -maxdepth 3 -name 'tailwind.config.*' -not -path '*/node_modules/*' 2>/dev/null | grep -q . \
  && { echo "MOCK-CSS: SKIP (Tailwind — 유틸리티 클래스라 목업 이름과 원래 다르다. 목업 토큰이 tailwind 설정으로 옮겨졌는지는 사람이 본다)"; exit 0; }

app_cls=$(printf '%s\n' "$app_css" | while IFS= read -r f; do sed 's/{[^}]*}//g' "$f" 2>/dev/null; done | _classes)
n=$(printf '%s\n' "$mock_cls" | grep -c .)
missing=$(LC_ALL=C comm -23 <(printf '%s\n' "$mock_cls") <(printf '%s\n' "$app_cls"))
m=$(printf '%s' "$missing" | grep -c .)
k=$((n - m)); pct=$((k * 100 / n))
if [ "$pct" -lt "$WARN_BELOW" ]; then
  echo "MOCK-CSS: WARN ${pct}% (${k}/${n}) — 목업 클래스 대부분이 앱 CSS 에 없다(화면이 브라우저 기본 모양일 수 있다). 빠진 것: $(printf '%s\n' "$missing" | head -12 | tr '\n' ' ')"
else
  echo "MOCK-CSS: OK ${pct}% (${k}/${n})"
fi
exit 0
