#!/usr/bin/env bash
# specops-ko 간이 뮤테이션 하니스 (수동 측정 도구)
# 사용: bash scripts/tests/mutation-score.sh [config]
#       bash scripts/tests/mutation-score.sh --check-conf [config]   # 변이 없이 equivalent conf 정합만 검사 (1초)
#       bash scripts/tests/mutation-score.sh --anchor <target> <line> <pattern>   # 그 사이트의 equivalent conf 행을 출력
#         (reason 칸은 비어 있다. 터미널에서 복사하면 TAB 이 공백으로 바뀔 수 있으니 `>> mutation-equivalent.conf` 로 붙인다)
#       bash scripts/tests/mutation-score.sh --target <target-path> [config]   # 해당 대상 1건만 측정 (CI matrix 용 —
#         conf 에 없는 대상이면 rc 2: 오타 난 matrix 항목이 "0건 측정 = 초록" 으로 통과하는 것을 막는다)
# 소스 가능 — 함수만 정의, main 은 가드. run-all 미포함(test-*.sh 비매칭 명명).
set -uo pipefail

mut::catalog() {
  printf '%s\t%s\n' '-eq' 's/-eq/-ne/'
  printf '%s\t%s\n' '-ne' 's/-ne/-eq/'
  printf '%s\t%s\n' '-gt' 's/-gt/-lt/'
  printf '%s\t%s\n' '-lt' 's/-lt/-gt/'
  printf '%s\t%s\n' 'return 0' 's/return 0/return 1/'
  printf '%s\t%s\n' '&&' 's/&&/||/'
}

mut::judge() {  # <test_command> → killed|survived
  if bash -c "$1" >/dev/null 2>&1; then echo survived; else echo killed; fi
}

mut::score() {  # <killed> <survived> → 백분율 정수
  local killed="$1" survived="$2" total=$(( $1 + $2 ))
  [ "$total" -eq 0 ] && { echo 0; return 0; }
  echo $(( killed * 100 / total ))
}

# ── equivalent conf 의 키: 줄번호가 아니라 **함수 + 줄 원문** (20261010-mutation-equiv-anchors) ──
# 종전 키는 절대 줄번호였다. 대상 파일이 자라면 줄이 밀리고, 밀린 자리에 마침 같은 패턴의 다른 줄이 오면
#   --check-conf 가 통과한 채로 **엉뚱한 가드가 등가로 빠졌다**(실측 3건 — conf 머리말). 재정렬을 6번 했다.
# 지금 키는 (target · 함수 · pattern · 줄 원문)이고 **정확 일치**다. 다른 곳에 줄을 넣고 빼도 따라가고,
#   그 줄 자체가 바뀌거나 같은 원문의 줄이 함수 안에 늘거나 줄면 STALE 로 멈춘다(조용히 다른 줄에 붙지 않는다).
# conf 행(TAB 구분 5칸): <target> <함수[#k/n]> <pattern> <원문> <reason>
#   · TAB 인 이유: 줄 원문과 reason 에 `|` 가 흔하다(`… || return 0`). 원문은 공백을 정규화하므로 TAB 을 품지 않는다.
#   · #k/n: 같은 (함수·pattern·원문) 줄이 n개일 때 위에서 k번째. n 이 달라지면 STALE — 순번만 적으면 같은 원문의
#     줄이 앞에 하나 끼는 순간 순번이 조용히 밀린다(줄번호 키와 같은 병).
#   · 행은 `--anchor <target> <line> <pattern>` 이 만들어 준다(reason 만 덧붙인다).

