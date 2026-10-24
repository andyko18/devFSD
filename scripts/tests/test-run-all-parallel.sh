#!/usr/bin/env bash
# test-run-all-parallel.sh — run-all 병렬 실행 계약 (FID 20260911-run-all-parallel)
# 방식: run-all.sh 를 sandbox 플러그인 트리에 복사해 더미 스위트로 돌린다
#   (PLUGIN 은 BASH_SOURCE 기준이라 sandbox 로 격리 — test-run-all-verify-token 과 같은 방식).
# ★ 동시성은 ps 로 보지 않는다 — Claude Code sandbox 의 ps 는 자식 프로세스조차 못 본다(실측).
#   더미 스위트가 공용 로그에 남기는 시작·종료 시각(ms)과 heartbeat 줄 수로 관측한다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0

ROOT=$(mktemp -d) || exit 1
trap 'rm -rf "$ROOT"' EXIT

# sandbox 트리 1개 → 경로. 스위트는 _suite 로 채운다.
_sb() {
  local d; d=$(mktemp -d "$ROOT/sb.XXXXXX") || return 1
  mkdir -p "$d/scripts/tests" "$d/scripts/_internal"
  cp "$PLUGIN/scripts/tests/run-all.sh" "$d/scripts/tests/run-all.sh"
  cp "$PLUGIN/scripts/_internal/run-bounded.sh" "$d/scripts/_internal/run-bounded.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/scripts/_internal/validate-structure.sh"
  printf '%s\n' "$d"
}
# $1=sandbox $2=이름(test-*.sh 의 * 부분) $3=본문. 공용 헬퍼 ms·logline 을 앞에 붙인다.
_suite() {
  {
    printf '#!/usr/bin/env bash\n%s\n' "${4:-}"
    printf '%s\n' 'ms() { perl -MTime::HiRes=time -e '"'"'printf "%d", time*1000'"'"'; }'
    printf '%s\n' "$3"
  } > "$1/scripts/tests/test-$2.sh"
}
# 시각 로그("이름 시작 종료")에서 최대 동시 실행 수
_max_overlap() {
  awk '{ print $3, 1; print $4, -1 }' "$1" | sort -n -k1,1 -k2,2 \
    | awk '{ c += $2; if (c > m) m = c } END { print m + 0 }'
}
_expected_auto() {
  local n; n=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)
  case "$n" in ''|*[!0-9]*|0*) n=1 ;; esac
  [ "$n" -gt 8 ] && n=8
  printf '%s' "$n"
}

# ── T1: 끝나는 순서가 뒤집혀도 집계는 원래 순서로 결정적 (AC-1) ──
S=$(_sb)
_suite "$S" a 'sleep 1.2; echo "FAIL a1"; echo "FAIL a2"; echo "PASS=0 FAIL=2"; exit 1'
_suite "$S" b 'sleep 0.9; echo "SKIP b1"; echo "PASS=1 FAIL=0 SKIP=1"; exit 0'
_suite "$S" c 'sleep 0.6; echo "FAIL c1"; echo "PASS=0 FAIL=1"; exit 1'
_suite "$S" d 'sleep 0.3; echo "SKIP d1"; echo "SKIP d2"; echo "PASS=1 FAIL=0 SKIP=2"; exit 0'
_suite "$S" e 'echo "PASS=1 FAIL=0"; exit 0'
o1=$(SPECOPS_RUN_ALL_JOBS=5 bash "$S/scripts/tests/run-all.sh" --quiet 2>&1); rc1=$?
o2=$(SPECOPS_RUN_ALL_JOBS=5 bash "$S/scripts/tests/run-all.sh" --quiet 2>&1); rc2=$?
o3=$(SPECOPS_RUN_ALL_JOBS=5 bash "$S/scripts/tests/run-all.sh" --quiet 2>&1); rc3=$?
printf '%s\n' "$o1" | grep -qx '==== run-all: suites PASS=4 FAIL=2 (total=6) ====' \
  && ok "T1.a 요약 수치 (PASS=4 FAIL=2 total=6)" || nope "T1.a 요약" "$(printf '%s' "$o1" | grep '====')"
printf '%s\n' "$o1" | grep -q 'SKIP된 케이스 3건' \
  && ok "T1.b SKIP 합산 3" || nope "T1.b SKIP 합산" "$(printf '%s' "$o1" | grep SKIP)"
_fl=$(printf '%s\n' "$o1" | grep '^FAIL ' | tr '\n' '|')
[ "$_fl" = "FAIL a1|FAIL a2|FAIL c1|" ] \
  && ok "T1.c FAIL 줄 블록이 원래 스위트 순서 (a 가 c 보다 늦게 끝나도 먼저)" || nope "T1.c FAIL 순서" "$_fl"
printf '%s\n' "$o1" | grep -qx 'FAILED: scripts/tests/test-a.sh' \
  && [ "$(printf '%s\n' "$o1" | grep '^FAILED:' | tr '\n' '|')" = "FAILED: scripts/tests/test-a.sh|FAILED: scripts/tests/test-c.sh|" ] \
  && ok "T1.d FAILED 목록 원래 순서" || nope "T1.d FAILED 순서" "$(printf '%s' "$o1" | grep '^FAILED')"
