#!/usr/bin/env bash
# mutation-score.sh 하니스 로직 stub 단위 (토큰 0)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck disable=SC1091
source "$PLUGIN/scripts/tests/mutation-score.sh"
ck() { if [ "$2" = "$3" ]; then echo "PASS $1"; PASS=$((PASS+1)); else echo "FAIL $1 — exp '$3' got '$2'"; FAIL=$((FAIL+1)); fi; }
# equivalent conf 행 1줄 (TAB 5칸: target · 함수[#k/n] · pattern · 원문 · reason)
row() { printf '%s\t%s\t%s\t%s\t%s\n' "$@"; }

ck "T1 score 8/2 → 80" "$(mut::score 8 2)" "80"
ck "T2 score 0/0 → 0"  "$(mut::score 0 0)" "0"
ck "T3 score 10/0 → 100" "$(mut::score 10 0)" "100"

n=$(mut::catalog | grep -c .)
if [ "$n" -ge 5 ]; then echo "PASS T4 catalog ≥5 ($n)"; PASS=$((PASS+1)); else echo "FAIL T4 catalog <5 ($n)"; FAIL=$((FAIL+1)); fi

ck "T5 judge fail→killed" "$(mut::judge 'exit 1')" "killed"
ck "T6 judge pass→survived" "$(mut::judge 'exit 0')" "survived"

tmp=$(mktemp -d)
cat > "$tmp/tgt.sh" <<'EOS'
#!/usr/bin/env bash
check() { [ "$1" -eq 0 ] && echo ok || echo no; }
check "$@"
EOS
orig_hash=$(md5 -q "$tmp/tgt.sh" 2>/dev/null || md5sum "$tmp/tgt.sh" | cut -d' ' -f1)
out=$(mut::run_target "$tmp/tgt.sh" "bash $tmp/tgt.sh 0 | grep -q ok" 2>/dev/null)
after_hash=$(md5 -q "$tmp/tgt.sh" 2>/dev/null || md5sum "$tmp/tgt.sh" | cut -d' ' -f1)
ck "T7 복원 무결성 (변형 잔류 0)" "$after_hash" "$orig_hash"
if grep -q "MUTATION .*score=" <<<"$out"; then echo "PASS T8 리포트 형식"; PASS=$((PASS+1)); else echo "FAIL T8 리포트 ($out)"; FAIL=$((FAIL+1)); fi

cat > "$tmp/syn.sh" <<'EOS'
#!/usr/bin/env bash
echo foo
EOS
mut::catalog() { printf 'foo\ts/foo/(/\n'; }
out2=$(mut::run_target "$tmp/syn.sh" "true" 2>/dev/null)
unset -f mut::catalog; source "$PLUGIN/scripts/tests/mutation-score.sh"
if grep -qE "invalid=[1-9]" <<<"$out2" && grep -q "killed=0 survived=0" <<<"$out2"; then
  echo "PASS T9 invalid 결정적 집계 (score 분모 제외)"; PASS=$((PASS+1))
else echo "FAIL T9 invalid ($out2)"; FAIL=$((FAIL+1)); fi
rm -rf "$tmp"

out3=$(mut::run_target "/nonexistent/tgt.sh" "true" 2>/dev/null)
if grep -q "SKIP" <<<"$out3"; then echo "PASS T10 target 부재 SKIP"; PASS=$((PASS+1)); else echo "FAIL T10 SKIP ($out3)"; FAIL=$((FAIL+1)); fi

# T11 equivalent 제외 — config 매칭 (target·함수·pattern·원문) 변형은 equivalent 카운트 + 분모 제외
tmpe=$(mktemp -d)
cat > "$tmpe/tgt.sh" <<'EOS'
#!/usr/bin/env bash
f() { [ -f "$1" ] || return 0; echo found; }
f "$@"
EOS
row "$tmpe/tgt.sh" f 'return 0' 'f() { [ -f "$1" ] || return 0; echo found; }' 'test stub equivalent' > "$tmpe/eqv.conf"
if MUT_EQUIV_CONF="$tmpe/eqv.conf" mut::is_equivalent "$tmpe/tgt.sh" 2 "return 0"; then echo "PASS T11 is_equivalent 매칭"; PASS=$((PASS+1)); else echo "FAIL T11"; FAIL=$((FAIL+1)); fi
if MUT_EQUIV_CONF="$tmpe/eqv.conf" mut::is_equivalent "$tmpe/tgt.sh" 2 "&&"; then echo "FAIL T12 다른 pattern 매칭됨"; FAIL=$((FAIL+1)); else echo "PASS T12 pattern 정밀 미매칭"; PASS=$((PASS+1)); fi
if MUT_EQUIV_CONF="/nonexistent" mut::is_equivalent "$tmpe/tgt.sh" 2 "return 0"; then echo "FAIL T13 config 부재 매칭됨"; FAIL=$((FAIL+1)); else echo "PASS T13 config 부재 graceful"; PASS=$((PASS+1)); fi
out=$(MUT_EQUIV_CONF="$tmpe/eqv.conf" mut::run_target "$tmpe/tgt.sh" "true" 2>/dev/null)
if grep -qE "equivalent=[0-9]+" <<<"$out"; then echo "PASS T14 리포트 equivalent="; PASS=$((PASS+1)); else echo "FAIL T14 ($out)"; FAIL=$((FAIL+1)); fi
rm -rf "$tmpe"

