#!/usr/bin/env bash
# test-attempt-fingerprint.sh — verify 동일 실패 지문 (FID 20261002-attempt-fingerprint · AC-1~AC-7)
#
# 계기: verify→fix 루프·Phase B/C 재dispatch·§auto 전역 재시도는 횟수 cap 만 있어 같은 실패를 같은 방식으로
#   반복해도 횟수만 소모했다. 카운터 4종은 전부 모델 손편집이라 스크립트가 쓰거나 검사하는 곳도 없다.
#   attempt-fp.sh 가 실패 출력을 정규화·해시해 "같은 실패 연속" 을 기계적으로 판정하고,
#   run-verification.sh 가 FAIL·PASS 판정 합류점에서 기록한다(모델은 쓰지 못한다).
#
# 단언 원칙: 모든 "같다" 단언은 입력이 실제로 다른지(raw 차이)와 "다르다" 짝(헛돌지 않음)을 함께 잠근다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
AFP="$PLUGIN/scripts/_internal/attempt-fp.sh"
RUN="$PLUGIN/scripts/_internal/run-verification.sh"
SKILL="$PLUGIN/skills/verifying-evidence-ko/SKILL.md"
SH="${BASH:-bash}"
TMP=$(mktemp -d) || { echo "FATAL: mktemp 실패" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT
# 정규화·해시 함수를 직접 단언하기 위해 source 한다(source 시 main 은 실행되지 않는다)
# shellcheck source=/dev/null
source "$AFP" || { echo "FATAL: attempt-fp.sh source 실패" >&2; exit 1; }
command -v afp::normalize >/dev/null 2>&1 || { echo "FATAL: afp::normalize 미정의" >&2; exit 1; }

# ── helpers ──────────────────────────────────────────────────────────
mkd() { mktemp -d "$TMP/d.XXXXXX"; }   # 서브셸($(mkd))에서도 서로 다른 격리 디렉터리
afp_in() { local d="$1"; shift; ( cd "$d" && "$SH" "$AFP" "$@" ); }       # stdout·stderr 그대로
mat() { local f="$1"; shift; printf '%s\n' "$@" > "$f"; }                  # 줄별 인자 → 재료 파일
matstr() { printf '%s\n' "$2" > "$1"; }                                   # 개행 포함 문자열 → 재료 파일
attempts() { printf '%s\n' "$1/.specops/${2:-fx}/attempts.jsonl"; }
nlines() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }
field() { sed -n "s/.*\"$2\":\"\{0,1\}\([^\",}]*\)\"\{0,1\}[,}].*/\1/p" <<< "$1"; }   # 줄, 필드 → 값
line_at() { sed -n "${2}p" "$1"; }                                         # 파일, 줄번호
eq() { # <desc> <기대> <실제>
  if [ "$2" = "$3" ]; then ok "$1"; else nope "$1" "기대='$2' 실제='$3'"; fi
}
# fp_of <문자열 재료> — 새 디렉터리에 record FAIL 후 fp 반환(재료 원문의 fp)
fp_of() {
  local d; d=$(mkd)
  matstr "$d/m" "$1"
  afp_in "$d" record fx FAIL --material "$d/m" >/dev/null 2>&1
  field "$(line_at "$(attempts "$d")" 1)" fp
}
# same_fp <desc> <재료A> <재료B> — raw 가 다르면서 fp 가 같아야 한다
same_fp() {
  local a b
  if [ "$2" = "$3" ]; then nope "$1" "입력이 동일 — 헛도는 단언"; return; fi
  a=$(fp_of "$2"); b=$(fp_of "$3")
  if [ -n "$a" ] && [ "$a" != "-" ] && [ "$a" = "$b" ]; then ok "$1"; else nope "$1" "fpA=$a fpB=$b"; fi
}
# diff_fp <desc> <재료A> <재료B> — 둘 다 유효 fp 이면서 서로 달라야 한다
diff_fp() {
  local a b
  a=$(fp_of "$2"); b=$(fp_of "$3")
  if [ -n "$a" ] && [ "$a" != "-" ] && [ -n "$b" ] && [ "$b" != "-" ] && [ "$a" != "$b" ]; then ok "$1"; else nope "$1" "fpA=$a fpB=$b"; fi
}
HEAD3=$'CMD: bash scripts/tests/test-x.sh\nEXIT: 1'

# ── T1 (AC-1) 동일 지문 2연속이면 정지 ─────────────────────────────
d=$(mkd); A=$(attempts "$d")
mat "$d/mA" 'CMD: bash scripts/tests/test-foo.sh' 'EXIT: 1' 'FAIL T15 boom'
out=$(afp_in "$d" record fx FAIL --material "$d/mA" 2>&1); rc=$?
l1=$(line_at "$A" 1)
if [ "$rc" -eq 0 ] && [ "$(nlines "$A")" = 1 ] && [ "$(field "$l1" verdict)" = FAIL ] && [ "$(field "$l1" n)" = 1 ]; then
  ok "T1.a record FAIL 1건 → 1줄 FAIL n=1 rc0"
else nope "T1.a" "rc=$rc lines=$(nlines "$A") l1=$l1"; fi
out=$(afp_in "$d" check fx); rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" == "ATTEMPT: OK"* ]]; then ok "T1.b FAIL 1건 → check rc0 'ATTEMPT: OK'"
else nope "T1.b" "rc=$rc out=$out"; fi
afp_in "$d" record fx FAIL --material "$d/mA" >/dev/null 2>&1
l2=$(line_at "$A" 2); fp1=$(field "$l1" fp); fp2=$(field "$l2" fp)
if [ "$(field "$l2" n)" = 2 ] && [ -n "$fp1" ] && [ "$fp1" != "-" ] && [ "$fp1" = "$fp2" ]; then
  ok "T1.c 같은 재료 2회 → 같은 fp, 두 번째 n=2"
else nope "T1.c" "l1=$l1 l2=$l2"; fi
out=$(afp_in "$d" check fx); rc=$?
if [ "$rc" -eq 1 ] && [[ "$out" == "ATTEMPT-STOP:"* ]] && [[ "$out" == *"2회"* ]] && [[ "$out" == *"fp=${fp1:0:8}"* ]] \
   && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ]; then
  ok "T1.d n=2 → check rc1 'ATTEMPT-STOP:' 1줄 (2회·fp 앞8자 포함)"