# T1.e 실패 진단 (20261024-quality-gate-fixes · AC-4) — CI 로그에는 실패 스위트의 `^FAIL` 줄만 남는다(run-all 집계 `grep '^FAIL' | head -5`).
#   그래서 rc 3개와 처음 달라진 실행 쌍·줄 번호·양쪽 줄(각 80바이트)을 nope 상세 **한 줄**에 넣는다.
_first_diff() { # $1 $2 = 출력 두 개 → `L<n>: [<앞>] ≠ [<뒤>]` (같으면 빈 문자열 · 줄 수가 다르면 없는 쪽은 [])
#   80바이트로 자르면 멀티바이트 문자가 쪼개진다 — iconv -c 로 유효 UTF-8 만 남긴다(깨진 줄은 UTF-8 로케일 grep 이 `binary file matches` 로 가린다)
  A="$1" B="$2" awk 'BEGIN { na = split(ENVIRON["A"], a, "\n"); nb = split(ENVIRON["B"], b, "\n"); n = (na > nb ? na : nb)
    for (i = 1; i <= n; i++) if ((i > na) != (i > nb) || a[i] != b[i]) { printf "L%d: [%s] ≠ [%s]", i, substr(a[i], 1, 80), substr(b[i], 1, 80); exit } }' \
    | if command -v iconv >/dev/null 2>&1; then iconv -c -f UTF-8 -t UTF-8 2>/dev/null; else LC_ALL=C tr -c '\n\040-\176' '?'; fi
  return 0   # glibc iconv -c 는 문자를 버리면 rc 1 — rc 로 대체 경로를 고르면 이미 읽힌 입력이 비어 진단이 사라진다
}
_t1e_detail() {
  local d="rc=$rc1/$rc2/$rc3"
  if [ "$o1" != "$o2" ]; then d="$d o1≠o2 $(_first_diff "$o1" "$o2")"
  elif [ "$o2" != "$o3" ]; then d="$d o2≠o3 $(_first_diff "$o2" "$o3")"; fi
  printf '%s' "$d"
}
{ [ "$o1" = "$o2" ] && [ "$o2" = "$o3" ] && [ "$rc1" -eq 1 ]; } \
  && ok "T1.e 3회 실행 출력 바이트 동일 + rc=1" || nope "T1.e 결정성" "$(_t1e_detail)"
# 진단 함수 자체 — 달라진 줄 · 같은 출력 · 줄 수 차이 · 한 줄 보장
[ "$(_first_diff "$(printf 'a\nb\nc')" "$(printf 'a\nX\nc')")" = "L2: [b] ≠ [X]" ] \
  && ok "T1.f 진단 — 처음 달라진 줄 번호와 양쪽 줄" || nope "T1.f" "$(_first_diff "$(printf 'a\nb\nc')" "$(printf 'a\nX\nc')")"
{ [ -z "$(_first_diff "$(printf 'a\nb')" "$(printf 'a\nb')")" ] && [ "$(_first_diff "$(printf 'a\nb')" a)" = "L2: [b] ≠ []" ] \
    && [ "$(_first_diff "$(printf 'x\ny')" "$(printf 'x\ny\n\nz')")" = "L3: [] ≠ []" ]; } \
  && ok "T1.g 진단 — 같으면 빈 문자열 · 줄 수가 다르면 없는 쪽 []" || nope "T1.g" "$(_first_diff "$(printf 'a\nb')" a)"
_long=$(printf '%0100d' 0)
o1="$(printf 'x\n%s' "$_long")" o2="$(printf 'x\ny')" o3="$o2" rc1=1 rc2=0 rc3=2
_d=$(_t1e_detail)
{ [ "$(printf '%s\n' "$_d" | awk 'END{print NR}')" = 1 ] && printf '%s' "$_d" | grep -qF 'rc=1/0/2 o1≠o2 L2: [' && printf '%s' "$_d" | grep -qF "[$(printf '%080d' 0)] ≠ [y]"; } \
  && ok "T1.h 진단은 한 줄 · rc 3개 · 80바이트로 자른다" || nope "T1.h" "$_d"
o1=a o2=a o3="$(printf 'a\nb')" rc1=1 rc2=1 rc3=1
[ "$(_t1e_detail)" = "rc=1/1/1 o2≠o3 L2: [] ≠ [b]" ] \
  && ok "T1.i 진단 — o1=o2 이면 o2≠o3 쌍을 낸다" || nope "T1.i" "$(_t1e_detail)"
# 100자 — 바이트 단위 awk(BSD·mawk)도 문자 단위 awk(gawk UTF-8)도 자른다
_kr=$(printf '가%.0s' $(seq 1 100)); o1="$_kr" o2=b o3=b
_d=$(_t1e_detail)
{ printf '%s' "$_d" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 && [ "$(printf '%s' "$_d" | LC_ALL=C grep -c '^rc=1/1/1 o1≠o2 L1: \[가')" = 1 ]; } \
  && ok "T1.j 진단 — 멀티바이트 줄을 잘라도 유효 UTF-8" || nope "T1.j" "$(printf '%s' "$_d" | LC_ALL=C tr -c '\040-\176' '?')"

