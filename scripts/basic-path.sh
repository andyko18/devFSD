#!/usr/bin/env bash
# /basic 경로의 기계 절차 (20261112 speed) — spec 1장 → 주 세션 직접 구현 → 리뷰 1회 → 검증 1회 → PR.
#
# Usage:
#   basic-path.sh lane "<요청 한 줄>" [<FID>]   갈래 판정만 한다(쓰지 않는다) — `LANE: basic|full <신호>` 1줄
#   basic-path.sh start <FID> "<요청 한 줄>"    갈래 판정 → FID 폴더·진행 기록·spec 골격(기본 브랜치 위면 브랜치도)
#   basic-path.sh approve <FID>                 사용자 승인 뒤: spec 절 확인 → 갈래 재판정 → acceptance-criteria.md 도출
#   basic-path.sh seal <FID> "<test_command>"   리뷰 뒤: 변경 파일로 갈래 재판정 → 1-태스크 문서 · 리뷰 감사 행
#   basic-path.sh design-scope <화면 수> [new|flow]   화면 설계 확인 범위 — `DESIGN: none|update|approve`
#   basic-path.sh done <FID> "<한 줄 요약>"     종결 기록
# Exit: 0 = 성공 · 3 = 풀 경로 대상(위험 신호) · 4 = 리뷰 보고서 없음 · 1 = 그 밖(입력 오류 · 절 누락 · 관할 아님)
#
# 갈래: 풀 = 인증·권한 변경 · DB 스키마 변경 · 데이터 삭제·이관 · 기존 API 응답 형태 변경 · 되돌릴 수 없는 외부 작업.
#   기존 판정기(risk-profile.sh 의 rp::detect_strict_signals — 영문 낱말·경로)를 그대로 쓰고, 그것이 못 잡는 한글 낱말만 여기서 더한다.
#   **애매하면 무거운 쪽이다** — 신호가 하나라도 보이면 풀이다. spec 의 "범위 밖" 절은 판정에서 뺀다(하지 않는 일을 적은 곳).
# 강제는 여기가 아니라 기존 훅이 한다: 이 경로의 FID 는 spec.md + tasks.md 를 가진 **정식 FID** 다 — 커밋(R-1)·PR(R-2)은
#   run-verification.sh 의 `VERIFY: PASS` 실행 출력과 진행 기록이 있어야 열린다. 훅·검증 러너는 고치지 않았다.
set -u

BASIC_SCREEN_APPROVAL_MIN=3   # 이 수 이상의 화면을 고치면 화면 스펙·목업을 먼저 만들고 승인받는다(근거 얇은 기본값 — 여기 한 곳에서 고친다)

ACTION="${1:-}"
SPECOPS="${SPECOPS_ROOT:-.specops}"
# risk-profile.sh 는 source 되면 PLUGIN·SPECOPS 를 자기 기준($0 의 두 단계 위)으로 다시 잡는다 — 이 스크립트는 한 단계 위가 루트라 이름을 달리 쓴다.
BP_ROOT=$(cd "$(dirname "$0")/.." && pwd)
BP_SPECOPS="$SPECOPS"
APPEND="$BP_ROOT/scripts/session-progress-append.sh"

_die() { echo "basic-path: $1" >&2; exit "${2:-1}"; }
_fid_ok() { printf '%s' "$1" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || _die "FID 형식이 아니다 (YYYYMMDD-kebab-slug): $1"; }

# 한글 위험 낱말 — rp::detect_strict_signals 가 보지 않는 것만.
_ko_signals() {  # <말뭉치>
  local c="$1" s=""
  printf '%s\n' "$c" | grep -qE '인증|인가|권한|로그인|비밀번호|토큰' && s="$s auth"
  printf '%s\n' "$c" | grep -qE '스키마|마이그레이션|컬럼|테이블 ?(추가|변경|삭제|생성)|인덱스 ?(추가|삭제)' && s="$s db_schema"
  printf '%s\n' "$c" | grep -qiE '데이터 ?(삭제|이관|이전|정리)|일괄 ?삭제|백필|backfill|truncate|purge' && s="$s data_move"
  printf '%s\n' "$c" | grep -qiE '응답 ?(형태|형식|구조|필드|스키마)|하위 ?호환|breaking|API ?(변경|수정|삭제)' && s="$s api_shape"
  printf '%s\n' "$c" | grep -qE '운영 ?(배포|반영)|결제|과금|환불|(메일|문자|푸시|알림) ?발송|되돌릴 수 없' && s="$s irreversible_ext"
  printf '%s' "$s"
}

