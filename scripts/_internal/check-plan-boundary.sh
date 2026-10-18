#!/usr/bin/env bash
# check-plan-boundary.sh — plan.md 의 「경계 약속」을 파일 목록·헌법 구조 규칙과 대조한다 (읽기 전용 · 경고 전용)
#   FID 20261015-plan-boundary-commitments
#
# Usage: check-plan-boundary.sh <FID>                       # .specops/<FID>/plan.md
#        check-plan-boundary.sh --plan <경로> [--constitution <경로>]
#        (헌법 기본값: ${SPECOPS_ROOT:-.specops}/memory/constitution.md)
#
# 출력 첫 줄: PLAN-BOUNDARY: OK | WARN | SKIP — 그 아래 줄은 두 칸 들여쓰기
#   [경고] …        경계 약속 절 없음 · 칸이 비었거나 자리표시자 · 소유 칸에 백틱 경로 없음
#   [소유 밖] <경로>  파일 구조 목록(생성·수정·삭제)의 경로가 소유 경로 밖이다 — 테스트 경로도 예외 없음(`.specops/` 아래 파일만 뺀다 — FID 작업 파일·memory 문서는 제품 코드가 아니다)
#   RULE <ID> (<적용 경로>) — <규칙> — 닿는 파일: …   헌법 구조 규칙 중 이 plan 의 파일에 닿는 것(정보 — 경고 아님)
#   [판정 불가] …    plan 을 확인할 수 없음(끊어진 링크·들어갈 수 없는 디렉터리) · 파일 목록을 찾지 못함 · 구조 규칙 표를 읽지 못함 — "없음"으로 쓰지 않는다
# Exit: 0 = 판정 완료(경고 포함)·SKIP · 1 = 사용 오류 · 2 = 판정 불가 항목 있음
#
# 막지 않는다: planning-ko 는 종료 코드와 무관하게 진행하고, 이 출력을 plan-reviewer 에 넘긴다(리뷰어는 Minor 로만 적는다).
# 경로는 파일 구조 절(제목에 `파일` 이 든 `##` 절)의 목록 항목 줄·표 첫 칸의 백틱에서만 뽑는다 — 산문 백틱은 보지 않는다(오탐).
# 구조 규칙 표는 check-constitution-rules.sh --list 로만 읽는다(표 규칙을 두 군데에 두지 않는다).
# 한계: import 방향은 보지 않는다(헌법 판정 명령·리뷰어 몫). 경로 비교는 폴더 경계 기준 접두 비교다(소유 `src` 는 `src/a.sh` 를 포함하고 `src2/` 는 포함하지 않는다 · 심볼릭 링크·`..` 해석 없음).
#   굵은 이름표(`**Create:** \`x\``)처럼 위 꼴이 아닌 줄의 경로는 뽑지 않는다(조용히 빠진다 — 판정 불가는 경로가 하나도 없을 때만).
set -u
set -f   # 규칙 적용 경로를 단어로 나눌 때 `*` 가 파일 이름으로 펼쳐지지 않게
export LC_ALL=C   # 바이트로 비교한다 — macOS awk 의 `==` 는 로캘 정렬(strcoll)이라 UTF-8 에서 다른 한글 칸 이름을 같다고 본다(실측)

HERE=$(cd "$(dirname "$0")" && pwd)
SPECOPS="${SPECOPS_ROOT:-.specops}"
PLAN=""; CONST="$SPECOPS/memory/constitution.md"
usage() { echo "usage: check-plan-boundary.sh <FID> | --plan <경로> [--constitution <경로>]" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --plan)         [ $# -ge 2 ] && [ -z "$PLAN" ] || usage; PLAN="$2"; shift 2 ;;
    --constitution) [ $# -ge 2 ] || usage; CONST="$2"; shift 2 ;;
    -*|"")          usage ;;
    *)              [ -z "$PLAN" ] || usage; PLAN="$SPECOPS/$1/plan.md"; shift ;;
  esac
done
[ -n "$PLAN" ] || usage

WARN=0; CANT=0; LINES=""
add()  { LINES="${LINES}  $1"$'\n'; }
warn() { add "[경고] $1"; WARN=1; }
cant() { add "[판정 불가] $1"; CANT=1; }