# ── T2: 병렬 모드의 VERIFY 토큰·rc·마커·TIMEOUT (AC-2) ──
S=$(_sb)
# file-class.sh 도 함께 복사해야 한다 — verification-state.sh 가 이를 source 하고,
#   없으면 fail-safe(전건 비문서)로 떨어져 지문이 달라진다(T2.a 가 마커와 대조하므로 red).
cp "$PLUGIN/scripts/_internal/verification-state.sh" "$PLUGIN/scripts/_internal/file-class.sh" "$S/scripts/_internal/"
_suite "$S" p1 'sleep 0.3; echo "PASS=1 FAIL=0"'
_suite "$S" p2 'echo "PASS=1 FAIL=0"'
# ★ 커밋 필수 — HEAD 가 없으면 지문의 임시 index(빈 파일)를 git 이 손상으로 보아 NO_GIT 이 된다(실측)
( cd "$S" && git init -q && git add -A && git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm base ) >/dev/null 2>&1
mkdir -p "$S/.specops"   # 관할이 열린 저장소 — run-all 은 .specops/ 가 있을 때만 마커를 남긴다(20261021)
_fp=$( cd "$S" && bash -c '. scripts/_internal/verification-state.sh; vs::nondoc_fingerprint' )
o=$( cd "$S" && SPECOPS_RUN_ALL_JOBS=2 bash scripts/tests/run-all.sh --quiet 2>&1 ); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$o" | tail -1)" = "VERIFY: PASS" ] \
  && [ "$(head -1 "$S/.specops/.full-suite-pass" 2>/dev/null)" = "$_fp" ]; } \
  && ok "T2.a 전건 PASS → VERIFY: PASS · rc=0 · 마커=실행 전 지문" \
  || nope "T2.a" "rc=$rc last=$(printf '%s\n' "$o" | tail -1) marker=$(head -1 "$S/.specops/.full-suite-pass" 2>/dev/null) fp=$_fp"
_suite "$S" p3 'echo "FAIL p3"; echo "PASS=0 FAIL=1"; exit 1'
( cd "$S" && git add -A )
o=$( cd "$S" && SPECOPS_RUN_ALL_JOBS=2 bash scripts/tests/run-all.sh --quiet 2>&1 ); rc=$?
{ [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$o" | tail -1)" = "VERIFY: FAIL" ] \
  && ! printf '%s\n' "$o" | grep -qx 'VERIFY: PASS' && [ ! -f "$S/.specops/.full-suite-pass" ]; } \
  && ok "T2.b 1개 FAIL → VERIFY: FAIL · rc=1 · 마커 삭제 · PASS 토큰 없음" \
  || nope "T2.b" "rc=$rc last=$(printf '%s\n' "$o" | tail -1) marker=$([ -f "$S/.specops/.full-suite-pass" ] && echo 잔존 || echo 없음)"
rm -f "$S/scripts/tests/test-p3.sh"
_suite "$S" p4 'sleep 30'
_t0=$(date +%s)
e=$( cd "$S" && SPECOPS_RUN_ALL_JOBS=2 SPECOPS_SUITE_TIMEOUT=2 bash scripts/tests/run-all.sh --quiet 2>&1 >"$ROOT/t2c.out" ); rc=$?
_el=$(( $(date +%s) - _t0 ))
{ [ "$rc" -eq 1 ] && printf '%s\n' "$e" | grep -q '⏱  TIMEOUT: scripts/tests/test-p4.sh (>2s)' \
  && grep -q '^FAIL TIMEOUT — 2s 상한 초과' "$ROOT/t2c.out" && grep -qx 'FAILED: scripts/tests/test-p4.sh' "$ROOT/t2c.out" \
  && [ "$_el" -lt 15 ]; } \
  && ok "T2.c 상한 초과 → stderr TIMEOUT · FAIL TIMEOUT · FAIL 계상 (${_el}s)" \
  || nope "T2.c TIMEOUT" "rc=$rc el=${_el}s err=[$e] out=[$(cat "$ROOT/t2c.out")]"

# ── T3: 직렬 표시 스위트는 병렬 풀과 시간이 겹치지 않는다 (AC-3) ──
S=$(_sb); LOG="$ROOT/t3.log"; : > "$LOG"
for n in 1 2 3 4; do
  _suite "$S" "p$n" 's=$(ms); sleep 1; echo "par '"$n"' $s $(ms)" >> "$LOG"; echo "PASS=1 FAIL=0"'
done
_suite "$S" s1 's=$(ms); sleep 0.5; echo "ser 1 $s $(ms)" >> "$LOG"; echo "PASS=1 FAIL=0"' '# run-all: serial — 테스트용 직렬 1'
_suite "$S" s2 's=$(ms); sleep 0.5; echo "ser 2 $s $(ms)" >> "$LOG"; echo "PASS=1 FAIL=0"' '# run-all: serial — 테스트용 직렬 2'
# 음성 대조군: 표시가 21번째 줄에만 있다 → 직렬이 아니다
{ printf '#!/usr/bin/env bash\n'; for k in $(seq 2 20); do echo "# pad $k"; done
  echo '# run-all: serial — 21번째 줄'; echo 'echo "PASS=1 FAIL=0"'; } > "$S/scripts/tests/test-q.sh"
e=$( LOG="$LOG" SPECOPS_RUN_ALL_JOBS=4 bash "$S/scripts/tests/run-all.sh" --quiet 2>&1 >/dev/null ); rc=$?
_par_end=$(awk '$1=="par"{ if ($4 > m) m = $4 } END { print m + 0 }' "$LOG")
_s1=$(awk '$1=="ser" && $2==1 { print $3, $4 }' "$LOG"); _s2=$(awk '$1=="ser" && $2==2 { print $3, $4 }' "$LOG")
if [ "$rc" -eq 0 ] && [ -n "$_s1" ] && [ -n "$_s2" ] \
   && [ "${_s1% *}" -ge "$_par_end" ] && [ "${_s1#* }" -le "${_s2% *}" ]; then
  ok "T3.a 직렬 2개가 병렬 풀 종료 뒤 순서대로 · 서로 비중첩 (par_end=$_par_end s1=[$_s1] s2=[$_s2])"
else
  nope "T3.a 직렬 비중첩" "rc=$rc par_end=$_par_end s1=[$_s1] s2=[$_s2]"
fi
printf '%s\n' "$e" | grep -q '▶ run-all: 병렬 4 · 직렬 2 스위트' \
  && ok "T3.b 21번째 줄 표시는 직렬로 취급하지 않는다 (직렬 2)" || nope "T3.b 표시 위치" "$e"