# spec 에서 "범위 밖"·"제외" 절을 뺀 본문 — 하지 않는 일을 적은 낱말로 풀 판정이 나지 않게 한다.
_spec_corpus() {  # <spec.md>
  [ -f "$1" ] || return 0
  awk '
    function lvl(s,  n) { n = 0; while (substr(s, n + 1, 1) == "#") n++; return n }
    /^#+ / { if (skip && lvl($0) <= depth) skip = 0
             if (!skip && $0 ~ /(범위 밖|제외|하지 않는)/) { skip = 1; depth = lvl($0); next } }
    !skip { print }
  ' "$1"
}

# 갈래 판정 — stdout `LANE: basic` 또는 `LANE: full <신호…>` · rc 0 = basic, 3 = full, 1 = 판정기 로드 불가(막는다)
_lane() {  # <요청 문장> [<FID>] [<변경 파일 목록>]
  local text="$1" fid="${2:-}" files="${3:-}" corpus sig
  # shellcheck source=/dev/null
  . "$BP_ROOT/scripts/_internal/risk-profile.sh" 2>/dev/null || { echo "LANE: full 판정기(risk-profile.sh)를 읽을 수 없다"; return 1; }
  SPECOPS="$BP_SPECOPS"
  corpus="$text"
  [ -n "$fid" ] && corpus="$corpus
$(_spec_corpus "$SPECOPS/$fid/spec.md")"
  sig="$(rp::detect_strict_signals "$corpus" "$files") $(_ko_signals "$corpus")"
  sig=$(printf '%s' "$sig" | xargs -n1 2>/dev/null | sort -u | xargs)
  if [ -n "$sig" ]; then echo "LANE: full $sig"; return 3; fi
  echo "LANE: basic"; return 0
}
_full_msg() { echo "basic-path: 위험 신호가 있어 풀 경로 대상이다 — /start <설명>(신규) 또는 /maintain <대상>(유지보수)로 진행한다. 만든 것은 그대로 남는다." >&2; }

_changed_files() {
  # shellcheck source=/dev/null
  . "$BP_ROOT/scripts/_internal/risk-profile.sh" 2>/dev/null || return 1
  SPECOPS="$BP_SPECOPS"
  { rp::collect_files; git ls-files -o --exclude-standard 2>/dev/null; } | sed '/^$/d' | grep -v '^\.specops/' | sort -u
}

