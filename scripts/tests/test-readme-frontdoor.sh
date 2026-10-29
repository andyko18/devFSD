#!/usr/bin/env bash
# README 대문 불변식 (FID 20261012-readme-redesign)
#   히어로·배지·카드·정직한 박스가 `## 설치` 보다 앞 · 정적 버전 배지 금지 · 히어로 SVG 의 well-formed·외부 참조 0·라이트/다크 규칙 ·
#   README 와 docs/adoption-notes.md 의 로컬 링크 해석 · 이동한 9절 존재 · Mermaid 블록 존재.
#   각 검사는 사본 트리에 위반을 하나씩 주입해 그 코드가 정확히 나오는지 본다(변이 주입) — 항상 통과하는 검사를 막는다.
#   F10 은 `validate-structure` version_sync 가 버전 줄이 없으면 조용히 OK 를 내는 틈을 막는다(조립 중 푸터가 사라진 실측 20261012).
#   F7 은 인라인 링크 `](경로)` 와 src/srcset 의 로컬 경로만 본다 — 참조형 링크·공백/괄호가 든 경로·#앵커 유효성은 보지 못한다.
#   실 트리는 읽기만 한다. Mermaid 문법·SVG 렌더는 이 스위트가 보지 못한다(네트워크·브라우저 필요) — 구현 FID 의 evidence 에 따로 적는다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
if ! command -v python3 >/dev/null 2>&1; then skip "python3 없음 — 대문 불변식 검사 불가"; finish; exit $?; fi

# frontdoor_check <루트> → 위반 코드를 줄마다 출력한다(위반이 없으면 무출력)
frontdoor_check() {
  local root="$1" rd="$1/README.md" svg="$1/docs/assets/hero.svg" notes="$1/docs/adoption-notes.md"
  local l_hero l_badge l_cards l_box l_inst f h
  l_hero=$(grep -n 'docs/assets/hero.svg' "$rd" | head -1 | cut -d: -f1)
  l_badge=$(grep -nE 'img\.shields\.io|badge\.svg' "$rd" | head -1 | cut -d: -f1)
  l_cards=$(grep -n '^## 왜 쓰나' "$rd" | head -1 | cut -d: -f1)
  l_box=$(grep -n '보장하지 않는 것' "$rd" | head -1 | cut -d: -f1)
  l_inst=$(grep -n '^## 설치' "$rd" | head -1 | cut -d: -f1)
  [ -n "$l_hero" ] || echo "F1-hero-ref"
  if [ -n "$l_hero" ] && [ -n "$l_badge" ] && [ -n "$l_cards" ] && [ -n "$l_box" ] && [ -n "$l_inst" ] \
     && [ "$l_hero" -lt "$l_badge" ] && [ "$l_badge" -lt "$l_cards" ] && [ "$l_cards" -lt "$l_box" ] && [ "$l_box" -lt "$l_inst" ]; then
    :
  else
    echo "F2-order"
  fi
  grep -E 'img\.shields\.io|badge\.svg' "$rd" | grep -qE '[0-9]+\.[0-9]+(\.[0-9]+)?|[=(/-]v[0-9]' && echo "F3-static-version"
  grep -q 'github/v/release/andyko18/devFSD' "$rd" || echo "F3-no-dynamic-release"
  if [ -f "$svg" ]; then
    python3 -I -c 'import sys, xml.etree.ElementTree as E; E.parse(sys.argv[1])' "$svg" 2>/dev/null || echo "F4-svg-malformed"
    grep -qiE "(href|src)=[\"']https?:|url\([\"']?https?:|@import|<script" "$svg" && echo "F5-svg-external"
    { grep -q 'prefers-color-scheme: dark' "$svg" && grep -q '<title' "$svg"; } || echo "F6-svg-theme"
  else
    echo "F4-svg-missing"
  fi
  for f in "$rd" "$notes"; do
    if [ ! -f "$f" ]; then
      [ "$f" = "$notes" ] && echo "F8-notes-missing"
      continue
    fi
    python3 -I - "$f" 2>/dev/null <<'PY' || echo "F7-broken-link"
import os, re, sys
path = sys.argv[1]
base = os.path.dirname(path)
text = open(path, encoding="utf-8").read()
text = re.sub(r"```.*?```", "", text, flags=re.S)
targets = re.findall(r"\]\(([^)\s]+)\)", text) + re.findall(r"(?:src|srcset)=\"([^\"]+)\"", text)
bad = [t for t in targets
       if not re.match(r"^(https?:|mailto:|#)", t)
       and t.split("#", 1)[0]
       and not os.path.exists(os.path.join(base, t.split("#", 1)[0]))]
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
PY
  done
  if [ -f "$notes" ]; then
    for h in '필요한 도구' '한 건에 걸리는 시간' '적용 범위' '저장소에 생기는 변화' '끄는 법' '산출물은 기본적으로 로컬이다' '설계를 한 화면에서 보기' '데이터와 프라이버시' '업그레이드 · 삭제'; do
      grep -qxF "### $h" "$notes" || echo "F8-notes-heading"
    done
  fi
  [ "$(grep -c '^```mermaid' "$rd")" -ge 3 ] || echo "F9-mermaid"
  { head -15 "$rd" | grep -qE '\(v[0-9]+\.[0-9]+\.[0-9]+\)' && grep -qE '최신: v[0-9]+\.[0-9]+\.[0-9]+' "$rd"; } || echo "F10-version-stamps"
}