# ── T4: 병렬 수 해석 · 직렬 강제 스위치 (AC-4) ──
S=$(_sb)
for n in 1 2 3 4 5 6; do
  _suite "$S" "w$n" 's=$(ms); sleep 0.6; echo "w '"$n"' $s $(ms)" >> "$LOG"; echo "PASS=1 FAIL=0"'
done
# w3 은 직렬 표시 — JOBS=1 에서도 풀 뒤로 밀리면 T4.a 진행 순서가 깨진다(plan-review 1회차 지적)
_suite "$S" w3 's=$(ms); sleep 0.6; echo "w 3 $s $(ms)" >> "$LOG"; echo "PASS=1 FAIL=0"' '# run-all: serial — 테스트용 순서 대조'
LOG="$ROOT/t4a.log"; : > "$LOG"
o=$( LOG="$LOG" SPECOPS_RUN_ALL_JOBS=1 bash "$S/scripts/tests/run-all.sh" 2>/dev/null )
_prog=$(printf '%s\n' "$o" | grep '^--- ' | tr '\n' '|')
_want="--- scripts/_internal/validate-structure.sh|--- scripts/tests/test-w1.sh|--- scripts/tests/test-w2.sh|--- scripts/tests/test-w3.sh|--- scripts/tests/test-w4.sh|--- scripts/tests/test-w5.sh|--- scripts/tests/test-w6.sh|"
{ [ "$(_max_overlap "$LOG")" = 1 ] && [ "$_prog" = "$_want" ]; } \
  && ok "T4.a JOBS=1 → 동시 최대 1 · 진행 줄이 원래 순서 (직렬 표시 w3 포함)" || nope "T4.a" "max=$(_max_overlap "$LOG") prog=$_prog"
LOG="$ROOT/t4b.log"; : > "$LOG"
LOG="$LOG" SPECOPS_RUN_ALL_JOBS=3 bash "$S/scripts/tests/run-all.sh" --quiet >/dev/null 2>&1
_m=$(_max_overlap "$LOG")
{ [ "$_m" -le 3 ] && [ "$_m" -ge 2 ]; } && ok "T4.b JOBS=3 → 동시 최대 $_m (2..3)" || nope "T4.b" "max=$_m"
_exp=$(_expected_auto)
LOG="$ROOT/t4c.log"; : > "$LOG"
e=$( unset SPECOPS_RUN_ALL_JOBS; LOG="$LOG" bash "$S/scripts/tests/run-all.sh" --quiet 2>&1 >/dev/null ); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$e" | grep -q "▶ run-all: 병렬 $_exp · " && [ "$(_max_overlap "$LOG")" -le "$_exp" ]; } \
  && ok "T4.c 미지정 → 코어 수 상한 8 ($_exp)" || nope "T4.c" "rc=$rc exp=$_exp err=[$e]"
_d_bad=""
for v in abc 0 -2; do
  e=$( LOG="$ROOT/t4d.log" SPECOPS_RUN_ALL_JOBS="$v" bash "$S/scripts/tests/run-all.sh" --quiet 2>&1 >/dev/null ); rc=$?
  { [ "$rc" -eq 0 ] && printf '%s\n' "$e" | grep -q "▶ run-all: 병렬 $_exp · "; } || _d_bad="$_d_bad [$v rc=$rc err=$e]"
done
[ -z "$_d_bad" ] && ok "T4.d 잘못된 값(abc·0·-2) → 중단 없이 자동 기본값" || nope "T4.d" "$_d_bad"

# ── T5: 중단 = 즉시 전부 종료 (AC-9 · clarify Q1) ──
#   ★ SIGINT 무시 상태는 두 겹으로 막는다 — 비대화형 셸의 `&` 는 자식의 SIGINT 를 무시 상태로 두고,
#     무시 상태로 시작한 셸은 INT 를 trap 할 수 없다(bash 규약). 실제 호출(pre-push 의 $(...))은 포그라운드다.
#     (1) 안쪽 run-all 은 set -m 으로 띄운다. (2) **이 스위트 자신이** `&` 로(예: implementing-ko 의 전체 스위트 병행) 기동되면
#     SIGINT 를 무시한 채 시작하고, set -m 은 "원래 상태(무시)" 를 자식에게 되돌려 주므로 (1) 만으로는 INT 가 먹지 않는다
#     (실측 20261012, macOS bash 3.2: 백그라운드 기동 → T5.b `rc=0(기대 130) el=61s`. ubuntu bash 5.2 에서는 이 조합이 INT 를 받아 재현되지 않는다).
#     그래서 안쪽 run-all 을 perl 로 SIGINT 기본 상태로 되살려 띄운다.
S=$(_sb)
for n in 1 2 3 4 5 6; do
  # 손자까지 만든다 — 스위트 그룹째 끝나는지 본다(pkill -P 류는 손자에 뚫린다).
  #   루프는 유한(최대 ~20s)이다 — 종료가 실패해도 이 스위트가 무한 부하를 남기지 않게.
  _suite "$S" "h$n" 'echo "start" >> "$LOG"; bash -c '"'"'for k in $(seq 1 100); do echo x >> "$HB"; sleep 0.2; done'"'"''
