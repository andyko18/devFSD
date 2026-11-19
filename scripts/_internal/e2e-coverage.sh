#!/usr/bin/env bash
# e2e-coverage.sh — 화면 수용 기준(AC)이 실제 브라우저 시나리오로 덮였는지 센다 (20261119 · 선택 기능 · 기본 끔)
#
# 사용: e2e-coverage.sh <FID> [--force]
#   --force   설정이 꺼져 있어도 센다(시범·점검용)
# 출력(마지막 줄):
#   E2E-COVERAGE: PASS (화면 AC <n>/<m> = <p>% · 기준 <t>% · 백엔드 <b> · 해당 없음 <k>)
#   E2E-COVERAGE: FAIL (… 같은 꼴 …)  또는  FAIL (분류 안 된 AC <N>건 | 사유 없는 제외 <N>건)
#   E2E-COVERAGE: SKIP (OFF|NO_AC|NO_SCOPE|NO_BROWSER_AC — 사유)   — 판정하지 못함. PASS 로 적지 않는다
#   그 위에 문제마다 `  - <AC> <내용>` 한 줄
# rc: 0 PASS · 1 FAIL · 3 SKIP · 2 사용법
#
# 왜 필요한가 (20261119 실측): 하류 프론트 테스트는 가짜 브라우저(jsdom)뿐이고, 브라우저 점검(ui-probe)은 화면을 여는 데까지만 본다.
#   포커스 이동·키보드·실제 내비게이션은 실제 브라우저에서만 드러난다. 비율을 세지 않으면 "E2E 를 붙였다"는 말만 남는다.
#
# 무엇을 읽나:
#   .specops/<FID>/acceptance-criteria.md   `### AC-<id>` 제목이 분모의 원천이다
#   .specops/<FID>/e2e-scope.txt            AC 마다 한 줄 — `AC-3 browser` · `AC-7 backend — <사유>` · `AC-15 none — <사유>`
#                                           모든 AC 가 있어야 한다(빠진 AC 가 있으면 FAIL — 분모를 조용히 줄이지 못하게).
#                                           backend·none 은 사유가 있어야 한다.
#   시나리오 파일                            이름이 `*.e2e.mjs|js|cjs` 이고 본문에 `FID: <FID>` 줄이 있는 파일의 `@AC-<id>` 태그
#                                           (node_modules·.git·dist·build 는 보지 않는다)
# 설정 (`.specops/config.yaml` 의 `browser_e2e:` 블록 · 환경변수 우선):
#   enabled: true|false     DEVFSD_BROWSER_E2E=1        (기본 false)
#   min_coverage: 95        DEVFSD_E2E_MIN_COVERAGE     (0~100 · 기본 95)
set -u

SPECOPS="${SPECOPS_ROOT:-.specops}"
CONFIG="${SPECOPS_CONFIG:-$SPECOPS/config.yaml}"

