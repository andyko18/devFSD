#!/usr/bin/env bash
# check-foundation-manifest.sh — foundation 산출물 게이트 (20260806)
# Usage: check-foundation-manifest.sh <FID>
# Exit: 0 = PASS 또는 해당 없음(skip) · 1 = FAIL(미산출·미채움)
#
# 왜 스크립트인가: `verifying-evidence-ko` 는 이 게이트를 **HARD** 로 선언하고, 그 근거로
#   "생산은 planning-ko 산문 지시뿐(강제 evaluator 부재)이라 verify 가 실제 산출물을 확인하지
#    않으면 후속 `/start` 재사용 게이트가 침묵 무발동(no-op) 한다" 고 적어 뒀다.
#   그런데 run-verification·release-ready·DAG 어디에도 구현이 없어서, **침묵 무발동을 막으려는
#   게이트 자체가 침묵 무발동**이었다(실측 20260806). 산문을 실행 가능한 판정으로 옮긴다.
#
# 채움 판정: 구 산문은 `grep -q '<경로>'` **단일 토큰**이라 경로만 채우고 `<설명>`·
#   `<import 예시>`·`<확정된 프레임워크>` 가 전부 남아도 통과했다. 템플릿이 가진 자리표시자 **전부**를
#   대조한다(foundation-manifest-content.sh `fmc_template_leftovers`).
#
# 최소 내용 (20261009): 자리표시자만 없으면 통과하던 것 — 내용이 `x` 한 줄이어도, 모듈 행이 0개여도,
#   저장소에 없는 경로만 적어도 PASS 였다. 표에 적힌 경로 가운데 **실재하는 것이 하나는** 있어야 한다
#   (foundation-manifest-content.sh). 없는 경로는 경고로 나열한다(차단 아님 — 표기 오독 가능).
# 덮어쓰기 경고: base 브랜치의 manifest 에 있던 모듈명이 사라졌으면 알린다 — 두 번째 `/start-foundation` 이
#   템플릿으로 다시 써서 앞선 공통부 행을 지우는 경우(차단 아님 — 모듈을 실제로 없앤 것일 수 있다).
# 공통 FR 안내: 요구사항 표의 공통부 FR 가운데 `관련 spec` 칸이 빈 것이 있으면 적는 명령을 알린다.
#
# fail-open: spec.md 부재·§유형 판독 불가 → 0 (무관 FID·초기 상태에 월권 금지).
set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/base-branch.sh" 2>/dev/null || true   # specops_default_branch (20261115)

FID="${1:?usage: $0 <FID>}"
SPECOPS="${SPECOPS_ROOT:-.specops}"
SPEC="$SPECOPS/$FID/spec.md"
MANIFEST="$SPECOPS/memory/foundation-manifest.md"
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
SCAN="$PLUGIN/scripts/_internal/scan-enrich-placeholders.sh"

# 판정 불가 → skip (fail-open)
[ -f "$SPEC" ] || { echo "FOUNDATION-MANIFEST: SKIP (spec.md 부재)"; exit 0; }

# §유형=foundation 이 아니면 무관
if ! grep -qE '^\*\*§유형\*\*:[[:space:]]*foundation' "$SPEC" 2>/dev/null; then
  echo "FOUNDATION-MANIFEST: SKIP (§유형≠foundation)"
  exit 0
fi

if [ ! -f "$MANIFEST" ]; then
  echo "FOUNDATION-MANIFEST: FAIL — $MANIFEST 부재"
  echo "  foundation lifecycle 은 manifest 산출로 완료된다 (planning-ko 마지막 태스크)."
  echo "  이 파일이 없으면 후속 /start 의 재사용 게이트(decomposing-ko)가 침묵 무발동한다."
  exit 1
fi

# 채움 판정 — **이 템플릿의 자리표시자**가 남았는가 (20261009: 범용 스캐너 → 템플릿 토큰 대조)
#   범용 스캐너는 manifest 의 사용 예(`<AppShell …>`·`apiFetch<T>`)까지 세어 다 채운 문서를 막았다.
#   템플릿을 읽을 수 없을 때만 종전 스캐너·단일 토큰 판정으로 물러난다(fail-open 하지 않는다).
CONTENT="$PLUGIN/scripts/_internal/foundation-manifest-content.sh"
TPL="$PLUGIN/templates/foundation-manifest.md"
_left_rc=2; _left=""
if [ -f "$CONTENT" ]; then
  # shellcheck source=/dev/null
  . "$CONTENT"
  _left=$(fmc_template_leftovers "$MANIFEST" "$TPL"); _left_rc=$?
fi
if [ "$_left_rc" -eq 1 ]; then
  echo "FOUNDATION-MANIFEST: FAIL — 템플릿 placeholder 잔존(미채움)"
  printf '%s\n' "$_left" | sed 's/^/  /'
  exit 1