done
_DFL=(); command -v perl >/dev/null 2>&1 && _DFL=(perl -e '$SIG{INT}="DEFAULT"; exec @ARGV')
# 백그라운드 기동 헬퍼 — $1=ign|- , 나머지=명령. 출력은 $_OUT, pid 는 $_PID. ign 이면 이 셸이 SIGINT 를 무시한 채 띄운다
#   (= 스위트가 `&` 로 기동돼 SIGINT 무시 상태로 시작한 경우의 재현 — 실제 호출과 같은 경로라서 아래 전제 확인이 T5.c 의 기동을 그대로 검증한다).
_PID=""; _OUT=/dev/null
_spawn() {
  local ign="$1"; shift
  [ "$ign" = ign ] && trap '' INT
  set -m
  "$@" > "$_OUT" 2>&1 &
  _PID=$!
  set +m
  [ "$ign" = ign ] && trap - INT
  return 0
}
_t5() {  # $1=신호 $2=기대 rc $3=라벨 $4=ign(선택: 무시 상태로 기동된 스위트 재현)
  if [ "$1" = INT ] && [ "${#_DFL[@]}" -eq 0 ]; then
    skip "$3 INT perl 부재 — 안쪽 run-all 의 SIGINT 를 되살릴 수 없어 INT 중단 미검증 (PASS 집계 제외)"; return 0
  fi
  if [ "$3" = "T5.c" ] && [ "${4:-}" != ign ]; then   # T5.c 는 무시 상태 재현이 존재 이유 — ign 없이는 T5.b 의 중복으로 공허하게 통과한다
    nope "$3" "ign 인자 누락 — 호출부에서 ign 이 빠졌다"; return 0
  fi
  local tmpd="$ROOT/t5tmp.$3" pid rc t0 el n1 n2 h1 h2 probe
  if [ "${4:-}" = ign ]; then   # 전제 — _spawn ign 으로 띄운 자식은 INT 를 trap 할 수 없다. 깨지면 T5.c 는 아무것도 재현하지 못한다
    _OUT="$ROOT/t5.$3.probe"
    #   ★ `trap -p INT` 출력으로 감지하지 않는다 — bash 5.x 는 무시 상태인 신호에도 `trap -- '' SIGINT` 를 출력해 항상 "trappable" 로 오판한다
    #     (ubuntu bash 5.1/5.2 실측 — CI 에서만 FAIL). 실제로 INT 를 보내 핸들러가 도는지 본다.
    _spawn ign bash -c 'trap "echo trappable; exit 0" INT; kill -INT $$; sleep 1; echo ignored'
    wait "$_PID"; probe=$(cat "$_OUT")
    [ "$probe" = ignored ] && ok "$3 전제: _spawn ign 으로 띄운 자식은 INT 를 trap 할 수 없다(무시 상속 흉내가 실제로 유효)" \
      || { nope "$3 전제" "probe=$probe — _spawn ign 이 무시를 물려주지 못한다"; return 0; }
  fi
  mkdir -p "$tmpd"; LOG="$ROOT/t5.$3.log"; HB="$ROOT/t5.$3.hb"; : > "$LOG"; : > "$HB"
  _OUT="$ROOT/t5.$1.out"   # 판정 블록이 읽는 경로(`t5.$1.out`)는 그대로 둔다 — T5.b·T5.c 는 순차이고 `>` 가 매번 비운다(판정 블록 0줄 변경: AC-2)
  _spawn "${4:--}" env LOG="$LOG" HB="$HB" TMPDIR="$tmpd" SPECOPS_RUN_ALL_JOBS=2 ${_DFL[@]+"${_DFL[@]}"} bash "$S/scripts/tests/run-all.sh" --quiet
  pid=$_PID
  sleep 2
  n1=$(wc -l < "$LOG" | tr -d ' ')
  t0=$(date +%s); kill -"$1" "$pid"; wait "$pid"; rc=$?; el=$(( $(date +%s) - t0 ))
  sleep 1; h1=$(wc -l < "$HB" | tr -d ' '); n2=$(wc -l < "$LOG" | tr -d ' ')
  sleep 2; h2=$(wc -l < "$HB" | tr -d ' ')
  if [ "$rc" -eq "$2" ] && [ "$el" -le 5 ] && [ "$n1" -ge 1 ] && [ "$n2" -eq "$n1" ] && [ "$h2" -eq "$h1" ] \
     && [ -z "$(ls -d "$tmpd"/specops-run-all.* 2>/dev/null)" ] && ! grep -q 'VERIFY: PASS' "$ROOT/t5.$1.out"; then
    ok "$3 $1 → rc=$rc · ${el}s · 신규 시작 0 (시작 $n1) · heartbeat 정지 · 작업 디렉터리 정리"
  else
    nope "$3 $1" "rc=${rc}(기대 ${2}) el=${el}s 시작 ${n1}→${n2} hb ${h1}→${h2} work=$(ls -d "$tmpd"/specops-run-all.* 2>/dev/null)"
    [ "$h2" -eq "$h1" ] || pkill -f "$HB" 2>/dev/null   # 실패 시 잔존 정리(sandbox 에선 무효일 수 있음)
  fi
}
_t5 TERM 143 "T5.a"
_t5 INT 130 "T5.b"
_t5 INT 130 "T5.c" ign   # 스위트가 SIGINT 무시 상태로 기동된 경우를 기동 방식과 무관하게 결정적으로 재현 (전제 확인 포함)

