#!/usr/bin/env bash
# check-constitution-rules.sh — 헌법의 「구조 규칙」 표를 읽는다 (형식 판정 + 기계용 줄 출력 · 읽기 전용)
#
# Usage:
#   check-constitution-rules.sh [--list] [헌법 파일]     # 기본 파일: ${SPECOPS_ROOT:-.specops}/memory/constitution.md
#
# 표는 헌법 안의 두 표지 사이에 있다(표지는 줄 전체가 표지여야 한다):
#   <!-- structure-rules:start -->
#   | ID | 규칙 | 적용 경로 | 판정 | 판정 명령 |
#   |---|---|---|---|---|
#   | S-1 | 외부 API 는 어댑터에서만 부른다 | `src/adapters/` | 리뷰 | - |
#   <!-- structure-rules:end -->
# 표지 사이의 첫 행은 위 머리 행, 둘째 행은 구분 행이어야 한다. 그 뒤로 ID 칸이 `(예시)` 로 시작하는 행은
# 규칙이 아니다(읽지 않는다). 표지 사이에는 빈 줄과 표 행만 둘 수 있다. 표지 없이 머리 행만 있으면 위반이다(표지 낱말을 틀리게 적은 경우).
#
# 종료 코드 — 셋을 섞지 않는다:
#   0 = 형식 통과(규칙 N건) 또는 해당 없음(헌법 없음 · 절 없음 · 규칙 0건)
#   1 = 형식 위반 (위반마다 `파일:줄: 사유` 를 표준 오류로)
#   2 = 판정 불가 (사용 오류 · 파일에 닿을 수 없거나 읽을 수 없음(정책으로 접근이 거부된 파일 포함) · 텍스트가 아님 · 내부 도구 실패) — "규칙 0건"으로 답하지 않는다
# --list: 형식이 통과일 때만 규칙마다 `ID|규칙|적용 경로|판정|판정 명령` 한 줄을 표준 출력으로 낸다
#   (칸 앞뒤 공백 제거 · 판정 명령이 없으면(`-` 포함) 빈 칸 · 백틱은 적힌 그대로). 그 밖의 줄은 전부 표준 오류로 간다.
# 한계: 칸 안에 `|` 를 쓸 수 없다(칸 수 위반으로 잡힌다). 규칙 내용의 옳고 그름·경로 실재·명령 실행 가능 여부는 보지 않는다.
#   UTF-8 이 아닌 헌법은 지원하지 않는다(NUL 바이트가 있으면 판정 불가, 그 밖의 인코딩은 표지·낱말이 맞지 않아 위반이나 절 없음으로 읽힌다).
#   부르는 곳(모두 --list): scripts/dag/emit-context.sh(dispatch 컨텍스트 §8) · check-rule-commands.sh(verify 가 `명령` 규칙 실행) ·
#   check-plan-boundary.sh(plan 파일이 닿는 규칙을 plan-reviewer 에 전달). 표가 틀려도 아무것도 막지 않는다 — 부르는 쪽이 경고만 남긴다.
set -u

SPECOPS="${SPECOPS_ROOT:-.specops}"
LIST=0; FILE=""; GOT=0
usage() { echo "usage: check-constitution-rules.sh [--list] [헌법 파일]" >&2; }
for a in "$@"; do
  case "$a" in
    --list) LIST=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage; exit 2 ;;
    *) if [ "$GOT" = 0 ] && [ -n "$a" ]; then FILE="$a"; GOT=1; else usage; exit 2; fi ;;   # 빈 인자·둘째 파일 인자는 사용 오류
  esac
done
[ "$GOT" = 1 ] || FILE="$SPECOPS/memory/constitution.md"

# 요약 줄 — --list 일 때 표준 출력은 규칙 줄 전용이라 표준 오류로 보낸다.
say() { if [ "$LIST" = 1 ]; then printf '%s\n' "$1" >&2; else printf '%s\n' "$1"; fi; }
cant() { echo "CONSTITUTION-RULES: 판정 불가 — $1: $FILE" >&2; exit 2; }

