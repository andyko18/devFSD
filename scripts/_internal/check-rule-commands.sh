#!/usr/bin/env bash
# check-rule-commands.sh — 헌법 「구조 규칙」 중 판정이 `명령` 인 규칙을 실행한다 (20261015 · 소비자: run-verification — 경고 전용)
#
# Usage: check-rule-commands.sh [헌법 파일]     # 기본: ${SPECOPS_ROOT:-.specops}/memory/constitution.md
#
# 실행 규칙:
#   - 현재 디렉터리에서 실행한다 — 테스트 명령과 같은 기준이고, 헌법 파일도 이 기준으로 찾는다.
#   - 허용 판정은 run-verification.sh 의 단일 줄 _WHITELIST_PAT 를 읽어 쓴다(emit-context 와 같은 추출 — 정규식을 복제하지 않는다)
#     + `..` 포함 거부. 허용 밖 명령은 실행하지 않는다(SKIP). 패턴을 읽지 못하면 하나도 실행하지 않는다(판정 불가).
#   - 셸을 거치지 않는다 — 토큰 배열로 실행한다(run-verification 과 같은 방식: `cd 하위 && 러너` · `bash 스크립트` · 그 밖은 첫 토큰).
#   - 규칙마다 bounded_run 상한 SPECOPS_RULE_CMD_TIMEOUT(초 · 기본 60 · 숫자가 아니거나 0 이면 기본값).
#     전체 상한은 없다 — 명령 규칙이 N건이면 최악 N×상한 동안 걸린다(한계).
#   - 표준 입력은 /dev/null 이다 — 명령이 표준 입력을 읽어도 뒤 규칙 목록을 먹지 못한다(plan-review 실측 결함).
#
# 출력: 규칙마다 `RULE <ID>: PASS` · `RULE <ID>: FAIL (rc=N)` · `RULE <ID>: TIMEOUT (N초)` · `RULE <ID>: SKIP — …` 한 줄
#       (FAIL 은 아래에 명령 출력 앞 10줄을 두 칸 들여 붙인다). 끝에 `RULE-COMMANDS: PASS a · FAIL b · TIMEOUT c · SKIP d`.
#       해당 없음·판정 불가는 `RULE-COMMANDS: 해당 없음 (…)` · `RULE-COMMANDS: 판정 불가 (…)` 한 줄.
# 종료 코드 — 셋을 섞지 않는다:
#   0 = 명령 규칙 전부 PASS 또는 해당 없음(헌법 없음 · 절 없음 · 규칙 0건 · 명령 규칙 0건)
#   1 = FAIL·TIMEOUT·SKIP 1건 이상
#   2 = 판정 불가(헌법 표 형식 위반·읽기 실패 · 허용 패턴을 읽지 못함 · 도구 없음) — "규칙 없음"으로 답하지 않는다
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
LIST_SH="$HERE/check-constitution-rules.sh"
RV_SH="$HERE/run-verification.sh"
BOUND_SH="$HERE/run-bounded.sh"
MAXLINES=10
TIMEOUT="${SPECOPS_RULE_CMD_TIMEOUT:-60}"
case "$TIMEOUT" in ''|*[!0-9]*|0) TIMEOUT=60 ;; esac

cant() { echo "RULE-COMMANDS: 판정 불가 ($1)"; exit 2; }
[ -f "$LIST_SH" ] || cant "check-constitution-rules.sh 없음"
[ -f "$BOUND_SH" ] || cant "run-bounded.sh 없음"
# shellcheck source=/dev/null
source "$BOUND_SH"

errf=$(mktemp "${TMPDIR:-/tmp}/specops-rulecmd.XXXXXX") || cant "임시 파일을 만들 수 없음"
list=$(bash "$LIST_SH" --list "$@" 2>"$errf"); lrc=$?
lerr=$(head -1 "$errf"); rm -f "$errf"
[ "$lrc" -eq 0 ] || cant "헌법 표 rc=${lrc} — ${lerr:-사유 없음}"

# --list 는 규칙 줄만 표준 출력으로, 판정 줄(CONSTITUTION-RULES: OK·SKIP)은 표준 오류로 낸다
summary=${lerr#CONSTITUTION-RULES: }
rules=$(printf '%s\n' "$list" | grep -v '^$')

# 허용 판정을 통과한 명령만 온다 — 셸 해석 없이 토큰으로 실행한다
_run() {
  local c="$1" sub
  local -a parts
  if [[ "$c" =~ ^cd[[:blank:]]+([^[:blank:]]+)[[:blank:]]+\&\&[[:blank:]]+(.*)$ ]]; then
    sub="${BASH_REMATCH[1]}"; read -r -a parts <<< "${BASH_REMATCH[2]}"
    ( cd "$sub" && "${parts[@]}" )
  else
    read -r -a parts <<< "$c"
    if [ "${parts[0]}" = "bash" ]; then bash "${parts[@]:1}"; else "${parts[@]}"; fi
  fi
}

pat=""; ncmd=0; npass=0; nfail=0; ntime=0; nskip=0
while IFS='|' read -r id _rule _path kind cmd; do
  [ -n "${id:-}" ] || continue
  [ "$kind" = "명령" ] || continue
  if [ -z "$pat" ]; then
    [ -f "$RV_SH" ] && pat=$(grep -m1 '^_WHITELIST_PAT=' "$RV_SH" 2>/dev/null | sed -E "s/^_WHITELIST_PAT='(.*)'\$/\1/")
    [ -n "$pat" ] || cant "허용 패턴을 읽지 못함 — run-verification.sh 의 _WHITELIST_PAT"
    # 추출은 작은따옴표 한 줄 형태를 전제한다 — 형태가 바뀌어 따옴표가 남으면 모든 명령이 "목록 밖"으로 잘못 보고된다
    case "$pat" in '^'*) ;; *) cant "허용 패턴 형태가 예상과 다름 — run-verification.sh 의 _WHITELIST_PAT" ;; esac
  fi
  ncmd=$((ncmd + 1))
  cmd=${cmd#\`}; cmd=${cmd%\`}
  if [[ ! "$cmd" =~ $pat ]] || [[ "$cmd" == *..* ]]; then
    nskip=$((nskip + 1))
    echo "RULE $id: SKIP — 허용 목록 밖이라 실행하지 않음 (테스트 명령과 같은 형식만 실행한다 — 스크립트로 감싸세요: bash scripts/tests/test-structure.sh $id)"
    continue
  fi
  out=$(bounded_run "$TIMEOUT" _run "$cmd" </dev/null 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then
    npass=$((npass + 1)); echo "RULE $id: PASS"
  elif [ "$rc" -eq 124 ]; then
    ntime=$((ntime + 1)); echo "RULE $id: TIMEOUT (${TIMEOUT}초)"
  else
    nfail=$((nfail + 1)); echo "RULE $id: FAIL (rc=$rc)"
    [ -n "$out" ] && printf '%s\n' "$out" | head -n "$MAXLINES" | sed 's/^/  /'
  fi
done <<EOF_RULES
$rules
EOF_RULES

if [ "$ncmd" -eq 0 ]; then
  echo "RULE-COMMANDS: 해당 없음 (판정 명령 규칙 0건 — ${summary:-헌법 표 없음})"
  exit 0
fi
echo "RULE-COMMANDS: PASS $npass · FAIL $nfail · TIMEOUT $ntime · SKIP $nskip"
[ $((nfail + ntime + nskip)) -eq 0 ]