# threshold + baseline sanity (20260714-mutation-ci-gate) — cron 게이트 로직 회귀 잠금
tmpt=$(mktemp -d)
printf '#!/bin/bash\necho hi\n' > "$tmpt/t.sh"
printf '%s|true\n' "$tmpt/t.sh" > "$tmpt/c.conf"
# T15 MUTATION_MIN_SCORE 미설정 → exit 0 (하위호환 — 측정만)
( bash "$PLUGIN/scripts/tests/mutation-score.sh" "$tmpt/c.conf" >/dev/null 2>&1 ); ck "T15 threshold 미설정 → exit 0" "$?" "0"
# T16 MIN=50, mutant 0 → score 0% < 50 → exit 1 (미달 차단)
( MUTATION_MIN_SCORE=50 bash "$PLUGIN/scripts/tests/mutation-score.sh" "$tmpt/c.conf" >/dev/null 2>&1 ); ck "T16 MIN 미달 → exit 1" "$?" "1"
# T17 ★ baseline sanity — 무변형에서 testcmd 파손(false)이면 MUT_BELOW_MIN=1 (score 거짓통과 차단)
MUT_BELOW_MIN=0
mut::run_target "$tmpt/t.sh" "false" >/dev/null 2>&1
ck "T17 sanity 파손 testcmd → MUT_BELOW_MIN=1" "$MUT_BELOW_MIN" "1"
rm -rf "$tmpt"

# ── T18~T27: conf stale 감지 · 주석 skip (FID 20260827-mutation-conf-stale) ──
tmps=$(mktemp -d); trap 'rm -rf "$tmps"' EXIT

# fixture target: 3줄이 변이 후보 — L3 코드, L4 주석, L5 인라인주석 코드
cat > "$tmps/tgt.sh" <<'FIX'
#!/usr/bin/env bash
f1() {
  [ -n "${1:-}" ] && return 0
  # 주석: [ -z "$x" ] && return 0 — 변이돼선 안 된다
  [ "$2" = "y" ] && return 0  # 인라인 주석 — 이 줄은 코드다
}
FIX

# T18 주석 판정 — 선행 공백 제거 후 첫 문자
mut::is_comment_line '  # foo'      && r1=0 || r1=1
mut::is_comment_line '[ x ] && y # z' && r2=0 || r2=1
if [ "$r1" = 0 ] && [ "$r2" = 1 ]; then
  echo "PASS T18 주석 판정 — 선행공백 주석=참, 인라인#=거짓"; PASS=$((PASS+1))
else echo "FAIL T18 (r1=$r1 r2=$r2)"; FAIL=$((FAIL+1)); fi

# T19 주석 줄은 변이 사이트가 아니다 (AC-2) — L4 의 'return 0' 은 집계 0
out=$(MUT_EQUIV_CONF=/nonexistent mut::run_target "$tmps/tgt.sh" "true" 2>/dev/null)
tot=$(printf '%s' "$out" | sed -n 's/.*killed=\([0-9]*\) survived=\([0-9]*\) invalid=\([0-9]*\) equivalent=\([0-9]*\).*/\1+\2+\3+\4/p')
tot=$(( $(echo "${tot:-0+0+0+0}") ))
# 변이 후보: L3 'return 0'+'&&', L5 'return 0'+'&&' = 4 (L4 주석 2건 제외)
if [ "$tot" = 4 ]; then echo "PASS T19 주석 줄 제외 — 집계 4건 (AC-2)"; PASS=$((PASS+1));
else echo "FAIL T19 집계 $tot (기대 4 — 주석 L4 가 섞였나?)"; FAIL=$((FAIL+1)); fi

# T20 인라인 # 코드 줄은 정상 변이 (AC-3) — L5 를 가리키는 equivalent 가 매칭되면 사이트가 살아 있다는 뜻
row "$tmps/tgt.sh" f1 'return 0' '[ "$2" = "y" ] && return 0  # 인라인 주석 — 이 줄은 코드다' 'inline-comment 코드 줄' > "$tmps/eq-ok.conf"
out=$(MUT_EQUIV_CONF="$tmps/eq-ok.conf" mut::run_target "$tmps/tgt.sh" "true" 2>/dev/null)
if grep -q 'equivalent=1' <<<"$out"; then
  echo "PASS T20 인라인 # 코드 줄 변이 유지 (AC-3)"; PASS=$((PASS+1))
else echo "FAIL T20 ($out)"; FAIL=$((FAIL+1)); fi

# T21 사이트 판정 (anchor_row) — 정상/주석/부재
mut::anchor_row "$tmps/tgt.sh" 3 'return 0' >/dev/null && s1=0 || s1=1
mut::anchor_row "$tmps/tgt.sh" 4 'return 0' >/dev/null && s2=0 || s2=1
mut::anchor_row "$tmps/tgt.sh" 999 'return 0' >/dev/null && s3=0 || s3=1
if [ "$s1" = 0 ] && [ "$s2" = 1 ] && [ "$s3" = 1 ]; then
  echo "PASS T21 사이트 판정 — 코드=참 주석=거짓 범위밖=거짓"; PASS=$((PASS+1))
