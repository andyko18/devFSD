#!/usr/bin/env bash
# run-related.sh — 변경 파일이 닿는 스위트만 고르고(--list) 돌린다 (20261112 speed)
#
# 사용:
#   run-related.sh --list [<변경 파일>…]     변경 파일(인자, 없으면 stdin 한 줄에 하나) → 관련 스위트 경로를 한 줄에 하나
#   run-related.sh <스위트 경로>…            그 스위트만 실행 (경로는 repo 기준 — --list 가 낸 그대로)
# 종료 코드:
#   --list  0 = 골랐다 · 3 = 고를 수 없다(사유는 stderr — 호출자는 전체 스위트를 쓴다) · 2 = 사용 오류
#   실행    0 = 전부 통과 · 1 = 실패 있음 · 2 = 사용 오류(스위트 목록에 없는 경로 포함)
#   실행은 run-all.sh 와 같은 병렬 풀이다 — SPECOPS_RUN_ALL_JOBS(기본 코어 수·상한 8 · 1 = 하나씩) · `# run-all: serial` 표시 스위트는 풀 뒤.
#
# 소비자: `/basic` 의 검증 1회(basic-path.sh related → seal 의 test_command). **전체 스위트의 대체가 아니다** —
#   전체는 push 전 게이트(.githooks/pre-push)와 PR 의 CI 가 맡는다. 그래서 이 러너는:
#   - 전체 스위트 통과 마커(.specops/.full-suite-pass)를 쓰지 않는다 → pre-push 는 이 실행을 통과 기록으로 치지 않는다.
#   - `VERIFY: …` 토큰을 내지 않는다 → 커밋 훅(R-1)의 실행 증거가 되지 않는다(증거는 run-verification.sh 가 낸다).
#   - 스위트별 소요는 `.specops/suite-times-related.tsv` 에 남긴다(전체 스위트의 기록 suite-times.tsv 와 다른 파일).
#
# 고르는 규칙 (--list) — **애매하면 전체다**(rc 3):
#   1. 변경 파일이 스위트 자신이면 그 스위트.
#   2. 그 밖의 코드 파일은 **파일 이름을 언급하는 스위트** 전부(글자 그대로 찾는다 · 같은 이름의 파일이 저장소에 둘 이상이면
#      `상위폴더/이름` 으로 좁힌다 — skills/x/SKILL.md 같은 흔한 이름). 그 파일을 언급하는 hooks/·scripts/ 스크립트(한 단계)의
#      이름을 언급하는 스위트도 넣는다 — 라이브러리를 고치면 그것을 source 하는 진입 스크립트의 스위트가 따라온다.
#      폴더를 순회하는 스위트(`skills/*/SKILL.md`·`find … commands` 처럼 최상위 폴더의 glob·find 를 쓰는 것)도 넣는다.
#   3. 문서(루트의 *.md · docs/ 아래 · 하위 폴더의 CLAUDE.md·README.md)는 따로 찾지 않는다 — 아래 상시 스위트가 본다.
#   4. 상시 스위트(구조 검증 · 문서 수치 · 전파 원장)는 항상 넣는다.
#   - 어느 스위트도 언급하지 않는 코드 파일이 하나라도 있으면 rc 3 (관련 테스트를 특정할 수 없다).
#   - 고른 스위트가 RELATED_MAX 개를 넘으면 rc 3 (그만큼 넓게 닿는 변경은 전체 스위트가 맞다).
# 한계: 이름 언급으로 찾는다 — 스위트가 파일을 변수 조합으로만 가리키거나(이름이 글자로 없음), 두 단계 이상의 간접 의존이면
#   놓친다. 이름이 주석에만 나와도 관련으로 친다(넓게 잡는 쪽). 놓친 것은 push 전 게이트와 CI 의 전체 스위트가 잡는다.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES

# 이 수를 넘게 닿으면 전체 스위트로 돌린다(여기 한 곳에서 고친다).
#   20261112 실측(관련 48개 — 러너 5 + 스위트 2 변경): 하나씩 591초 · 병렬 풀 172초 · 전체 스위트(222개 병렬) 358초(같은 세션 · 첫 실측 416초).
#   병렬이면 48개도 전체보다 빠르지만 상한은 올리지 않았다 — 관련 스위트로 검증하면 전체 통과 기록이 없어 push 전 게이트가
#   전체를 한 번 더 돈다(172 + 358초). 전체로 검증하면 게이트가 건너뛴다(358초 + push 0.8초 — 희생용 복제본 실측). 넓게 닿는 변경은 전체 한 번이 싸다.
#   소요는 개수가 아니라 무거운 스위트 몇 개가 정한다(상위 7개가 591초 중 394초) — 스위트별 소요 자료가 생기면 기준을 소요로 바꾼다.
RELATED_MAX=30
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ALWAYS="scripts/_internal/validate-structure.sh scripts/tests/test-doc-numbers.sh scripts/tests/test-propagation.sh"