# "없음"과 "확인할 수 없음"을 가른다 — 끊어진 링크·들어갈 수 없는 상위 디렉터리는 부재가 아니다(check-constitution-rules.sh 와 같은 구분).
if [ ! -e "$PLAN" ]; then
  _why=""
  if [ -L "$PLAN" ]; then
    _why="따라갈 수 없는 심볼릭 링크"
  else
    _d=$(dirname "$PLAN")
    while [ ! -e "$_d" ] && [ ! -L "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do _d=$(dirname "$_d"); done
    if [ -L "$_d" ] && [ ! -e "$_d" ]; then _why="따라갈 수 없는 심볼릭 링크(상위 경로 $_d)"
    elif [ ! -d "$_d" ] || [ ! -x "$_d" ]; then _why="들어갈 수 없는 상위 경로 $_d"; fi
  fi
  if [ -n "$_why" ]; then
    cant "plan — 확인할 수 없음($_why): $PLAN"
    printf 'PLAN-BOUNDARY: WARN\n%s' "$LINES"; exit 2
  fi
  echo "PLAN-BOUNDARY: SKIP (plan.md 부재 — lite·trivial 정상 경로)"; exit 0
fi

if [ ! -f "$PLAN" ] || [ ! -r "$PLAN" ]; then
  cant "plan — 읽을 수 없음: $PLAN"
  printf 'PLAN-BOUNDARY: WARN\n%s' "$LINES"; exit 2
fi

# 한 번의 awk 로 plan 을 읽는다(CR 제거). 출력 줄:
#   B<TAB>1                       경계 약속 절이 있다
#   K<TAB><칸 이름><TAB><값>       경계 약속 칸
#   F<TAB><경로>                  파일 구조 절의 목록 항목·표 첫 칸에서 뽑은 백틱 경로
#   Z<TAB>end                     끝까지 읽었다
# mawk 호환: 구간 반복({2,4})·한글 문자 클래스를 쓰지 않는다 — 한글은 index() 로 찾는다.
parsed=$(awk '
  { sub(/\r$/, "") }
  /^(```|~~~)/ { fence = !fence; next }
  fence { next }
  /^#+ / {
    lvl = index($0, " ") - 1
    if (index($0, "경계 약속") > 0 && lvl >= 2 && lvl <= 4) { inbd = 1; bdl = lvl; print "B\t1"; next }
    if (inbd && lvl <= bdl) inbd = 0
    if (lvl == 2) infile = (index($0, "파일") > 0)
    next
  }
  inbd {
    if ($0 ~ /^[-*][ \t]+\*\*[^*]+\*\*:/) {
      s = $0; sub(/^[-*][ \t]+\*\*/, "", s)
      k = s; sub(/\*\*:.*$/, "", k)
      v = s; sub(/^[^*]*\*\*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      print "K\t" k "\t" v
    }
    next
  }
  # 목록 항목 줄(`-`·`*`·`1.`): 백틱이 바로 오거나, 짧은 이름표(`생성:`·`T1:` 처럼 백틱 없는 30바이트 이하 + 콜론) 뒤에 온다.
  #   그 줄의 백틱 토큰 중 경로처럼 생긴 것(공백 없음 · `/` 나 `.` 포함)을 모두 뽑는다 — `if [ … ]` 같은 코드 조각은 빠진다.
  # 표 행: 첫 칸이 백틱이면 첫 칸 토큰만 뽑는다(다른 칸은 설명이다).
  infile && /^[ \t]*([-*]|[0-9]+\.)[ \t]+/ {
    s = $0; sub(/^[ \t]*([-*]|[0-9]+\.)[ \t]+/, "", s)
    b = index(s, "`"); if (b == 0) next
    pre = substr(s, 1, b - 1)
    if (pre != "" && !(pre ~ /:[ \t]*$/ && length(pre) <= 30)) next
    emit(substr(s, b)); next
  }
  infile && /^\|[ \t]*`/ {
    s = $0; sub(/^\|[ \t]*/, "", s); e = index(s, "|"); if (e > 0) s = substr(s, 1, e - 1)
    emit(s); next
  }
  function emit(s,   t, e, p) {
    while ((t = index(s, "`")) > 0) {
      s = substr(s, t + 1); e = index(s, "`"); if (e == 0) return
      p = substr(s, 1, e - 1); s = substr(s, e + 1)
      sub(/:[0-9][0-9,-]*$/, "", p); sub(/^\.\//, "", p)
      # 경로꼴 = 공백 없음 · `/` 나 `.` 포함(spec FR-4). 셸·코드 조각 글자(< > | * ? $ ")와 `-`·`=` 로 시작하는 옵션꼴은 뺀다.
      #   문자 집합을 좁히지 않는다 — 한글·`[id]`·`(group)`·`@`·`+` 경로가 조용히 빠지면 소유 밖 파일이 있어도 OK 가 난다.
      if (p !~ /[ \t<>|*?$"]/ && p !~ /^[-=]/ && (index(p, "/") > 0 || index(p, ".") > 0)) print "F\t" p
    }
  }
  END { print "Z\tend" }
' "$PLAN" 2>/dev/null); arc=$?
if [ "$arc" -ne 0 ] || [ "$(printf '%s\n' "$parsed" | tail -1)" != "$(printf 'Z\tend')" ]; then
  cant "plan — 읽는 도구가 실패함(awk rc=$arc)"
  printf 'PLAN-BOUNDARY: WARN\n%s' "$LINES"; exit 2
fi

files=$(printf '%s\n' "$parsed" | sed -n 's/^F	//p' | awk '!seen[$0]++')

# ── 경계 약속 절과 칸 ────────────────────────────────────────────────
owned=""
if ! printf '%s\n' "$parsed" | grep -q '^B	1$'; then
  warn "경계 약속 절 없음 — templates/plan.md 의 \`### 경계 약속\` 칸 4개(소유·범위 밖·허용 의존·다시 검토할 조건)를 채우세요"
else
  for k in "소유" "범위 밖" "허용 의존" "다시 검토할 조건"; do
    v=$(printf '%s\n' "$parsed" | awk -F '\t' -v k="$k" '$1 == "K" && $2 == k { sub(/^K\t[^\t]*\t/, ""); print; exit }')
    if ! printf '%s\n' "$parsed" | awk -F '\t' -v k="$k" '$1 == "K" && $2 == k { f = 1 } END { exit !f }'; then
      warn "칸 없음: $k"
    elif [ -z "$v" ]; then
      warn "칸 비어 있음: $k"
    elif [ "${v#<}" != "$v" ]; then
      warn "칸 자리표시자 그대로: $k"
    elif [ "$k" = "소유" ]; then
      owned=$(printf '%s\n' "$v" | grep -oE '`[^`]+`' | tr -d '`' | sed 's#^\./##')
      [ -n "$owned" ] || warn "소유 칸에 백틱 경로가 없어 소유 밖 비교를 하지 않음"
    fi
  done
fi

# 경로 접두 판정: 같은 경로이거나, 접두가 `/` 로 끝나면 그 아래, 아니면 접두 + `/` 아래
_under() {  # $1=경로 $2=접두
  case "$2" in
    */) case "$1" in "$2"*) return 0 ;; esac ;;
    *)  [ "$1" = "$2" ] && return 0; case "$1" in "$2"/*) return 0 ;; esac ;;
  esac
  return 1
}

# ── 파일 목록 ↔ 소유 ────────────────────────────────────────────────
if [ -z "$files" ]; then
  cant "파일 목록 — 파일 구조 절(제목에 '파일' 이 든 ## 절)의 목록 항목에서 백틱 경로를 찾지 못함 — 소유 밖 비교·구조 규칙 접점을 판정하지 못했다"
else
  if [ -n "$owned" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in .specops/*|*/.specops/*) continue ;; esac   # `.specops/` 아래(FID 작업 파일·memory 문서)는 제품 코드가 아니다
      hit=0
      while IFS= read -r o; do [ -n "$o" ] && _under "$f" "$o" && { hit=1; break; }; done <<EOF_O
$owned
EOF_O
      [ "$hit" = 1 ] || { add "[소유 밖] $f"; WARN=1; }
    done <<EOF_F
$files
EOF_F
  fi

  # ── 헌법 구조 규칙 접점 ─────────────────────────────────────────────
  LIST_SH="$HERE/check-constitution-rules.sh"
  if [ ! -f "$LIST_SH" ]; then
    cant "구조 규칙 — 판독기 없음(check-constitution-rules.sh)"
  else
    rerr=$(mktemp "${TMPDIR:-/tmp}/plan-boundary.XXXXXX") || rerr=""
    rrc=0; rules=$(bash "$LIST_SH" --list "$CONST" 2>"${rerr:-/dev/null}") || rrc=$?
    if [ "$rrc" -ne 0 ]; then
      why=$( [ -n "$rerr" ] && head -1 "$rerr" ); [ -n "$why" ] || why="사유 없음"
      cant "구조 규칙 — 표를 읽지 못함(rc=$rrc) — $why"
    else
      while IFS='|' read -r rid rtext rpath _rest; do
        [ -n "$rid" ] || continue
        hits=""
        for pre in $(printf '%s\n' "$rpath" | tr -d '`' | tr ',' ' '); do
          pre=${pre#./}; [ -n "$pre" ] || continue
          while IFS= read -r f; do
            [ -n "$f" ] && _under "$f" "$pre" || continue
            case ",$hits," in *",$f,"*) ;; *) hits="${hits:+$hits,}$f" ;; esac
          done <<EOF_R
$files
EOF_R
        done
        [ -n "$hits" ] && add "RULE $rid ($rpath) — $rtext — 닿는 파일: $(printf '%s' "$hits" | sed 's/,/, /g')"
      done <<EOF_L
$rules
EOF_L
    fi
    [ -n "$rerr" ] && rm -f "$rerr"
  fi
fi

if [ "$WARN" = 1 ] || [ "$CANT" = 1 ]; then echo "PLAN-BOUNDARY: WARN"; else echo "PLAN-BOUNDARY: OK"; fi
printf '%s' "$LINES"
[ "$CANT" = 1 ] && exit 2
exit 0
