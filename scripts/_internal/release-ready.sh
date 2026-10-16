#!/usr/bin/env bash
# RELEASE_READY 합성 판정 (P0-3). PR 직전 품질 축을 한곳에서 본다.
# Usage: release-ready.sh <FID>
# Exit: 0=READY · 1=NOT_READY · 2=UNKNOWN(fail-open / legacy)
set -u

FID="${1:?usage: $0 <FID>}"
printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || {
  echo "RELEASE_READY: UNKNOWN"
  echo "  reason=invalid-fid"
  exit 2
}

PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
# worktree 에서 불려도 메인 worktree 의 .specops 로 판정한다 — git 조회는 export 된 GIT_DIR·GIT_WORK_TREE 로 그 worktree (20261016-judge-scripts-worktree-root)
#   훅은 .specops 가 있는 프로젝트 폴더에서 부르므로 이동하지 않는다(셸이 다른 worktree 면 git env 도 이미 export 돼 있다). SPECOPS_ROOT 를 준 호출도 그대로다.
#   이동하면 상대경로 $0 의 뜻이 바뀐다 — 자기 경로는 그 전에 잡는다. 테스트 명령을 실행하지 않으므로 _sr_leave 는 부르지 않는다.
# shellcheck source=/dev/null
. "$PLUGIN/scripts/_internal/specops-root.sh" 2>/dev/null && specops_root_enter 2>/dev/null || true
SPECOPS="${SPECOPS_ROOT:-.specops}"
FID_DIR="$SPECOPS/$FID"
STATE_SH="$PLUGIN/scripts/_internal/verification-state.sh"
AUDIT_SH="$PLUGIN/scripts/_internal/check-review-audit.sh"
RECON_SH="$PLUGIN/scripts/_internal/reconcile-check.sh"
# shellcheck source=/dev/null
source "$PLUGIN/scripts/skip-tracker.sh"

# ── 리뷰 미해결 판정 (⑦ crit_high) ────────────────────────────────────────────
# 헤딩·토큰 존재로 판정하면 안 된다 — agents/code-reviewer-ko.md 출력 템플릿은
# 발견 0건이어도 `## 🔴 Critical` 헤딩과 `## 종합 판정` 3종 메뉴를 항상 찍는다.
# 그래서 구 `grep -RqlE 'NEEDS_FIX|## 🔴 Critical'` 는 end-loaded 기본 흐름
# (requesting skip → session-progress 에 `/receive-review` 줄 없음)을 전부 오탐해
# strict FID·batch 브랜치 PR 을 통째로 hard deny 시켰다.
# 대신 (a) 🔴 절의 **실제 항목** (b) READY_TO_MERGE 없이 NEEDS_FIX 만 남은 **선택된 판정**
# 두 신호만 인정한다. 스캔 대상도 최종 판정물 `*-report.md` 로 한정 —
# `-feedback.md` 는 해소된 과거 라운드가 그대로 남는 산출물이다.