else echo "FAIL T21 (s1=$s1 s2=$s2 s3=$s3)"; FAIL=$((FAIL+1)); fi

# T22 stale 감지 양성 (AC-4)
row "$tmps/tgt.sh" f1 'return 0' '#!/usr/bin/env bash' 'stale — shebang 은 사이트가 아니다' > "$tmps/eq-stale.conf"
printf '%s\n' "$tmps/tgt.sh|true" > "$tmps/tg.conf"
err=$(MUT_EQUIV_CONF="$tmps/eq-stale.conf" mut::check_conf "$tmps/tg.conf" 2>&1); rc=$?
if [ "$rc" != 0 ] && grep -q 'STALE' <<<"$err"; then
  echo "PASS T22 stale 감지 양성 (AC-4)"; PASS=$((PASS+1))
else echo "FAIL T22 rc=$rc out=$err"; FAIL=$((FAIL+1)); fi

# T23 stale 음성 — 정상 conf 는 무발화 (AC-5)
err=$(MUT_EQUIV_CONF="$tmps/eq-ok.conf" mut::check_conf "$tmps/tg.conf" 2>&1); rc=$?
if [ "$rc" = 0 ] && ! grep -q 'STALE' <<<"$err"; then
  echo "PASS T23 정상 conf 무발화 (AC-5)"; PASS=$((PASS+1))
else echo "FAIL T23 rc=$rc out=$err"; FAIL=$((FAIL+1)); fi

# T24 오발 방지 — conf 에 항목 없는 target (AC-6) + conf 부재 graceful (D-8)
printf '%s\n' "$tmps/other.sh|true" > "$tmps/tg2.conf"
cp "$tmps/tgt.sh" "$tmps/other.sh"
err=$(MUT_EQUIV_CONF="$tmps/eq-stale.conf" mut::check_conf "$tmps/tg2.conf" 2>&1); rc1=$?
# err2 는 stdout·stderr 를 삼켜 리포트를 더럽히지 않기 위한 버림 변수다 — 판정은 rc2 만 쓴다.
# shellcheck disable=SC2034
err2=$(MUT_EQUIV_CONF=/nonexistent mut::check_conf "$tmps/tg.conf" 2>&1); rc2=$?
if [ "$rc1" = 0 ] && [ "$rc2" = 0 ]; then
  echo "PASS T24 무관 target·conf 부재 오발 없음 (AC-6·D-8)"; PASS=$((PASS+1))
else echo "FAIL T24 rc1=$rc1 rc2=$rc2"; FAIL=$((FAIL+1)); fi

# T25 --check-conf 독립 모드 (AC-10) — 실 스크립트 서브프로세스
_MS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mutation-score.sh"
o=$(MUT_EQUIV_CONF="$tmps/eq-ok.conf" bash "$_MS" --check-conf "$tmps/tg.conf" 2>&1); rc=$?
if [ "$rc" = 0 ] && grep -q 'CONF-CHECK' <<<"$o"; then
  echo "PASS T25 --check-conf 정합 시 rc=0 (AC-10)"; PASS=$((PASS+1))
else echo "FAIL T25 rc=$rc out=$o"; FAIL=$((FAIL+1)); fi

o=$(MUT_EQUIV_CONF="$tmps/eq-stale.conf" bash "$_MS" --check-conf "$tmps/tg.conf" 2>&1); rc=$?
if [ "$rc" != 0 ] && grep -q 'STALE' <<<"$o"; then
  echo "PASS T26 --check-conf stale 시 rc≠0 (AC-10)"; PASS=$((PASS+1))
else echo "FAIL T26 rc=$rc out=$o"; FAIL=$((FAIL+1)); fi

# T27 fail-fast — stale 이면 채점 줄이 없다 + 5초 이내 (AC-9)
_t0=$SECONDS
o=$(MUT_EQUIV_CONF="$tmps/eq-stale.conf" bash "$_MS" "$tmps/tg.conf" 2>&1); rc=$?
_el=$(( SECONDS - _t0 ))
# ★ ABORT 도 함께 요구한다 — rc≠0 + MUTATION 부재만 보면 stale 무관 실패(러너 문법 파손 등)에도
#   통과해 fail-fast 회귀를 놓친다. AC-9 의 4요건(ABORT·채점줄 부재·rc≠0·5초 이내)을 모두 잠근다.
# ★ 경과시간까지 보는 이유 — "채점 줄 부재" 는 채점이 **끝까지 돌고 마지막에** 막혀도 성립한다.
#   fail-fast 는 judge **앞에서** 끊는 것이므로 시간이 유일한 직접 증거다.
if [ "$rc" != 0 ] && [ "$_el" -lt 5 ] && grep -q 'ABORT' <<<"$o" && ! grep -q '^MUTATION ' <<<"$o"; then
  echo "PASS T27 fail-fast — ABORT + 채점 미진입 + ${_el}s (AC-9)"; PASS=$((PASS+1))