usage() { sed -n '4,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; }

cfg() {  # browser_e2e: 블록의 한 단계 키. 없으면 빈 문자열
  [ -r "$CONFIG" ] || return 0
  awk -v key="$1" '
    /^browser_e2e:[[:space:]]*(#.*)?$/ { inb = 1; next }
    inb && /^[^[:space:]#]/ { inb = 0 }
    inb {
      line = $0; sub(/[[:space:]]+#.*$/, "", line)
      if (match(line, "^[[:space:]]+" key ":[[:space:]]*")) {
        v = substr(line, RLENGTH + 1); sub(/[[:space:]]+$/, "", v); gsub(/^["\047]|["\047]$/, "", v); print v; exit
      }
    }' "$CONFIG"
}

FID="${1:-}"; FORCE=0
[ "${2:-}" = "--force" ] && FORCE=1
case "$FID" in ''|*/*|*..*|-*) usage; exit 2 ;; esac

skip() { echo "E2E-COVERAGE: SKIP ($1)"; exit 3; }

enabled="${DEVFSD_BROWSER_E2E:-}"; [ -n "$enabled" ] || enabled=$(cfg enabled)
case "$(printf '%s' "$enabled" | tr 'A-Z' 'a-z')" in
  true|yes|on|1) : ;;
  *) [ "$FORCE" = 1 ] || skip "OFF — config browser_e2e.enabled: true 로 켠다" ;;
esac

min="${DEVFSD_E2E_MIN_COVERAGE:-}"; [ -n "$min" ] || min=$(cfg min_coverage)
case "$min" in ''|*[!0-9]*) min=95 ;; esac
[ "$min" -le 100 ] || min=100

AC_FILE="$SPECOPS/$FID/acceptance-criteria.md"
SCOPE="$SPECOPS/$FID/e2e-scope.txt"
[ -r "$AC_FILE" ] || skip "NO_AC — $AC_FILE 없음"
acs=$(grep -oE '^### AC-[A-Za-z0-9-]+' "$AC_FILE" | sed 's/^### //' | sort -u)
[ -n "$acs" ] || skip "NO_AC — $AC_FILE 에 \`### AC-<id>\` 제목이 없다"
[ -r "$SCOPE" ] || skip "NO_SCOPE — $SCOPE 없음(AC 마다 browser|backend|none 한 줄)"

# 시나리오 파일의 태그 — 이 FID 표지가 있는 파일만
tags=$(find . \( -name node_modules -o -name .git -o -name dist -o -name build \) -prune -o \
         -type f \( -name '*.e2e.mjs' -o -name '*.e2e.js' -o -name '*.e2e.cjs' \) -print 2>/dev/null \
       | while IFS= read -r f; do
           grep -qE "FID:[[:space:]]*$FID([^A-Za-z0-9-]|\$)" "$f" 2>/dev/null || continue
           grep -oE '@AC-[A-Za-z0-9-]+' "$f" | sed 's/^@//'
         done | sort -u)

problems=""; n_browser=0; n_cover=0; n_backend=0; n_none=0; n_unclassified=0; n_noreason=0
while IFS= read -r ac; do
  [ -n "$ac" ] || continue
  line=$(grep -E "^${ac}[[:space:]]" "$SCOPE" | head -n 1)
  kind=$(printf '%s' "$line" | awk '{print $2}')
  reason=$(printf '%s' "$line" | sed -E "s/^${ac}[[:space:]]+[a-z]+[[:space:]]*(—|-)?[[:space:]]*//")
  case "$kind" in
    browser)
      n_browser=$((n_browser + 1))
      if printf '%s\n' "$tags" | grep -qx "$ac"; then n_cover=$((n_cover + 1)); else problems="$problems  - $ac 시나리오 없음(@$ac 태그를 단 *.e2e 파일이 없다)\n"; fi ;;
    backend|none)
      [ "$kind" = backend ] && n_backend=$((n_backend + 1)) || n_none=$((n_none + 1))
      if [ -z "$reason" ]; then n_noreason=$((n_noreason + 1)); problems="$problems  - $ac $kind 인데 사유가 없다\n"; fi ;;
    *)
      n_unclassified=$((n_unclassified + 1)); problems="$problems  - $ac 분류 없음($SCOPE 에 browser|backend|none 한 줄이 필요하다)\n" ;;
  esac
done <<EOF
$acs
EOF

# 문서에 없는 AC 를 가리키는 태그는 알리기만 한다(오타·옛 번호)
while IFS= read -r t; do
  [ -n "$t" ] || continue
  printf '%s\n' "$acs" | grep -qx "$t" || problems="$problems  - $t 태그가 가리키는 AC 가 문서에 없다(경고)\n"
done <<EOF
$tags
EOF

[ -n "$problems" ] && printf '%b' "$problems"
if [ "$n_unclassified" -gt 0 ] || [ "$n_noreason" -gt 0 ]; then
  echo "E2E-COVERAGE: FAIL (분류 안 된 AC ${n_unclassified}건 · 사유 없는 제외 ${n_noreason}건)"; exit 1
fi
[ "$n_browser" -gt 0 ] || skip "NO_BROWSER_AC — 브라우저로 볼 AC 가 없다(백엔드 $n_backend · 해당 없음 $n_none)"

pct=$((n_cover * 100 / n_browser))
summary="화면 AC $n_cover/$n_browser = ${pct}% · 기준 ${min}% · 백엔드 $n_backend · 해당 없음 $n_none"
if [ "$pct" -ge "$min" ]; then echo "E2E-COVERAGE: PASS ($summary)"; exit 0; fi
echo "E2E-COVERAGE: FAIL ($summary)"; exit 1