# "없음"과 "확인할 수 없음"을 가른다 — 없다고 답하려면 그 자리까지 실제로 가 볼 수 있어야 한다.
if [ ! -e "$FILE" ]; then
  [ -L "$FILE" ] && cant "따라갈 수 없는 심볼릭 링크"
  d=$(dirname "$FILE"); c=$FILE
  while [ ! -e "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
    [ -L "$d" ] && cant "따라갈 수 없는 심볼릭 링크(상위 경로 $d)"      # 링크인 조상을 지나쳐 올라가면 그 너머를 못 본 채 "없음"이라 답하게 된다
    c=$d; d=$(dirname "$d")
  done
  if [ ! -d "$d" ] || [ ! -x "$d" ]; then cant "경로를 확인할 수 없음(들어갈 수 없는 상위 경로 $d)"; fi
  # 목록에는 이름이 있는데 stat 이 안 되면 없는 것이 아니라 거부된 것이다(샌드박스·TCC·SELinux 류 정책). 목록을 못 읽으면(ls 실패) stat 의 "없음"을 따른다.
  # ls 출력은 호출자 환경(CLICOLOR 류)에 따라 바뀐다 — 색을 내려고 stat 하다 거부된 항목을 목록에서 뺀다. 셸이 디렉터리 항목을 직접 읽는다.
  cb=$(basename "$c")
  if ( shopt -s nullglob dotglob; for e in "$d"/*; do [ "${e##*/}" = "$cb" ] && exit 0; done; exit 1 ); then cant "이름은 있는데 확인할 수 없음(접근 거부 — $c)"; fi
  say "CONSTITUTION-RULES: SKIP (헌법 없음: $FILE)"; exit 0
fi
if [ ! -f "$FILE" ] || [ ! -r "$FILE" ]; then cant "읽을 수 없는 파일"; fi
if [ "$(LC_ALL=C tr -d '\000' < "$FILE" 2>/dev/null | wc -c | tr -d ' ')" != "$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')" ]; then
  cant "텍스트 파일이 아님(NUL 바이트 — UTF-16 등은 지원하지 않는다)"
fi

# 한 번의 awk 로 읽는다. 출력 줄: E<TAB>줄번호<TAB>사유 · R<TAB>규칙 줄 · 마지막에 Z<TAB>표지 쌍 수(끝까지 돌았다는 표시).
out=$(LC_ALL=C awk '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  function bare(s) { gsub(/`/, "", s); return trim(s) }                 # 백틱을 벗긴 값(빈 값·자리표시자 판정용)
  function err(n, why) { print "E\t" n "\t" why; nerr++ }
  function row(line, n,   c, k, i, id, rule, path, mode, cmd, sep) {
    nrow++
    if (line !~ /\|[ \t]*$/) { err(n, "표 행이 | 로 끝나지 않음"); return }
    k = split(line, c, "|") - 2                                          # 양끝의 빈 조각을 뺀 칸 수
    for (i = 1; i <= k; i++) c[i] = trim(c[i + 1])
    if (nrow == 1) {                                                     # 첫 행 = 머리 행(칸 이름·순서가 계약이다)
      if (!(k == 5 && c[1] == "ID" && c[2] == "규칙" && c[3] == "적용 경로" && c[4] == "판정" && c[5] == "판정 명령"))
        err(n, "첫 행이 머리 행이 아님 — | ID | 규칙 | 적용 경로 | 판정 | 판정 명령 |")
      return
    }
    if (nrow == 2) {                                                     # 둘째 행 = 구분 행
      sep = (k == 5); for (i = 1; i <= k; i++) if (c[i] !~ /^:?-+:?$/) sep = 0
      if (!sep) err(n, "둘째 행이 구분 행이 아님 — |---|---|---|---|---|")
      return
    }
    if (k >= 1 && index(c[1], "(예시)") == 1) return                     # 예시 행 — 읽지 않는다
    if (k != 5) { err(n, "칸이 5개가 아님(" k "개) — 칸 안에 | 를 쓸 수 없다"); return }
    id = c[1]; rule = c[2]; path = c[3]; mode = c[4]; cmd = c[5]
    if (id !~ /^S-[0-9]+$/) err(n, "ID 가 S-숫자 꼴이 아님: " id)
    else if (id in seen) err(n, "ID 중복: " id " (앞선 줄 " seen[id] ")")
    else seen[id] = n
    if (bare(rule) == "" || bare(rule) ~ /^<.*>$/) err(n, "규칙 칸이 비었거나 자리표시자")
    if (bare(path) == "" || bare(path) ~ /^<.*>$/) err(n, "적용 경로 칸이 비었거나 자리표시자")
    if (mode != "리뷰" && mode != "명령") err(n, "판정은 리뷰 또는 명령: " mode)
    if (bare(cmd) == "-") cmd = ""
    if (mode == "명령" && bare(cmd) == "") err(n, "판정이 명령인데 판정 명령이 비었음")
    rules[++nr] = id "|" rule "|" path "|" mode "|" cmd
  }
  { line = $0; sub(/\r$/, "", line) }
  line ~ /^[ \t]*<!--[ \t]*structure-rules:start[ \t]*-->[ \t]*$/ {
    starts++; if (open) err(NR, "시작 표지가 닫히지 않은 채 다시 나옴"); open = 1; openline = NR; nrow = 0; next
  }
  line ~ /^[ \t]*<!--[ \t]*structure-rules:end[ \t]*-->[ \t]*$/ {
    if (!open) err(NR, "끝 표지가 시작 표지 없이 나옴"); open = 0; next
  }
  index(line, "structure-rules:") > 0 { err(NR, "표지 꼴이 틀림 — 줄 전체가 표지여야 한다(앞뒤에 다른 글자 금지 · 콜론 뒤 공백 금지)"); next }
  !open { t = line; gsub(/[ \t]/, "", t); if (t == "|ID|규칙|적용경로|판정|판정명령|" && !hdrout) hdrout = NR }   # 표지 밖의 머리 행 — 표지가 하나도 없을 때만 쓴다
  open {
    t = trim(line); if (t == "") next
    if (substr(t, 1, 1) != "|") { err(NR, "표지 사이에 표 행이 아닌 줄 — 행은 | 로 시작한다"); next }
    row(t, NR)
  }
  END {
    if (open) err(openline, "시작 표지가 닫히지 않음(끝 표지 없음)")
    if (starts > 1) err(openline, "구조 규칙 표지 쌍이 둘 이상 — 하나만 둔다")
    if (starts == 0 && hdrout) err(hdrout, "구조 규칙 머리 행은 있는데 시작 표지가 없음 — 표지 낱말·꼴을 확인한다")
    for (i = 1; i <= nr; i++) print "R\t" rules[i]                      # 위반이 있으면 아래 셸이 규칙을 내지 않고 끝낸다
    print "Z\t" starts + 0 "\t" nerr + 0
  }' "$FILE" 2>/dev/null); arc=$?

zline=$(printf '%s\n' "$out" | LC_ALL=C grep '^Z	' | tail -1)
if [ "$arc" -ne 0 ] || [ -z "$zline" ]; then cant "표를 읽는 도구가 실패함(awk rc=${arc})"; fi
zline=${zline#Z	}; starts=${zline%%	*}; zerr=${zline#*	}
case "$starts" in ''|*[!0-9]*) cant "읽은 결과를 해석할 수 없음" ;; esac
case "$zerr" in ''|*[!0-9]*) cant "읽은 결과를 해석할 수 없음" ;; esac

nerr=0; nrule=0; rules=""
while IFS= read -r l; do
  case "$l" in
    E"	"*) nerr=$((nerr + 1)); l=${l#E	}; printf '%s:%s: %s\n' "$FILE" "${l%%	*}" "${l#*	}" >&2 ;;
    R"	"*) nrule=$((nrule + 1)); rules="${rules}${l#R	}
" ;;
  esac
done <<EOF_OUT
$out
EOF_OUT
[ "$nerr" -eq "$zerr" ] || cant "읽은 결과가 어긋남(위반 ${zerr}건 중 ${nerr}건만 읽힘)"

if [ "$nerr" -gt 0 ]; then
  echo "CONSTITUTION-RULES: FAIL (형식 위반 ${nerr}건: $FILE)" >&2; exit 1
fi
if [ "$starts" -eq 0 ]; then say "CONSTITUTION-RULES: SKIP (구조 규칙 절 없음: $FILE)"; exit 0; fi
if [ "$nrule" -eq 0 ]; then say "CONSTITUTION-RULES: SKIP (규칙 0건 — 예시 행만 있거나 표가 비어 있음: $FILE)"; exit 0; fi
[ "$LIST" = 1 ] && printf '%s' "$rules"
say "CONSTITUTION-RULES: OK (규칙 ${nrule}건: $FILE)"
exit 0