else echo "FAIL T27 rc=$rc elapsed=${_el}s out=$o"; FAIL=$((FAIL+1)); fi

# T28 빈 pattern 행은 stale 이다 (AC-4 잔여 구멍) — pattern 이 빈 행은 어떤 사이트에도 안 맞는 죽은 항목이다.
#   "이 대상 것이 아닌 행" 으로 넘기면 건강하다고 오보하므로 stale 로 잡아야 한다.
row "$tmps/tgt.sh" f1 '' '[ -n "${1:-}" ] && return 0' '빈 pattern' > "$tmps/eq-empty.conf"
err=$(MUT_EQUIV_CONF="$tmps/eq-empty.conf" mut::check_conf "$tmps/tg.conf" 2>&1); rc=$?
if [ "$rc" != 0 ] && grep -q 'STALE' <<<"$err"; then
  echo "PASS T28 빈 pattern 행 stale 판정 (AC-4 잔여 구멍)"; PASS=$((PASS+1))
else echo "FAIL T28 rc=$rc out=$err"; FAIL=$((FAIL+1)); fi

# T29~T31 --target <path> — CI matrix 가 대상 1건만 측정한다 (20261008-test-holes)
#   other.sh 는 baseline 이 파손된 대상(testcmd=false → MUT_BELOW_MIN=1)이라, 필터가 안 먹으면 rc=1 이 된다.
tmpq=$(mktemp -d)
printf '#!/bin/bash\necho hi\n' > "$tmpq/t.sh"
printf '#!/bin/bash\necho other\n' > "$tmpq/other.sh"
printf '%s|true\n%s|false\n' "$tmpq/t.sh" "$tmpq/other.sh" > "$tmpq/two.conf"
( bash "$_MS" "$tmpq/two.conf" >/dev/null 2>&1 ); ck "T29a --target 없음 → 전 대상 측정(파손 대상 포함 rc=1) — 기본 동작 불변" "$?" "1"
o=$(bash "$_MS" --target "$tmpq/t.sh" "$tmpq/two.conf" 2>&1); rc=$?
if [ "$rc" = 0 ] && grep -q 't.sh' <<<"$o" && ! grep -q 'other.sh' <<<"$o"; then
  echo "PASS T29b --target 지정 대상만 측정 (다른 대상 미실행)"; PASS=$((PASS+1))
else echo "FAIL T29b rc=$rc out=$o"; FAIL=$((FAIL+1)); fi
o=$(bash "$_MS" --target "$tmpq/nope.sh" "$tmpq/two.conf" 2>&1); rc=$?
if [ "$rc" = 2 ] && grep -q 'conf 에 없는 대상' <<<"$o"; then
  echo "PASS T30 conf 에 없는 --target → rc=2 (오타가 초록이 되지 않는다)"; PASS=$((PASS+1))
else echo "FAIL T30 rc=$rc out=$o"; FAIL=$((FAIL+1)); fi
o=$(bash "$_MS" --target 2>&1); rc=$?
if [ "$rc" = 2 ] && grep -q -- '--target' <<<"$o"; then
  echo "PASS T31 --target 값 누락 → rc=2"; PASS=$((PASS+1))
else echo "FAIL T31 rc=$rc out=$o"; FAIL=$((FAIL+1)); fi

rm -rf "$tmpq"

# ── T32~T41: equivalent conf 의 키 = 함수 + 줄 원문 (20261010-mutation-equiv-anchors) ──
# 종전 키는 절대 줄번호였다. 줄이 밀린 자리에 같은 패턴의 다른 줄이 오면 --check-conf 가 통과한 채
#   엉뚱한 가드가 등가로 빠졌다(conf 머리말 실측 3건). 아래는 그 병이 구조적으로 없어졌음을 잠근다.
A1='[ -n "${1:-}" ] && return 0'      # fixture f1 의 L3 원문
_eq() { MUT_EQUIV_CONF="$1" mut::is_equivalent "$2" "$3" "$4"; }                 # <conf> <target> <line> <pattern>
_cc() { MUT_EQUIV_CONF="$1" mut::check_conf "$2" 2>&1; }                          # <conf> <targets_conf>
mkfix() {  # <path> — 줄을 밀고·바꾸고·늘려 볼 사본
  cp "$tmps/tgt.sh" "$1"; printf '%s|true\n' "$1" > "$1.tg"
}

# T32 위에 줄이 끼어도 같은 사이트를 따라간다 (핵심 이득 — 종전에는 여기서 stale 또는 무음 오매칭)
mkfix "$tmps/shift.sh"
row "$tmps/shift.sh" f1 'return 0' "$A1" '줄 이동 추적' > "$tmps/shift.conf"
_eq "$tmps/shift.conf" "$tmps/shift.sh" 3 'return 0' && b0=0 || b0=1
# 파일 머리에 3줄 + 함수 안 사이트 앞에 1줄을 끼운다
awk 'NR == 1 { print; print "# pad 1"; print "x=1"; print ""; next } { print } $0 == "f1() {" { print "  : inserted" }' \
  "$tmps/tgt.sh" > "$tmps/shift.sh"