# 스위트 목록 — run-all.sh 의 대상과 같아야 한다(test-run-related.sh RR-set 이 두 목록을 대조한다)
_suites() {
  local f
  printf '%s\n' "scripts/_internal/validate-structure.sh"
  for f in "$PLUGIN"/scripts/tests/test-*.sh \
           "$PLUGIN"/scripts/tests/dag/test-*.sh \
           "$PLUGIN"/scripts/tests/governance/test-*.sh \
           "$PLUGIN"/scripts/tests/llm-eval/test-*.sh \
           "$PLUGIN"/scripts/tests/test-convention/test-*.sh \
           "$PLUGIN"/scripts/tests/freecomment/test-*.sh \
           "$PLUGIN"/scripts/tests/promote/test-*.sh; do
    [ -f "$f" ] || continue
    printf '%s\n' "${f#"$PLUGIN"/}"
  done
}

_list() {
  local files f key keys base n hits out="" all names b d d2 top globs
  all=$(_suites)
  if [ "$#" -gt 0 ]; then files=$(printf '%s\n' "$@"); else files=$(cat); fi
  files=$(printf '%s\n' "$files" | sed '/^$/d' | sort -u)
  [ -n "$files" ] || { echo "run-related: 변경 파일이 없다" >&2; return 3; }
  names=$(git -C "$PLUGIN" ls-files 2>/dev/null | awk -F/ '{ print $NF }' | sort | uniq -d)
  while IFS= read -r f; do
    case "$f" in
      .specops/*) continue ;;
      /*|*..*) echo "run-related: repo 기준 상대 경로가 아니다: $f" >&2; return 3 ;;
    esac
    if printf '%s\n' "$all" | grep -Fxq -- "$f"; then out="$out$f"$'\n'; continue; fi
    case "$f" in
      docs/*|*/CLAUDE.md|*/README.md) continue ;;   # 문서 — 상시 스위트가 본다
      */*) ;;
      *.md) continue ;;          # 루트 문서 — 상시 스위트가 본다
    esac
    base=${f##*/}; key=$base
    if printf '%s\n' "$names" | grep -Fxq -- "$base"; then
      case "$f" in */*/*) key="${f%/*}"; key="${key##*/}/$base" ;; *) key=$f ;; esac
    fi
    # 찾을 이름 — 그 파일, 그리고 그 파일을 언급하는(source·호출하는) hooks/·scripts/ 의 스크립트 한 단계까지.
    #   훅 라이브러리처럼 스위트가 직접 부르지 않고 진입 스크립트를 거쳐 검사하는 파일을 놓치지 않기 위해서다.
    keys=$( { printf '%s\n' "$key"
      git -C "$PLUGIN" ls-files -- hooks scripts 2>/dev/null | grep -v '^scripts/tests/' | while IFS= read -r d; do
        [ "$d" != "$f" ] && [ -f "$PLUGIN/$d" ] && grep -Fq -- "$key" "$PLUGIN/$d" 2>/dev/null || continue
        case "$d" in (*.sh|*.py|*.cjs|*.js|*.ts) ;; (*) continue ;; esac   # $( ) 안이라 여는 괄호를 쓴다(bash 3.2)
        b=${d##*/}
        if printf '%s\n' "$names" | grep -Fxq -- "$b"; then d2=${d%/*}; printf '%s/%s\n' "${d2##*/}" "$b"; else printf '%s\n' "$b"; fi
      done; } | sort -u )
    hits=$(printf '%s\n' "$all" | while IFS= read -r s; do
      [ -f "$PLUGIN/$s" ] && grep -Fq -f <(printf '%s\n' "$keys") -- "$PLUGIN/$s" 2>/dev/null && printf '%s\n' "$s"
    done)
    # 폴더를 순회하며 보는 스위트 — 파일 이름을 적지 않고 `skills/*/SKILL.md`·`find … commands` 처럼 그 폴더 전체를 훑는다.
    #   이름 언급으로는 잡히지 않으므로 최상위 폴더의 glob·find·변수 조합(`skills/${name}/…`)을 쓰는 스위트를 함께 넣는다(넘치면 상한이 전체로 보낸다).
    case "$f" in
      */*) top=${f%%/*}
        globs=$(printf '%s\n' "$all" | while IFS= read -r s; do
          [ -f "$PLUGIN/$s" ] && grep -Eq -- "(^|[^A-Za-z0-9_.-])$top/[^[:space:]]*\*|find[[:space:]][^|;]*[\"/[:space:]]$top([\"/[:space:]]|\$)|(^|[^A-Za-z0-9_.-])$top/\"?\\\$" "$PLUGIN/$s" 2>/dev/null && printf '%s\n' "$s"
        done)
        hits="$hits${globs:+
$globs}" ;;
    esac
    hits=$(printf '%s\n' "$hits" | sed '/^$/d')
    [ -n "$hits" ] || { echo "run-related: 이 파일을 언급하는 스위트가 없다 — 관련 테스트를 특정할 수 없다: $f" >&2; return 3; }
    out="$out$hits"$'\n'
  done <<< "$files"
  for f in $ALWAYS; do [ -f "$PLUGIN/$f" ] && out="$out$f"$'\n'; done
  out=$(printf '%s' "$out" | sed '/^$/d' | sort -u)
  n=$(printf '%s\n' "$out" | awk 'END { print NR }')
  [ "$n" -le "$RELATED_MAX" ] || { echo "run-related: 관련 스위트 ${n}개 (상한 ${RELATED_MAX}) — 전체 스위트가 맞다" >&2; return 3; }
  printf '%s\n' "$out"
}

case "${1:-}" in
  --list) shift; _list "$@"; exit $? ;;
  ""|-*) echo "usage: $0 --list [<변경 파일>…] | $0 <스위트 경로>…" >&2; exit 2 ;;
esac

# ── 실행 ──
ALL=$(_suites)
for s in "$@"; do
  printf '%s\n' "$ALL" | grep -Fxq -- "$s" || { echo "run-related: 스위트 목록에 없는 경로다: $s" >&2; exit 2; }
done
# run-all.sh 와 같은 실행 환경 — 재귀 가드(스위트 안의 release.sh·pre-push 가 전체 스위트를 다시 부르지 않게) · 네트워크 SAST 금지
export SPECOPS_RUN_ALL=1
export SPECOPS_SAST_EXTERNAL=0
SUITE_TIMEOUT="${SPECOPS_SUITE_TIMEOUT:-600}"
if [ -f "$PLUGIN/scripts/_internal/run-bounded.sh" ]; then
  # shellcheck source=/dev/null
  . "$PLUGIN/scripts/_internal/run-bounded.sh"
else
  echo "WARN: run-bounded.sh 부재 — 스위트별 상한 없이 진행" >&2
  bounded_run() { shift; "$@"; }
  bounded_timed_out() { return 1; }
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/specops-run-related.XXXXXX") || { echo "run-related: 작업 디렉터리 생성 실패" >&2; exit 1; }
cd "$PLUGIN" || exit 1

# 병렬 풀 (20261112 실측: 관련 48개를 하나씩 돌리면 591초 — 전체 스위트 병렬 416초보다 길었다) — run-all.sh 와 같은 규칙이다:
#   병렬 수 = SPECOPS_RUN_ALL_JOBS(정수≥1) > CPU 코어 수(상한 8) > 1 · 선두 20줄에 `# run-all: serial — <사유>` 가 있는 스위트는 풀이 끝난 뒤 하나씩.
_rr_jobs() {
  local n="${SPECOPS_RUN_ALL_JOBS:-}"
  case "$n" in ''|*[!0-9]*|0*) ;; *) printf '%s' "$n"; return 0 ;; esac
  n=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)
  case "$n" in ''|*[!0-9]*|0*) n=1 ;; esac
  [ "$n" -gt 8 ] && n=8
  printf '%s' "$n"
}
JOBS=$(_rr_jobs)
# 중단하면 풀을 그룹째 끝낸다(작업자는 `set -m` 으로 띄워 자기 프로세스 그룹이다 — run-all.sh 와 같다).
_rr_bg=""
_rr_stop() {
  trap - INT TERM
  [ -n "$_rr_bg" ] && { kill -TERM -- "-$_rr_bg" 2>/dev/null || kill -TERM "$_rr_bg" 2>/dev/null; }
  rm -rf "$WORK"
  exit "$1"
}
trap '_rr_stop 130' INT
trap '_rr_stop 143' TERM
trap 'rm -rf "$WORK"' EXIT

# 작업자 — 스위트 1개를 돌리고 out.<i>·rc.<i> 를 남긴다. 함수를 export 하지 않고 소스 문자열로 넘긴다(run-all.sh 의 작업자 주석 참조).
read -r -d '' _RR_WORKER <<'WORKER'
w=$1; plugin=$2; SUITE_TIMEOUT=$3; i=$4
suite=$(sed -n "${i}p" "$w/list")
if [ -f "$plugin/scripts/_internal/run-bounded.sh" ]; then
  . "$plugin/scripts/_internal/run-bounded.sh"
else
  bounded_run() { shift; "$@"; }
  bounded_timed_out() { return 1; }
fi
_w_stop() {
  for j in $(jobs -p); do kill -TERM -- "-$j" 2>/dev/null || kill -TERM "$j" 2>/dev/null; done
  exit 143
}
trap _w_stop TERM INT
cd "$plugin" || exit 0
t0=$SECONDS
bounded_run "$SUITE_TIMEOUT" bash "$suite" > "$w/out.$i" 2>&1 < /dev/null
rc=$?
echo "$((SECONDS - t0))" > "$w/sec.$i"
if bounded_timed_out "$rc"; then
  printf '%s\n' "FAIL TIMEOUT — ${SUITE_TIMEOUT}s 상한 초과. 재현: bash $suite" >> "$w/out.$i"
fi
echo "$rc" > "$w/rc.$i"
exit 0
WORKER

printf '%s\n' "$@" | sort -u > "$WORK/list"
: > "$WORK/par"; : > "$WORK/ser"
i=0
while IFS= read -r s; do
  i=$((i + 1))
  if [ "$JOBS" -gt 1 ] && awk 'NR > 20 { exit } /^# run-all: serial — ./ { f = 1; exit } END { exit !f }' "$PLUGIN/$s" 2>/dev/null; then
    echo "$i" >> "$WORK/ser"
  else
    echo "$i" >> "$WORK/par"
  fi
done < "$WORK/list"
if [ -s "$WORK/par" ]; then
  set -m
  xargs -n 1 -P "$JOBS" bash -c "$_RR_WORKER" _ "$WORK" "$PLUGIN" "$SUITE_TIMEOUT" < "$WORK/par" &
  _rr_bg=$!
  set +m
  wait "$_rr_bg" || kill -TERM -- "-$_rr_bg" 2>/dev/null || true
  _rr_bg=""
fi
while read -r i <&3; do
  set -m
  bash -c "$_RR_WORKER" _ "$WORK" "$PLUGIN" "$SUITE_TIMEOUT" "$i" &
  _rr_bg=$!
  set +m
  wait "$_rr_bg" || true
  _rr_bg=""
done 3< "$WORK/ser"

# 집계는 목록 순서로 — 끝난 순서와 무관하게 출력이 같다. 결과를 못 남긴 스위트는 실패다(통째로 빠진 통과 방지).
PASS=0; FAIL=0; FAILED=()
i=0
while IFS= read -r s; do
  i=$((i + 1))
  rc=$(cat "$WORK/rc.$i" 2>/dev/null || true)
  if [ -z "$rc" ]; then
    rc=1
    printf '%s\n' "FAIL WORKER — 결과 없음 (작업자 비정상 종료·중단). 재현: bash $s" >> "$WORK/out.$i"
  fi
  printf -- '--- %s\n%s\n' "$s" "$(grep -v '^$' "$WORK/out.$i" | tail -1)"
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1)); FAILED+=("$s")
    grep '^FAIL' "$WORK/out.$i" | head -5
  fi
  sec=$(cat "$WORK/sec.$i" 2>/dev/null || true)
  case "$sec" in ''|*[!0-9]*) sec=0 ;; esac
  printf '%s\t%s\t%s\n' "$sec" "$rc" "$s" >> "$WORK/times"
done < "$WORK/list"

# 스위트별 소요 기록 (20261112-related-suite-narrowing) — run-all.sh 와 같은 형식(머리 주석 + `<초>\t<rc>\t<경로>` 초 내림차순)이다.
#   전체 스위트의 기록(suite-times.tsv)을 덮지 않게 다른 파일에 쓴다. `.specops/` 가 없으면 만들지 않는다 · 판정에는 쓰지 않는다.
TIMES="$PLUGIN/${SPECOPS_ROOT:-.specops}/suite-times-related.tsv"
if [ -s "$WORK/times" ] && [ -d "$(dirname "$TIMES")" ]; then
  { printf '# run-related %s jobs=%s suites=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$JOBS" "$((PASS + FAIL))"
    LC_ALL=C sort -t "$(printf '\t')" -k1,1nr -k3,3 "$WORK/times"; } 2>/dev/null > "$TIMES" || true
fi

echo ""
echo "==== run-related: suites PASS=$PASS FAIL=$FAIL (total=$((PASS + FAIL))) — 관련 스위트만 돌렸다(전체 스위트 아님) ===="
if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}"
  exit 1
fi
exit 0