# 사이트 맵 — 대상 파일의 모든 변이 사이트를 한 번에 푼다. conf 를 푸는 쪽과 행을 만드는 쪽이 이것 하나를 쓴다.
#   출력(TAB, 사이트당 1줄): <line> <pattern> <func> <k> <n> <text>
#     func: col-0 `name()`(또는 `function name`) 헤더부터 col-0 `}` 까지. 함수 밖은 `-`.
#     text: 줄 원문에서 앞뒤 공백을 떼고 연속 공백을 1칸으로 줄인 것.
#   ★ 한계 고백: 함수 경계는 lexical 이다 — heredoc·문자열 안의 col-0 `}` 나 `name()` 도 경계로 본다. 헤더 줄의 주석이
#     `}` 로 끝나면(`f() { # note }`) 여러 줄 함수를 한 줄 함수로 본다. 어느 쪽이든 결과는 결정적이고(같은 파일 → 같은 맵),
#     등재 행이 걸리면 STALE 로 드러난다. 20261010 의 대상 6종에는 해당 줄이 없다(함수별 `bash -n` 대조).
mut::site_map() {  # <file>
  [ -f "$1" ] || return 0
  MUT_PATS="$(mut::catalog | cut -f1)" awk '
    function norm(s) { gsub(/[ \t\r\f\v]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
    BEGIN { np = split(ENVIRON["MUT_PATS"], P, "\n"); cur = "-" }
    {
      hdr = 0
      if (match($0, /^(function[ \t]+[A-Za-z_][A-Za-z0-9_:.-]*|[A-Za-z_][A-Za-z0-9_:.-]*[ \t]*\(\))/)) {
        name = substr($0, RSTART, RLENGTH)
        sub(/^function[ \t]+/, "", name); sub(/[ \t]*\(\)$/, "", name)
        cur = name; hdr = 1
      }
      t = norm($0)
      # 주석 줄은 사이트가 아니다 (mut::is_comment_line 과 같은 기준)
      if (t != "" && substr(t, 1, 1) != "#") {
        for (i = 1; i <= np; i++) {
          if (P[i] == "" || index($0, P[i]) == 0) continue
          key = cur SUBSEP P[i] SUBSEP t
          cnt[key]++; m++
          L[m] = NR; PT[m] = P[i]; F[m] = cur; K[m] = cnt[key]; KEY[m] = key; T[m] = t
        }
      }
      # 한 줄 함수(`f() { …; }`)는 그 줄에서 끝난다
      if (hdr) { if ($0 ~ /\{.*\}[ \t]*(#.*)?$/) cur = "-" }
      else if (substr($0, 1, 1) == "}") cur = "-"
    }
    END { for (i = 1; i <= m; i++) printf "%d\t%s\t%s\t%d\t%d\t%s\n", L[i], PT[i], F[i], K[i], cnt[KEY[i]], T[i] }
  ' "$1"
}

mut::_equiv_conf() { printf '%s' "${MUT_EQUIV_CONF:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mutation-equivalent.conf}"; }

# conf 형식 검사 — 대상과 무관하게 전 행을 본다. 깨진 행은 건너뛰지 않고 STALE 로 낸다
#   (건너뛰면 그 행의 등가 제외가 조용히 사라져 score 가 거짓 하락한다).
mut::conf_format_errors() {  # <equiv_conf> → stdout 'STALE <행> (<사유>)' · rc 0(깨끗) | 1
  awk -F'\t' '
    $0 ~ /^[ \t]*$/ || substr($0, 1, 1) == "#" { next }
    {
      why = ""
      if (NF == 1 && $0 ~ /^[^|]+\|[0-9]+\|/) why = "구 형식 — 줄번호 키다. --anchor <target> <line> <pattern> 출력으로 바꾼다"
      else if (NF != 5) why = "형식 오류 — TAB 으로 나눈 5칸(target·함수·pattern·원문·reason)이어야 한다. 지금 " NF "칸"
      else if ($3 == "") why = "pattern 필드 비어 있음"
      else if ($1 == "" || $2 == "" || $4 == "") why = "형식 오류 — target·함수·원문 중 빈 칸"
      else if ($5 ~ /^[ \t]*$/) why = "reason 비어 있음 — 근거 없는 등재는 받지 않는다"
      if (why != "") { d = $0; gsub(/\t/, "|", d); print "STALE " d " (" why ")"; bad = 1 }
    }
    END { exit bad ? 1 : 0 }
  ' "$1"
}

# target 표기가 대상 목록과 어긋나 **통째로 무시되는 행**을 찾는다 — 없는 파일(오타)과 같은 파일의 다른 표기(`./x` · 절대경로).
#   행은 target 문자열이 대상 목록과 글자 그대로 같아야 풀린다. 어긋난 행은 어느 대상의 것도 아니게 되어, 형식이 멀쩡한 채
#   등가 제외만 사라진다(score 거짓 하락). 목록에 없는 **다른 실재 파일**의 행은 건드리지 않는다 — 대상 일부만 담은
#   targets conf 로 재는 쓰임이 있다.
mut::conf_orphan_targets() {  # <equiv_conf> <targets_conf> → stdout 'STALE <target>|*| (<사유>)' · rc 0(깨끗) | 1
  local equiv="$1" tconf="$2" rc=0 listed n et x same
  listed=$(grep -v '^#' "$tconf" | cut -d'|' -f1 | grep .)
  while IFS=$'\t' read -r n et; do
    [ -n "$et" ] || continue
    case $'\n'"$listed"$'\n' in *$'\n'"$et"$'\n'*) continue ;; esac
    if [ ! -f "$et" ]; then
      echo "STALE ${et}|*| (target 파일이 없다 — ${n}행이 조용히 무시된다)"; rc=1; continue
    fi
    same=""
    while IFS= read -r x; do
      [ -n "$x" ] && [ "$et" -ef "$x" ] && same="$x"
    done <<EOF
$listed
EOF
    if [ -n "$same" ]; then
      echo "STALE ${et}|*| (target 표기가 대상 목록의 '${same}' 와 다르다 — ${n}행이 조용히 무시된다)"; rc=1
    fi
  done < <(awk -F'\t' '$0 !~ /^[ \t]*$/ && substr($0, 1, 1) != "#" && NF == 5 && $1 != "" { c[$1]++ }
                       END { for (k in c) print c[k] "\t" k }' "$equiv" | sort -t"$(printf '\t')" -k2)
  return $rc
}

# conf 의 <target> 행을 사이트로 푼다. stdout:
#   EQ<TAB><line><TAB><pattern>                         — 등가로 풀린 사이트
#   STALE <target>|<함수>|<pattern>|<원문>| (<사유>)     — 풀리지 않는 행 (0건 · 같은 원문 여럿 · 개수 불일치)
#   형식이 깨진 행은 여기서 다루지 않는다(mut::conf_format_errors 가 잡는다).
#   <content-file> 을 따로 주는 이유: run_target 은 대상 파일을 제자리에서 변이하므로 원본 사본에서 풀어야 한다.
mut::resolve_conf() {  # <target> [<content-file>=target]
  local target="$1" file="${2:-$1}" conf
  conf=$(mut::_equiv_conf)
  [ -f "$conf" ] || return 0
  # 사이트 맵과 conf 를 한 줄기로 넘긴다(구분은 \001 한 줄) — 맵이 비어도 FNR==NR 류의 오판이 없다.
  { mut::site_map "$file"; printf '\001\n'; cat "$conf"; } | MUT_TGT="$target" awk -F'\t' '
    function norm(s) { gsub(/[ \t\r\f\v]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
    BEGIN { tgt = ENVIRON["MUT_TGT"]; inmap = 1 }
    inmap {
      if ($0 == "\001") { inmap = 0; next }
      key = $3 SUBSEP $2 SUBSEP $6
      cnt[key] = $5 + 0; at[key SUBSEP ($4 + 0)] = $1
      next
    }
    $0 ~ /^[ \t]*$/ || substr($0, 1, 1) == "#" { next }
    NF != 5 || $1 != tgt || $2 == "" || $3 == "" || $4 == "" { next }
    {
      disp = $1 "|" $2 "|" $3 "|" $4 "|"
      f = $2; k = 1; n = 0; h = index(f, "#")
      if (h) {
        ord = substr(f, h + 1); f = substr(f, 1, h - 1)
        if (ord !~ /^[0-9]+\/[0-9]+$/) { print "STALE " disp " (순번 표기 오류 — 함수#k/n 꼴이어야 한다)"; next }
        s = index(ord, "/"); k = substr(ord, 1, s - 1) + 0; n = substr(ord, s + 1) + 0
        if (k < 1 || k > n) { print "STALE " disp " (순번 표기 오류 — k 는 1 이상 n 이하)"; next }
      }
      key = f SUBSEP $3 SUBSEP norm($4)
      c = (key in cnt) ? cnt[key] : 0
      if (c == 0)           print "STALE " disp " (매칭 사이트 0건)"
      else if (!h && c > 1) print "STALE " disp " (같은 원문 " c "건 — " f "#k/" c " 로 몇 번째인지 적는다)"
      else if (h && c != n) print "STALE " disp " (개수 불일치 — conf " n "건, 지금 " c "건)"
      else                  print "EQ\t" at[key SUBSEP k] "\t" $3
    }
  '
}

# 등가로 풀린 사이트 집합 — '<line><TAB><pattern>' 줄들.
mut::equiv_sites() {  # <target> [<content-file>]
  mut::resolve_conf "$@" | awk -F'\t' '$1 == "EQ" { print $2 "\t" $3 }'
}

# 집합 소속 판정. 파이프(`… | grep -q`)를 쓰지 않는다 — pipefail 아래에서 grep 이 먼저 끝나면 앞단이 SIGPIPE 로
#   죽어 "찾았는데 실패" 가 된다.
mut::_in_sites() {  # <sites> <line> <pattern>
  case $'\n'"$1"$'\n' in *$'\n'"$2"$'\t'"$3"$'\n'*) return 0 ;; esac
  return 1
}

# equivalent-mutant 판정 (return-code/관찰불가 변형 제외용)
# config: MUT_EQUIV_CONF env 또는 스크립트 디렉토리 mutation-equivalent.conf
mut::is_equivalent() {  # <target> <line> <pattern> [<content-file>] → 0(equivalent) | 1
  mut::_in_sites "$(mut::equiv_sites "$1" "${4:-$1}")" "$2" "$3"
}

# conf 행 만들기 — 그 사이트의 키를 conf 형식으로 낸다(reason 칸은 비워 둔다 — 근거는 사람이 쓴다).
mut::anchor_row() {  # <target> <line> <pattern> → stdout 행 접두 · rc 1 = 그 줄은 사이트가 아니다
  mut::site_map "$1" | MUT_TGT="$1" MUT_L="$2" MUT_P="$3" awk -F'\t' '
    $1 + 0 == ENVIRON["MUT_L"] + 0 && $2 == ENVIRON["MUT_P"] {
      f = $3; if ($5 + 0 > 1) f = f "#" $4 "/" $5
      printf "%s\t%s\t%s\t%s\t\n", ENVIRON["MUT_TGT"], f, $2, $6; found = 1
    }
    END { exit found ? 0 : 1 }
  '
}

# 주석 줄 판정 — 선행 공백 제거 후 첫 문자가 '#'
#   ★ 줄 안 '#' 존재로 판정하면 안 된다: `[ "$x" = "true" ] && return 0  # PASS` 는 **코드**이고,
#     이걸 skip 하면 정상 변이가 사라져 score 가 거짓 상승한다.
#   ★ 한계 고백: lexical 판정이라 heredoc·문자열 리터럴 안에서 '#' 로 시작하는 **데이터** 줄도
#     주석으로 보고 skip 한다 (현 target 2개에는 해당 줄이 없어 실측 무영향).
mut::is_comment_line() {  # <line text> → 0(주석) | 1
  case "${1#"${1%%[![:space:]]*}"}" in \#*) return 0 ;; *) return 1 ;; esac
}

# equivalent conf 정합 검사 — 사이트로 풀리지 않는 항목을 stdout 에 'STALE ...' 로 보고
#   ★ mut::run_target 의 baseline sanity 검사와 **대칭**이다. 그쪽은 stale 로 인한 거짓 '통과'를,
#     이쪽은 stale 로 인한 무음 'red' 를 막는다. 종전엔 방향이 하나뿐이라 equivalent 18건이
#     전량 무음 사망해도 아무도 몰랐다(실측: score 64% → 50%).
mut::check_conf() {  # <targets_conf> → 0(전건 매칭) | 1(stale 1건 이상)
  local tconf="$1" equiv rc=0 target testcmd out n ok
  equiv=$(mut::_equiv_conf)
  [ -f "$equiv" ] || return 0
  # 형식이 깨진 행(구 줄번호 형식·칸 수 불일치·빈 pattern·빈 reason)은 어느 대상의 것이든 stale 이다.
  #   conf 행의 유효성(스키마) 판정은 conf 를 읽는 쪽 책임이다 — 깨진 행을 "이 대상 것이 아님" 으로 넘기지 않는다.
  mut::conf_format_errors "$equiv" || rc=1
  mut::conf_orphan_targets "$equiv" "$tconf" || rc=1
  while IFS='|' read -r target testcmd; do
    [ -z "$target" ] && continue
    case "$target" in \#*) continue ;; esac
    [ -f "$target" ] || continue
    out=$(mut::resolve_conf "$target")
    [ -n "$out" ] || continue
    n=$(printf '%s\n' "$out" | grep -c .)
    ok=$(printf '%s\n' "$out" | grep -c '^EQ')
    printf '%s\n' "$out" | grep '^STALE ' && rc=1
    echo "CONF-CHECK: $target ${ok}/${n} 매칭"
  done < "$tconf"
  return $rc
}

mut::run_target() {  # <target> <test_command>
  local target="$1" testcmd="$2"
  [ -f "$target" ] || { echo "SKIP: $target 부재"; return 0; }
  local bak; bak=$(mktemp)
  cp "$target" "$bak"
  trap 'cp "$bak" "$target" 2>/dev/null; rm -f "$bak"' RETURN INT TERM
  # ★ baseline sanity (20260714): 무변형 상태(원본 target)에서 testcmd 는 green 이어야 한다
  #   (mut::judge → survived = testcmd 성공). testcmd 파손(스위트 rename 등)이면 무변형에서도
  #   FAIL(killed) → 전 mutant 가 killed 로 오집계돼 score 100% 거짓 통과한다. 이 게이트가 잡으려는
  #   stale conf 의 역방향이 게이트를 무음 무력화하는 것 — self-check 로 차단.
  if [ "$(mut::judge "$testcmd")" = "killed" ]; then
    echo "ERROR: $target — baseline testcmd 가 무변형 상태에서 FAIL (conf/스위트 파손?)" >&2
    MUT_BELOW_MIN=1
    return 0
  fi
  local killed=0 survived=0 invalid=0 equivalent=0 survived_list=""
  local pat sedexpr lines ln eqsites
  # 등가 사이트는 변이 전에 **원본 사본에서 한 번** 푼다 — 루프 안에서는 대상 파일에 직전 변이가 남아 있다.
  eqsites=$(mut::equiv_sites "$target" "$bak")
  while IFS=$'\t' read -r pat sedexpr; do
    [ -z "$pat" ] && continue
    lines=$(grep -nF -- "$pat" "$bak" 2>/dev/null | cut -d: -f1)
    for ln in $lines; do
      # 주석 줄은 변이 사이트가 아니다 — killed·survived·equivalent·invalid 어디에도 넣지 않는다
      mut::is_comment_line "$(sed -n "${ln}p" "$bak")" && continue
      if mut::_in_sites "$eqsites" "$ln" "$pat"; then
        equivalent=$(( equivalent + 1 )); continue
      fi
      cp "$bak" "$target"
      sed "${ln}${sedexpr}" "$bak" > "$target" 2>/dev/null
      # 빈 결과(sed 실패) 또는 문법 오류 → invalid (거짓 survived 차단 — Phase C Important)
      if [ ! -s "$target" ] || ! bash -n "$target" 2>/dev/null; then
        invalid=$(( invalid + 1 )); continue
      fi
      case "$(mut::judge "$testcmd")" in
        killed)   killed=$(( killed + 1 )) ;;
        survived) survived=$(( survived + 1 ))
                  survived_list="${survived_list}${target}:${ln}:${pat}"$'\n' ;;
      esac
    done
  done < <(mut::catalog)
  cp "$bak" "$target"
  local score; score=$(mut::score "$killed" "$survived")
  echo "MUTATION $target: killed=$killed survived=$survived invalid=$invalid equivalent=$equivalent score=${score}%"
  [ -n "$survived_list" ] && printf 'SURVIVED:\n%s' "$survived_list"
  # threshold (20260714): MUTATION_MIN_SCORE 설정 시 미달 target 을 기록 → main 이 exit 1.
  #   미설정 시 기존 동작(측정만) — 하위호환. cron 강제화용 (governance 커버리지 회귀 감지).
  if [ -n "${MUTATION_MIN_SCORE:-}" ] && [ "$score" -lt "$MUTATION_MIN_SCORE" ]; then
    echo "FAIL: $target score ${score}% < MUTATION_MIN_SCORE ${MUTATION_MIN_SCORE}%" >&2
    MUT_BELOW_MIN=1
  fi
  trap - RETURN INT TERM
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  check_only=0; only_target=""; target_flag=0; anchor_flag=0; anchor_t=""; anchor_l=""; anchor_p=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --check-conf) check_only=1; shift ;;
      --target)
        only_target="${2:-}"; target_flag=1; shift; [ $# -gt 0 ] && shift ;;
      --anchor)
        anchor_flag=1; anchor_t="${2:-}"; anchor_l="${3:-}"; anchor_p="${4:-}"; shift $# ;;
      *) break ;;
    esac
  done
  conf="${1:-$(dirname "$0")/mutation-targets.conf}"
  root=$(cd "$(dirname "$0")/../.." && pwd)
  # --anchor: 그 사이트의 conf 행을 낸다(reason 은 비어 있다 — 덧붙여야 --check-conf 가 받는다).
  #   대상 경로는 conf 와 같은 기준(저장소 루트 상대 · 또는 절대)이다. rc: 0 출력 · 1 사이트 아님 · 2 인자 누락.
  if [ "$anchor_flag" = 1 ]; then
    if [ -z "$anchor_t" ] || [ -z "$anchor_l" ] || [ -z "$anchor_p" ]; then
      echo "ERROR: --anchor <target> <line> <pattern> 세 값이 필요하다" >&2
      exit 2
    fi
    cd "$root" || exit 2
    # 행의 target 은 대상 목록과 글자 그대로 같아야 풀린다 — `./x`·저장소 안 절대경로는 목록의 표기(루트 상대)로 맞춘다.
    anchor_t=${anchor_t#./}
    case "$anchor_t" in "$root"/*) anchor_t=${anchor_t#"$root"/} ;; esac
    if ! mut::anchor_row "$anchor_t" "$anchor_l" "$anchor_p"; then
      echo "ERROR: ${anchor_t}:${anchor_l} 은 '${anchor_p}' 변이 사이트가 아니다 (파일 없음·주석 줄·범위 밖·패턴 없음)" >&2
      exit 1
    fi
    exit 0
  fi
  [ -f "$conf" ] || { echo "SKIP: config 부재 ($conf)"; exit 0; }
  cd "$root" || exit 2
  # --target 값 누락(빈 값 포함) → rc 2 (인자 파싱 직후의 exit 2 는 test-mutation-score 의 source 분석에서 shellcheck SC2218 오탐을 부른다)
  if [ "${target_flag:-0}" = 1 ] && [ -z "$only_target" ]; then
    echo "ERROR: --target 에 대상 경로가 필요하다" >&2
    exit 2
  fi

  # conf 정합 — 변이 판정 **전에** 검사한다(fail-fast). 사이트 열거는 즉시 끝나고,
  #   18분을 먹는 건 mutant 별 judge 다. stale 이면 score 자체가 틀린 값이라 기다릴 이유가 없다.
  if ! conf_out=$(mut::check_conf "$conf"); then
    if [ "$check_only" = 1 ]; then
      # ★ STALE 원문을 stdout 에 보존한다 — 사용자 승인 포맷이 `CONF-CHECK: STALE <entry>` 이고,
      #   ERROR 로만 치환하면 스크립트 레벨 출력에서 'STALE' 토큰이 사라져 어서션이 잠글 대상을 잃는다.
      # ★ `-n ... p` 를 쓰지 않는다 — sed 는 두 치환을 같은 pattern space 에 순차 적용하므로
      #   STALE 줄이 1번째에서 바뀐 뒤 2번째 `^CONF-CHECK: ` 에 재매칭돼 **2회 출력**된다(실측 36줄).
      #   conf_out 은 STALE·CONF-CHECK 두 종류뿐이라 전체 통과 출력이 곧 의도한 형태다.
      printf '%s\n' "$conf_out" | sed 's/^STALE /CONF-CHECK: STALE /'
      echo "CONF-CHECK: FAIL ($(printf '%s\n' "$conf_out" | grep -c '^STALE ')건 stale)" >&2
    else
      # 사유(0건·같은 원문 여럿·개수 불일치·형식 오류)는 STALE 줄 끝 괄호에 이미 붙어 있다.
      printf '%s\n' "$conf_out" | grep '^STALE ' \
        | sed 's/^STALE /ERROR: mutation-equivalent.conf stale — /' >&2
      echo "ABORT: stale conf — 채점을 진행하지 않는다 (수정 후 재실행: bash $0 --check-conf)" >&2
    fi
    exit 1
  fi
  if [ "$check_only" = 1 ]; then
    printf '%s\n' "$conf_out" | grep '^CONF-CHECK: ' || true
    echo "CONF-CHECK: PASS"
    exit 0
  fi

  MUT_BELOW_MIN=0
  target_seen=0
  while IFS='|' read -r target testcmd; do
    [ -z "$target" ] && continue
    case "$target" in \#*) continue ;; esac
    if [ -n "$only_target" ]; then
      [ "$target" = "$only_target" ] || continue
      target_seen=1
    fi
    mut::run_target "$target" "$testcmd"
  done < "$conf"
  if [ -n "$only_target" ] && [ "$target_seen" = 0 ]; then
    echo "ERROR: --target $only_target — conf 에 없는 대상 ($conf)" >&2
    exit 2
  fi
  # threshold 미달 target 존재 → exit 1 (MUTATION_MIN_SCORE 설정 시). if 필수 —
  #   `[ ... ] && exit 1` 을 마지막 명령으로 두면 조건 false 시 `[` 의 exit 1 이 스크립트 코드가 된다.
  if [ "${MUT_BELOW_MIN:-0}" = 1 ]; then exit 1; fi
fi
