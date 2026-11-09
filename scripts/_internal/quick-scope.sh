#!/usr/bin/env bash
# quick 경로 판정기 — 스테이징된 변경의 범위와 리뷰 보고서를 본다 (20261010-quick-fix-path).
#
# Usage: quick-scope.sh <FID> [<task-id>=T1] [--explain]
# Exit : 0 = 범위 안 ∧ 통과한 리뷰가 마지막 수정보다 새것
#        3 = 범위 초과 (판정 불가도 3 — quick 구조의 FID 에서만 불리므로 막는 쪽이 정식 경로의 거짓 차단이 되지 않는다)
#        4 = 리뷰 미충족 (보고서 없음 · 마지막 판정이 통과가 아님 · 리뷰 뒤에 다시 고침)
# stdout 1줄: `QUICK-SCOPE: OK|OVER|NOREVIEW <사유>` · --explain 이면 접두 없이 사유만(거부 문안에 그대로 넣는다).
#
# 누가 부르는가: 훅이 부르는 check-task-receipt.sh(권위 있는 판정)와 quick-fix.sh seal(이른 안내). 판정을 두 벌로 두지 않는다.
# 범위: 구현 파일 수 ≤ QUICK_MAX_IMPL_FILES ∧ 변경 줄 수(추가+삭제) ≤ QUICK_MAX_LINES ∧ 고위험 신호 없음.
#   문서(file-class SoT)와 테스트 파일은 파일 수·줄 수에 넣지 않는다. 수치는 근거가 얇은 기본값이다 — 실사용 뒤 여기 한 곳에서 고친다.
set -u

QUICK_MAX_IMPL_FILES=2
QUICK_MAX_LINES=20

FID="${1:-}"; TASK="T1"; MODE=""
shift || true
for _a in "$@"; do
  case "$_a" in --explain) MODE="--explain" ;; *) TASK="$_a" ;; esac
done

SPECOPS="${SPECOPS_ROOT:-.specops}"
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)

_out() {  # <rc> <종류> <사유>
  if [ "$MODE" = "--explain" ]; then printf '%s\n' "$3"; else printf 'QUICK-SCOPE: %s %s\n' "$2" "$3"; fi
  exit "$1"
}

printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || _out 3 OVER "판정 불가 — FID 형식이 아니다"
printf '%s' "$TASK" | grep -qE '^T[0-9]+$' || _out 3 OVER "판정 불가 — task id 형식이 아니다"
# shellcheck source=/dev/null
source "$PLUGIN/scripts/_internal/file-class.sh" 2>/dev/null || _out 3 OVER "판정 불가 — file-class.sh 를 읽을 수 없다"
# shellcheck source=/dev/null
source "$PLUGIN/scripts/_internal/risk-profile.sh" 2>/dev/null || _out 3 OVER "판정 불가 — risk-profile.sh 를 읽을 수 없다"

top=$(git rev-parse --show-toplevel 2>/dev/null) || _out 3 OVER "판정 불가 — git 저장소가 아니다"
# core.quotePath=false — 기본값이면 git 이 비ASCII 경로를 "src/\355\225\234…" 처럼 따옴표로 이스케이프해 낸다. 그 문자열로는
#   파일을 찾지 못해 리뷰 신선도 비교를 건너뛰고, 그 경로로 diff 를 뽑으면 빈 값이라 내용 신호도 놓친다(둘 다 조용히 통과 쪽).
_git() { git -C "$top" -c core.quotePath=false "$@"; }
numstat=$(_git diff --cached --numstat --no-renames 2>/dev/null) || _out 3 OVER "판정 불가 — git diff 실패"
[ -n "$numstat" ] || _out 3 OVER "판정 불가 — 스테이징된 변경이 없다"

# 테스트 파일 — 경로로 판정한다. 이름 중간에 test·spec 이 든 구현 파일(inspect.sh · contest.py)을 빼지 않는다.
qs::is_test() {
  case "$1" in
    tests/*|test/*|__tests__/*|*/tests/*|*/test/*|*/__tests__/*) return 0 ;;
  esac
  case "${1##*/}" in
    test_*.py|*_test.*|*.test.*|*.spec.*|test-*.sh) return 0 ;;
  esac
  return 1
}

