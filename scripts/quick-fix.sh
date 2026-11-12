#!/usr/bin/env bash
# /quick-fix 경로의 기계 절차 (20261010-quick-fix-path) — 명세·수용 기준·분해 문서 없이 끝내는 작은 수정.
#
# Usage:
#   quick-fix.sh start <FID> "<한 줄 설명>"   FID 폴더와 진행 기록을 연다(기본 브랜치 위면 브랜치도 만든다)
#   quick-fix.sh seal  <FID> "<test_command>" 스테이징된 변경으로 1-태스크 문서를 만들고, 범위·리뷰를 판정하고,
#                                             테스트를 실제로 돌려 영수증을 남긴다
#   quick-fix.sh done  <FID> "<한 줄 요약>"   커밋 뒤 종결 기록(진행 기록 · 자유작업 로그 1줄)
# Exit: 0 = 성공 · 3 = quick 범위 초과 · 4 = 리뷰 미충족 · 1 = 그 밖(입력 오류 · 테스트 실패 · 관할 아님)
#
# 강제는 여기가 아니라 훅이 한다: 커밋 때 check-task-receipt.sh 가 같은 판정기(quick-scope.sh)를 다시 부른다.
#   이 스크립트의 판정은 이른 안내다 — 건너뛰고 영수증을 직접 만들어도 커밋에서 걸린다.
set -u

ACTION="${1:-}"; FID="${2:-}"; ARG="${3:-}"
SPECOPS="${SPECOPS_ROOT:-.specops}"
PLUGIN=$(cd "$(dirname "$0")/.." && pwd)
APPEND="$PLUGIN/scripts/session-progress-append.sh"

_die() { echo "quick-fix: $1" >&2; exit "${2:-1}"; }
_usage() { _die "usage: $0 {start <FID> \"<설명>\" | seal <FID> \"<test_command>\" | done <FID> \"<요약>\"}"; }

[ -n "$ACTION" ] && [ -n "$FID" ] && [ -n "$ARG" ] || _usage
printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || _die "FID 형식이 아니다 (YYYYMMDD-kebab-slug): $FID"
case "$ARG" in *$'\n'*) _die "설명·명령은 한 줄이어야 한다" ;; esac
# 관할은 여는 쪽(/init-project · /start)만 연다 — 여기서 .specops 를 만들면 specops 를 쓰지 않는 저장소가 편입된다.
[ -d "$SPECOPS" ] || _die "이 저장소에는 $SPECOPS 가 없다 — specops 관할이 아니다(/init-project 또는 /start 로 시작한다)"
[ ! -L "$SPECOPS" ] && [ ! -L "$SPECOPS/$FID" ] || _die "symlink 거부"
# 명세가 있으면 정식 경로의 FID 다 — quick 이 덮어쓰지 않는다.
[ ! -f "$SPECOPS/$FID/spec.md" ] || _die "$FID 에는 명세(spec.md)가 있다 — 정식 경로의 FID 는 quick-fix 로 다루지 않는다"

case "$ACTION" in
  start)
    mkdir -p "$SPECOPS/$FID" || _die "FID 폴더를 만들 수 없다"
    cur=$(git symbolic-ref --short HEAD 2>/dev/null || true)
    case "$cur" in
      main|master) bash "$PLUGIN/scripts/git-branch-create.sh" "$FID" || _die "브랜치를 만들 수 없다" ;;
    esac
    bash "$APPEND" "$FID" /quick-fix 시작 "$ARG" "$ARG" >/dev/null || _die "진행 기록을 남길 수 없다"
    echo "QUICK-FIX: STARTED $FID"
    ;;

  seal)
    [ -d "$SPECOPS/$FID" ] || _die "$FID 폴더가 없다 — 먼저 start 를 실행한다"
    case "$ARG" in *'"'*|*'\'*) _die "test_command 에 따옴표·역슬래시를 쓸 수 없다" ;; esac
    staged=$(git diff --cached --name-only --no-renames 2>/dev/null) || _die "git diff 실패"
    [ -n "$staged" ] || _die "스테이징된 변경이 없다 — 이번 수정에 넣을 파일을 git add 한 뒤 다시 실행한다"

    # 이른 안내 — 범위·리뷰. 넘으면 아무것도 쓰지 않고 멈춘다.
    bash "$PLUGIN/scripts/_internal/quick-scope.sh" "$FID" T1; qrc=$?
    case "$qrc" in
      0) ;;
      4) echo "quick-fix: 리뷰 조건 미충족 — code-reviewer-ko 를 'quick 경로: yes' 로 호출해 통과 판정을 받은 뒤 다시 실행한다" >&2; exit 4 ;;
      *) echo "quick-fix: quick 범위 초과 — /maintain <설명> 으로 진행한다(고친 내용은 작업 트리에 남는다)" >&2; exit 3 ;;
    esac

    # 1-태스크 문서 — outputs 는 스테이징된 파일 그대로다(영수증 검사가 staged ⊆ outputs 를 본다).
    {
      printf '# tasks — %s (quick-fix)\n\n' "$FID"
      printf '> `/quick-fix` 가 만든 1-태스크 문서다. 명세 없이 이 파일만 있는 FID 는 quick 경로로 판정된다 —\n'
      printf '> 범위 상한과 리뷰는 커밋 때 훅이 본다(`scripts/_internal/quick-scope.sh`).\n\n'
      printf '### Task 1: quick-fix\n\n'
      printf '## 의존 그래프\n\n```yaml\nreview_mode: end-loaded\ntasks:\n  - id: T1\n    depends_on: []\n    inputs: []\n    outputs:\n'
      printf '%s\n' "$staged" | while IFS= read -r f; do
        [ -n "$f" ] && printf '      - %s\n' "$(printf '%s' "$f" | jq -Rs .)"
      done
      printf '    ac: []\n    test_command: "%s"\n```\n' "$ARG"
    } > "$SPECOPS/$FID/tasks.md" || _die "태스크 문서를 쓸 수 없다"

    # 테스트를 실제로 돌려 통과할 때만 영수증이 생긴다(기존 태스크 영수증 장치 그대로).
    bash "$PLUGIN/scripts/_internal/record-task-receipt.sh" "$FID" T1 || _die "영수증을 남기지 못했다 — 위 사유를 고친 뒤 다시 실행한다"
    bash "$APPEND" "$FID" /implement DONE "(T1) quick-fix 봉인 — 테스트 통과: $ARG" >/dev/null || true
    echo "QUICK-FIX: SEALED $FID — 커밋 메시지에 'Task: T1' 을 넣는다(봉인 뒤 코드를 고치면 영수증이 무효다)"
    ;;

  done)
    [ -d "$SPECOPS/$FID" ] || _die "$FID 폴더가 없다"
    bash "$APPEND" "$FID" /lifecycle DONE "quick-fix — $ARG" >/dev/null || _die "진행 기록을 남길 수 없다"
    files=$(jq -r '.outputs // [] | join(", ")' "$SPECOPS/$FID/receipts/T1.json" 2>/dev/null || true)
    log="$SPECOPS/freelog.md"; day=$(date +%Y%m%d)
    grep -qx "## $day" "$log" 2>/dev/null || printf '\n## %s\n\n' "$day" >> "$log"
    printf -- '- %s [fix] (%s) %s — %s\n' "$(date +%H:%M)" "$FID" "${files:-(파일 목록 없음)}" "$ARG" >> "$log"
    echo "QUICK-FIX: DONE $FID"
    ;;

  *) _usage ;;
esac