elif [ "$_left_rc" -eq 2 ]; then
  if [ -f "$SCAN" ]; then
    if ! scan_out=$(bash "$SCAN" "$MANIFEST" 2>/dev/null); then
      echo "FOUNDATION-MANIFEST: FAIL — 템플릿 placeholder 잔존(미채움)"
      printf '%s\n' "$scan_out" | sed 's/^/  /'
      exit 1
    fi
  elif grep -q '<경로>' "$MANIFEST" 2>/dev/null; then
    echo "FOUNDATION-MANIFEST: FAIL — 템플릿 placeholder 잔존(<경로>)"
    exit 1
  fi
fi

# ── 최소 내용 ────────────────────────────────────────────────────────────────
case "${SPECOPS%/}" in   # 끝 슬래시가 붙어 와도 같은 루트로 읽는다
  .specops|*/.specops) ROOT=$(dirname "${SPECOPS%/}") ;;
  *) ROOT=. ;;
esac
if [ -f "$CONTENT" ]; then
  fmc_scan "$MANIFEST" "$ROOT"
  if [ "$FMC_REAL" -eq 0 ]; then
    echo "FOUNDATION-MANIFEST: FAIL — 실재하는 모듈 경로가 하나도 없다 (표에 적힌 경로 ${FMC_TOTAL}개)"
    [ -n "$FMC_MISSING" ] && printf '%s\n' "$FMC_MISSING" | sed 's/^/  - 없음: /'
    echo "  manifest 는 공통부 모듈의 **실제 경로**를 표에 백틱으로 적어야 한다(저장소 루트 기준 또는 추적 파일의 끝부분)."
    echo "  예: | 라우팅 | \`src/router/index.ts\` | 앱 라우트 정의 | … |"
    exit 1
  fi
  if [ -n "$FMC_MISSING" ]; then
    echo "FOUNDATION-MANIFEST: WARN — 표의 경로 가운데 저장소에 없는 것 (차단 아님)"
    printf '%s\n' "$FMC_MISSING" | sed 's/^/  - /'
  fi

  # 덮어쓰기 경고 — base 의 manifest 에 있던 모듈명이 사라졌는가
  _base=""
  _oh=$(git -C "$ROOT" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null || true); _oh=${_oh#origin/}   # 기본 브랜치가 develop·trunk 인 저장소(20261115)
  [ -n "$_oh" ] || ! declare -F specops_default_branch >/dev/null || _oh=$(specops_default_branch "$ROOT" 2>/dev/null) || _oh=""   # origin/HEAD 없는 저장소 — 로컬 develop 등(20261115)
  for _b in ${_oh:+"$_oh"} main master; do
    if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$_b" 2>/dev/null; then
      _base=$(git -C "$ROOT" merge-base HEAD "$_b" 2>/dev/null || true); break
    fi
  done
  _rel=${MANIFEST#"$ROOT"/}
  if [ -n "$_base" ] && _old=$(git -C "$ROOT" show "$_base:$_rel" 2>/dev/null) && [ -n "$_old" ]; then
    _lost=$(printf '%s\n' "$_old" | fmc_module_names - | LC_ALL=C sort -u \
      | LC_ALL=C grep -vxF -f <(fmc_module_names "$MANIFEST" | LC_ALL=C sort -u; echo "") 2>/dev/null || true)
    if [ -n "$_lost" ]; then
      echo "FOUNDATION-MANIFEST: WARN — 이전 manifest 에 있던 모듈이 사라졌다 (차단 아님)"
      printf '%s\n' "$_lost" | sed 's/^/  - /'
      echo "  manifest 는 템플릿으로 다시 쓰지 않고 행을 더하거나 고친다 — 지운 것이 의도가 아니면 되살리세요."
    fi
  fi
fi

# 공통 FR 안내 — 이 FID 가 만든 공통부 FR 을 요구사항 표에 남긴다(queue 에는 공통 FR 의 FID 칸이 없다)
FRSET="$PLUGIN/scripts/_internal/fr-set-fid.sh"
if [ -f "$FRSET" ]; then
  _pend=$(SPECOPS_ROOT="$SPECOPS" bash "$FRSET" --pending-foundation 2>/dev/null | tr '\n' ' ')
  if [ -n "${_pend% }" ]; then
    echo "FOUNDATION-MANIFEST: NOTE — 공통부 FR 의 \`관련 spec\` 칸이 비어 있다: ${_pend% }"
    echo "  이 FID 가 만든 것을 적는다: bash \"$FRSET\" $FID <FR-ID>…"
  fi
fi

echo "FOUNDATION-MANIFEST: PASS"
exit 0
