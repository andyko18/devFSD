#!/usr/bin/env bash
# scan-enrich-placeholders.sh — Phase 11 보강 후 원시 placeholder 스캔 (e2e V21 판정의 SoT)
# 사용: scan-enrich-placeholders.sh <file...>
#   exit 0 = 검출 없음(clean) · exit 1 = 검출 있음(file:line 출력) · exit 2 = 사용 오류
#
# 제외 3계층:
#   ⓪ 토큰 단위 — **HTML 주석** `<!-- ... -->` (20260806 실측 결함):
#      모든 specops 템플릿이 `<!-- OWNER_COMMAND: ... -->`·`<!-- layer: ... -->` 헤더를 갖는다.
#      이건 구조 계약이라 **지울 수 없는데** 구 패턴이 placeholder 로 셌다 → e2e V21(검출 0)이
#      구조적으로 달성 불가였다(부트스트랩 산출물 163건 중 26건이 이 주석).
#      주석 **밖** 실 placeholder 는 검출을 유지해야 하므로 줄 단위가 아니라 토큰 단위로 지운다.
#   ① 줄 단위 — `미확정 — 근거 필요` 마커 줄 (Phase 11 계약상 허용)
#   ② 토큰 단위 — 규약 표기 (채움 대상 아닌 문서 본문 서술; 문맥 포함 매칭이라
#      같은 줄의 실 placeholder 는 검출 유지):
#      .specops/<FID> · screens/<name> · design-screen <name> · <YYYYMMDDHHMMSS>_<description>
#      · <feature> 경로/테스트 표기 · "<UI 기능>" · "<첫 기능>"
#      · 백틱 단독 표기 <FID>·<fid>·<name>·<task-id> — 채움 대상이 아닌 문서 본문 표기
#      (`<화면A>`·`<화면B>` 는 화면 목록에서 도출 가능한 실 보강 대상 — 제외하지 않음)
set -u
[ $# -ge 1 ] || { echo "Usage: $0 <file...>" >&2; exit 2; }

# 문자 클래스 가-힣 금지: GNU grep + LC_ALL=C 에서 "Invalid collation character"
# → 파이프 전체가 비어 CI(T10.a/c) false-FAIL. ASCII·UTF-8 바이트 안전 패턴 사용.
_PH='<([A-Za-z]|[^[:space:][:cntrl:]/<>])[^>]{0,40}>'
out=$(grep -HnE "$_PH" "$@" 2>/dev/null \
  | grep -v '미확정 — 근거 필요' \
  | sed -e 's|<!--[^>]*-->||g' \
        -e 's|\.specops/<FID>|.specops/FID|g' \
        -e 's|screens/<name>|screens/name|g' \
        -e 's|design-screen <name>|design-screen name|g' \
        -e 's|<YYYYMMDDHHMMSS>_<description>|TIMESTAMP_DESCRIPTION|g' \
        -e 's|test-<feature>|test-feature|g' \
        -e 's|src/<feature>|src/feature|g' \
        -e 's|tests/<feature>|tests/feature|g' \
        -e 's|<feature>/|feature/|g' \
        -e 's|"<UI 기능>"|"UI-기능"|g' \
        -e 's|"<첫 기능>"|"첫-기능"|g' \
  | sed -E 's/`<(FID|fid|name|task-id)>`//g' \
  | grep -E "$_PH")

# ── 예시 블록 잔존 검출 (20260806) ───────────────────────────────────────────
# `<...>` placeholder 는 "안 채운 티" 가 나지만, 템플릿의 **예시 표**(api-spec 의
# `/v1/users/:id`, data-model 의 users/orders/products)는 **완성된 실값처럼 보여서**
# 위 패턴으로는 구조적으로 못 잡는다(실측: 검출 0). 그런데 이 두 문서는 구현의
# **설계 계약**이라, 전자상거래가 아닌 프로젝트에 유령 스키마가 계약으로 남는다.
# 템플릿이 예시를 마커로 감싸고, 채울 때 블록째 삭제한다.
ex_out=$(awk -v FN="" '
  FILENAME != FN { FN = FILENAME; inblk = 0 }
  /specops:example:start/ { inblk = 1; print FILENAME ":" FNR ": [example-block] 예시 블록 잔존 — 실제 내용으로 교체 후 마커째 삭제"; next }
  /specops:example:end/   { inblk = 0; next }
' "$@" 2>/dev/null)

if [ -n "$ex_out" ]; then
  [ -n "$out" ] && printf '%s\n' "$out"
  printf '%s\n' "$ex_out"
  exit 1
fi

[ -z "$out" ] && exit 0
printf '%s\n' "$out"
exit 1