# ── T6: 병렬 수 stderr 표시 · 비quiet FAIL 줄 위치 (AC-11) ──
S=$(_sb)
_suite "$S" f1 'sleep 0.4; echo "FAIL f1"; echo "PASS=0 FAIL=1"; exit 1'
_suite "$S" f2 'echo "PASS=1 FAIL=0"'
_suite "$S" f3 'echo "FAIL f3"; echo "PASS=0 FAIL=1"; exit 1'
_suite "$S" f4 'echo "PASS=1 FAIL=0"' '# run-all: serial — 표시 확인'
SPECOPS_RUN_ALL_JOBS=3 bash "$S/scripts/tests/run-all.sh" > "$ROOT/t6.v.out" 2> "$ROOT/t6.v.err"
SPECOPS_RUN_ALL_JOBS=3 bash "$S/scripts/tests/run-all.sh" --quiet > "$ROOT/t6.q.out" 2> "$ROOT/t6.q.err"
{ grep -qx '▶ run-all: 병렬 3 · 직렬 1 스위트' "$ROOT/t6.v.err" && grep -qx '▶ run-all: 병렬 3 · 직렬 1 스위트' "$ROOT/t6.q.err" \
  && ! grep -q '▶ run-all' "$ROOT/t6.v.out" "$ROOT/t6.q.out"; } \
  && ok "T6.a 병렬 수 표시는 두 모드 모두 stderr 1줄 · stdout 없음" || nope "T6.a" "v.err=$(cat "$ROOT/t6.v.err") q.err=$(cat "$ROOT/t6.q.err")"
_last_prog=$(grep -n '^--- ' "$ROOT/t6.v.out" | tail -1 | cut -d: -f1)
_first_fail=$(grep -n '^FAIL ' "$ROOT/t6.v.out" | head -1 | cut -d: -f1)
_vblk=$(grep '^FAIL ' "$ROOT/t6.v.out" | tr '\n' '|'); _qblk=$(grep '^FAIL ' "$ROOT/t6.q.out" | tr '\n' '|')
{ [ -n "$_last_prog" ] && [ -n "$_first_fail" ] && [ "$_first_fail" -gt $((_last_prog + 1)) ] \
  && [ "$_vblk" = "FAIL f1|FAIL f3|" ] && [ "$_vblk" = "$_qblk" ]; } \
  && ok "T6.b 비quiet FAIL 줄은 진행 줄 뒤·원래 순서로 모이고 quiet 와 같다" \
  || nope "T6.b" "last_prog=$_last_prog first_fail=$_first_fail v=[$_vblk] q=[$_qblk]"

# ── T7: 부하 취약 스위트의 직렬 표시 · 임계 무변경 (AC-6 — 20261006-runall-serial-split 로 위치 이전) ──
#   표시 형식은 spec FR-3 계약 문자열이다(run-all 의 판정 규칙은 T3 이 행위로 잠근다).
#   타이밍 단언(T-hg.d·GH-ci.5·GH-ci.5b)은 test-timing-serial.sh 로 옮겼다 — 큰 스위트째 직렬로 두지 않고 단언만 직렬로 둔다.
_t7_bad=""
for f in test-timing-serial.sh test-gbrain-recall.sh; do
  awk 'NR > 20 { exit } /^# run-all: serial — ./ { f = 1; exit } END { exit !f }' "$PLUGIN/scripts/tests/$f" 2>/dev/null || _t7_bad="$_t7_bad $f"
done
[ -z "$_t7_bad" ] && ok "T7.a 부하 취약 스위트가 선두 20줄 안에 사유 있는 직렬 표시" || nope "T7.a 직렬 표시 누락" "$_t7_bad"
{ [ "$(grep -c '"\$_d" -lt 3 \]' "$PLUGIN/scripts/tests/test-timing-serial.sh" 2>/dev/null)" -eq 2 ] \
  && grep -q '"\$elapsed" -lt 2000 \]' "$PLUGIN/scripts/tests/test-gbrain-recall.sh" \
  && grep -q '^  sleep 2  *# 유예' "$PLUGIN/scripts/tests/test-timing-serial.sh" 2>/dev/null; } \
  && ok "T7.b 시간 임계(< 3s ×2 · < 2000ms · 2s 유예) 무변경 — 타이밍 단언은 test-timing-serial.sh" \
  || nope "T7.b 임계 변경 감지" "직렬 표시로 대응하기로 했다 — 임계를 넓히면 그 테스트가 잡던 결함을 못 잡는다"
# 음성 잠금: 이동한 단언이 원 스위트에 이중으로 남거나 직렬 표시가 되살아나지 않는다
_t7_dup=""
awk 'NR > 20 { exit } /^# run-all: serial — ./ { f = 1; exit } END { exit !f }' "$PLUGIN/scripts/tests/test-validate-structure.sh" 2>/dev/null && _t7_dup="$_t7_dup vs:표시"
grep -q '^  sleep 2  *# 유예' "$PLUGIN/scripts/tests/test-validate-structure.sh" && _t7_dup="$_t7_dup vs:유예"
awk 'NR > 20 { exit } /^# run-all: serial — ./ { f = 1; exit } END { exit !f }' "$PLUGIN/scripts/tests/test-git-hooks.sh" 2>/dev/null && _t7_dup="$_t7_dup gh:표시"
[ "$(grep -c '"\$_d" -lt 3 \]' "$PLUGIN/scripts/tests/test-git-hooks.sh")" -eq 0 ] || _t7_dup="$_t7_dup gh:워치독"
[ -z "$_t7_dup" ] && ok "T7.c 두 큰 스위트(validate-structure·git-hooks)에 직렬 표시·타이밍 단언이 없다 (풀에서 돈다)" || nope "T7.c 이동 후 잔존" "$_t7_dup"

