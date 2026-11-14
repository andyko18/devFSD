#!/usr/bin/env bash
# reconcile-check.sh — 기록 frontier ↔ 증거 frontier 대조 (show-fid-status FR-6 추출·공유 SoT)
# Usage: reconcile-check.sh <FID> [--hook]
#   default : '## 실제 진행 대조 (reconcile)' 블록 출력 — show-fid-status 가 위임(출력 byte-동일)
#   --hook  : DESYNC 시에만 간결 경고+재개점 1줄 출력, 정합/무효 FID/디렉토리 부재 시 무출력·exit 0
#             (SessionStart 훅이 재개 desync 를 자동표면화 — dogfood test1 FR-3 의 24h 오판 정체 방지)
# 배경: 정체 후 재개 시 session-progress 단독은 현실을 과소보고한다(주 breadcrumb 만 읽으면 "미구현"
#   오판). git·dispatch·산출물로 진짜 frontier 를 계산해 desync 를 경고하고 재개점을 준다.
set -u

FID="${1:-}"
MODE="${2:-}"
SPECOPS="${SPECOPS_ROOT:-.specops}"
PROGRESS="$SPECOPS/session-progress.md"
FID_DIR="$SPECOPS/$FID"
STATE_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verification-state.sh"

# --hook 은 훅 additionalContext 주입용 — 무효 FID/디렉토리 부재는 silent (훅 출력 오염 금지)
if [ "$MODE" = "--hook" ]; then
  printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || exit 0
  [ -d "$FID_DIR" ] || exit 0
fi

# 단계 rank (유지보수 analyze=5·specify=10·clarify=20·plan=30·tasks=40·implement=50·verify=60·review=70·finishing=80)
_stage_name() { case "$1" in 5) echo analyze;; 10) echo specify;; 20) echo clarify;; 30) echo plan;; 40) echo tasks;; 50) echo implement;; 60) echo verify;; 70) echo review;; 80) echo finishing;; *) echo "-";; esac; }
_stage_next() { case "$1" in 5) echo 10;; 10) echo 20;; 20) echo 30;; 30) echo 40;; 40) echo 50;; 50) echo 60;; 60) echo 70;; 70) echo 80;; *) echo 999;; esac; }