ln_new=$(grep -nF -- "$A1" "$tmps/shift.sh" | cut -d: -f1)
_eq "$tmps/shift.conf" "$tmps/shift.sh" "$ln_new" 'return 0' && b1=0 || b1=1
_eq "$tmps/shift.conf" "$tmps/shift.sh" 3 'return 0' && b2=0 || b2=1
o=$(_cc "$tmps/shift.conf" "$tmps/shift.sh.tg"); rc=$?
if [ "$b0" = 0 ] && [ "$ln_new" != 3 ] && [ "$b1" = 0 ] && [ "$b2" = 1 ] && [ "$rc" = 0 ]; then
  echo "PASS T32 줄이 밀려도 같은 사이트 (L3 → L${ln_new}) — 옛 줄번호 자리는 등가가 아니다"; PASS=$((PASS+1))
else echo "FAIL T32 b0=$b0 ln_new=$ln_new b1=$b1 b2=$b2 rc=$rc out=$o"; FAIL=$((FAIL+1)); fi

# T33 무음 오매칭 불가 — 그 자리에 같은 패턴의 **다른 줄**이 오면 stale 이다 (종전: 줄번호+패턴이 맞아 통과)
mkfix "$tmps/swap.sh"
row "$tmps/swap.sh" f1 'return 0' "$A1" '원래 가드' > "$tmps/swap.conf"
sed '3s/.*/  [ -z "${9:-}" ] \&\& return 0/' "$tmps/tgt.sh" > "$tmps/swap.sh"
_eq "$tmps/swap.conf" "$tmps/swap.sh" 3 'return 0' && b1=0 || b1=1
o=$(_cc "$tmps/swap.conf" "$tmps/swap.sh.tg"); rc=$?
if [ "$b1" = 1 ] && [ "$rc" != 0 ] && grep -q 'STALE.*매칭 사이트 0건' <<<"$o"; then
  echo "PASS T33 같은 줄번호·같은 패턴의 다른 줄 → 등가 아님 + STALE"; PASS=$((PASS+1))
else echo "FAIL T33 b1=$b1 rc=$rc out=$o"; FAIL=$((FAIL+1)); fi

# T34 같은 원문이 함수 안에 늘면 멈춘다 — 순번 없는 행은 "여럿", 순번 있는 행은 개수 불일치
mkfix "$tmps/twin.sh"
row "$tmps/twin.sh" f1 'return 0' "$A1" '쌍둥이 전' > "$tmps/twin.conf"
sed "3p" "$tmps/tgt.sh" > "$tmps/twin.sh"                       # L3 을 한 번 더 (L3·L4 가 같은 원문)
o=$(_cc "$tmps/twin.conf" "$tmps/twin.sh.tg"); rc=$?
_eq "$tmps/twin.conf" "$tmps/twin.sh" 3 'return 0' && b1=0 || b1=1
row "$tmps/twin.sh" 'f1#2/2' 'return 0' "$A1" '둘째만 등가' > "$tmps/twin2.conf"
_eq "$tmps/twin2.conf" "$tmps/twin.sh" 4 'return 0' && k2=0 || k2=1
_eq "$tmps/twin2.conf" "$tmps/twin.sh" 3 'return 0' && k1=0 || k1=1
sed "3p;3p" "$tmps/tgt.sh" > "$tmps/twin.sh"                    # 셋으로 늘린다 → #2/2 는 개수 불일치
o3=$(_cc "$tmps/twin2.conf" "$tmps/twin.sh.tg"); rc3=$?
_eq "$tmps/twin2.conf" "$tmps/twin.sh" 4 'return 0' && k3=0 || k3=1
if [ "$rc" != 0 ] && [ "$b1" = 1 ] && grep -q 'STALE.*같은 원문 2건' <<<"$o" \
   && [ "$k2" = 0 ] && [ "$k1" = 1 ] \
   && [ "$rc3" != 0 ] && [ "$k3" = 1 ] && grep -q 'STALE.*개수 불일치' <<<"$o3"; then
  echo "PASS T34 같은 원문 추가 → STALE(여럿) · #k/n 은 k번째만 · n 이 달라지면 STALE(개수 불일치)"; PASS=$((PASS+1))
else echo "FAIL T34 rc=$rc b1=$b1 k2=$k2 k1=$k1 rc3=$rc3 k3=$k3 o=$o o3=$o3"; FAIL=$((FAIL+1)); fi

# T35 구 형식(줄번호 키) 행은 거부한다 — 조용히 건너뛰면 그 행의 등가 제외가 사라진 채 채점된다
printf '%s\n' "$tmps/tgt.sh|3|return 0|legacy row" > "$tmps/legacy.conf"
o=$(_cc "$tmps/legacy.conf" "$tmps/tg.conf"); rc=$?
_eq "$tmps/legacy.conf" "$tmps/tgt.sh" 3 'return 0' && b1=0 || b1=1
if [ "$rc" != 0 ] && [ "$b1" = 1 ] && grep -q 'STALE.*구 형식 — 줄번호 키' <<<"$o"; then
  echo "PASS T35 구 형식 행 → STALE(구 형식 — 줄번호 키) + 등가 아님"; PASS=$((PASS+1))