case "$ACTION" in
  lane)
    [ -n "${2:-}" ] || _die "usage: $0 lane \"<요청 한 줄>\" [<FID>]"
    [ -z "${3:-}" ] || _fid_ok "$3"
    _lane "$2" "${3:-}" ""; exit $?
    ;;

  design-scope)
    n="${2:-}"; kind="${3:-}"
    case "$n" in ''|*[!0-9]*) _die "usage: $0 design-scope <화면 수> [new|flow]" ;; esac
    case "$kind" in ""|new|flow) ;; *) _die "둘째 인자는 new(새 화면) 또는 flow(흐름 변경)" ;; esac
    if [ -n "$kind" ] || [ "$n" -ge "$BASIC_SCREEN_APPROVAL_MIN" ]; then
      echo "DESIGN: approve — 화면 스펙·목업을 먼저 만들고 승인받는다 (/design-screen · /design-screens)"
    elif [ "$n" -ge 1 ]; then
      echo "DESIGN: update — 기존 화면 스펙(screens/<name>.md)의 해당 부분을 구현과 함께 갱신한다"
    else
      echo "DESIGN: none — 문구·스타일만 바뀐다(화면 설계 확인 없음)"
    fi
    ;;

  start)
    FID="${2:-}"; ARG="${3:-}"
    [ -n "$FID" ] && [ -n "$ARG" ] || _die "usage: $0 start <FID> \"<요청 한 줄>\""
    _fid_ok "$FID"
    case "$ARG" in *$'\n'*) _die "요청은 한 줄이어야 한다" ;; esac
    # 관할은 여는 쪽(/init-project · /start)만 연다 — 여기서 .specops 를 만들면 specops 를 쓰지 않는 저장소가 편입된다.
    [ -d "$SPECOPS" ] || _die "이 저장소에는 $SPECOPS 가 없다 — specops 관할이 아니다(/init-project 또는 /start 로 시작한다)"
    [ ! -L "$SPECOPS" ] && [ ! -L "$SPECOPS/$FID" ] || _die "symlink 거부"
    [ ! -f "$SPECOPS/$FID/tasks.md" ] || _die "$FID 에는 이미 태스크 문서가 있다 — 다른 경로의 FID 는 다루지 않는다"
    _lane "$ARG" "" "" ; rc=$?
    [ "$rc" = 0 ] || { _full_msg; exit 3; }
    mkdir -p "$SPECOPS/$FID" || _die "FID 폴더를 만들 수 없다"
    cur=$(git symbolic-ref --short HEAD 2>/dev/null || true)
    case "$cur" in
      main|master) bash "$BP_ROOT/scripts/git-branch-create.sh" "$FID" || _die "브랜치를 만들 수 없다" ;;
    esac
    if [ ! -f "$SPECOPS/$FID/spec.md" ]; then
      sed "s|{{FID}}|$FID|g" "$BP_ROOT/templates/spec-basic.md" > "$SPECOPS/$FID/spec.md" || _die "spec 골격을 쓸 수 없다"
    fi
    bash "$APPEND" "$FID" /basic 시작 "$ARG" "$ARG" >/dev/null || _die "진행 기록을 남길 수 없다"
    echo "BASIC: STARTED $FID — $SPECOPS/$FID/spec.md 를 채우고 승인받는다"
    ;;

  approve)
    FID="${2:-}"; [ -n "$FID" ] || _die "usage: $0 approve <FID>"; _fid_ok "$FID"
    SPEC="$SPECOPS/$FID/spec.md"
    [ -f "$SPEC" ] || _die "spec.md 가 없다 — 먼저 start 를 실행한다"
    for sec in '목표' '범위' '수용 기준'; do
      grep -qE "^## .*${sec}" "$SPEC" || _die "spec.md 에 '## … ${sec}' 절이 없다"
    done
    grep -q '{{' "$SPEC" && _die "spec.md 에 채우지 않은 자리표시({{…}})가 남아 있다"
    _lane "" "$FID" ""; rc=$?
    [ "$rc" = 0 ] || { _full_msg; exit 3; }
    # 수용 기준 절을 acceptance-criteria.md 로 옮긴다 — 검증 러너와 스펙 리뷰어가 읽는 계약 파일이다(사용자가 보는 것은 spec 1장).
    {
      printf '# 수용 기준 — %s\n\n> `/basic` 경로: spec.md 의 수용 기준 절에서 도출했다(basic-path.sh approve). 고칠 때는 spec.md 를 고치고 approve 를 다시 실행한다.\n\n' "$FID"
      awk '/^## .*수용 기준/ { f = 1; next } f && /^## / { exit } f { print }' "$SPEC"
    } > "$SPECOPS/$FID/acceptance-criteria.md" || _die "acceptance-criteria.md 를 쓸 수 없다"
    out=$(bash "$BP_ROOT/scripts/_internal/check-ac-format.sh" "$FID" 2>&1); rc=$?
    [ "$rc" = 0 ] || { printf '%s\n' "$out" >&2; _die "수용 기준 형식이 맞지 않다 — spec.md 의 수용 기준 절을 고친 뒤 다시 실행한다"; }
    bash "$APPEND" "$FID" /approve 완료 "spec 1장 승인 (/basic)" >/dev/null || _die "진행 기록을 남길 수 없다"
    echo "BASIC: APPROVED $FID"
    ;;

  seal)
    FID="${2:-}"; ARG="${3:-}"
    [ -n "$FID" ] && [ -n "$ARG" ] || _die "usage: $0 seal <FID> \"<test_command>\""
    _fid_ok "$FID"
    D="$SPECOPS/$FID"
    [ -f "$D/spec.md" ] && [ -f "$D/acceptance-criteria.md" ] || _die "spec.md·acceptance-criteria.md 가 없다 — start → approve 를 먼저 실행한다"
    case "$ARG" in *'"'*|*'\'*|*$'\n'*) _die "test_command 에 따옴표·역슬래시·줄바꿈을 쓸 수 없다" ;; esac
    files=$(_changed_files) || _die "변경 파일을 알 수 없다"
    [ -n "$files" ] || _die "변경된 파일이 없다"
    case "$files" in *'"'*|*'\'*) _die "따옴표·역슬래시가 든 파일 이름은 다룰 수 없다" ;; esac
    _lane "" "$FID" "$files"; rc=$?
    [ "$rc" = 0 ] || { _full_msg; exit 3; }
    [ -f "$D/reviews/T1-B-report.md" ] && [ -f "$D/reviews/T1-C-report.md" ] \
      || { echo "basic-path: 리뷰 보고서가 없다 — spec-reviewer-ko·code-reviewer-ko 를 tid=T1 로 호출한 뒤 다시 실행한다" >&2; exit 4; }
    acs=$(grep -oE '^#{2,3} AC-[A-Za-z0-9-]+' "$D/acceptance-criteria.md" | sed -E 's/^#+ //' | sort -u | paste -sd, - | sed 's/,/, /g')
    {
      printf '# tasks — %s (/basic)\n\n' "$FID"
      printf '> `/basic` 경로가 만든 1-태스크 문서다. 주 세션이 직접 구현했다 — plan·분해·구현자 dispatch 가 없다.\n\n'
      printf '### Task 1: 구현 (주 세션)\n\n## 의존 그래프\n\n```yaml\nreview_mode: end-loaded\ntasks:\n  - id: T1\n    depends_on: []\n    inputs: []\n    outputs:\n'
      printf '%s\n' "$files" | while IFS= read -r f; do [ -n "$f" ] && printf '      - "%s"\n' "$f"; done
      printf '    ac: [%s]\n    test_command: "%s"\n```\n' "$acs" "$ARG"
    } > "$D/tasks.md" || _die "태스크 문서를 쓸 수 없다"
    # 리뷰 감사 행 — check-review-audit.sh 가 reviews 파일마다 dispatch-log 행을 요구한다(병렬 쌍의 사후 대조 포함).
    LOG="$D/dispatch-log.md"
    [ -f "$LOG" ] || printf '# dispatch-log — %s (/basic)\n\n| # | 시각 | Phase | agent | 결과 | 비고 |\n|---|---|---|---|---|---|\n' "$FID" > "$LOG"
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if ! grep -q 'BC-PAR-CHECK:T1' "$LOG"; then
      if [ -f "$D/reviews/T1-B-feedback.md" ]; then par="C 폐기(B FAIL) — 지적은 주 세션이 고쳤다"; else par="B PASS"; fi
      {
        printf '| - | %s | B:T1 | spec-reviewer-ko | 기록 | reviews/T1-B-report.md |\n' "$ts"
        printf '| - | %s | C:T1 | code-reviewer-ko | 기록 | reviews/T1-C-report.md |\n' "$ts"
        printf '| - | %s | BC-PAR-CHECK:T1 | - | %s | reviews/T1-B-report.md · reviews/T1-C-report.md |\n' "$ts" "$par"
        for fb in T1-B-feedback.md T1-C-feedback.md; do
          [ -f "$D/reviews/$fb" ] && printf '| - | %s | REVIEW-FIX:T1 | 주 세션 | FIXED | reviews/%s |\n' "$ts" "$fb"
        done
      } >> "$LOG"
    fi
    echo "BASIC: SEALED $FID — 이제 run-verification.sh $FID 를 실행한다(봉인 뒤 코드를 고치면 다시 seal)"
    ;;

  done)
    FID="${2:-}"; ARG="${3:-}"
    [ -n "$FID" ] && [ -n "$ARG" ] || _die "usage: $0 done <FID> \"<한 줄 요약>\""
    _fid_ok "$FID"
    [ -d "$SPECOPS/$FID" ] || _die "$FID 폴더가 없다"
    bash "$APPEND" "$FID" /lifecycle DONE "/basic — $ARG" >/dev/null || _die "진행 기록을 남길 수 없다"
    echo "BASIC: DONE $FID"
    ;;

  *) _die "usage: $0 {lane \"<요청>\" [<FID>] | start <FID> \"<요청>\" | approve <FID> | seal <FID> \"<test_command>\" | design-scope <화면 수> [new|flow] | done <FID> \"<요약>\"}" ;;
esac