# ── T8: 작업자 비정상 종료 → FAIL WORKER 계상 · 미실행 스위트는 원인과 구분 (AC-2 · Phase C 지적) ──
#   JOBS=1 로 결정적 재현 — 스위트가 자기 작업자를 KILL 하면 xargs 가 abort 해 뒤 스위트는 시작조차 못 한다.
#   가드가 없으면 rc 파일 부재 스위트가 조용히 빠지고, 구분이 없으면 무고한 미실행 스위트가 "비정상 종료" 로 오귀속된다.
#   ★ 죽은 작업자의 bounded_run 워치독은 flag 가 안 지워져 상한까지 산다 — bash 가 함수 리다이렉트 때 원 stdout 을
#     높은 fd 에 보관하고 fork 한 subshell 이 그것을 물려받아, `$(run-all)` 캡처가 상한(기본 300s)만큼 멈췄다(실측 3s→3s·8s→8s).
S=$(_sb)
_suite "$S" a-killer 'sleep 0.3; kill -KILL $PPID'
_suite "$S" b-late 'echo "PASS=1 FAIL=0"'
_t0=$(date +%s)
o=$( SPECOPS_SUITE_TIMEOUT=20 SPECOPS_RUN_ALL_JOBS=1 bash "$S/scripts/tests/run-all.sh" --quiet 2>"$ROOT/t8.err" ); rc=$?
_el=$(( $(date +%s) - _t0 ))
{ [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$o" | tail -1)" = "VERIFY: FAIL" ] \
  && printf '%s\n' "$o" | grep -q '^FAIL WORKER — 결과 없음 (작업자 비정상 종료.*test-a-killer.sh$' \
  && printf '%s\n' "$o" | grep -qx 'FAILED: scripts/tests/test-a-killer.sh'; } \
  && ok "T8.a 작업자를 죽인 스위트 → FAIL WORKER 결과 없음 · VERIFY: FAIL" || nope "T8.a" "rc=$rc out=[$o]"
{ printf '%s\n' "$o" | grep -q '^FAIL WORKER — 미실행 (작업자 풀 중단.*test-b-late.sh$' \
  && ! printf '%s\n' "$o" | grep -q '비정상 종료.*test-b-late.sh'; } \
  && ok "T8.b 시작 못 한 스위트는 미실행으로 구분 (오귀속 없음)" || nope "T8.b" "out=[$o]"
grep -q '^⚠  run-all: 작업자 풀 비정상 종료' "$ROOT/t8.err" \
  && ok "T8.c 풀 비정상 종료를 stderr 로 알린다" || nope "T8.c" "err=[$(cat "$ROOT/t8.err")]"
[ "$_el" -lt 10 ] \
  && ok "T8.d 죽은 작업자의 워치독이 캡처를 붙잡지 않는다 (${_el}s < 10s · 상한 20s)" || nope "T8.d 고아 워치독" "el=${_el}s (상한 20s 까지 멈춤)"

# ── T9: 병렬 풀 longest-first — suite-order.txt (20261006-runall-serial-split) ──
#   JOBS>1 이고 목록이 있을 때만 풀 **시작 순서**를 앞당긴다. 집계·출력 순서·rc 는 불변, JOBS=1·목록 부재·무시 대상은 종전 순서.
_t9_mk() {   # $1=sandbox — p1~p4 (각 1초), 시작·종료 시각 로그
  for n in 1 2 3 4; do
    _suite "$1" "p$n" 's=$(ms); sleep 1; echo "p '"$n"' $s $(ms)" >> "$LOG"; echo "PASS=1 FAIL=0"'
  done
}
_t9_start() { awk -v n="$2" '$1=="p" && $2==n { print $3 }' "$1"; }
# 통제군 — 목록 없음, JOBS=2: p3 은 두 번째 파도(p1·p2 뒤)에 시작한다
S=$(_sb); LOG="$ROOT/t9a.log"; : > "$LOG"; _t9_mk "$S"
LOG="$LOG" SPECOPS_RUN_ALL_JOBS=2 bash "$S/scripts/tests/run-all.sh" --quiet >"$ROOT/t9a.out" 2>&1; _rc9a=$?
_p1=$(_t9_start "$LOG" 1); _p3=$(_t9_start "$LOG" 3)
{ [ "$_rc9a" -eq 0 ] && [ $((_p3 - _p1)) -ge 700 ]; } \
  && ok "T9.a 통제군(목록 없음) — 글롭 순서: p3 은 p1 보다 늦게 시작 (+$((_p3 - _p1))ms)" || nope "T9.a" "rc=$_rc9a p1=$_p1 p3=$_p3"
# 목록 있음 — p4·p3 를 앞세운다: 첫 파도가 p4·p3, p1 은 뒤
S=$(_sb); LOG="$ROOT/t9b.log"; : > "$LOG"; _t9_mk "$S"
printf '# 긴 순서\n\nscripts/tests/test-p4.sh\nscripts/tests/test-p3.sh\n' > "$S/scripts/tests/suite-order.txt"
LOG="$LOG" SPECOPS_RUN_ALL_JOBS=2 bash "$S/scripts/tests/run-all.sh" --quiet >"$ROOT/t9b.out" 2>&1; _rc9b=$?
_p1=$(_t9_start "$LOG" 1); _p3=$(_t9_start "$LOG" 3); _p4=$(_t9_start "$LOG" 4)
{ [ "$_rc9b" -eq 0 ] && [ $((_p1 - _p4)) -ge 700 ] && [ $((_p1 - _p3)) -ge 700 ]; } \
  && ok "T9.b 목록 선두(p4·p3)가 p1 보다 먼저 시작 (p1 이 +$((_p1 - _p4))ms 늦음)" || nope "T9.b" "rc=$_rc9b p1=$_p1 p3=$_p3 p4=$_p4"