else echo "FAIL T35 rc=$rc b1=$b1 out=$o"; FAIL=$((FAIL+1)); fi

# T36 원문은 정확 일치다 — 부분 문자열로는 안 붙는다 (과잉 제외 차단)
row "$tmps/tgt.sh" f1 'return 0' 'return 0' '원문의 일부만 적음' > "$tmps/part.conf"
row "$tmps/tgt.sh" f1 'return 0' '[ -n "${1:-}" ]' '앞부분만 적음' >> "$tmps/part.conf"
o=$(_cc "$tmps/part.conf" "$tmps/tg.conf"); rc=$?
_eq "$tmps/part.conf" "$tmps/tgt.sh" 3 'return 0' && b1=0 || b1=1
_eq "$tmps/part.conf" "$tmps/tgt.sh" 5 'return 0' && b2=0 || b2=1
if [ "$rc" != 0 ] && [ "$b1" = 1 ] && [ "$b2" = 1 ] && [ "$(printf '%s\n' "$o" | grep -c '^STALE ')" = 2 ]; then
  echo "PASS T36 부분 문자열 원문 2행 → 둘 다 STALE · 어느 사이트도 등가 아님"; PASS=$((PASS+1))
else echo "FAIL T36 rc=$rc b1=$b1 b2=$b2 out=$o"; FAIL=$((FAIL+1)); fi

# T37 함수가 키의 일부다 — 함수 밖(-)과 함수 안의 같은 원문을 구분하고, 다른 함수의 같은 원문에 붙지 않는다
cat > "$tmps/scope.sh" <<'FIX'
#!/usr/bin/env bash
g1() { return 0; }
[ -d "${2:-}" ] && return 0
g2() {
  [ -n "${1:-}" ] && return 0
}
function g3 {
  [ -n "${1:-}" ] && return 0
}
[ -n "${1:-}" ] && return 0
FIX
printf '%s|true\n' "$tmps/scope.sh" > "$tmps/scope.tg"
row "$tmps/scope.sh" - '&&' "$A1" '함수 밖' > "$tmps/scope.conf"
row "$tmps/scope.sh" g3 '&&' "$A1" 'function 키워드 정의' >> "$tmps/scope.conf"
row "$tmps/scope.sh" g1 'return 0' 'g1() { return 0; }' '한 줄 함수' >> "$tmps/scope.conf"
row "$tmps/scope.sh" - '&&' '[ -d "${2:-}" ] && return 0' '한 줄 함수 바로 뒤의 함수 밖 줄' >> "$tmps/scope.conf"
o=$(_cc "$tmps/scope.conf" "$tmps/scope.tg"); rc=$?
got=$(MUT_EQUIV_CONF="$tmps/scope.conf" mut::equiv_sites "$tmps/scope.sh" | sort -n | tr '\t\n' ': ')
if [ "$rc" = 0 ] && [ "$got" = "2:return 0 3:&& 8:&& 10:&& " ]; then
  echo "PASS T37 함수 경계 — 함수 밖(-)·function 키워드·한 줄 함수와 그 직후 (g2 의 같은 원문 L5 는 등가 아님)"; PASS=$((PASS+1))
else echo "FAIL T37 rc=$rc got='$got' out=$o"; FAIL=$((FAIL+1)); fi

# T38 형식이 깨진 행은 건너뛰지 않는다 — 칸 수 불일치 · 빈 reason
printf '%s\t%s\t%s\t%s\n' "$tmps/tgt.sh" f1 'return 0' "$A1" > "$tmps/f4.conf"            # 4칸 (reason 칸 없음)
row "$tmps/tgt.sh" f1 'return 0' "$A1" '' > "$tmps/noreason.conf"                          # reason 빈 값
row "$tmps/tgt.sh" f1 'return 0' "$A1" "$(printf 'reason\textra')" > "$tmps/f6.conf"       # 6칸
o1=$(_cc "$tmps/f4.conf" "$tmps/tg.conf"); r1=$?
o2=$(_cc "$tmps/noreason.conf" "$tmps/tg.conf"); r2=$?
o3=$(_cc "$tmps/f6.conf" "$tmps/tg.conf"); r3=$?
if [ "$r1" != 0 ] && [ "$r2" != 0 ] && [ "$r3" != 0 ] && grep -q 'STALE.*형식 오류' <<<"$o1" \
   && grep -q 'STALE.*reason 비어 있음' <<<"$o2" && grep -q 'STALE.*형식 오류' <<<"$o3"; then
  echo "PASS T38 형식 오류 행(4칸·6칸·빈 reason) → STALE"; PASS=$((PASS+1))
else echo "FAIL T38 r1=$r1 r2=$r2 r3=$r3 o1=$o1 o2=$o2 o3=$o3"; FAIL=$((FAIL+1)); fi