# ── FD-0: 실 트리 ──
out=$(frontdoor_check "$PLUGIN" | sort -u)
if [ -z "$out" ]; then ok "FD-0 실 트리: 대문 불변식 위반 0"; else nope "FD-0 실 트리" "$(echo $out)"; fi

# ── FD-m: 사본 트리에 위반을 하나씩 주입 → 그 코드가 나와야 한다 ──
SB=$(mktemp -d) || exit 1
trap 'rm -rf "$SB"' EXIT
T="$SB/t"
fresh() {
  rm -rf "$T"; mkdir -p "$T"
  cp "$PLUGIN/README.md" "$PLUGIN/CLAUDE.md" "$PLUGIN/LICENSE" "$T/" 2>/dev/null
  cp -R "$PLUGIN/docs" "$T/docs"
}
edit() { local f="$1"; shift; [ -f "$f" ] || return 0; sed "$@" "$f" > "$f.new" && mv "$f.new" "$f"; }   # BSD·GNU sed 공통 — -i 를 쓰지 않는다
inject() {   # <기대 코드> <설명> — 변이는 호출 전에 $T 에 적용한다
  local want="$1" desc="$2" got
  got=$(frontdoor_check "$T" | sort -u)
  if printf '%s\n' "$got" | grep -qxF "$want"; then ok "FD-m $desc → $want"; else nope "FD-m $desc" "기대 $want · 실제: $(echo $got)"; fi
}

fresh
got=$(frontdoor_check "$T" | sort -u)
if [ "$got" = "$out" ]; then ok "FD-m0 사본 기준선이 실 트리와 같다"; else nope "FD-m0" "사본 기준선 불일치: $(echo $got)"; fi

fresh; edit "$T/README.md" -e '/docs\/assets\/hero\.svg/d';                          inject "F1-hero-ref" "히어로 참조 삭제"
fresh; { printf '## 설치\n'; cat "$T/README.md"; } > "$T/R.new" && mv "$T/R.new" "$T/README.md"; inject "F2-order" "설치 헤딩을 맨 위로"
fresh; awk '{print} /img\.shields\.io|badge\.svg/ && !d {print "[![v](https://img.shields.io/badge/version-2.20.2-blue)](https://x)"; d=1}' "$T/README.md" > "$T/R.new" && mv "$T/R.new" "$T/README.md"; inject "F3-static-version" "정적 버전 배지 삽입"
fresh; awk '{print} /img\.shields\.io|badge\.svg/ && !d {print "[![v](https://img.shields.io/badge/version-2.20-blue)](https://x)"; d=1}' "$T/README.md" > "$T/R.new" && mv "$T/R.new" "$T/README.md"; inject "F3-static-version" "점 두 개짜리 정적 버전 배지 삽입"
fresh; edit "$T/README.md" -e 's#github/v/release#github/license#';                  inject "F3-no-dynamic-release" "동적 릴리즈 배지 제거"
fresh; rm -f "$T/docs/assets/hero.svg";                                              inject "F4-svg-missing" "SVG 삭제"
fresh; edit "$T/docs/assets/hero.svg" -e '/<\/svg>/d';                               inject "F4-svg-malformed" "SVG 닫는 태그 삭제"
fresh; edit "$T/docs/assets/hero.svg" -e 's#</svg>#<image href="https://example.com/x.png"/></svg>#'; inject "F5-svg-external" "SVG 외부 이미지 삽입"
fresh; edit "$T/docs/assets/hero.svg" -e 's/prefers-color-scheme: dark/prefers-color-scheme: light/'; inject "F6-svg-theme" "SVG 다크 규칙 제거"
fresh; printf '\n[x](docs/nope.md)\n' >> "$T/README.md";                              inject "F7-broken-link" "깨진 링크 추가"
fresh; rm -f "$T/docs/adoption-notes.md";                                            inject "F8-notes-missing" "adoption-notes 삭제"
fresh; edit "$T/docs/adoption-notes.md" -e '/^### 끄는 법/d';                         inject "F8-notes-heading" "9절 헤딩 하나 삭제"
fresh; edit "$T/README.md" -e 's/^```mermaid/```text/';                              inject "F9-mermaid" "Mermaid 블록 해제"
fresh; edit "$T/README.md" -e '/최신: v/d';                                         inject "F10-version-stamps" "푸터 버전 스탬프 줄 삭제"
fresh; edit "$T/README.md" -e 's/(v[0-9][0-9.]*)/(버전)/';                              inject "F10-version-stamps" "헤더 버전 표기 삭제"

finish