plugin_rc=1; fc::is_plugin_repo && plugin_rc=0   # 루프 밖에서 1회 (file-class.sh 주석)
files=0; lines=0; impl=""; nondoc=""; all=""
while IFS=$'\t' read -r add del path; do
  [ -n "$path" ] || continue
  # git 은 따옴표·역슬래시·제어문자가 든 경로를 "…" 로 감싸 이스케이프해 낸다(core.quotePath 와 무관하다). 그 문자열은
  #   파일 경로가 아니라서 아래의 신선도 비교와 내용 신호가 조용히 빠진다 — 해석할 수 없으면 막는다.
  case "$path" in '"'*) _out 3 OVER "판정 불가 — 경로를 해석할 수 없다(따옴표·역슬래시·제어문자가 든 파일 이름: ${path})" ;; esac
  all="${all}${path}"$'\n'
  fc::is_doc "$path" "$plugin_rc" && continue
  nondoc="${nondoc}${path}"$'\n'
  qs::is_test "$path" && continue
  if [ "$add" = "-" ] || [ "$del" = "-" ]; then
    _out 3 OVER "바이너리 파일 변경(${path}) — 줄 수를 셀 수 없다"
  fi
  files=$((files + 1)); lines=$((lines + add + del)); impl="${impl}${path}"$'\n'
done <<< "$numstat"

[ "$files" -le "$QUICK_MAX_IMPL_FILES" ] \
  || _out 3 OVER "구현 파일 ${files}개 (상한 ${QUICK_MAX_IMPL_FILES}개)"
[ "$lines" -le "$QUICK_MAX_LINES" ] \
  || _out 3 OVER "변경 ${lines}줄 (상한 ${QUICK_MAX_LINES}줄 · 테스트·문서 제외)"

# 고위험 신호 — 경로와 변경 내용을 함께 본다. 신호가 뜨면 크기와 무관하게 정식 경로다.
sig=""
# jq 가 없으면 판정할 수 없다 — quick 은 보수 방향이라 신호를 켠다(리뷰 M-1: 종전 grep 은 항상 있는 도구였다).
if [ "$plugin_rc" -eq 0 ] && { ! command -v jq >/dev/null 2>&1 || [ "$(printf '%s\n' "$all" | jq -Rn --arg rt "$FC_RUNTIME_RE" '[inputs | select(test($rt))] | length > 0' 2>/dev/null)" = true ]; }; then
  sig="${sig} plugin_runtime"     # 플러그인 저장소의 훅·규칙·에이전트·스킬 본문·커맨드 = 강제층 본체
fi
printf '%s' "$all" | grep -qE '(^|/)screens/|(^|/)api-spec[^/]*\.md$|(^|/)data-model\.md$' \
  && sig="${sig} ui_if"           # 화면·인터페이스 설계 문서 — design-first 대상
# 스키마 정의 파일 — 내용에 CREATE/ALTER TABLE 이 없어도(필드 한 줄 추가 · ADD COLUMN) 스키마 변경이다
printf '%s' "$all" | grep -qiE '(^|/)schema\.[a-z0-9]+$|\.prisma$|\.sql$' \
  && sig="${sig} schema"
if [ -n "$impl" ]; then
  # 변경 줄만(문맥 줄 제외) 본다. 신호 정의는 risk-profile 의 것을 그대로 쓴다 — 그중 명세(FR-3)가 든 세 가지만 센다.
  corpus=$(printf '%s' "$impl" | tr '\n' '\0' | xargs -0 git -C "$top" -c core.quotePath=false diff --cached --no-renames -U0 -- 2>/dev/null \
    | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' || true)
  for s in $(rp::detect_strict_signals "$corpus" "$impl"); do
    case "$s" in auth|db_migration|public_api) sig="${sig} ${s}" ;; esac
  done
fi
[ -z "${sig// /}" ] || _out 3 OVER "고위험 신호:${sig}"

# 리뷰 — 통과 판정의 코드 리뷰 보고서가 있고, 스테이징된 비문서 파일보다 새것이어야 한다.
#   판정은 저장 훅(save-review-report.sh)의 파일 규약에서 읽는다: 통과가 아닌 판정은 report 와 함께 feedback 을 쓴다.
#   그래서 "feedback 이 report 보다 오래됐다(또는 없다)" = 마지막 판정이 통과다.
rep="$SPECOPS/$FID/reviews/$TASK-C-report.md"
fb="$SPECOPS/$FID/reviews/$TASK-C-feedback.md"
[ -f "$rep" ] || _out 4 NOREVIEW "리뷰 보고서가 없다 (${rep})"
if [ -f "$fb" ] && [ ! "$rep" -nt "$fb" ]; then
  _out 4 NOREVIEW "마지막 리뷰 판정이 통과가 아니다 (${fb})"
fi
while IFS= read -r p; do
  [ -n "$p" ] && [ -e "$top/$p" ] || continue
  [ "$top/$p" -nt "$rep" ] && _out 4 NOREVIEW "리뷰 뒤에 ${p} 가 다시 수정됐다"
done <<< "$nondoc"

_out 0 OK "구현 파일 ${files}개 · ${lines}줄"