# 🔴 Critical 절에 플레이스홀더가 아닌 실제 항목이 있는가
rr::has_critical_item() {
  awk '
    /^[[:space:]]*#+[[:space:]]*.*🔴/ { in_sec=1; next }
    in_sec && /^[[:space:]]*#+[[:space:]]/ { in_sec=0 }
    in_sec && /^[[:space:]]*(---|===)/ { in_sec=0 }
    in_sec && /^[[:space:]]*[-*][[:space:]]+/ {
      line=$0
      sub(/^[[:space:]]*[-*][[:space:]]+/, "", line)
      gsub(/[`*_]/, "", line)
      sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
      if (line == "") next
      if (line ~ /^(없음|없다|해당 없음|N\/A|n\/a|NA|TBD|-|\.\.\.)[[:space:].]*$/) next
      if (line ~ /<[A-Za-z_]+>/) next   # `<file>:<line>` — 템플릿 플레이스홀더
      found=1
    }
    END { exit(found ? 0 : 1) }
  ' "$1" 2>/dev/null
}

# 판정이 NEEDS_FIX 로 **선택**됐는가 (3종 메뉴 그대로면 READY_TO_MERGE 도 함께 있다)
rr::needs_fix_selected() {
  grep -q 'NEEDS_FIX' "$1" 2>/dev/null && ! grep -q 'READY_TO_MERGE' "$1" 2>/dev/null
}

rr::unresolved_review() {
  local dir="$1" f
  for f in "$dir"/*-report.md; do
    [ -f "$f" ] || continue
    if rr::has_critical_item "$f" || rr::needs_fix_selected "$f"; then
      return 0
    fi
  done
  # 짝 report 가 아예 없는 feedback = 해소되지 않은 FAIL 라운드 (report 가 있으면 그쪽이 최종)
  for f in "$dir"/*-feedback.md; do
    [ -f "$f" ] || continue
    [ -f "${f%-feedback.md}-report.md" ] && continue
    if rr::has_critical_item "$f" || rr::needs_fix_selected "$f"; then
      return 0
    fi
  done
  return 1
}

if [ ! -d "$FID_DIR" ]; then
  echo "RELEASE_READY: UNKNOWN"
  echo "  reason=fid-dir-missing"
  exit 2
fi

# legacy: 구조화 상태도 evidence stamp도 없으면 판정 불가 → fail-open
has_state=0
[ -f "$FID_DIR/verification-state.json" ] && has_state=1
has_stamp=0
[ -f "$FID_DIR/evidence.md" ] \
  && grep -q '^RUN-VERIFICATION-RESULT: ' "$FID_DIR/evidence.md" 2>/dev/null \
  && has_stamp=1
if [ "$has_state" -eq 0 ] && [ "$has_stamp" -eq 0 ]; then
  echo "RELEASE_READY: UNKNOWN"
  echo "  reason=legacy-no-verify-artifact"
  exit 2
fi

verify=UNKNOWN
review=UNKNOWN
security=UNKNOWN
integration=UNKNOWN
performance=UNKNOWN
reconcile=UNKNOWN
crit_high=UNKNOWN
ready=1

# ① verify — PASS only
if [ -f "$STATE_SH" ]; then
  verify=$(SPECOPS_ROOT="$SPECOPS" bash "$STATE_SH" current "$FID" 2>/dev/null || echo NOT_RUN)
else
  verify=NOT_RUN
fi
[ "$verify" = "PASS" ] || ready=0

# ② review
if [ -f "$AUDIT_SH" ]; then
  audit_out=$(SPECOPS_ROOT="$SPECOPS" bash "$AUDIT_SH" "$FID" 2>&1) || true
  case "$audit_out" in
    REVIEW-AUDIT:\ PASS*) review=PASS ;;
    REVIEW-AUDIT:\ FAIL*) review=FAIL; ready=0 ;;
    REVIEW-AUDIT:\ SKIP*)
      if [ -f "$FID_DIR/review-request.md" ] \
         || { [ -d "$FID_DIR/reviews" ] && [ -n "$(ls -A "$FID_DIR/reviews" 2>/dev/null)" ]; }; then
        review=SKIP_OK
      else
        review=SKIP_EMPTY
        ready=0
      fi
      ;;
    *) review=UNKNOWN; ready=0 ;;
  esac
else
  review=UNKNOWN
  ready=0
fi

# ③④⑤ lifecycle tail gates — PASS|SKIP 허용, 부재·FAIL 거부
#
# ★ SKIP 은 **근거 라인 인용**을 요구한다 (20260829-bare-skip-teeth).
#   왜: 이 세 게이트는 실측 87회 평가에서 FAIL 0건이고 SKIP 이 integration 72%·performance 55% 다.
#   SKIP 판정 주체가 모델 자신이라, 근거 없는 SKIP 은 v1.45.0 이 제거한 §auto 자기발급 면제표와
#   같은 클래스다 — 라벨만 안 쓸 뿐 "내가 해당 없다고 했으니 넘어간다" 는 동일하다.
#   세 skill 본문은 이미 "근거 없는 SKIP 은 형식화 — 거부" 를 선언하는데, 그 선언에 대응하는
#   기계 검사가 없었다(skip-tracker 는 advisory — 이 repo 가 advisory 를 방치한 전례 그 자체다).
#   판정 SoT 는 skip::cite_status (위에서 source) — 인용 regex 를 여기 다시 쓰면 드리프트한다.
#
# 왜 warn 이 아니라 ready=0(하드)인가: 소급 FAIL 이 실질 0 이기 때문이다. bare 보유 FID 는
#   8건(세 게이트 판정 보유 23건의 34%)인데 **전부 종결**이고 열린 PR 은 0건이다(실측).
#   check-review-presence 가 35% 소급 FAIL 때문에 warn 으로 남은 것과 숫자는 같지만 대상이 다르다 —
#   저건 살아있는 FID 였고 이건 이미 끝난 것들이라 앞으로의 PR 에만 걸린다.
#
# 한계 고백: 인용 판정은 `L<숫자>`·`§...<숫자>` **토큰 존재**만 본다. `§범위 L999` 처럼 실재하지
#   않는 라인을 인용해도 통과한다 — 근거를 **쓰게** 만들 뿐, 근거가 **참인지**는 검증하지 않는다.
#   라인 실재 대조는 spec.md 길이·섹션 파싱이 필요해 별건으로 남긴다.
ev="$FID_DIR/evidence.md"
skip_cite=OK
bare_gates=""
for gate in security integration performance; do
  v=$(skip::verdicts "$ev" "$gate" 2>/dev/null | tail -1)
  [ -n "$v" ] || v=MISSING
  case "$gate" in
    security) security="$v" ;;
    integration) integration="$v" ;;
    performance) performance="$v" ;;
  esac
  case "$v" in
    PASS) ;;
    SKIP)
      if skip::cite_status "$ev" "$gate" 2>/dev/null | grep -qx BARE; then
        bare_gates="${bare_gates}${bare_gates:+,}$gate"
        ready=0
      fi
      ;;
    *) ready=0 ;;
  esac
done
[ -n "$bare_gates" ] && skip_cite="BARE:$bare_gates"

# ⑥ reconcile — DESYNC 문구면 NOT READY (--hook 모드 사용, 기본 출력 불변)
if [ -f "$RECON_SH" ]; then
  recon_out=$(SPECOPS_ROOT="$SPECOPS" bash "$RECON_SH" "$FID" --hook 2>&1) || true
  if printf '%s' "$recon_out" | grep -q 'DESYNC'; then
    reconcile=DESYNC
    ready=0
  else
    reconcile=OK
  fi
else
  reconcile=UNKNOWN
  ready=0
fi

# ⑦ Critical/High — best-effort (오탐 시 축만 UNKNOWN, 전체 fail-open 금지)
crit_high=OK
if [ -f "$ev" ]; then
  if skip::verdicts "$ev" security 2>/dev/null | grep -qx FAIL; then
    crit_high=SECURITY_FAIL
    ready=0
  fi
fi
if [ -d "$FID_DIR/reviews" ]; then
  if rr::unresolved_review "$FID_DIR/reviews"; then
    # receive-review 수용 흔적이 없으면 미승인으로 본다 (휴리스틱)
    if ! grep -qE '/receive-review|수용' "$SPECOPS/session-progress.md" 2>/dev/null; then
      crit_high=UNRESOLVED_REVIEW
      ready=0
    fi
  fi
fi

if [ "$ready" -eq 1 ]; then
  echo "RELEASE_READY: OK"
else
  echo "RELEASE_READY: NOT_READY"
fi
printf '  verify=%s\n' "$verify"
printf '  review=%s\n' "$review"
printf '  security=%s\n' "$security"
printf '  integration=%s\n' "$integration"
printf '  performance=%s\n' "$performance"
printf '  reconcile=%s\n' "$reconcile"
printf '  crit_high=%s\n' "$crit_high"
# 축 이름을 따로 찍는다 — `integration=SKIP` 만 보면 왜 막혔는지 알 수 없다(원인 오안내가
#   BYPASS 를 부르는 것은 이 repo 가 두 번 겪은 실패 형태다).
printf '  skip_cite=%s\n' "$skip_cite"
[ "$skip_cite" = OK ] || printf '  ↳ SKIP 근거에 spec.md 섹션명+라인번호를 인용하세요 (예: §범위 L12-15)\n'

[ "$ready" -eq 1 ] && exit 0 || exit 1