# T39 --anchor — 사이트의 conf 행을 만든다 (`|` 가 든 원문 · 공백 정규화 · 쌍둥이 순번 · rc 계약)
cat > "$tmps/anc.sh" <<'FIX'
#!/usr/bin/env bash
h1() {
  [ -f "$1" ]   ||   return 0
  # [ -f "$1" ] || return 0
  x=$(a | b) && return 0
  return 0
  return 0
}
FIX
exp1=$(printf '%s\th1\treturn 0\t[ -f "$1" ] || return 0\t' "$tmps/anc.sh")
exp2=$(printf '%s\th1#2/2\treturn 0\treturn 0\t' "$tmps/anc.sh")
g1=$(bash "$_MS" --anchor "$tmps/anc.sh" 3 'return 0' 2>/dev/null); a1=$?
g2=$(bash "$_MS" --anchor "$tmps/anc.sh" 7 'return 0' 2>/dev/null); a2=$?
bash "$_MS" --anchor "$tmps/anc.sh" 4 'return 0' >/dev/null 2>&1; a3=$?
bash "$_MS" --anchor "$tmps/anc.sh" 3 >/dev/null 2>&1; a4=$?
# 만든 행에 reason 을 붙이면 그대로 풀린다 (생성기 ↔ 판정기 왕복)
{ printf '%s%s\n' "$g1" 'r1'; printf '%s%s\n' "$g2" 'r2'; bash "$_MS" --anchor "$tmps/anc.sh" 5 '&&' | sed 's/$/r3/'; } > "$tmps/anc.conf"
got=$(MUT_EQUIV_CONF="$tmps/anc.conf" mut::equiv_sites "$tmps/anc.sh" | sort | tr '\t\n' ': ')
if [ "$a1" = 0 ] && [ "$g1" = "$exp1" ] && [ "$a2" = 0 ] && [ "$g2" = "$exp2" ] && [ "$a3" = 1 ] && [ "$a4" = 2 ] \
   && [ "$got" = "3:return 0 5:&& 7:return 0 " ]; then
  echo "PASS T39 --anchor — 원문 정규화·\`|\` 보존·#k/n · 주석 줄 rc 1 · 인자 누락 rc 2 · 왕복 일치"; PASS=$((PASS+1))
else echo "FAIL T39 a1=$a1 a2=$a2 a3=$a3 a4=$a4 g1='$g1' g2='$g2' got='$got'"; FAIL=$((FAIL+1)); fi

# T40 채점 경로는 등가를 **원본에서** 푼다 — 루프 안에서 풀면 대상 파일에 직전 변이가 남아 있어 원문이 달라진다.
#   L3 의 `return 0` 변이(등재 안 함)가 대상에 남은 채 같은 줄의 `&&` 를 물으면, 원문이 `… return 1` 이라 안 맞는다.
cat > "$tmps/pristine.sh" <<'FIX'
#!/usr/bin/env bash
p1() {
  [ -n "${1:-}" ] && return 0
}
FIX
row "$tmps/pristine.sh" p1 '&&' "$A1" '&& 만 등가' > "$tmps/pristine.conf"
out=$(MUT_EQUIV_CONF="$tmps/pristine.conf" mut::run_target "$tmps/pristine.sh" "true" 2>/dev/null)
if grep -q 'survived=1 invalid=0 equivalent=1' <<<"$out"; then
  echo "PASS T40 run_target — 같은 줄의 다른 패턴 변이 뒤에도 등가 판정 유지"; PASS=$((PASS+1))
else echo "FAIL T40 ($out)"; FAIL=$((FAIL+1)); fi

# T41 conf 원문도 공백을 정규화해 비교한다 (손으로 정렬을 바꿔도 같은 사이트) · 주석 줄의 같은 원문은 사이트가 아니다
row "$tmps/tgt.sh" f1 'return 0' '  [ -n "${1:-}" ]   &&  return 0 ' '공백이 다른 원문' > "$tmps/ws.conf"
row "$tmps/tgt.sh" f1 'return 0' '# 주석: [ -z "$x" ] && return 0 — 변이돼선 안 된다' '주석 줄을 가리킴' > "$tmps/cmt.conf"
_eq "$tmps/ws.conf" "$tmps/tgt.sh" 3 'return 0' && b1=0 || b1=1
o=$(_cc "$tmps/cmt.conf" "$tmps/tg.conf"); rc=$?
if [ "$b1" = 0 ] && [ "$rc" != 0 ] && grep -q 'STALE.*매칭 사이트 0건' <<<"$o"; then
  echo "PASS T41 원문 공백 정규화 · 주석 줄은 사이트가 아니다"; PASS=$((PASS+1))
else echo "FAIL T41 b1=$b1 rc=$rc out=$o"; FAIL=$((FAIL+1)); fi