# ── 산출물 완결성 판정 (20260807-reconcile-completeness) ──
# 토큰 한도 등으로 단계 중간에 끊긴 "쓰다 만" 산출물 3형태를 탐지한다.
# frontier 계산과 **완전히 분리**된 warn-only 판정 — evidence 사다리·`evidence > recorded`
# 비교에 영향을 주지 않는다(AC-R-1). 파일 존재만 보던 기존 판정이 반쪽 plan 을 "완료"로
# 계산해 재개가 그 위에서 진행되던 문제(current-state §4 [A][B] 실증)의 완화다.
# NFR-2 예산: 파일당 grep 2회 + tail 1회. 마지막 줄 추출은 변수 확장, 표 구분행 분류는 builtin =~.
# 한계(spec §7-1): 문장 중간 중단·빈 파일은 미탐지 — 완전 탐지를 약속하지 않는다.
#   추가 실측 한계(Phase C): table-hdr 는 spec FR-1 계약대로 **끝 3줄**만 본다 —
#   구분행 뒤에 빈 줄이 3개 이상 붙어 창 밖으로 밀리면 미탐지다. 창을 넓히면
#   FR-1·AC-3 의 "끝 3줄" 계약을 벗어나므로 여기서 바꾸지 않고 한계로 남긴다.
_artifact_incomplete() {  # $1=파일경로 → stdout 신호명 · rc 0=불완전 · 1=완결/부재
  [ -f "$1" ] || return 1
  local body last fences tail3 line seen_sep=0
  local sep_re='^\|[-: |]+\|[[:space:]]*$'

  # 판정 불가(권한 없음·I/O 오류)는 fail-open — 경고를 만들지 않는다. stderr 누출은 막는다:
  # default 모드 출력은 /status 로 사용자에게 그대로 보이므로 grep/tail 오류가 섞이면 안 된다.

  # ① heading-end — 마지막 비어있지 않은 줄이 '#' 로 시작 (섹션 제목만 쓰고 중단)
  body=$(grep -vE '^[[:space:]]*$' "$1" 2>/dev/null)   # grep 1/2
  last="${body##*$'\n'}"                                # 변수 확장 — 추가 프로세스 0
  case "$last" in '#'*) echo "heading-end"; return 0 ;; esac

  # ② odd-fence — 코드펜스가 **열린 채로** 파일이 끝남 (코드블록·YAML DAG 중간 중단)
  #   ★ 펜스 **길이를 추적**한다. 종전 `grep -cE '^[[:space:]]*```'` 는 길이를 보지 않아
  #     4-backtick 블록 안의 3-backtick 처럼 **의도적으로 짝이 안 맞는 내부 펜스**를 세어
  #     정상 문서를 불완전으로 오판했다 (실측 20260809: plan.md 1건 오탐 → R18 red).
  #     CommonMark 는 "닫는 펜스는 여는 펜스 **이상** 길이" 다 — `==` 로 두면
  #     3-open/4-close 라는 **유효한** 문서를 미완결로 새로 오탐한다(Phase C 프로브 P5).
  fences=$(awk '
    { line = $0; sub(/^[ \t]+/, "", line)
      if (match(line, /^`+/) && RLENGTH >= 3) {
        n = RLENGTH
        if (f == 0)      f = n
        else if (n >= f) f = 0
      } }
    END { print (f == 0 ? 0 : 1) }' "$1" 2>/dev/null)
  [ "${fences:-0}" -eq 1 ] 2>/dev/null && { echo "odd-fence"; return 0; }

  # ③ table-hdr — 끝 3줄에 표 구분행이 있고 그 뒤 데이터 행이 없음 (표 헤더만 쓰고 중단)
  tail3=$(tail -3 "$1" 2>/dev/null)            # tail 1/1
  # 파이프 금지 — 서브셸이 생기면 seen_sep 갱신이 유실된다. here-doc 입력 사용.
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # 구분행 뒤에 **어떤** 비어있지 않은 줄이든 오면 데이터가 이어진 것이다.
    # 선행 파이프(`| a | b |`)만 데이터로 치면 markdown 합법인 pipeless 행(`a | b`)이
    # 오탐된다 — spec FR-1 의 "데이터 행이 뒤따르지 않음" 은 파이프 스타일을 한정하지 않는다.
    [ "$seen_sep" -eq 1 ] && seen_sep=0
    [[ "$line" =~ $sep_re ]] && seen_sep=1
  done <<EOF
$tail3
EOF
  [ "$seen_sep" -eq 1 ] && { echo "table-hdr"; return 0; }

  return 1
}

# 불완전 산출물마다 경고 1줄 방출 (AC-9 — 파일별 1줄, 최대 2줄).
# 문구는 **중립**이다(clarify Q3) — 판정이 3신호 휴리스틱이라 100% 가 아니므로
# "재실행하라" 류 지시형을 쓰지 않는다. 판단은 사용자 몫(5원칙 4 주권).
# 탐지 0건이면 완전 무출력 — `--hook` 노이즈 0 계약 보존(AC-R-2).
_emit_completeness_warnings() {  # $1=FID 디렉토리 $2=줄 접두어
  local f sig
  for f in plan.md tasks.md; do
    sig=$(_artifact_incomplete "$1/$f") || continue
    printf '%s⚠️ %s 불완전 가능(%s) — 재개 전 확인 요망\n' "$2" "$f" "$sig"
  done
}

# ── 이미 머지됨 판정 (20261109-reconcile-merged-fid) ──
# session-progress 에 종결 줄(PR 생성·DONE)이 빠져도 FID 브랜치가 main 에 들어갔으면 미완이 아니다.
# git 만 쓴다(gh·네트워크 없음 — SessionStart 마다 돌아 지연·계정 문제를 피한다). 브랜치 tip 이
# main 의 조상이면서 first-parent 체인에는 없을 때 = 머지 커밋으로 들어온 브랜치. 새로 딴 브랜치
# (tip 이 first-parent 체인 위)와 fast-forward·squash 머지는 보수적으로 "머지됨 아님"(한계).
merged_into=""
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  for _r in refs/remotes/origin/main refs/heads/main refs/remotes/origin/master refs/heads/master; do
    git show-ref --verify --quiet "$_r" && { mref="$_r"; break; }
  done
  if [ -n "${mref:-}" ]; then
    for _b in "refs/heads/feat/$FID" "refs/remotes/origin/feat/$FID"; do
      tip=$(git rev-parse --verify -q "$_b" 2>/dev/null) || continue
      if git merge-base --is-ancestor "$tip" "$mref" 2>/dev/null \
         && ! git rev-list --first-parent "$mref" 2>/dev/null | grep -qx "$tip"; then
        merged_into="${mref#refs/remotes/}"; merged_into="${merged_into#refs/heads/}"; break
      fi
    done
  fi
fi
_merged_line() { printf '%sℹ️ 이미 머지됨 — feat/%s 가 %s 에 머지 커밋으로 들어갔다. session-progress 에 종결 줄이 없어도 미완이 아니다(재개 제안 불필요).\n' "$1" "$FID" "$merged_into"; }

# 기록 frontier — session-progress FID 섹션에서 등장한 최고 단계
recorded=0
if [ -f "$PROGRESS" ] && grep -qE "^## $FID([[:space:]]|$)" "$PROGRESS"; then
  section=$(awk "/^## $FID([[:space:]]|\$)/{f=1;next} f&&/^## /{exit} f{print}" "$PROGRESS")
  printf '%s' "$section" | grep -qE '/analyze' && recorded=5
  printf '%s' "$section" | grep -qE '/specify' && [ "$recorded" -lt 10 ] && recorded=10
  printf '%s' "$section" | grep -qE '/clarify' && [ "$recorded" -lt 20 ] && recorded=20
  printf '%s' "$section" | grep -qE '/plan' && [ "$recorded" -lt 30 ] && recorded=30
  printf '%s' "$section" | grep -qE '/tasks' && [ "$recorded" -lt 40 ] && recorded=40
  printf '%s' "$section" | grep -qE '/implement' && [ "$recorded" -lt 50 ] && recorded=50
  printf '%s' "$section" | grep -qE '/verify' && [ "$recorded" -lt 60 ] && recorded=60
  printf '%s' "$section" | grep -qE '/(request-review|receive-review|review)' && [ "$recorded" -lt 70 ] && recorded=70
  printf '%s' "$section" | grep -qE '/finishing|/lifecycle' && [ "$recorded" -lt 80 ] && recorded=80
fi

# ── 기본 경로 FID (20261114) — 단계가 다르다(명확화·분해가 없고 리뷰가 검증보다 앞선다). 아래 사다리로 재면
#   spec.md 만으로 "clarify 부터 재개" 가 나온다(실측: 승인 직후·승격 직후 DESYNC 오보). `/basic` 기록이 있고
#   `/full 승격` 이 없으면 기본 경로다 — 가장 최근 단계 줄로 다음 할 일만 말한다(commands/basic.md 번호).
#   한계: --hook 에서는 기본 경로 FID 의 DESYNC(기록이 실제보다 뒤처짐)를 내지 않는다 — 오보를 막는 대신 진짜 지연도 알리지 않는다.
basic_next=""
if [ -n "${section:-}" ] && printf '%s' "$section" | grep -qE '^- [^ ]+ [^ ]+ /basic ' && ! printf '%s' "$section" | grep -qE '^- [^ ]+ [^ ]+ /full '; then
  # 가장 최근 단계 줄(기록은 최신이 위)로 정한다 — 줄 머리(`- 날짜 시각 /명령`)에 고정해 메모 속 글자를 읽지 않는다
  #   (`/basic 시작` 의 메모는 사용자 요청 원문이라 "/verify PASS 표시를 고친다" 같은 말이 들어온다 — 코드 리뷰 실측).
  #   검증 뒤 코드를 고쳐 다시 봉인했으면 그 봉인 줄이 위에 있으므로 7번 검증을 가리킨다.
  _top=$(printf '%s\n' "$section" | grep -m1 -E '^- [^ ]+ [^ ]+ /(lifecycle|verify|review|implement|plan|approve|basic) ' | sed -E 's/^- [^ ]+ [^ ]+ (\/[a-z-]+ [^ ]+).*/\1/')
  case "$_top" in
    "/lifecycle "*)      basic_next="없음 — 끝난 작업이다" ;;
    "/verify PASS")      basic_next="8번 커밋 · PR" ;;
    "/verify "*)         basic_next="7번 — 검증이 통과하지 않았다(고치고 다시 seal → 검증)" ;;
    "/review 완료")      basic_next="7번 검증(run-verification.sh)" ;;
    "/review "*|"/implement "*) basic_next="6번 리뷰 → 7번 봉인" ;;
    "/plan "*)           basic_next="4-1번 계획·전문가 반영 → 5번 구현" ;;
    "/approve "*)        basic_next="4-1번 켤 단계 판정(basic-path.sh plan)" ;;
    *)                   basic_next="2번 spec → 4번 승인" ;;
  esac
fi
if [ -n "$basic_next" ]; then
  if [ "$MODE" = "--hook" ]; then
    [ -n "$merged_into" ] && { _merged_line ''; exit 0; }
    _emit_completeness_warnings "$FID_DIR" ''
    exit 0
  fi
  printf '\n## 실제 진행 대조 (reconcile)\n\n'
  [ -n "$merged_into" ] && _merged_line '  '
  printf '  기본 경로 — 다음: %s (commands/basic.md)\n' "$basic_next"
  _emit_completeness_warnings "$FID_DIR" '  '
  exit 0
fi

# 증거 frontier — 파일시스템 산출물 + git 브랜치 커밋
evidence=0
{ [ -f "$FID_DIR/current-state.md" ] || [ -f "$FID_DIR/impact-analysis.md" ]; } && evidence=5
[ -f "$FID_DIR/spec.md" ] && [ "$evidence" -lt 10 ] && evidence=10
[ -f "$FID_DIR/clarifications.md" ] && [ "$evidence" -lt 20 ] && evidence=20
[ -f "$FID_DIR/plan.md" ] && [ "$evidence" -lt 30 ] && evidence=30
[ -f "$FID_DIR/tasks.md" ] && [ "$evidence" -lt 40 ] && evidence=40
impl_ev=0
[ -f "$FID_DIR/dispatch-log.md" ] && grep -qE 'DONE|IMPL' "$FID_DIR/dispatch-log.md" 2>/dev/null && impl_ev=1
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  base=$(git show-ref --verify --quiet refs/heads/main && echo main || { git show-ref --verify --quiet refs/heads/master && echo master; })
  if [ -n "$base" ] && git show-ref --verify --quiet "refs/heads/feat/$FID"; then
    n=$(git rev-list --count "$base..feat/$FID" 2>/dev/null || echo 0)
    [ "${n:-0}" -gt 0 ] 2>/dev/null && impl_ev=1
  fi
fi
[ "$impl_ev" -eq 1 ] && [ "$evidence" -lt 50 ] && evidence=50
verify_complete=0
if [ -f "$FID_DIR/verification-state.json" ] && [ -f "$STATE_SH" ]; then
  verify_verdict=$(SPECOPS_ROOT="$SPECOPS" bash "$STATE_SH" current "$FID" 2>/dev/null || echo NOT_RUN)
  case "$verify_verdict" in PASS|WAIVED) verify_complete=1 ;; esac
elif [ -s "$FID_DIR/evidence.md" ]; then
  # 기존 FID 읽기 호환: 구조화 상태가 없는 과거 evidence는 기존 frontier 의미를 유지한다.
  verify_complete=1
fi
[ "$verify_complete" -eq 1 ] && [ "$evidence" -lt 60 ] && evidence=60
# review=70: lifecycle request/receive(또는 lite skip)만. Phase B/C reviews/ 는 implement 산출물이라
# 여기 올리면 finishing 과대보고(downstream-dogfood). 판정 불가 시 낮은 단계 유지.
{ [ -f "$FID_DIR/review-request.md" ] || [ -f "$FID_DIR/review-skip.md" ]; } \
  && [ "$evidence" -lt 70 ] && evidence=70

# ── --hook 모드: DESYNC 시에만 간결 1줄 (정합 시 무출력) ──
if [ "$MODE" = "--hook" ]; then
  # 머지 끝난 FID 는 과소보고·산출물 경고가 의미 없다 — 안내 1줄만 내고 끝낸다.
  [ -n "$merged_into" ] && { _merged_line ''; exit 0; }
  if [ "$evidence" -gt "$recorded" ]; then
    printf '⚠️ 재개 DESYNC — session-progress 가 실제 진행보다 과소보고 중. 기록 frontier=%s, 증거 frontier=%s (산출물/dispatch/git 이 더 진행됨). → 재개점: %s 부터. 미기록 구간(%s~%s)은 session-progress-append.sh 로 보정할 것.\n' \
      "$(_stage_name "$recorded")" "$(_stage_name "$evidence")" \
      "$(_stage_name "$(_stage_next "$evidence")")" \
      "$(_stage_name "$(_stage_next "$recorded")")" "$(_stage_name "$evidence")"
  fi
  # 완결성 경고는 DESYNC 와 독립 — 정합이어도 반쪽 산출물이면 알린다(AC-5).
  _emit_completeness_warnings "$FID_DIR" ''
  exit 0
fi

# ── default 모드: show-fid-status 위임 (출력 byte-동일) ──
printf '\n## 실제 진행 대조 (reconcile)\n\n'
[ -n "$merged_into" ] && _merged_line '  '
if [ "$evidence" -gt "$recorded" ]; then
  printf '  \xe2\x9a\xa0\xef\xb8\x8f  DESYNC — session-progress 과소보고\n'
  printf '     기록 frontier: %s (단계 %s)\n' "$(_stage_name "$recorded")" "$recorded"
  printf '     증거 frontier: %s (단계 %s) — 산출물/dispatch/git 이 더 진행됨\n' "$(_stage_name "$evidence")" "$evidence"
  printf '     → 재개점: %s 부터 (증거상 %s 까지 완료 — 그 다음 단계).\n' \
    "$(_stage_name "$(_stage_next "$evidence")")" "$(_stage_name "$evidence")"
  printf '     → 먼저 기록 보정: %s~%s 단계가 실제 완료됐으나 session-progress 미기록 — session-progress-append.sh 로 채울 것.\n' \
    "$(_stage_name "$(_stage_next "$recorded")")" "$(_stage_name "$evidence")"
elif [ "$evidence" -eq "$recorded" ]; then
  printf '  \xe2\x9c\x85 정합 — 기록(%s) = 증거(%s)\n' "$(_stage_name "$recorded")" "$(_stage_name "$evidence")"
else
  # evidence < recorded — 종전엔 이 경우도 위 else 로 흡수돼 서로 다른 값을 '=' 로 표기했다
  # (`✅ 정합 — 기록(clarify) = 증거(specify)`). 거짓 안심이라 갈래를 분리한다(AC-8).
  printf '  \xe2\x84\xb9\xef\xb8\x8f 기록이 증거보다 앞섬 — 기록(%s) > 증거(%s)\n' "$(_stage_name "$recorded")" "$(_stage_name "$evidence")"
  printf '     → session-progress 가 실제보다 앞서 기록됐을 수 있습니다. 산출물을 확인하세요.\n'
fi
_emit_completeness_warnings "$FID_DIR" '  '