# JOBS=1 — 목록이 있어도 글롭 순서(되돌림 스위치)
S=$(_sb); LOG="$ROOT/t9c.log"; : > "$LOG"; _t9_mk "$S"
printf 'scripts/tests/test-p4.sh\nscripts/tests/test-p3.sh\n' > "$S/scripts/tests/suite-order.txt"
LOG="$LOG" SPECOPS_RUN_ALL_JOBS=1 bash "$S/scripts/tests/run-all.sh" --quiet >"$ROOT/t9c.out" 2>&1; _rc9c=$?
_seq9=$(sort -k3,3n "$LOG" | awk '{ printf "%s", $2 }')
{ [ "$_rc9c" -eq 0 ] && [ "$_seq9" = "1234" ]; } \
  && ok "T9.c JOBS=1 은 목록을 보지 않는다 — 시작 순서 $_seq9" || nope "T9.c" "rc=$_rc9c seq=$_seq9"
# 무시 대상 — 주석·빈 줄·존재하지 않는 경로·중복·직렬 표시 스위트·공백 접미: 전부 한 번씩 실행, rc 0
S=$(_sb); LOG="$ROOT/t9d.log"; : > "$LOG"; _t9_mk "$S"
_suite "$S" ser 's=$(ms); sleep 0.2; echo "p 9 $s $(ms)" >> "$LOG"; echo "PASS=1 FAIL=0"' '# run-all: serial — 테스트용 직렬'
printf '# c\n\n   \nscripts/tests/test-nope.sh\nscripts/tests/test-p2.sh   \nscripts/tests/test-p2.sh\nscripts/tests/test-ser.sh\n' > "$S/scripts/tests/suite-order.txt"
LOG="$LOG" SPECOPS_RUN_ALL_JOBS=2 bash "$S/scripts/tests/run-all.sh" --quiet >"$ROOT/t9d.out" 2>&1; _rc9d=$?
_cnt9=$(awk '$1=="p"{ c[$2]++ } END { n=0; for (k in c) if (c[k]!=1) n++; print n+0 }' "$LOG"); _tot9=$(awk '$1=="p"' "$LOG" | wc -l | tr -d ' ')
{ [ "$_rc9d" -eq 0 ] && [ "$_cnt9" -eq 0 ] && [ "$_tot9" -eq 5 ] && tail -1 "$ROOT/t9d.out" | grep -qx 'VERIFY: PASS'; } \
  && ok "T9.d 무시 대상(주석·빈 줄·없는 경로·중복·직렬·공백) — 스위트 5개 모두 정확히 1회·VERIFY: PASS" || nope "T9.d" "rc=$_rc9d 중복=$_cnt9 총=$_tot9"
# 출력 불변 — FAIL 스위트 2개(p2·p4)일 때 목록 유무와 무관하게 FAIL 블록·FAILED 목록 순서·마지막 줄이 같다(시작·목록 순서가 집계 순서로 새는 결함을 잡는다)
_t9_out() {   # $1=목록 내용(빈 문자열이면 파일 없음)
  local S2; S2=$(_sb); LOG="$ROOT/t9e.log"; : > "$LOG"; _t9_mk "$S2"
  _suite "$S2" p2 'echo "FAIL p2 — 의도된 실패"; echo "PASS=0 FAIL=1"; exit 1'
  _suite "$S2" p4 'sleep 0.3; echo "FAIL p4 — 의도된 실패"; echo "PASS=0 FAIL=1"; exit 1'
  [ -n "$1" ] && printf "$1\n" > "$S2/scripts/tests/suite-order.txt"
  LOG="$LOG" SPECOPS_RUN_ALL_JOBS=2 bash "$S2/scripts/tests/run-all.sh" --quiet 2>/dev/null | sed "s#$S2#SB#g"
}
_o_no=$(_t9_out ""); _o_yes=$(_t9_out "scripts/tests/test-p4.sh\nscripts/tests/test-p2.sh")
{ [ -n "$_o_no" ] && [ "$_o_no" = "$_o_yes" ] && printf '%s\n' "$_o_yes" | tail -1 | grep -qx 'VERIFY: FAIL' \
  && [ "$(printf '%s\n' "$_o_yes" | grep -c '^FAILED:')" -eq 2 ]; } \
  && ok "T9.e FAIL 스위트 2개 — 시작·목록 순서가 집계로 새지 않아 목록 유무와 무관하게 quiet 출력(FAIL 블록·FAILED 2건·마지막 줄)이 같다" || nope "T9.e" "no=[$_o_no] yes=[$_o_yes]"
# 실 목록 무결성 — 존재하지 않는 경로 0·중복 0·직렬 표시 스위트 0·15~25개(목록은 손봐도 된다)
_ord="$PLUGIN/scripts/tests/suite-order.txt"
_t9_bad=""; _t9_n=0
if [ -f "$_ord" ]; then
  while IFS= read -r _l; do
    _l=${_l%$'\r'}; case "$_l" in ''|'#'*) continue ;; esac
    _t9_n=$((_t9_n + 1))
    [ -f "$PLUGIN/$_l" ] || _t9_bad="$_t9_bad 없음:$_l"
    awk 'NR > 20 { exit } /^# run-all: serial — ./ { f = 1; exit } END { exit !f }' "$PLUGIN/$_l" 2>/dev/null && _t9_bad="$_t9_bad 직렬:$_l"
  done < "$_ord"
  _dup=$(grep -v '^#' "$_ord" | grep -v '^[[:space:]]*$' | sort | uniq -d | head -1)
  [ -z "$_dup" ] || _t9_bad="$_t9_bad 중복:$_dup"
fi
{ [ -f "$_ord" ] && [ -z "$_t9_bad" ] && [ "$_t9_n" -ge 15 ] && [ "$_t9_n" -le 25 ]; } \
  && ok "T9.f suite-order.txt 무결성 — ${_t9_n}개(15~25)·없는 경로 0·중복 0·직렬 표시 스위트 0" || nope "T9.f" "n=$_t9_n bad=[$_t9_bad]"

echo ""
finish