else nope "T1.d" "rc=$rc out=$out"; fi
afp_in "$d" record fx FAIL --material "$d/mA" >/dev/null 2>&1
out=$(afp_in "$d" check fx); rc=$?
if [ "$(field "$(line_at "$A" 3)" n)" = 3 ] && [ "$rc" -eq 1 ] && [[ "$out" == *"3회"* ]]; then ok "T1.e 3연속 → n=3 rc1 (n>=2 면 계속 정지)"
else nope "T1.e" "rc=$rc out=$out"; fi
# ATTEMPT_FP_MAX 는 상수 — env 로 완화도 강화도 못 한다
out=$(cd "$d" && ATTEMPT_FP_MAX=99 "$SH" "$AFP" check fx); rc=$?
[ "$rc" -eq 1 ] && ok "T1.f env ATTEMPT_FP_MAX=99 로 정지를 풀 수 없다(n=3 → 여전히 rc1)" || nope "T1.f" "rc=$rc out=$out"
d2=$(mkd); mat "$d2/m" 'CMD: x' 'EXIT: 1' 'FAIL T1 a'
afp_in "$d2" record fx FAIL --material "$d2/m" >/dev/null 2>&1
out=$(cd "$d2" && ATTEMPT_FP_MAX=1 "$SH" "$AFP" check fx); rc=$?
[ "$rc" -eq 0 ] && [[ "$out" == "ATTEMPT: OK"* ]] && ok "T1.g env ATTEMPT_FP_MAX=1 로 정지를 당길 수 없다(n=1 → rc0)" || nope "T1.g" "rc=$rc out=$out"
# 줄 형식 — 고정 스키마, 원문 미저장
if grep -Eq '^\{"ts":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z","verdict":"FAIL","fp":"[0-9a-f]{16}","n":[0-9]+\}$' "$A" \
   && [ "$(grep -Evc '^\{"ts":"[^"]*","verdict":"(FAIL|PASS)","fp":"([0-9a-f]+|-)","n":[0-9]+\}$' "$A")" = 0 ]; then
  ok "T1.h attempts.jsonl 줄 형식 {ts,verdict,fp,n} 고정"
else nope "T1.h" "$(cat "$A")"; fi
if command -v jq >/dev/null 2>&1; then
  if jq -e '.verdict and (.n|type=="number")' "$A" >/dev/null 2>&1; then ok "T1.i 줄이 유효 JSON (jq)"; else nope "T1.i" "jq 파싱 실패"; fi
else skip "T1.i jq 부재"; fi

# ── T2 (AC-2) 지문이 다르거나 PASS 가 끼면 정지하지 않는다 ──────────
d=$(mkd); A=$(attempts "$d")
mat "$d/A" 'CMD: bash scripts/tests/test-foo.sh' 'EXIT: 1' 'FAIL T15 boom'
mat "$d/B" 'CMD: bash scripts/tests/test-foo.sh' 'EXIT: 1' 'FAIL T16 other'
afp_in "$d" record fx FAIL --material "$d/A" >/dev/null 2>&1
afp_in "$d" record fx FAIL --material "$d/B" >/dev/null 2>&1
out=$(afp_in "$d" check fx); rc=$?
if [ "$(field "$(line_at "$A" 2)" n)" = 1 ] && [ "$rc" -eq 0 ] && [[ "$out" == "ATTEMPT: OK"* ]]; then ok "T2.a FAIL(A)→FAIL(B): 마지막 n=1·check rc0"
else nope "T2.a" "rc=$rc out=$out l2=$(line_at "$A" 2)"; fi
d=$(mkd); A=$(attempts "$d")
mat "$d/A" 'CMD: bash scripts/tests/test-foo.sh' 'EXIT: 1' 'FAIL T15 boom'
afp_in "$d" record fx FAIL --material "$d/A" >/dev/null 2>&1
afp_in "$d" record fx PASS >/dev/null 2>&1
afp_in "$d" record fx FAIL --material "$d/A" >/dev/null 2>&1
out=$(afp_in "$d" check fx); rc=$?
lp=$(line_at "$A" 2)
if [ "$(field "$lp" verdict)" = PASS ] && [ "$(field "$lp" fp)" = "-" ] && [ "$(field "$lp" n)" = 0 ] \
   && [ "$(field "$(line_at "$A" 3)" n)" = 1 ] && [ "$rc" -eq 0 ]; then
  ok "T2.b FAIL(A)→PASS→FAIL(A): PASS 줄 fp='-' n=0, 마지막 FAIL n=1(PASS 가 연속을 끊는다)·rc0"
else nope "T2.b" "rc=$rc $(cat "$A")"; fi
d=$(mkd); A=$(attempts "$d")
mat "$d/A" 'CMD: x' 'EXIT: 1' 'FAIL T1 a'; mat "$d/B" 'CMD: x' 'EXIT: 1' 'FAIL T2 b'
for m in A A B A; do afp_in "$d" record fx FAIL --material "$d/$m" >/dev/null 2>&1; done
seq=$(for i in 1 2 3 4; do field "$(line_at "$A" $i)" n; done | tr '\n' ,)
eq "T2.c A,A,B,A → n 수열 1,2,1,1" "1,2,1,1," "$seq"
afp_in "$d" record fx FAIL --material "$d/A" >/dev/null 2>&1; afp_in "$d" record fx PASS >/dev/null 2>&1
out=$(afp_in "$d" check fx); rc=$?
[ "$rc" -eq 0 ] && [[ "$out" == "ATTEMPT: OK"* ]] && ok "T2.d 정지 직전(n=2) 뒤 PASS → check rc0" || nope "T2.d" "rc=$rc out=$out"
# 재료 없음/실패 줄 없음은 '같은 실패' 로 세지 않는다(빈 지문이 상수 해시로 충돌하지 않게)
d=$(mkd); A=$(attempts "$d"); mat "$d/P" 'PASS T1 ok' 'PASS=3 FAIL=0'
afp_in "$d" record fx FAIL >/dev/null 2>&1; afp_in "$d" record fx FAIL >/dev/null 2>&1
afp_in "$d" record fx FAIL --material "$d/P" >/dev/null 2>&1; afp_in "$d" record fx FAIL --material "$d/P" >/dev/null 2>&1
fps=$(for i in 1 2 3 4; do field "$(line_at "$A" $i)" fp; done | tr '\n' ,)
ns=$(for i in 1 2 3 4; do field "$(line_at "$A" $i)" n; done | tr '\n' ,)
out=$(afp_in "$d" check fx); rc=$?
if [ "$fps" = "-,-,-,-," ] && [ "$ns" = "1,1,1,1," ] && [ "$rc" -eq 0 ]; then ok "T2.e 재료 없음·실패 줄 없음 → fp '-' n=1 고정(오탐 정지 없음)"
else nope "T2.e" "fps=$fps ns=$ns rc=$rc"; fi

# 직전이 PASS 면 fp 가 같게 위조돼 있어도(n=5) 연속이 아니다 — 연속은 직전 verdict=FAIL 에서만
d=$(mkd); A=$(attempts "$d"); mat "$d/m" 'CMD: x' 'EXIT: 1' 'FAIL T1 a'
fpx=$(fp_of "$(cat "$d/m")")
mkdir -p "$d/.specops/fx"; printf '{"ts":"t","verdict":"PASS","fp":"%s","n":5}\n' "$fpx" > "$A"
afp_in "$d" record fx FAIL --material "$d/m" >/dev/null 2>&1
eq "T2.f 직전 PASS(fp 동일·n=5 위조) 뒤 FAIL → n=1 (PASS 가 연속을 끊는다)" 1 "$(field "$(line_at "$A" 2)" n)"

# ── T3 (AC-3) 정규화: 동일 실패는 같게, 다른 실패는 다르게 ─────────
b="$HEAD3"$'\nFAIL T15 boom'
same_fp "T3.a ISO 시각(날짜·시각 값만 다름) 무시" "$b at 2026-10-02T10:11:12Z" "$b at 2027-01-05 23:59:01"
same_fp "T3.a2 시각만(HH:MM:SS) 무시" "$b at 10:11:12" "$b at 23:59:59"
same_fp "T3.a3 날짜만(YYYY-MM-DD) 무시" "$b on 2026-10-02" "$b on 2027-01-05"
same_fp "T3.a4 요일·월·일(date 기본 출력) 무시" "$b at Fri Oct  2" "$b at Sat Nov 14"
same_fp "T3.b 소요시간 1.2s ↔ 35ms" "$b took 1.2s" "$b took 35ms"
same_fp "T3.b2 괄호 소요시간 (0.00s) ↔ (12 ms)" "$b (0.00s)" "$b (12 ms)"
same_fp "T3.b3 복합 소요시간 0m1.234s ↔ 2m10.5s" "$b real 0m1.234s" "$b real 2m10.5s"
diff_fp "T3.b4 소요시간 치환이 T15s 같은 테스트 id 를 먹지 않는다(T15s≠T16s)" "$HEAD3"$'\nFAIL T15s boom' "$HEAD3"$'\nFAIL T16s boom'
same_fp "T3.c1 tmp 경로 /tmp/tmp.XXXX" "$b in /tmp/tmp.AbCd1234/out.log" "$b in /tmp/tmp.ZyXw9876/out.log"
same_fp "T3.c2 tmp 경로 /var/folders/…/T/tmp.X" "$b in /var/folders/ab/cdef0123_xyz/T/tmp.Q1w2E3/out.log" "$b in /var/folders/zz/9876abcd_qrs/T/tmp.R4t5Y6/out.log"
same_fp "T3.c3 tmp 경로 /private/var/folders/…" "$b in /private/var/folders/ab/cdef0123_xyz/T/tmp.Q1w2E3/out.log" "$b in /private/var/folders/zz/9876abcd_qrs/T/tmp.R4t5Y6/out.log"
same_fp "T3.c4 tmp 경로 /private/tmp/…" "$b in /private/tmp/run.AbCdEf/out.log" "$b in /private/tmp/run.UvWxYz/out.log"
same_fp "T3.c5 mktemp 랜덤 접미 tmp.Ab12Cd (경로 없이)" "$b dir tmp.Ab12Cd end" "$b dir tmp.Zz99Yy end"
diff_fp "T3.c6 tmp 루트 뒤의 파일명은 보존(a.log≠b.log)" "$b in /tmp/tmp.AbCd1234/a.log" "$b in /tmp/tmp.AbCd1234/b.log"
diff_fp "T3.c7 tmp 가 아닌 경로의 /tmp/ 컴포넌트는 건드리지 않는다" "$b in src/tmp/a.sh" "$b in src/tmp/b.sh"
same_fp "T3.d1 16진 주소 0x…" "$b addr 0xdeadbeef" "$b addr 0x12345678"
same_fp "T3.d2 16진 8자 이상(bare)" "$b sum deadbeef01 end" "$b sum 0123456789abcdef end"
diff_fp "T3.d3 16진 7자 이하는 보존(abc1234≠abc1235)" "$b ref abc1234 end" "$b ref abc1235 end"
same_fp "T3.e PID" "$b pid 123 gone" "$b pid 98765 gone"
same_fp "T3.e2 PID(pid=…)" "$b [pid=4567]" "$b [pid=89012]"
same_fp "T3.f1 요약 카운트 줄 PASS=N FAIL=M" "$b"$'\nPASS=16 FAIL=1' "$b"$'\nPASS=17 FAIL=1'
same_fp "T3.f2 요약 카운트 줄 passed=N failed=M·Results:" "$b"$'\npassed=16 failed=1\nResults: 16/17' "$b"$'\npassed=40 failed=1\nResults: 40/41'
same_fp "T3.f1b 요약 카운트 줄(FAIL 선두 순서) FAIL=N PASS=M" "$b"$'\nFAIL=1 PASS=16' "$b"$'\nFAIL=1 PASS=17'
same_fp "T3.f5 키워드만 있는 배너 === FAILURES === 도 요약(배너)이라 제외" "$b" "$b"$'\n=== FAILURES ===\n=== ERRORS ==='
same_fp "T3.f3 ==== … ==== 배너" "$b"$'\n==== 1 failed, 16 passed in 0.12s ====' "$b"$'\n==== 1 failed, 40 passed in 9.99s ===='
same_fp "T3.f4 단독 요약 줄(Results: N failures · Tests: N failed · N failed)" "$b"$'\nResults: 3 failures\nTests:       1 failed\n1 failed' "$b"$'\nResults: 9 failures\nTests:       4 failed\n7 failed'
diff_fp "T3.g 테스트 id 만 다름(FAIL T15 ≠ FAIL T16)" "$HEAD3"$'\nFAIL T15 boom' "$HEAD3"$'\nFAIL T16 boom'
diff_fp "T3.g2 CMD 만 다름" $'CMD: bash scripts/tests/test-x.sh\nEXIT: 1\nFAIL T15 boom' $'CMD: bash scripts/tests/test-y.sh\nEXIT: 1\nFAIL T15 boom'
diff_fp "T3.g3 EXIT 만 다름" $'CMD: x\nEXIT: 1\nFAIL T15 boom' $'CMD: x\nEXIT: 2\nFAIL T15 boom'
diff_fp "T3.g4 조용한 실패(키워드 줄 없음)도 CMD 로 구분된다" $'CMD: bash scripts/tests/a.sh\nEXIT: 1' $'CMD: bash scripts/tests/b.sh\nEXIT: 1'
diff_fp "T3.g5 REASON 만 다름" $'REASON: ac-format' $'REASON: review-audit'
same_fp "T3.h 줄 순서만 다름" $'CMD: x\nEXIT: 1\nFAIL T15 a\nFAIL T16 b' $'FAIL T16 b\nFAIL T15 a\nEXIT: 1\nCMD: x'
same_fp "T3.h2 중복 줄(같은 실패 3번 vs 1번)" $'CMD: x\nEXIT: 1\nFAIL T15 a' $'CMD: x\nEXIT: 1\nFAIL T15 a\nFAIL T15 a\nFAIL T15 a'
same_fp "T3.h3 통과 줄이 늘어도 불변" "$b" "$b"$'\nPASS T1 ok\nPASS T2 error handling ok\nok  \tpkg/x\t0.003s'
same_fp "T3.h4 CRLF·ANSI 색 코드 무시" $'CMD: x\nEXIT: 1\nFAIL T15 boom' $'CMD: x\r\nEXIT: 1\r\n\033[31mFAIL T15 boom\033[0m\r'
# 원문 미저장 — 해시만 남는다
RAW_RE='SECRET|hunter2|boom|test-x|FAIL T15'   # 재료 원문 토큰 — 'T15' 단독은 ts 의 UTC 15시(…T15:…)와 겹친다
d=$(mkd); A=$(attempts "$d")
mat "$d/S" 'CMD: bash scripts/tests/test-x.sh' 'EXIT: 1' 'FAIL T15 SECRET-TOKEN-7781 password=hunter2'
afp_in "$d" record fx FAIL --material "$d/S" >/dev/null 2>&1
if [ -s "$A" ] && ! grep -Eq "$RAW_RE" "$A" && ! grep -rEq 'SECRET|hunter2' "$d/.specops"; then
  ok "T3.i 원문 미저장 — attempts.jsonl·.specops 어디에도 출력 원문 없음"
else nope "T3.i" "$(cat "$A" 2>/dev/null)"; fi
# 같은 단언이 기록 시각에 따라 갈리지 않는다 — UTC 15시 ts(…T15:13:28Z)를 date 스텁으로 강제(CI 실측 오탐)
d=$(mkd); A=$(attempts "$d"); mkdir -p "$d/dshim"
printf '#!/bin/sh\necho 2026-10-02T15:13:28Z\n' > "$d/dshim/date"; chmod +x "$d/dshim/date"
mat "$d/S" 'CMD: bash scripts/tests/test-x.sh' 'EXIT: 1' 'FAIL T15 SECRET-TOKEN-7781 password=hunter2'
( cd "$d" && PATH="$d/dshim:$PATH" "$SH" "$AFP" record fx FAIL --material "$d/S" >/dev/null 2>&1 )
if [ "$(field "$(line_at "$A" 1)" ts)" = 2026-10-02T15:13:28Z ] && grep -Eq "$RAW_RE" "$d/S" && ! grep -Eq "$RAW_RE" "$A"; then
  ok "T3.i2 ts 가 UTC 15시(T15:…)여도 원문 미저장 단언이 시각과 충돌하지 않는다(같은 패턴이 재료 원문에는 적중)"
else nope "T3.i2" "$(cat "$A" 2>/dev/null)"; fi
# 해시 = 정규화 집합의 sha256 앞 16자 / 해시 도구 폴백 체인
if command -v shasum >/dev/null 2>&1; then hsh() { shasum -a 256 | cut -c1-16; }; else hsh() { sha256sum | cut -c1-16; }; fi
exp=$(afp::normalize "$d/S" | hsh)
eq "T3.j fp = 정규화 집합의 sha256 앞 16자" "$exp" "$(field "$(line_at "$A" 1)" fp)"
stub="$TMP/stub"; mkdir -p "$stub"; printf '#!/bin/sh\nexit 1\n' > "$stub/shasum"; cp "$stub/shasum" "$stub/sha256sum"; chmod +x "$stub/shasum" "$stub/sha256sum"
d=$(mkd); A=$(attempts "$d"); mat "$d/m" 'CMD: x' 'EXIT: 1' 'FAIL T1 a'; mat "$d/m2" 'CMD: x' 'EXIT: 1' 'FAIL T2 b'
( cd "$d" && PATH="$stub:$PATH" "$SH" "$AFP" record fx FAIL --material "$d/m" >/dev/null 2>&1
  PATH="$stub:$PATH" "$SH" "$AFP" record fx FAIL --material "$d/m" >/dev/null 2>&1
  PATH="$stub:$PATH" "$SH" "$AFP" record fx FAIL --material "$d/m2" >/dev/null 2>&1 )
f1=$(field "$(line_at "$A" 1)" fp); f3=$(field "$(line_at "$A" 3)" fp)
exp2=$(afp::normalize "$d/m" | hsh)
if [[ "$f1" =~ ^[0-9a-f]{16}$ ]] && [ "$f1" != "$exp2" ] && [ "$(field "$(line_at "$A" 2)" n)" = 2 ] && [ "$f1" != "$f3" ]; then
  ok "T3.k shasum·sha256sum 불가 → cksum 폴백(16 hex·n 연속·재료별 상이)"
else nope "T3.k" "$(cat "$A")"; fi
# shasum 만 살아 있어도(sha256sum·cksum 불가) 같은 sha256 지문 — 체인 첫 도구가 단독으로 충분
stub2="$TMP/stub2"; mkdir -p "$stub2"; printf '#!/bin/sh\nexit 1\n' > "$stub2/sha256sum"; cp "$stub2/sha256sum" "$stub2/cksum"; chmod +x "$stub2/sha256sum" "$stub2/cksum"
if command -v shasum >/dev/null 2>&1; then
  d=$(mkd); A=$(attempts "$d"); mat "$d/m" 'CMD: x' 'EXIT: 1' 'FAIL T1 a'
  ( cd "$d" && PATH="$stub2:$PATH" "$SH" "$AFP" record fx FAIL --material "$d/m" >/dev/null 2>&1 )
  eq "T3.j2 shasum 만 가용(sha256sum·cksum 불가) → sha256 앞 16자" "$(afp::normalize "$d/m" | hsh)" "$(field "$(line_at "$A" 1)" fp)"
else skip "T3.j2 shasum 부재"; fi
# shasum 이 불가하고 sha256sum 이 가용하면 sha256sum 이 같은 지문을 낸다(폴백 2번째)
if command -v sha256sum >/dev/null 2>&1; then
  stub3="$TMP/stub3"; mkdir -p "$stub3"; printf '#!/bin/sh\nexit 1\n' > "$stub3/shasum"; cp "$stub3/shasum" "$stub3/cksum"; chmod +x "$stub3/shasum" "$stub3/cksum"
  d=$(mkd); A=$(attempts "$d"); mat "$d/m" 'CMD: x' 'EXIT: 1' 'FAIL T1 a'
  ( cd "$d" && PATH="$stub3:$PATH" "$SH" "$AFP" record fx FAIL --material "$d/m" >/dev/null 2>&1 )
  eq "T3.k2 shasum·cksum 불가 + sha256sum 가용 → 같은 sha256 앞 16자(폴백 2번째)" "$(afp::normalize "$d/m" | hsh)" "$(field "$(line_at "$A" 1)" fp)"
else skip "T3.k2 sha256sum 부재"; fi
printf '#!/bin/sh\nexit 1\n' > "$stub/cksum"; chmod +x "$stub/cksum"
d=$(mkd); A=$(attempts "$d"); mat "$d/m" 'CMD: x' 'EXIT: 1' 'FAIL T1 a'
err=$(cd "$d" && PATH="$stub:$PATH" "$SH" "$AFP" record fx FAIL --material "$d/m" 2>&1 >/dev/null); rc=$?
if [ "$rc" -eq 0 ] && [[ "$err" == *WARN* ]] && [ "$(field "$(line_at "$A" 1)" fp)" = "-" ] && [ "$(field "$(line_at "$A" 1)" n)" = 1 ]; then
  ok "T3.l 해시 도구 3종 모두 불가 → WARN·rc0·fp '-' n=1 (fail-open)"
else nope "T3.l" "rc=$rc err=$err $(cat "$A" 2>/dev/null)"; fi

# ── T4 (AC-4) fail-open · 인자 오류만 rc2 ─────────────────────────
d=$(mkd)
out=$(afp_in "$d" check fx); rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" == "ATTEMPT: OK"* ]] && [[ "$out" == *"기존 cap 경로"* ]]; then ok "T4.a attempts.jsonl 부재 → 'ATTEMPT: OK (… 기존 cap 경로)' rc0"
else nope "T4.a" "rc=$rc out=$out"; fi
d=$(mkd); mkdir -p "$d/.specops/fx"; : > "$d/.specops/fx/attempts.jsonl"
out=$(afp_in "$d" check fx); rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" == "ATTEMPT: OK"* ]] && [[ "$out" == *"기록 없음"* ]]; then ok "T4.a2 빈 attempts.jsonl → '기록 없음 — 기존 cap 경로' rc0"
else nope "T4.a2" "rc=$rc out=$out"; fi
GOOD2='{"ts":"2026-10-02T00:00:00Z","verdict":"FAIL","fp":"0123456789abcdef","n":2}'
i=0
for bad in 'garbage not json' '{"ts":"2026-10-02T00:00:00Z","verdict":"FAIL","fp":"0123456789ab' \
           '{"ts":"t","verdict":"MAYBE","fp":"0123456789abcdef","n":2}' \
           '{"ts":"t","verdict":"FAIL","fp":"0123456789abcdef","n":"x"}' \
           '{"ts":"t","verdict":"FAIL","fp":"0123456789abcdef","n":99999999999999}' ''; do
  i=$((i + 1)); d=$(mkd); mkdir -p "$d/.specops/fx"
  { printf '%s\n' "$GOOD2"; printf '%s\n' "$bad"; } > "$d/.specops/fx/attempts.jsonl"
  out=$(afp_in "$d" check fx); rc=$?
  if [ "$rc" -eq 0 ] && [[ "$out" == "ATTEMPT: OK"* ]] && [[ "$out" == *"기존 cap 경로"* ]]; then ok "T4.b$i 깨진 마지막 줄 → check rc0 '기존 cap 경로' (앞줄 n=2 가 있어도)"
  else nope "T4.b$i" "rc=$rc out=$out bad=$bad"; fi
done
# 마지막 줄만 읽는다 — 앞이 깨져도 마지막이 유효 STOP 이면 정지, 마지막이 PASS 면 앞의 n=2 에 무관
d=$(mkd); mkdir -p "$d/.specops/fx"
{ printf 'junk1\n'; printf 'junk2\n'; printf '%s\n' "$GOOD2"; } > "$d/.specops/fx/attempts.jsonl"
out=$(afp_in "$d" check fx); rc=$?
[ "$rc" -eq 1 ] && [[ "$out" == "ATTEMPT-STOP:"* ]] && ok "T4.c 앞 줄이 깨져도 마지막 줄이 유효 FAIL n=2 면 정지(마지막 줄만 읽는다)" || nope "T4.c" "rc=$rc out=$out"
d=$(mkd); mkdir -p "$d/.specops/fx"
{ printf '%s\n' "$GOOD2"; printf '{"ts":"t","verdict":"PASS","fp":"-","n":0}\n'; } > "$d/.specops/fx/attempts.jsonl"
out=$(afp_in "$d" check fx); rc=$?
[ "$rc" -eq 0 ] && ok "T4.c2 앞 줄 FAIL n=2 + 마지막 PASS → rc0 (앞 줄을 읽지 않는다)" || nope "T4.c2" "rc=$rc out=$out"
# 큰 파일에서도 마지막 줄만 — 수천 줄 뒤 STOP 줄
d=$(mkd); mkdir -p "$d/.specops/fx"
{ i=0; while [ "$i" -lt 3000 ]; do printf '{"ts":"t","verdict":"PASS","fp":"-","n":0}\n'; i=$((i + 1)); done; printf '%s\n' "$GOOD2"; } > "$d/.specops/fx/attempts.jsonl"
out=$(afp_in "$d" check fx); rc=$?
[ "$rc" -eq 1 ] && ok "T4.c3 3000줄 뒤 마지막 STOP 줄 판정" || nope "T4.c3" "rc=$rc"
d=$(mkd); mkdir -p "$d/.specops/fx"; printf '{"ts":"t","verdict":"PASS","fp":"0123456789abcdef","n":5}\n' > "$d/.specops/fx/attempts.jsonl"
out=$(afp_in "$d" check fx); rc=$?
[ "$rc" -eq 0 ] && [[ "$out" == "ATTEMPT: OK"* ]] && ok "T4.c4 마지막 줄이 PASS 면 n 값(위조 n=5)과 무관하게 rc0 — 정지는 FAIL 줄만" || nope "T4.c4" "rc=$rc out=$out"
# record 쓰기 불가 — stderr WARN · rc0
d=$(mkd); mkdir -p "$d/.specops/fx/attempts.jsonl"; mat "$d/m" 'CMD: x' 'EXIT: 1' 'FAIL T1 a'
out=$(afp_in "$d" record fx FAIL --material "$d/m" 2>"$d/err"); rc=$?
if [ "$rc" -eq 0 ] && grep -q 'WARN' "$d/err" && [ -z "$out" ]; then ok "T4.d1 attempts.jsonl 이 디렉터리(쓰기 불가) → stderr WARN·rc0·stdout 없음"
else nope "T4.d1" "rc=$rc out=$out err=$(cat "$d/err")"; fi
d=$(mkd); mkdir -p "$d/.specops"; : > "$d/.specops/fx"; mat "$d/m" 'CMD: x' 'EXIT: 1' 'FAIL T1 a'
out=$(afp_in "$d" record fx FAIL --material "$d/m" 2>"$d/err"); rc=$?
if [ "$rc" -eq 0 ] && grep -q 'WARN' "$d/err"; then ok "T4.d2 FID 디렉터리를 만들 수 없음 → stderr WARN·rc0"
else nope "T4.d2" "rc=$rc err=$(cat "$d/err")"; fi
d=$(mkd); mat "$d/m" 'CMD: x' 'EXIT: 1' 'FAIL T1 a'
out=$(afp_in "$d" record fx FAIL --material "$d/nonexistent" 2>"$d/err"); rc=$?
l1=$(line_at "$(attempts "$d")" 1)
if [ "$rc" -eq 0 ] && grep -q 'WARN' "$d/err" && [ "$(field "$l1" fp)" = "-" ] && [ "$(field "$l1" n)" = 1 ]; then ok "T4.d3 재료 파일 판독 불가 → WARN·rc0·fp '-' n=1"
else nope "T4.d3" "rc=$rc err=$(cat "$d/err") l1=$l1"; fi
# 개행 없이 끝난 마지막 줄(중단된 쓰기) 뒤에 이어 써도 줄이 붙지 않는다
d=$(mkd); A=$(attempts "$d"); mkdir -p "$d/.specops/fx"; mat "$d/m" 'CMD: x' 'EXIT: 1' 'FAIL T1 a'
afp_in "$d" record fx FAIL --material "$d/m" >/dev/null 2>&1
sz=$(wc -c < "$A" | tr -d ' '); head -c $((sz - 1)) "$A" > "$A.tmp"; mv "$A.tmp" "$A"
afp_in "$d" record fx FAIL --material "$d/m" >/dev/null 2>&1
if [ "$(nlines "$A")" = 2 ] && [ "$(field "$(line_at "$A" 2)" n)" = 2 ] \
   && [ "$(grep -Evc '^\{"ts":"[^"]*","verdict":"(FAIL|PASS)","fp":"([0-9a-f]+|-)","n":[0-9]+\}$' "$A")" = 0 ]; then
  ok "T4.e 개행 없는 마지막 줄 뒤에 이어 써도 각 줄이 유효(n 연속 2)"
else nope "T4.e" "$(cat "$A")"; fi
# 인자 오류 → rc2 + usage + 부작용 없음
i=0
while IFS='|' read -r label args; do
  i=$((i + 1)); d=$(mkd)
  # shellcheck disable=SC2086
  err=$(cd "$d" && "$SH" "$AFP" $args 2>&1 >/dev/null); rc=$?
  if [ "$rc" -eq 2 ] && [[ "$err" == *usage:* ]] && [ ! -e "$d/.specops" ]; then ok "T4.f$i 인자 오류($label) → rc2·usage·무기록"
  else nope "T4.f$i 인자 오류($label)" "rc=$rc err=$err"; fi
done <<'ARGS'
인자 없음|
record 단독|record
verdict 누락|record fx
verdict 오류|record fx MAYBE
소문자 verdict|record fx fail
FID 경로 탈출|record ../x FAIL
알 수 없는 옵션|record fx FAIL --bogus
--material 값 누락|record fx FAIL --material
check FID 누락|check
check 잉여 인자|check fx extra
check FID 경로 탈출|check ../x
알 수 없는 서브커맨드|nosuch
ARGS
d=$(mkd); err=$(cd "$d" && "$SH" "$AFP" record "" FAIL 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 2 ] && ok "T4.g 빈 FID → rc2" || nope "T4.g" "rc=$rc"

# ── T5 (AC-5) run-verification.sh 통합 ────────────────────────────
RV_PASS_LABEL=PASS
mk_tasks() { # <file> <cmd>...  — YAML test_command 로 명령 주입
  local f="$1"; shift
  { printf '%s\n' '## 의존 그래프' '' '```yaml' 'tasks:'
    local i=0 c
    for c in "$@"; do i=$((i + 1)); printf '  - id: T%s\n    test_command: "%s"\n    depends_on: []\n    inputs: []\n    outputs: []\n    ac: [AC-%s]\n' "$i" "$c" "$i"; done
    printf '%s\n' '```'
  } > "$f"
}
mk_fix() { # <dir> <fid> <스크립트 본문> [<스크립트명>] — 단일 테스트 명령 FID
  local d="$1" fid="$2" body="$3" name="${4:-dummy.sh}"
  mkdir -p "$d/.specops/$fid" "$d/scripts/tests"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$d/scripts/tests/$name"
  chmod +x "$d/scripts/tests/$name"
  mk_tasks "$d/.specops/$fid/tasks.md" "bash scripts/tests/$name"
}
rv() { ( cd "$1" && "$SH" "$RUN" "$2" >"$1/rv.out" 2>"$1/rv.err" ); }   # rc 반환, 출력은 rv.out/rv.err
FIDF=20261002-afp-fail
d=$(mkd); A=$(attempts "$d" "$FIDF")
mk_fix "$d" "$FIDF" 'echo "FAIL T15 boom at $(LC_ALL=C date) in /tmp/tmp.X$RANDOM/out took 0.$RANDOM s pid $$ addr 0x$RANDOM$RANDOM"; exit 1'
rv "$d" "$FIDF"; rc1=$?
cp "$d/rv.err" "$d/rv1.err"
rv "$d" "$FIDF"; rc2=$?
l1=$(line_at "$A" 1); l2=$(line_at "$A" 2)
if [ "$rc1" -eq 1 ] && [ "$rc2" -eq 1 ] && [ -z "$(cat "$d/rv.out")" ] && grep -qx 'VERIFY: FAIL bash scripts/tests/dummy.sh (exit=1)' "$d/rv.err"; then
  ok "T5.a 실패 fixture ×2: 종전과 같은 stderr 'VERIFY: FAIL … (exit=1)'·stdout 없음·종료코드 1"
else nope "T5.a" "rc=$rc1/$rc2 out=$(cat "$d/rv.out") err=$(cat "$d/rv.err")"; fi
if [ "$(nlines "$A")" = 2 ] && [ "$(field "$l1" verdict)" = FAIL ] && [ "$(field "$l2" verdict)" = FAIL ] \
   && [ "$(field "$l1" fp)" = "$(field "$l2" fp)" ] && [ "$(field "$l1" fp)" != "-" ] && [ "$(field "$l1" n)" = 1 ] && [ "$(field "$l2" n)" = 2 ]; then
  ok "T5.b FAIL 2줄·같은 fp(시각·tmp·소요·PID 가 매번 달라도)·n=1,2"
else nope "T5.b" "$(cat "$A" 2>/dev/null)"; fi
out=$(afp_in "$d" check "$FIDF"); rc=$?
[ "$rc" -eq 1 ] && [[ "$out" == "ATTEMPT-STOP:"* ]] && ok "T5.c 같은 실패 2회 후 check rc1" || nope "T5.c" "rc=$rc out=$out"
if ! grep -rEq 'FAIL T15|boom' "$A"; then ok "T5.d attempts.jsonl 에 출력 원문 없음"; else nope "T5.d" "원문 유출"; fi
# 재료 임시 파일은 종료 후 남지 않는다 — mktemp 를 래퍼로 바꿔(macOS 는 TMPDIR 를 무시한다) 만든 파일을 추적한다
# mk_mkshim <dir> — 무인자 호출(run-verification 의 MATERIAL)만 matdir/ 에 만들고 calls 에 적는다.
#   인자 있는 호출(bounded_run 의 flag · meter-tokens 의 NEWREC·NR)은 other/ 에 만들고 argcalls 에 적는다.
#   분리 이유(실측): meter 는 세션 transcript 를 읽어 run-all 부하에서 bounded_run 5초 상한 TERM 을 받고, 그 TERM 이
#   meter 의 mktemp 도중이나 EXIT trap 정리 경쟁에 걸리면 meter 자기 파일이 남는다 — 재료와 무관한 잔존이 단언을 깼다.
#   인자 있는 호출도 파일은 **만든다** — bounded_run 워치독은 flag 파일이 없으면 즉시 빠져 상한 경로가 사라진다.
mk_mkshim() {
  local d="$1"; mkdir -p "$d/shim" "$d/matdir" "$d/other"
  printf '#!/bin/sh\nif [ $# -eq 0 ]; then f="%s/mat.$$"; l="%s/calls"; else f="%s/mat.$$"; l="%s/argcalls"; fi\n: > "$f"\necho "$f" >> "$l"\necho "$f"\n' \
    "$d/matdir" "$d/shim" "$d/other" "$d/shim" > "$d/shim/mktemp"
  chmod +x "$d/shim/mktemp"
}
d=$(mkd); mk_mkshim "$d"; mk_fix "$d" "$FIDF" 'echo "FAIL T15 boom"; exit 1'
( cd "$d" && PATH="$d/shim:$PATH" "$SH" "$RUN" "$FIDF" >/dev/null 2>&1 )
ncall=$(wc -l < "$d/shim/calls" 2>/dev/null | tr -d ' ')
if [ "${ncall:-0}" -ge 1 ] && [ -z "$(ls -A "$d/matdir")" ]; then ok "T5.e 재료 임시 파일(mktemp ${ncall}회 호출)은 종료 후 삭제된다(원문이 디스크에 남지 않는다)"
else nope "T5.e" "mktemp 호출 ${ncall:-0}회 · 잔존=$(ls -A "$d/matdir")"; fi
# 실 FID(fid-start 기록 있음 — meter-tokens 가 bounded_run 으로 호출되는 경로)에서도 재료 파일이 삭제된다
d=$(mkd); mk_mkshim "$d"; mk_fix "$d" "$FIDF" 'echo "FAIL T15 boom"; exit 1'
printf '%s\n' '{"ts":"2026-10-02T00:00:00Z","phase":"fid-start","fid":"x"}' > "$d/.specops/$FIDF/metrics.jsonl"
( cd "$d" && PATH="$d/shim:$PATH" "$SH" "$RUN" "$FIDF" >/dev/null 2>&1 )
ncall=$(wc -l < "$d/shim/calls" 2>/dev/null | tr -d ' ')
nargc=$(wc -l < "$d/shim/argcalls" 2>/dev/null | tr -d ' ')   # ≥1 = bounded_run(meter 경로)에 실제로 들어갔다
if [ "${ncall:-0}" -ge 1 ] && [ "${nargc:-0}" -ge 1 ] && [ -z "$(ls -A "$d/matdir")" ]; then ok "T5.e2 meter 경로(fid-start 있는 실 FID)에서도 재료 임시 파일 삭제(EXIT trap 이 덮이지 않는다)"
else nope "T5.e2" "mktemp(무인자) ${ncall:-0}회 · 인자 ${nargc:-0}회 · 잔존=$(ls -A "$d/matdir")"; fi
# PASS fixture
FIDP=20261002-afp-pass
d=$(mkd); A=$(attempts "$d" "$FIDP"); mk_fix "$d" "$FIDP" 'exit 0'
rv "$d" "$FIDP"; rc=$?
lp=$(line_at "$A" 1)
if [ "$rc" -eq 0 ] && [ "$(cat "$d/rv.out")" = "VERIFY: PASS" ] && [ "$(nlines "$A")" = 1 ] \
   && [ "$(field "$lp" verdict)" = PASS ] && [ "$(field "$lp" fp)" = "-" ] && [ "$(field "$lp" n)" = 0 ]; then
  ok "T5.f 통과 fixture: stdout 'VERIFY: PASS'·rc0·PASS 줄 1개(fp '-' n=0)"
else nope "T5.f" "rc=$rc out=$(cat "$d/rv.out") $(cat "$A" 2>/dev/null)"; fi
# 실패 → 통과 → 실패 : PASS 가 연속을 끊는다
d=$(mkd); A=$(attempts "$d" "$FIDF"); mk_fix "$d" "$FIDF" 'echo "FAIL T15 boom"; exit 1'
rv "$d" "$FIDF"; rv "$d" "$FIDF"
mk_fix "$d" "$FIDF" 'exit 0'; rv "$d" "$FIDF"
mk_fix "$d" "$FIDF" 'echo "FAIL T15 boom"; exit 1'; rv "$d" "$FIDF"
seq=$(for i in 1 2 3 4; do field "$(line_at "$A" $i)" n; done | tr '\n' ,)
out=$(afp_in "$d" check "$FIDF"); rc=$?
if [ "$seq" = "1,2,0,1," ] && [ "$rc" -eq 0 ]; then ok "T5.g FAIL·FAIL·PASS·FAIL → n 1,2,0,1 · check rc0"
else nope "T5.g" "seq=$seq rc=$rc"; fi
# 다른 실패로 바뀌면 n=1·fp 상이
d=$(mkd); A=$(attempts "$d" "$FIDF"); mk_fix "$d" "$FIDF" 'echo "FAIL T15 boom"; exit 1'; rv "$d" "$FIDF"
mk_fix "$d" "$FIDF" 'echo "FAIL T16 boom"; exit 1'; rv "$d" "$FIDF"
l1=$(line_at "$A" 1); l2=$(line_at "$A" 2)
if [ "$(field "$l2" n)" = 1 ] && [ "$(field "$l1" fp)" != "$(field "$l2" fp)" ] && [ "$(field "$l1" fp)" != "-" ]; then ok "T5.h 실패 줄이 바뀌면(진전) fp 상이·n=1"
else nope "T5.h" "$(cat "$A")"; fi
# 조용한 실패(출력 0줄) — CMD 줄로 구분
d=$(mkd); A=$(attempts "$d" "$FIDF"); mk_fix "$d" "$FIDF" 'exit 1' silent-a.sh; rv "$d" "$FIDF"
mk_fix "$d" "$FIDF" 'exit 1' silent-b.sh; rv "$d" "$FIDF"
mk_fix "$d" "$FIDF" 'exit 1' silent-b.sh; rv "$d" "$FIDF"
seq=$(for i in 1 2 3; do field "$(line_at "$A" $i)" n; done | tr '\n' ,)
if [ "$seq" = "1,1,2," ] && [ "$(field "$(line_at "$A" 1)" fp)" != "-" ]; then ok "T5.i 출력 없는 실패 2종은 서로 다른 지문(CMD 줄), 같은 것은 연속"
else nope "T5.i" "seq=$seq $(cat "$A")"; fi
# 같은 조용한 명령이 다른 종료코드로 실패하면 다른 지문(EXIT 줄)
d=$(mkd); A=$(attempts "$d" "$FIDF"); mk_fix "$d" "$FIDF" 'exit 1'; rv "$d" "$FIDF"
mk_fix "$d" "$FIDF" 'exit 2'; rv "$d" "$FIDF"
l1=$(line_at "$A" 1); l2=$(line_at "$A" 2)
if [ "$(field "$l1" fp)" != "-" ] && [ "$(field "$l1" fp)" != "$(field "$l2" fp)" ] && [ "$(field "$l2" n)" = 1 ]; then ok "T5.i2 같은 명령·다른 종료코드(exit 1 ≠ exit 2) → 다른 지문"
else nope "T5.i2" "$(cat "$A")"; fi
# record 쓰기 불가에서도 판정·출력 불변
d=$(mkd); mk_fix "$d" "$FIDF" 'echo "FAIL T15 boom"; exit 1'; mkdir -p "$d/.specops/$FIDF/attempts.jsonl"
rv "$d" "$FIDF"; rc=$?
if [ "$rc" -eq 1 ] && [ -z "$(cat "$d/rv.out")" ] && grep -qx 'VERIFY: FAIL bash scripts/tests/dummy.sh (exit=1)' "$d/rv.err" \
   && grep -q 'RUN-VERIFICATION-RESULT: FAIL' "$d/.specops/$FIDF/evidence.md"; then
  ok "T5.j 기록 불가(attempts.jsonl 이 디렉터리)에서도 FAIL 판정·rc1·evidence 스탬프 불변"
else nope "T5.j" "rc=$rc out=$(cat "$d/rv.out") err=$(cat "$d/rv.err")"; fi
d=$(mkd); mk_fix "$d" "$FIDP" 'exit 0'; mkdir -p "$d/.specops/$FIDP/attempts.jsonl"
rv "$d" "$FIDP"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$d/rv.out")" = "VERIFY: PASS" ] && grep -q 'RUN-VERIFICATION-RESULT: PASS' "$d/.specops/$FIDP/evidence.md"; then
  ok "T5.k 기록 불가에서도 PASS 판정·rc0·stdout 불변"
else nope "T5.k" "rc=$rc out=$(cat "$d/rv.out") err=$(cat "$d/rv.err")"; fi
# record 가 비정상(rc2 — attempt-fp 가 거부하는 FID)이어도 판정·종료코드는 불변
d=$(mkd); mk_fix "$d" "afp fixture" 'echo "FAIL T15 boom"; exit 1'
rv "$d" "afp fixture"; rc=$?
if [ "$rc" -eq 1 ] && grep -qx 'VERIFY: FAIL bash scripts/tests/dummy.sh (exit=1)' "$d/rv.err" && grep -q 'WARN: attempt' "$d/rv.err" \
   && [ ! -e "$d/.specops/afp fixture/attempts.jsonl" ]; then
  ok "T5.s record 가 rc≠0(FID 거부)로 끝나도 FAIL 판정·rc1 불변 + WARN 표면화"
else nope "T5.s" "rc=$rc err=$(cat "$d/rv.err")"; fi
# 사전 검사 실패(REASON): spec.md 만 있고 AC 부재 → ac-format FAIL, 2회 → n=2
d=$(mkd); A=$(attempts "$d" "$FIDP"); mk_fix "$d" "$FIDP" 'exit 0'; : > "$d/.specops/$FIDP/spec.md"
rv "$d" "$FIDP"; rc=$?; rv "$d" "$FIDP"
l1=$(line_at "$A" 1); l2=$(line_at "$A" 2)
if [ "$rc" -eq 1 ] && grep -q 'VERIFY: FAIL ac-format' "$d/rv.err" && [ "$(field "$l1" verdict)" = FAIL ] \
   && [ "$(field "$l1" fp)" = "$(field "$l2" fp)" ] && [ "$(field "$l1" fp)" != "-" ] && [ "$(field "$l2" n)" = 2 ]; then
  ok "T5.l 사전 검사(ac-format) 실패도 REASON 재료로 기록 — 2회 n=2"
else nope "T5.l" "rc=$rc $(cat "$A" 2>/dev/null) err=$(head -3 "$d/rv.err")"; fi
ACFP=$(field "$l1" fp)
# review-audit(no spec.md → AC 면제 경로): dispatch-log 가 가리킨 리뷰 파일 부재 — 대상이 다르면 다른 지문
mk_audit() { # <dir> <missing-task-id>
  mk_fix "$1" "$FIDP" 'exit 0'
  printf '| 1 | t | B | spec-reviewer-ko | PASS | reviews/%s-B-report.md |\n' "$2" > "$1/.specops/$FIDP/dispatch-log.md"
}
d=$(mkd); A=$(attempts "$d" "$FIDP"); mk_audit "$d" T1; rv "$d" "$FIDP"; rca=$?
d2=$(mkd); A2=$(attempts "$d2" "$FIDP"); mk_audit "$d2" T2; rv "$d2" "$FIDP"
d3=$(mkd); A3=$(attempts "$d3" "$FIDP"); mk_audit "$d3" T1; rv "$d3" "$FIDP"
fa=$(field "$(line_at "$A" 1)" fp); fb=$(field "$(line_at "$A2" 1)" fp); fc=$(field "$(line_at "$A3" 1)" fp)
if [ "$rca" -eq 1 ] && grep -q 'VERIFY: FAIL review-audit' "$d/rv.err" && [ "$fa" = "$fc" ] && [ "$fa" != "$fb" ] \
   && [ "$fa" != "-" ] && [ "$fa" != "$ACFP" ]; then
  ok "T5.m review-audit 실패: 같은 대상=같은 지문 · 다른 대상(T1≠T2)=다른 지문 · ac-format 과도 다름"
else nope "T5.m" "rc=$rca fa=$fa fb=$fb fc=$fc acfp=$ACFP"; fi
# 사전 검사 사유별 재료 — 각 REASON 배선이 살아 있으면 FAIL 줄의 fp 가 '-' 가 아니고, 같은 실패 2회는 n=2
mk_spec() { # <dir> <spec 본문...> — spec.md + (빈) AC 파일(AC 부재 FAIL 을 비껴간다)
  local d="$1"; shift
  printf '%s\n' "$@" > "$d/.specops/$FIDP/spec.md"; : > "$d/.specops/$FIDP/acceptance-criteria.md"
}
reason_case() { # <id> <설명> <기대 stderr 문구> <명령 0건? yes|no> <spec 본문...>
  local id="$1" desc="$2" want="$3" nocmd="$4" d A rc l1 l2; shift 4
  d=$(mkd); A=$(attempts "$d" "$FIDP"); mk_fix "$d" "$FIDP" 'exit 0'
  [ "$nocmd" = yes ] && : > "$d/.specops/$FIDP/tasks.md"
  mk_spec "$d" "$@"
  rv "$d" "$FIDP"; rc=$?; rv "$d" "$FIDP"
  l1=$(line_at "$A" 1); l2=$(line_at "$A" 2)
  if [ "$rc" -eq 1 ] && grep -q "$want" "$d/rv.err" && [ "$(field "$l1" verdict)" = FAIL ] && [ "$(field "$l1" fp)" != "-" ] \
     && [ "$(field "$l1" fp)" = "$(field "$l2" fp)" ] && [ "$(field "$l2" n)" = 2 ]; then
    ok "T5.$id $desc → FAIL 줄 fp 유효·2회 n=2"
  else nope "T5.$id $desc" "rc=$rc $(cat "$A" 2>/dev/null) err=$(head -3 "$d/rv.err")"; fi
  printf '%s\n' "$(field "$l1" fp)" > "$TMP/last-reason-fp"
}
reason_case r1 "foundation-manifest(테스트 명령 있음)" 'VERIFY: FAIL foundation-manifest' no '**§유형**: foundation'
FP_FND=$(cat "$TMP/last-reason-fp")
reason_case r2 "foundation-manifest(명령 0건 경로)" 'VERIFY: FAIL foundation-manifest' yes '**§유형**: foundation'
reason_case r3 "review-presence(§lite 하드)" 'VERIFY: FAIL review-presence' no '**§lite**: true'
reason_case r4 "spec-label hybrid(+foundation-manifest)" 'VERIFY: FAIL spec-label' no '**§유형**: foundation' '**§batch**: batch-1'
FP_HYB=$(cat "$TMP/last-reason-fp")
[ "$FP_HYB" != "$FP_FND" ] && ok "T5.r5 spec-label 사유가 재료에 더해져 hybrid 지문 ≠ foundation 단독 지문" || nope "T5.r5" "fnd=$FP_FND hyb=$FP_HYB"
# review-audit 명령 0건 경로
d=$(mkd); A=$(attempts "$d" "$FIDP"); mk_audit "$d" T1; : > "$d/.specops/$FIDP/tasks.md"
rv "$d" "$FIDP"; rc=$?
l1=$(line_at "$A" 1)
if [ "$rc" -eq 1 ] && grep -q 'VERIFY: FAIL review-audit' "$d/rv.err" && [ "$(field "$l1" verdict)" = FAIL ] && [ "$(field "$l1" fp)" != "-" ]; then
  ok "T5.r6 review-audit(명령 0건 경로) 실패 → FAIL 줄 fp 유효"
else nope "T5.r6" "rc=$rc $(cat "$A" 2>/dev/null) err=$(head -3 "$d/rv.err")"; fi
# PARTIAL·NOT_RUN 은 기록하지 않는다 — 직전 줄 유지
d=$(mkd); A=$(attempts "$d" "$FIDF"); mk_fix "$d" "$FIDF" 'echo "FAIL T15 boom"; exit 1'; rv "$d" "$FIDF"
before=$(cat "$A")
mk_fix "$d" "$FIDF" 'exit 0'; mk_tasks "$d/.specops/$FIDF/tasks.md" "bash scripts/tests/dummy.sh" "make test"
rv "$d" "$FIDF"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'VERIFY: PARTIAL' "$d/rv.out" && [ "$(cat "$A")" = "$before" ] \
   && ! grep -Eq 'attempt|usage:' "$d/rv.err"; then
  ok "T5.n PARTIAL(whitelist 미통과) → record 호출 자체가 없다(새 줄 없음·직전 줄 그대로·stderr 무경고)"
else nope "T5.n" "rc=$rc out=$(cat "$d/rv.out") now=$(cat "$A") err=$(cat "$d/rv.err")"; fi
: > "$d/.specops/$FIDF/tasks.md"; rv "$d" "$FIDF"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'VERIFY: NOT_RUN' "$d/rv.err" && [ "$(cat "$A")" = "$before" ] \
   && ! grep -Eq 'attempt|usage:' "$d/rv.err"; then
  ok "T5.o NOT_RUN(명령 0건) → record 호출 자체가 없다(새 줄 없음·직전 줄 그대로·stderr 무경고)"
else nope "T5.o" "rc=$rc err=$(cat "$d/rv.err") now=$(cat "$A")"; fi
d=$(mkd); mk_fix "$d" "$FIDP" 'exit 0'; mk_tasks "$d/.specops/$FIDP/tasks.md" "make test"
rv "$d" "$FIDP"
if grep -q 'VERIFY: PARTIAL' "$d/rv.out" && [ ! -e "$(attempts "$d" "$FIDP")" ]; then ok "T5.p 신규 FID 의 PARTIAL → attempts.jsonl 생성 안 됨"
else nope "T5.p" "out=$(cat "$d/rv.out")"; fi
# 실패 + whitelist 미통과 혼합은 PARTIAL(기존 판정) → 기록 대상 아님 — 현행 동작 잠금
d=$(mkd); mk_fix "$d" "$FIDF" 'exit 1'; mk_tasks "$d/.specops/$FIDF/tasks.md" "bash scripts/tests/dummy.sh" "make test"
rv "$d" "$FIDF"
if grep -q 'VERIFY: PARTIAL' "$d/rv.out" && [ ! -e "$(attempts "$d" "$FIDF")" ]; then ok "T5.q 실패+SKIP 혼합은 PARTIAL 이라 미기록(Q2: PARTIAL 은 연속 판정 무관)"
else nope "T5.q" "out=$(cat "$d/rv.out")"; fi

# ── T6 (AC-6) SKILL.md 소비 지점 정적 잠금 + R-1/R-2 불변 ─────────
region() { sed -n '/^## Bounded verify→fix 루프/,/^## session-progress append/p' "$1"; }
CHK='"${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/attempt-fp.sh check <FID>'
skill_check_ok() { # <SKILL 파일> — check 호출이 fix_count ≤ 3 분기 안, dispatch 직전에 있고 rc1 처리 문구가 딸려 있다
  local f="$1" r lc lb lv li blk
  r=$(region "$f")
  lc=$(printf '%s\n' "$r" | grep -nF "$CHK" | head -1 | cut -d: -f1); [ -n "$lc" ] || return 1
  lb=$(printf '%s\n' "$r" | grep -n 'fix_count ≤ 3 →' | head -1 | cut -d: -f1); [ -n "$lb" ] || return 1
  lv=$(printf '%s\n' "$r" | grep -n 'verify-loop.md 갱신' | head -1 | cut -d: -f1); [ -n "$lv" ] || return 1
  li=$(printf '%s\n' "$r" | grep -n 'implementing-ko 호출' | head -1 | cut -d: -f1); [ -n "$li" ] || return 1
  [ "$lb" -lt "$lc" ] && [ "$lc" -lt "$lv" ] && [ "$lv" -lt "$li" ] || return 1
  blk=$(printf '%s\n' "$r" | sed -n "${lc},${lv}p")
  printf '%s\n' "$blk" | grep -q 'rc 1' && printf '%s\n' "$blk" | grep -q 'ATTEMPT-STOP' \
    && printf '%s\n' "$blk" | grep -q 'HARD GATE' && printf '%s\n' "$blk" | grep -q 'VERIFY-HARD-GATE: <FID> 동일 실패 지문' \
    && printf '%s\n' "$blk" | grep -q '§auto' && printf '%s\n' "$blk" | grep -q 'systematic-debugging-ko' \
    && printf '%s\n' "$blk" | grep -q '전역 재시도'
}
# 금지 문구 — 지문(attempt-fp·attempts.jsonl·동일 실패 지문)을 말하는 줄에서만 검사한다
#   (§auto 의 기존 `verify-loop.md 초기화 (fix_count=0)` 줄은 지문과 무관한 종전 cap 경로라 대상 밖)
ban_hits() { # <SKILL 파일> → 금지 문구 적중 줄 수
  local f="$1" scoped
  scoped=$(grep -E 'attempt-fp|attempts\.jsonl|동일 실패 지문|지문' "$f")
  {
    printf '%s\n' "$scoped" | grep -E 'fix_count.*(되돌|리셋|초기화|감소|차감|0 으로|=0)'
    printf '%s\n' "$scoped" | grep -E 'attempts\.jsonl.*(직접|손으로|수동)|(직접|손으로|수동).*attempts\.jsonl'
    printf '%s\n' "$scoped" | grep -E '(echo|printf|tee|sed -i|>>).*attempts\.jsonl|attempts\.jsonl.*(>>|append)'
  } | grep -c .
}
if skill_check_ok "$SKILL"; then ok "T6.a fix_count ≤ 3 분기 · dispatch 직전에 attempt-fp.sh check 호출 + rc1 처리(HARD GATE·§auto systematic-debugging 전역 재시도)"
else nope "T6.a" "SKILL.md fix_loop 에 check 호출·rc1 처리가 없다"; fi
eq "T6.b 금지 문구 0건(fix_count 되돌림·attempts.jsonl 손으로 쓰기)" 0 "$(ban_hits "$SKILL")"
if grep -q 'attempts\.jsonl.*스크립트 전용' "$SKILL" && grep -q '지문이 달라져도 `fix_count` 상한은 그대로' "$SKILL"; then ok "T6.c 스크립트 전용 기록·cap 비우회 문구 존재"
else nope "T6.c" "문구 없음"; fi
# 음성 대조 — 훼손한 사본에서 같은 검사가 실제로 실패/적중한다
sk="$TMP/skill-neg"; mkdir -p "$sk"
grep -vF "$CHK" "$SKILL" > "$sk/no-check.md"
if ! skill_check_ok "$sk/no-check.md"; then ok "T6.d 음성: check 호출 줄을 지우면 잠금 실패"; else nope "T6.d" "check 줄 삭제가 통과(헛도는 잠금)"; fi
awk -v chk="$CHK" 'index($0, chk) { held = $0; next } { print } /verify-loop.md 갱신/ && held != "" { print held; held = "" }' "$SKILL" > "$sk/late-check.md"
if ! skill_check_ok "$sk/late-check.md"; then ok "T6.e 음성: check 를 verify-loop 갱신 뒤로 옮기면(dispatch 직전 아님) 잠금 실패"; else nope "T6.e" "순서 위반이 통과"; fi
sed 's/rc 1 (ATTEMPT-STOP/rc 9 (ATTEMPT-X/' "$SKILL" > "$sk/no-rc1.md"
if ! skill_check_ok "$sk/no-rc1.md"; then ok "T6.f 음성: rc1 처리 문구를 지우면 잠금 실패"; else nope "T6.f" "rc1 처리 삭제가 통과"; fi
{ cat "$SKILL"; echo '- 지문이 달라지면 fix_count 를 0 으로 되돌린다 (attempt-fp 결과)'; } > "$sk/ban1.md"
[ "$(ban_hits "$sk/ban1.md")" -ge 1 ] && ok "T6.g 음성: 'fix_count 를 되돌린다' 문구를 주입하면 금지 검사 적중" || nope "T6.g" "되돌림 문구 미적중"
{ cat "$SKILL"; echo '- 모델이 attempts.jsonl 에 직접 한 줄을 기록한다'; } > "$sk/ban2.md"
[ "$(ban_hits "$sk/ban2.md")" -ge 1 ] && ok "T6.h 음성: 'attempts.jsonl 직접 기록' 문구를 주입하면 금지 검사 적중" || nope "T6.h" "손으로 쓰기 문구 미적중"
{ cat "$SKILL"; echo '- echo "{}" >> .specops/<FID>/attempts.jsonl'; } > "$sk/ban3.md"
[ "$(ban_hits "$sk/ban3.md")" -ge 1 ] && ok "T6.i 음성: attempts.jsonl 에 echo >> 하라는 줄을 주입하면 금지 검사 적중" || nope "T6.i" "echo >> 문구 미적중"
# FR-6 — R-1/R-2 판정·verification-state·evidence 스키마는 이 기록을 읽지 않는다
if ! grep -rEq 'attempts\.jsonl|attempt-fp' "$PLUGIN/hooks" "$PLUGIN/scripts/_internal/verification-state.sh"; then
  ok "T6.j hooks/·verification-state.sh 가 attempts.jsonl·attempt-fp 를 참조하지 않는다(면제 판정 불개입)"
else nope "T6.j" "$(grep -rEn 'attempts\.jsonl|attempt-fp' "$PLUGIN/hooks" "$PLUGIN/scripts/_internal/verification-state.sh" | head -3)"; fi
printf 'x attempts.jsonl y\n' > "$sk/probe.sh"
if grep -Eq 'attempts\.jsonl|attempt-fp' "$sk/probe.sh"; then ok "T6.k 음성: 같은 grep 이 참조가 있는 파일에서는 적중한다"; else nope "T6.k" "grep 헛돎"; fi
[ -x "$AFP" ] && [ "$(head -1 "$AFP")" = '#!/usr/bin/env bash' ] && ok "T6.l attempt-fp.sh: 실행권한·shebang" || nope "T6.l" "exec-bit/shebang"
# 한계 고백(원칙 5) — 키워드 없는 실패 출력·긴 hex/10진 id 의 접힘을 SKILL 지문 절과 스크립트 헤더 둘 다 밝힌다
fp_section() { sed -n '/^### 동일 실패 지문 정지/,/^### 규칙/p' "$1"; }
if fp_section "$SKILL" | grep -q '키워드가 없는 출력.*접힌다.*재료 부족'; then ok "T6.m SKILL 지문 절: 키워드 없는 출력 접힘 한계 고백"
else nope "T6.m" "SKILL 지문 절에 한계 문구 없음"; fi
if sed -n '/^# 한계(정직)/,/^set -u$/p' "$AFP" | grep -q '키워드가 없는 출력' \
   && sed -n '/^# 한계(정직)/,/^set -u$/p' "$AFP" | grep -q '재료 부족' \
   && sed -n '/^# 한계(정직)/,/^set -u$/p' "$AFP" | grep -q 'test_deadbeef01'; then ok "T6.n attempt-fp.sh 헤더 한계 절: 키워드 없는 출력·긴 id 접힘 고백"
else nope "T6.n" "헤더 한계 절에 문구 없음"; fi

# ── T7 (AC-7) 러너 5형상 — 실패 줄만 재료 ─────────────────────────
shape() { # <id> <이름> <FAILS> <NOISE_A> <NOISE_B> <FAILS2> <기대 정규화 집합(정렬)>
  local id="$1" name="$2" fails="$3" na="$4" nb="$5" fails2="$6" expect="$7" d got
  d=$(mkd); matstr "$d/m" "$HEAD3"$'\n'"$fails"$'\n'"$na"
  got=$(afp::normalize "$d/m")
  eq "T7.$id.1 $name: 정규화 집합 = CMD·EXIT + 실패 줄만(통과·요약 줄 제외)" "$expect" "$got"
  same_fp "T7.$id.2 $name: 통과 줄·요약 카운트 줄이 달라도 fp 불변" "$HEAD3"$'\n'"$fails"$'\n'"$na" "$HEAD3"$'\n'"$fails"$'\n'"$nb"
  diff_fp "T7.$id.3 $name: 실패 줄이 달라지면 fp 가 달라진다" "$HEAD3"$'\n'"$fails"$'\n'"$na" "$HEAD3"$'\n'"$fails2"$'\n'"$na"
}
shape pytest "pytest" \
  'FAILED tests/x.py::test_a - AssertionError: assert 1 == 2' \
  $'tests/x.py::test_error_case PASSED [ 50%]\n============ 1 failed, 3 passed in 0.12s ============\n3 passed, 1 failed in 0.12s' \
  $'tests/x.py::test_error_case PASSED [ 25%]\ntests/x.py::test_c PASSED [ 50%]\n============ 1 failed, 7 passed in 0.99s ============\n7 passed, 1 failed in 0.99s' \
  'FAILED tests/x.py::test_z - AssertionError: assert 1 == 2' \
  "$(printf '%s\n' 'CMD: bash scripts/tests/test-x.sh' 'EXIT: 1' 'FAILED tests/x.py::test_a - AssertionError: assert 1 == 2' | LC_ALL=C sort -u)"
shape go "go test" \
  $'--- FAIL: TestA (0.00s)\nFAIL\nFAIL\tgithub.com/x/pkg\t0.004s' \
  $'ok  \tgithub.com/x/other\t0.003s\n--- PASS: TestErrorCase (0.00s)\n=== RUN   TestErrorCase\nexit status 1' \
  $'ok  \tgithub.com/x/other\t0.512s\n--- PASS: TestErrorCase (0.31s)\n=== RUN   TestErrorCase\n--- PASS: TestMore (0.01s)\nexit status 1' \
  $'--- FAIL: TestB (0.00s)\nFAIL\nFAIL\tgithub.com/x/pkg\t0.004s' \
  "$(printf '%s\n' 'CMD: bash scripts/tests/test-x.sh' 'EXIT: 1' '--- FAIL: TestA (<DUR>)' 'FAIL' 'FAIL github.com/x/pkg <DUR>' | LC_ALL=C sort -u)"
shape jest "npm/jest" \
  '✕ rejects bad input (3 ms)' \
  $'✓ accepts good input (2 ms)\n✓ handles error case (4 ms)\n✔ also error path (1 ms)\nTests:       1 failed, 5 passed, 6 total\nTest Suites: 1 failed, 1 total\nTime:        1.234 s' \
  $'✓ accepts good input (9 ms)\n✓ handles error case (7 ms)\n✔ also error path (3 ms)\n✓ extra (1 ms)\nTests:       1 failed, 9 passed, 10 total\nTest Suites: 1 failed, 1 total\nTime:        7.5 s' \
  '✕ rejects other input (3 ms)' \
  "$(printf '%s\n' 'CMD: bash scripts/tests/test-x.sh' 'EXIT: 1' '✕ rejects bad input (<DUR>)' | LC_ALL=C sort -u)"
shape bash "bash 스위트" \
  'FAIL T15 expected 3 got 4' \
  $'PASS T1 error path ok\nPASS T2 something\nPASS=16 FAIL=1\nResults: 16/17' \
  $'PASS T1 error path ok\nPASS T2 something\nPASS T3 more\nPASS=40 FAIL=1\nResults: 40/41' \
  'FAIL T16 expected 3 got 4' \
  "$(printf '%s\n' 'CMD: bash scripts/tests/test-x.sh' 'EXIT: 1' 'FAIL T15 expected 3 got 4' | LC_ALL=C sort -u)"
shape python "Python traceback" \
  $'Traceback (most recent call last):\nValueError: bad input' \
  $'  File "x.py", line 3, in <module>\nRan 5 tests in 0.002s\nFAILED (errors=1)' \
  $'  File "x.py", line 3, in <module>\nRan 9 tests in 0.5s\nFAILED (errors=2)' \
  $'Traceback (most recent call last):\nValueError: other input' \
  "$(printf '%s\n' 'CMD: bash scripts/tests/test-x.sh' 'EXIT: 1' 'Traceback (most recent call last):' 'ValueError: bad input' | LC_ALL=C sort -u)"
shape node "node --test(TAP, 실측 형상)" \
  'not ok 2 - fails case' \
  $'# Subtest: passes with error word\nok 1 - passes with error word\n# tests 3\n# suites 0\n# pass 1\n# fail 2\n# duration_ms 42.460416' \
  $'# Subtest: passes with error word\n# Subtest: another error-free one\nok 1 - passes with error word\n# tests 9\n# suites 0\n# pass 7\n# fail 2\n# duration_ms 1042.5' \
  'not ok 2 - other case' \
  "$(printf '%s\n' 'CMD: bash scripts/tests/test-x.sh' 'EXIT: 1' 'not ok 2 - fails case' | LC_ALL=C sort -u)"
# 보강: not ok(TAP)·panic·✗ 도 실패 줄로 취한다 / ok(TAP) 줄은 키워드가 있어도 통과 줄
d=$(mkd); matstr "$d/m" $'not ok 3 - rejects input\nok 4 - handles failure path\npanic: runtime error: index out of range\n✗ broken case'
got=$(afp::normalize "$d/m")
eq "T7.x TAP not ok·panic·✗ 는 취하고 'ok 4 - handles failure path' 는 제외" "$(printf '%s\n' 'not ok 3 - rejects input' 'panic: runtime error: index out of range' '✗ broken case' | LC_ALL=C sort -u)" "$got"
# 줄 중간의 키워드(FAIL·ERROR·not ok·Traceback·panic·✗·✕)도 실패 줄로 취한다 — 키워드마다 한 줄씩
d=$(mkd); matstr "$d/m" $'x.py::test_a FAILED [ 50%]\nValueError: bad input\n# 3 not ok here\nlog 12 Traceback seen\ngoroutine 1 panic seen\n  - ✗ mid mark\n  - ✕ mid cross\nnoise line without markers\ninfo: all good'
got=$(afp::normalize "$d/m")
eq "T7.v 줄 중간 키워드 7종 각각 취하고 무관 줄은 제외" "$(printf '%s\n' 'x.py::test_a FAILED [ 50%]' 'ValueError: bad input' '# 3 not ok here' 'log 12 Traceback seen' 'goroutine 1 panic seen' '- ✗ mid mark' '- ✕ mid cross' | LC_ALL=C sort -u)" "$got"
# run-all 형상: `--- <스위트>.sh` 헤더는 스위트 이름에 fail/error 가 있어도 실패 줄이 아니다(실측: test-failure-modes.sh)
same_fp "T7.u run-all 스위트 헤더(--- …/test-failure-modes.sh)는 재료가 아니다" $'CMD: x\nEXIT: 1\nFAIL GH-ci.1 — rc=0\nFAILED: scripts/tests/test-git-hooks.sh' $'CMD: x\nEXIT: 1\n--- scripts/tests/governance/test-failure-modes.sh\nPASS=3 FAIL=0\n--- scripts/tests/test-error-paths.sh\nFAIL GH-ci.1 — rc=0\nFAILED: scripts/tests/test-git-hooks.sh'
# 실패 줄이 'passed' 를 말해도 실패 줄이다(통과 줄 규칙보다 실패 시작이 우선)
d=$(mkd); matstr "$d/m" $'FAIL T3 expected passed got x\nERROR step passed\nPASS T4 ok'
got=$(afp::normalize "$d/m")
eq "T7.w FAIL/ERROR 로 시작하는 줄은 ' passed ' 가 있어도 취한다(PASS 시작 줄만 제외)" "$(printf '%s\n' 'FAIL T3 expected passed got x' 'ERROR step passed' | LC_ALL=C sort -u)" "$got"
# 실패 줄 안의 가변부는 정규화돼 실제 러너 형상에서 지문이 안정된다
same_fp "T7.y go: --- FAIL 줄의 소요시간만 달라도 같은 실패" $'--- FAIL: TestA (0.00s)' $'--- FAIL: TestA (1.37s)'
diff_fp "T7.z pytest: 같은 파일 다른 테스트(test_a ≠ test_b)는 다른 실패" 'FAILED tests/x.py::test_a - AssertionError' 'FAILED tests/x.py::test_b - AssertionError'
# jest 기본(비-verbose) 리포터: 다중 파일 실행에서 실패 테스트는 `● <suite> › <name>` 헤더로만 나온다(✕ 줄 없음).
#   상세 줄(expect·Expected·at …)에는 키워드가 없어 ● 헤더를 취하지 않으면 같은 파일의 다른 실패가 같은 fp 로 접힌다
#   (Phase C 입력 프로브 R3 실측 [SAME]). `● Console`(구 jest 의 console 출력 머리줄 — 통과 테스트에도 나온다)는 실패가 아니다.
jest_mat() { # <케이스 이름> <파일 소요> <✓ 소요> <Time 값>
  printf '%s\n' 'CMD: npx jest' 'EXIT: 1' " FAIL  src/a.test.js ($2)" "  ✓ passes ($3)" '  ● Console' '' \
    '    console.log' '      hello' '' "  ● suite › $1" '' '    expect(received).toBe(expected) // Object.is equality' '' \
    '    Expected: 2' '    Received: 1' '' '      at Object.<anonymous> (src/a.test.js:5:13)' '' \
    'Test Suites: 1 failed, 1 total' 'Tests:       1 failed, 1 passed, 2 total' "Time:        $4"
}
d=$(mkd); jest_mat 'case A' '5.123 s' '3 ms' '1.234 s' > "$d/m"
got=$(afp::normalize "$d/m")
eq "T7.ja jest 기본 리포터: ● 실패 헤더는 취하고 ✓ 통과 줄·● Console·상세 줄·요약 줄은 제외" \
  "$(printf '%s\n' 'CMD: npx jest' 'EXIT: 1' 'FAIL src/a.test.js (<DUR>)' '● suite › case A' | LC_ALL=C sort -u)" "$got"
diff_fp "T7.jb jest 기본 리포터: 같은 파일의 다른 실패 테스트(● case A ≠ ● case B, 키워드 없는 줄)는 다른 실패" \
  "$(jest_mat 'case A' '5.123 s' '3 ms' '1.234 s')" "$(jest_mat 'case B' '5.123 s' '3 ms' '1.234 s')"
same_fp "T7.jc jest 기본 리포터: 같은 실패 테스트의 소요시간만 다르면(취한 FAIL 줄 포함) 같은 실패" \
  "$(jest_mat 'case A' '5.123 s' '3 ms' '1.234 s')" "$(jest_mat 'case A' '12.4 s' '9 ms' '7.5 s')"
same_fp "T7.jd jest 기본 리포터: ● 헤더의 ANSI 색 코드는 무시" \
  "$(jest_mat 'case A' '5.123 s' '3 ms' '1.234 s')" "$(jest_mat 'case A' '5.123 s' '3 ms' '1.234 s' | sed $'s/  ● suite/  \033[1m\033[31m● \033[22msuite/')"

finish