# T42 순번 표기(#k/n)가 틀린 행은 stale 이다 — 형식(#x)과 범위(k<1 · k>n)를 따로 잠근다.
#   범위 검사가 빠지면 `#0/1` 은 개수(1)가 맞아 빈 줄번호의 "등가" 로 풀리고 --check-conf 가 매칭으로 센다.
row "$tmps/tgt.sh" 'f1#x'   'return 0' "$A1" '순번 형식 오류' > "$tmps/ord.conf"
row "$tmps/tgt.sh" 'f1#0/1' 'return 0' "$A1" 'k 가 0'        >> "$tmps/ord.conf"
row "$tmps/tgt.sh" 'f1#2/1' 'return 0' "$A1" 'k 가 n 초과'   >> "$tmps/ord.conf"
o=$(_cc "$tmps/ord.conf" "$tmps/tg.conf"); rc=$?
_eq "$tmps/ord.conf" "$tmps/tgt.sh" 3 'return 0' && b1=0 || b1=1
if [ "$rc" != 0 ] && [ "$b1" = 1 ] && [ "$(printf '%s\n' "$o" | grep -c '^STALE ')" = 3 ] \
   && [ "$(printf '%s\n' "$o" | grep -c 'f1#x|.*함수#k/n 꼴')" = 1 ] \
   && [ "$(printf '%s\n' "$o" | grep -c 'k 는 1 이상 n 이하')" = 2 ] && grep -q ' 0/3 매칭' <<<"$o"; then
  echo "PASS T42 순번 표기 오류 3행(#x · #0/1 · #2/1) → 각각 STALE · 등가 아님"; PASS=$((PASS+1))
else echo "FAIL T42 rc=$rc b1=$b1 out=$o"; FAIL=$((FAIL+1)); fi

# T43 target 표기가 대상 목록과 어긋난 행은 조용히 버려지지 않는다 — 같은 파일의 다른 표기 · 없는 파일.
#   목록에 없는 **다른 실재 파일**의 행은 그대로 둔다(T24 — 대상 일부만 담은 targets conf).
row "$tmps/./tgt.sh" f1 'return 0' "$A1" '같은 파일 · 다른 표기' > "$tmps/spell.conf"
row "$tmps/tgt-typo.sh" f1 'return 0' "$A1" '없는 파일' > "$tmps/typo.conf"
o1=$(_cc "$tmps/spell.conf" "$tmps/tg.conf"); r1=$?
o2=$(_cc "$tmps/typo.conf" "$tmps/tg.conf"); r2=$?
if [ "$r1" != 0 ] && grep -q "STALE.*표기가 대상 목록의 '$tmps/tgt.sh' 와 다르다 — 1행" <<<"$o1" \
   && [ "$r2" != 0 ] && grep -q 'STALE.*target 파일이 없다 — 1행' <<<"$o2"; then
  echo "PASS T43 target 표기 불일치(./ 경유) · 없는 파일 → STALE"; PASS=$((PASS+1))
else echo "FAIL T43 r1=$r1 r2=$r2 o1=$o1 o2=$o2"; FAIL=$((FAIL+1)); fi

# T44 --anchor 는 저장소 안 경로를 대상 목록의 표기(루트 상대)로 찍는다 — `./x`·절대경로로 불러도 같은 행이 나온다
_rb="scripts/_internal/run-bounded.sh"
_site=$(mut::site_map "$PLUGIN/$_rb" | head -1)
_sl=$(printf '%s' "$_site" | cut -f1); _spat=$(printf '%s' "$_site" | cut -f2)
k0=$(bash "$_MS" --anchor "$_rb" "$_sl" "$_spat" 2>/dev/null)
k1=$(bash "$_MS" --anchor "./$_rb" "$_sl" "$_spat" 2>/dev/null)
k2=$(bash "$_MS" --anchor "$PLUGIN/$_rb" "$_sl" "$_spat" 2>/dev/null)
if [ -n "$_sl" ] && [ "$(printf '%s' "$k0" | cut -f1)" = "$_rb" ] && [ "$k1" = "$k0" ] && [ "$k2" = "$k0" ]; then
  echo "PASS T44 --anchor target 표기 정규화 (./ · 절대경로 → 루트 상대)"; PASS=$((PASS+1))
else echo "FAIL T44 site='$_site' k0='$k0' k1='$k1' k2='$k2'"; FAIL=$((FAIL+1)); fi

# T45 이 파일의 단언에 `printf … | grep -…q` 파이프가 없다 (20261015-test-pipefail-grep)
#   source 한 라이브러리가 `set -uo pipefail` 을 켠다 — 그 아래서 grep -q 가 먼저 끝나면 앞단 printf 의 쓰기 오류(SIGPIPE)가
#   파이프 실패가 되어 출력이 맞아도 단언이 간헐 실패한다(CI 실측 2건). 단언은 `grep -q 패턴 <<<"$출력"` 로 쓴다.
_np=$(grep -cE "printf '%s'[^|]*[|][[:space:]]*grep( -[A-Za-z-]+)* -[A-Za-z]*q" "${BASH_SOURCE[0]}")
if [ "$_np" = 0 ]; then echo "PASS T45 단언에 grep -q 파이프 없음 (pipefail 경합 방지)"; PASS=$((PASS+1)); else echo "FAIL T45 grep -q 파이프 ${_np}곳 — grep -q 패턴 <<<\"\$출력\" 로"; FAIL=$((FAIL+1)); fi

echo "==== Results: PASS=$PASS FAIL=$FAIL ===="
[ "$FAIL" -eq 0 ]
