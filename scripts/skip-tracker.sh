#!/usr/bin/env bash
# specops-ko SKIP 추적 관측 도구 (읽기 전용)
# 사용: bash scripts/skip-tracker.sh [.specops 경로]
# 소스 가능 — 함수만 정의, main 은 가드. integration/performance/security 게이트 SKIP 비율 집계.
# 환경: SKIP_TRACKER_THRESHOLD (기본 70) — SKIP 비율 advisory 경고 임계
set -uo pipefail

# 게이트 short 이름 → evidence.md 섹션 헤더 토큰 매핑.
#   integration/performance 는 '-test' 접미, security 는 '-review' 접미(헤더 불일치) — 하드코딩 '-test'
#   패턴은 security 를 못 잡았다(버그1: security-review-ko L42 관측 死문). 매핑으로 3게이트 정합.
skip::header() {  # <gate short> → 헤더 토큰
  case "$1" in
    integration) echo integration-test ;;
    performance) echo performance-test ;;
    security)    echo security-review ;;
    *)           echo "${1}-test" ;;   # 미지 게이트 하위호환(구 동작)
  esac
}

skip::verdicts() {  # <file> <gate: integration|performance|security>
  local file="$1" gate="$2"
  [ -f "$file" ] || return 0
  awk -v hdr="^## /$(skip::header "$gate")" '
    $0 ~ hdr {
      if ($0 ~ /SKIP/)      { print "SKIP"; pending=0 }
      else if ($0 ~ /PASS/) { print "PASS"; pending=0 }
      else if ($0 ~ /FAIL/) { print "FAIL"; pending=0 }
      else                  { pending=1 }
      next
    }
    /^## / { pending=0; next }   # 비게이트 섹션 헤더 도달 → pending 리셋 (인접 섹션 오연관 차단 — Phase C Important)
    pending && /^\*\*결과\*\*:/ {
      if ($0 ~ /SKIP/)      print "SKIP"
      else if ($0 ~ /PASS/) print "PASS"
      else if ($0 ~ /FAIL/) print "FAIL"
      pending=0
    }
  ' "$file"
}

skip::cite_status() {  # <file> <gate> → CITED|BARE per SKIP (라인인용 §...L<n> 또는 L<n> 유무)
  local file="$1" gate="$2"
  [ -f "$file" ] || return 0
  awk -v hdr="^## /$(skip::header "$gate")" -v cite='L[0-9]|§[^ ]*[0-9]' '
    # ★ 헤더가 SKIP 을 달고 있어도 **즉시 판정하지 않는다** (20260829-bare-skip-teeth).
    #   evidence 실물은 두 형태가 섞인다: `## /gate` + `**결과**: SKIP` (템플릿) 와
    #   `## /gate SKIP` (헤더 겸용). 종전 코드는 후자에서 헤더 한 줄만 보고 BARE 로 확정해,
    #   바로 다음 `**근거**: §범위 L12-15` 를 **읽지도 않고** 정직한 인용을 bare 로 셌다.
    #   그 오판정이 그대로 계측에 들어가 bare 건수를 부풀렸다(이 게이트를 하드로 올리기 직전
    #   실측에서 적발 — advisory 였을 때는 아무도 틀렸다는 걸 몰랐다).
    #   헤더 자체에 인용이 있으면 CITED 확정, 없으면 근거 줄까지 유예한다.
    $0 ~ hdr {
      if (skipwait) { print "BARE"; skipwait=0 }
      if ($0 ~ /SKIP/) {
        if ($0 ~ cite) { print "CITED"; skipwait=0 } else { skipwait=1 }
        pending=0
      }
      else { pending=1; skipwait=0 }
      next
    }
    /^## / { if (skipwait) { print "BARE"; skipwait=0 } pending=0; next }
    pending && /^\*\*결과\*\*:/ {
      if ($0 ~ /SKIP/) { skipwait=1 } else { pending=0 }
      next
    }
    skipwait && /^\*\*근거\*\*:/ {
      print ($0 ~ cite) ? "CITED" : "BARE"
      skipwait=0; pending=0
    }
    END { if (skipwait) print "BARE" }
  ' "$file"
}

skip::count() {  # <dir> <gate> → "PASS SKIP FAIL"
  # 파일마다 프로세스 치환을 열지 않는다 — bash 3.2(macOS 기본)는 evidence 160개 규모에서 skip::report 가
  #   프로세스 치환을 수백 번 열다 Abort trap/Bus error 로 죽었다(20261110 실측 5/5). 판정 줄을 한 파이프로 모아 센다.
  local dir="$1" gate="$2" file
  for file in "$dir"/*/evidence.md; do
    [ -f "$file" ] || continue
    skip::verdicts "$file" "$gate"
  done | awk '$0 == "PASS" { p++ } $0 == "SKIP" { s++ } $0 == "FAIL" { f++ } END { printf "%d %d %d\n", p + 0, s + 0, f + 0 }'
}

skip::rate() {  # <skip> <total> → 백분율 정수
  local s="$1" total="$2"
  [ "$total" -eq 0 ] && { echo 0; return 0; }
  echo $(( s * 100 / total ))
}

skip::report() {  # <dir>
  local dir="$1" thr="${SKIP_TRACKER_THRESHOLD:-70}" bthr="${SKIP_TRACKER_BARE_THRESHOLD:-0}"
  local any=0 file
  for file in "$dir"/*/evidence.md; do [ -f "$file" ] && { any=1; break; }; done
  [ "$any" -eq 0 ] && { echo "SKIP-TRACKER: evidence 없음 ($dir)"; return 0; }
  local g p s f total rate bare v
  for g in integration performance security; do
    read -r p s f <<EOF
$(skip::count "$dir" "$g")
EOF
    total=$(( p + s + f ))
    rate=$(skip::rate "$s" "$total")
    bare=$(for file in "$dir"/*/evidence.md; do
      [ -f "$file" ] || continue
      skip::cite_status "$file" "$g"
    done | awk '$0 == "BARE" { n++ } END { printf "%d\n", n + 0 }')
    local warn=""
    [ "$bare" -gt "$bthr" ] && warn="  ⚠️ 근거 없는 SKIP ${bare}건 (>${bthr})"
    echo "${g}: total=${total} PASS=${p} SKIP=${s} FAIL=${f} (SKIP ${rate}% 참고) bare=${bare}${warn}"
  done
  return 0
}

skip::default_root() {  # 인자 없는 호출의 기본 .specops — 호출 위치 git 루트, git 밖이면 ./.specops
  #   스크립트 옆 .specops 를 보면 설치본(플러그인 캐시)에서는 항상 "evidence 없음" 이다.
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ] && { printf '%s/.specops\n' "$top"; return 0; }
  printf '%s/.specops\n' "$PWD"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  root="${1:-$(skip::default_root)}"
  skip::report "$root"
fi
