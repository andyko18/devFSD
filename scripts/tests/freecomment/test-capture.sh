#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
HOOK="$PLUGIN/hooks/freecomment-capture.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# T1.a 변경 없는 세션 → continue:true + pending 미생성 (AC-2)
mkdir -p "$TMP/.specops"   # 도입 저장소 — 부재면 관할 가드가 먼저 빠져 이 단언이 공허해진다(부재 쪽은 T9)
tr_empty="$TMP/empty.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}' > "$tr_empty"
out=$(echo "{\"transcript_path\":\"$tr_empty\",\"cwd\":\"$TMP\"}" | bash "$HOOK" 2>/dev/null)
if echo "$out" | grep -q '"continue":true' && [ ! -f "$TMP/.specops/pending-capture.jsonl" ]; then
  PASS=$((PASS+1)); echo "PASS T1.a 변경없음 skip"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a (out=$out)"
fi

# T1.b 손상 transcript → fail-open continue:true (AC-7)
out=$(echo '{"transcript_path":"/nonexistent","cwd":"'"$TMP"'"}' | bash "$HOOK" 2>/dev/null)
if echo "$out" | grep -q '"continue":true'; then
  PASS=$((PASS+1)); echo "PASS T1.b fail-open"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b (out=$out)"
fi

# T2.a 자유작업 감지 → pending stub 기록 + type 분류 (AC-3)
work="$TMP/work"; mkdir -p "$work/.specops"
(cd "$work" && git init -q && git -c user.email=test@specops.test -c user.name=test commit --allow-empty -m init -q)
echo "x" > "$work/foo.sh"
(cd "$work" && git add foo.sh)
tr2="$TMP/tr2.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":[{"type":"text","text":"이 버그 고쳐줘"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"foo.sh"}}]}}' > "$tr2"
echo "{\"transcript_path\":\"$tr2\",\"cwd\":\"$work\"}" | bash "$HOOK" 2>/dev/null
if [ -f "$work/.specops/pending-capture.jsonl" ] && \
   grep -q '"type":"fix"' "$work/.specops/pending-capture.jsonl"; then
  PASS=$((PASS+1)); echo "PASS T2.a pending stub + type=fix"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.a"
fi

# T2.b 공백 파일명 → files_json 에 정확히 1항목 (분할 안 됨)
work2="$TMP/work2"; mkdir -p "$work2/.specops"
(cd "$work2" && git init -q && git -c user.email=test@specops.test -c user.name=test commit --allow-empty -m init -q)
printf 'x' > "$work2/a b.sh"
(cd "$work2" && git add "a b.sh")
tr2b="$TMP/tr2b.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":[{"type":"text","text":"고쳐줘"}]}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Edit\",\"input\":{\"file_path\":\"$work2/a b.sh\"}}]}}" > "$tr2b"
echo "{\"transcript_path\":\"$tr2b\",\"cwd\":\"$work2\"}" | bash "$HOOK" 2>/dev/null
if [ -f "$work2/.specops/pending-capture.jsonl" ]; then
  count=$(jq -r '.files | length' "$work2/.specops/pending-capture.jsonl" 2>/dev/null)
  first=$(jq -r '.files[0]' "$work2/.specops/pending-capture.jsonl" 2>/dev/null)
  if [ "$count" = "1" ] && [ "$first" = "a b.sh" ]; then
    PASS=$((PASS+1)); echo "PASS T2.b 공백파일명 1항목"
  else
    FAIL=$((FAIL+1)); echo "FAIL T2.b (count=$count first=$first)"
  fi
else
  FAIL=$((FAIL+1)); echo "FAIL T2.b pending 미생성"
fi

# T2.c substring 오탐 방지 — changed=app.sh, edit=pp.sh → pending 미생성
work3="$TMP/work3"; mkdir -p "$work3/.specops"   # 도입 저장소 — 부재면 관할 가드가 먼저 빠져 이 단언이 공허해진다
(cd "$work3" && git init -q && git -c user.email=test@specops.test -c user.name=test commit --allow-empty -m init -q)
printf 'x' > "$work3/app.sh"
(cd "$work3" && git add app.sh)
tr2c="$TMP/tr2c.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":[{"type":"text","text":"수정"}]}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Edit\",\"input\":{\"file_path\":\"$work3/pp.sh\"}}]}}" > "$tr2c"
echo "{\"transcript_path\":\"$tr2c\",\"cwd\":\"$work3\"}" | bash "$HOOK" 2>/dev/null
if [ ! -f "$work3/.specops/pending-capture.jsonl" ]; then
  PASS=$((PASS+1)); echo "PASS T2.c substring 오탐 없음"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.c (pending 생성됨 — 오탐)"
fi

# T4.a fid 필드 존재 — detect_fid 결과 기록 (AC-1, AC-2)
work4="$TMP/work4"; mkdir -p "$work4"
(cd "$work4" && git init -q && git -c user.email=t@t.t -c user.name=t commit --allow-empty -m init -q)
mkdir -p "$work4/.specops"
printf '## 20260625-live\n- 2026-06-25 10:00 /implement 진행\n' > "$work4/.specops/session-progress.md"
echo "y" > "$work4/bar.sh"; (cd "$work4" && git add bar.sh)
tr4="$TMP/tr4.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":[{"type":"text","text":"리팩터"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"bar.sh"}}]}}' > "$tr4"
echo "{\"transcript_path\":\"$tr4\",\"cwd\":\"$work4\"}" | bash "$HOOK" 2>/dev/null
got=$(jq -r '.fid' "$work4/.specops/pending-capture.jsonl" 2>/dev/null)
if [ "$got" = "20260625-live" ]; then
  PASS=$((PASS+1)); echo "PASS T4.a fid 필드=$got"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.a (fid=$got)"
fi

# T5.a .specops 디렉토리 symlink → 외부 write-through 차단 (#144 대칭)
work5="$TMP/work5"; outside5="$TMP/outside5"; mkdir -p "$work5" "$outside5"
(cd "$work5" && git init -q && git -c user.email=t@t.t -c user.name=t commit --allow-empty -m init -q)
ln -s "$outside5" "$work5/.specops"
echo "z" > "$work5/baz.sh"; (cd "$work5" && git add baz.sh)
tr5="$TMP/tr5.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":[{"type":"text","text":"고쳐줘"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"baz.sh"}}]}}' > "$tr5"
out=$(echo "{\"transcript_path\":\"$tr5\",\"cwd\":\"$work5\"}" | bash "$HOOK" 2>/dev/null)
if echo "$out" | grep -q '"continue":true' && [ ! -f "$outside5/pending-capture.jsonl" ]; then
  PASS=$((PASS+1)); echo "PASS T5.a .specops symlink write 거부"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.a (외부 write 관통 또는 continue 아님)"
fi

# T5.b pending-capture.jsonl 파일 symlink → append 거부 (#144 대칭, 파일 벡터)
work6="$TMP/work6"; outside6="$TMP/outside6"; mkdir -p "$work6/.specops" "$outside6"
(cd "$work6" && git init -q && git -c user.email=t@t.t -c user.name=t commit --allow-empty -m init -q)
ln -s "$outside6/leak.jsonl" "$work6/.specops/pending-capture.jsonl"
echo "w" > "$work6/qux.sh"; (cd "$work6" && git add qux.sh)
tr6="$TMP/tr6.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"content":[{"type":"text","text":"고쳐줘"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"qux.sh"}}]}}' > "$tr6"
out=$(echo "{\"transcript_path\":\"$tr6\",\"cwd\":\"$work6\"}" | bash "$HOOK" 2>/dev/null)
if echo "$out" | grep -q '"continue":true' && [ ! -f "$outside6/leak.jsonl" ]; then
  PASS=$((PASS+1)); echo "PASS T5.b pending 파일 symlink append 거부"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.b (파일 symlink 관통)"
fi


# ═══ redact.sh 관문 · capture 훅 마스킹 (FID 20261001-redact-capture) ═══
# 가짜 시크릿은 실행 중에 조각을 이어 붙여 만든다 — 저장소에 실제 형태의 리터럴을 두지 않는다 (SAST self-check·gitleaks)
REDACT="$PLUGIN/scripts/_internal/redact.sh"
pass() { PASS=$((PASS+1)); echo "PASS $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL $1${2:+ — $2}"; }
rep() { local n=$1 c=$2 s="" i=0; while [ "$i" -lt "$n" ]; do s="$s$c"; i=$((i+1)); done; printf '%s' "$s"; }
K_AWS="AK""IA$(rep 16 A)"
K_GH="gh""p_$(rep 36 a)"
K_ANT="s""k-an""t-$(rep 24 c)"
K_OAI="s""k-$(rep 24 b)"
K_SLK="xo""xb-$(rep 12 1)"
K_JWT="ey""J$(rep 10 a).$(rep 10 b).$(rep 10 c)"
K_STR="s""k_li""ve_$(rep 20 d)"
K_GGL="AI""za$(rep 35 e)"
VQ=$(rep 12 q)   # 키=값 테스트의 값 — 리터럴이면 gitleaks generic-api-key 가 잡는다
PEM_B="-----BEG""IN RSA PRIVATE KEY-----"
PEM_E="-----END RSA PRIVATE KEY-----"
PRIV_O="<priv""ate>"
PRIV_C="</priv""ate>"

# T7.a 고정 시그니처 8종(PEM 은 T7.c) — 원문 부재 + 종류별 마커 + 주변 문장 보존 (AC-1)
in="앞문장 $K_AWS 중간 $K_GH 와 $K_ANT 그리고 $K_OAI 또 $K_SLK 그리고 $K_JWT 와 $K_STR 및 $K_GGL 뒷문장"
out=$(printf '%s' "$in" | bash "$REDACT" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] || ok=0
for k in "$K_AWS" "$K_GH" "$K_ANT" "$K_OAI" "$K_SLK" "$K_JWT" "$K_STR" "$K_GGL"; do
  case "$out" in *"$k"*) ok=0 ;; esac
done
for m in aws github anthropic openai slack jwt stripe google; do
  case "$out" in *"[REDACTED:$m]"*) ;; *) ok=0 ;; esac
done
case "$out" in "앞문장 "*" 뒷문장") ;; *) ok=0 ;; esac
[ "$ok" -eq 1 ] && pass "T7.a 시그니처 8종 마스킹·주변 보존" || fail "T7.a" "rc=$rc out=$out"

# T7.b 키=값 휴리스틱·Bearer·URL 자격증명·CLI 플래그 (AC-2) — JSON 형태·달러 시작 비밀번호 포함. 값 없는 단어만 있는 문장은 불변
in="password=hunter2 secret: s3 api_key = $VQ token: ${VQ}x Authorization: Bearer ${VQ}${VQ} \"password\": \"hunter2\" 'api_key': '$VQ' password=\$up3rS3cret! DB_PASSWORD=abc secret_key=abc postgres://user:${VQ}@host/db --password hunter2 \"Authorization\": \"Bearer ${VQ}\""
out=$(printf '%s' "$in" | bash "$REDACT" 2>/dev/null)
ok=1
for v in hunter2 "$VQ" up3rS3cret "DB_PASSWORD=abc" "secret_key=abc"; do case "$out" in *"$v"*) ok=0 ;; esac; done
case "$out" in *"password="*"secret:"*"api_key"*"Bearer"*) ;; *) ok=0 ;; esac
plain2='password 는 비밀번호라는 뜻이고 token 이야기도 한다'
[ "$(printf '%s' "$plain2" | bash "$REDACT" 2>/dev/null)" = "$plain2" ] || ok=0
[ "$ok" -eq 1 ] && pass "T7.b 키=값·JSON·Bearer·URL·CLI 마스킹, 값 없는 문장 불변" || fail "T7.b" "out=$out"

# T7.c private 구간(닫힘·여러 줄·미닫힘·복수)·PEM 블록 제거 (AC-1 PEM · AC-3)
in=$(printf 'a %sS1\nS2%s b\n%sS3%s c %sS4\nS5' "$PRIV_O" "$PRIV_C" "$PRIV_O" "$PRIV_C" "$PRIV_O")
out=$(printf '%s' "$in" | bash "$REDACT" 2>/dev/null)
ok=1
for v in S1 S2 S3 S4 S5; do case "$out" in *"$v"*) ok=0 ;; esac; done
case "$out" in "a "*" b"*" c "*) ;; *) ok=0 ;; esac
inp=$(printf 'k %s\nMIIEdata\nabc\n%s z' "$PEM_B" "$PEM_E")
outp=$(printf '%s' "$inp" | bash "$REDACT" 2>/dev/null)
case "$outp" in *MIIEdata*) ok=0 ;; esac
case "$outp" in "k [REDACTED:pem]"*" z") ;; *) ok=0 ;; esac
inu=$(printf 'k %s\nQQQ\nRRR' "$PEM_B")
case "$(printf '%s' "$inu" | bash "$REDACT" 2>/dev/null)" in *QQQ*|*RRR*) ok=0 ;; esac
[ "$ok" -eq 1 ] && pass "T7.c private·PEM 구간 제거" || fail "T7.c" "out=$out | pem=$outp"

# T7.d 오탐 완화 + 멱등 (AC-9)
in="password=x secret: s3 api_key=$VQ token=abcd tk=\$TOKEN api_key={{KEY}} password=[REDACTED:kv]"
o1=$(printf '%s' "$in" | bash "$REDACT" 2>/dev/null)
o2=$(printf '%s' "$o1" | bash "$REDACT" 2>/dev/null)
ok=1
case "$o1" in *"password=[REDACTED:kv] secret: [REDACTED:kv] api_key=[REDACTED:kv] token=abcd tk=\$TOKEN api_key={{KEY}} password=[REDACTED:kv]") ;; *) ok=0 ;; esac
[ "$o1" = "$o2" ] || ok=0
[ "$ok" -eq 1 ] && pass "T7.d 키별 최소 길이·플레이스홀더 제외·멱등" || fail "T7.d" "o1=$o1"

# T7.e oversize — 스캔 없이 대체, 시간 상한 (AC-7)
big="$TMP/big.txt"; yes "$K_AWS token=$VQ" | head -c 1100000 > "$big"
t0=$(date +%s); out=$(bash "$REDACT" < "$big" 2>/dev/null); rc=$?; t1=$(date +%s)
[ "$rc" -eq 0 ] && [ "$out" = "[REDACTED:oversize]" ] && [ $((t1-t0)) -le 10 ] \
  && pass "T7.e 1.1MB oversize 대체" || fail "T7.e" "rc=$rc out=${out:0:40} sec=$((t1-t0))"

# T7.f 상한 이하·매치 수만 건도 선형 시간 (AC-7)
mid="$TMP/mid.txt"; yes "$K_AWS token=$VQ" | head -c 900000 > "$mid"
t0=$(date +%s); out=$(bash "$REDACT" < "$mid" 2>/dev/null); rc=$?; t1=$(date +%s)
case "$out" in *"$K_AWS"*) leak=1 ;; *) leak=0 ;; esac
[ "$rc" -eq 0 ] && [ "$leak" -eq 0 ] && [ -n "$out" ] && [ $((t1-t0)) -le 10 ] \
  && pass "T7.f 900KB 다수 매치 선형 시간" || fail "T7.f" "rc=$rc leak=$leak sec=$((t1-t0))"

# T7.g --max — 글자 단위 절단(한글 안 깨짐) + 마스킹 뒤에 자른다 (FR-6)
out=$(printf '%s' "$(rep 20 가)" | bash "$REDACT" --max 5 2>/dev/null)
ok=1; [ "$out" = "가가가가가…[TRUNCATED]" ] || ok=0
out2=$(printf '%s%s' "$(rep 7 x)" "$K_AWS" | bash "$REDACT" --max 12 2>/dev/null)
case "$out2" in *AKIA*) ok=0 ;; esac
[ "$ok" -eq 1 ] && pass "T7.g --max 글자 절단·선마스킹" || fail "T7.g" "out=$out out2=$out2"

# T7.h 평범한 입력은 바이트 단위 보존(개행 유무 포함) — 단어 속 sk-·Basic·secretary·PWD·total_tokens·평문 Authorization·환경변수 참조 음성 케이스
plain='평범한 한글 문장입니다 commit 0123456789abcdef0123456789abcdef01234567 token 이야기와 password 설명 task-20261001-redact-capture risk-adjusted-returns-for-the-quarter Basic authentication secretary: Kim PWD=/Users/x total_tokens: 15000000 Authorization: required passwords: 3개 password=$TOKEN password=${TOKEN} api_key={{KEY}}'
ok=1
printf '%s' "$plain" | bash "$REDACT" 2>/dev/null | cmp -s - <(printf '%s' "$plain") || ok=0
printf 'a\nb\n' | bash "$REDACT" 2>/dev/null | cmp -s - <(printf 'a\nb\n') || ok=0
[ "$ok" -eq 1 ] && pass "T7.h 평범한 입력 바이트 보존" || fail "T7.h"

# T7.i 마스킹 불가 → rc 3·stdout 비움: 패턴 파일 부재, 패턴 문법 오류(sed 실패) · 인자 오류 rc 2 (FR-1 · AC-6)
np="$TMP/np"; mkdir -p "$np"; cp "$REDACT" "$np/redact.sh" 2>/dev/null   # 패턴 파일은 일부러 복사하지 않는다
out=$(printf 'x' | bash "$np/redact.sh" 2>/dev/null); rc=$?
np2="$TMP/np2"; mkdir -p "$np2"; cp "$REDACT" "$np2/redact.sh" 2>/dev/null; printf 's/(/x/\n' > "$np2/redact-patterns.sed"
out2=$(printf 'x' | bash "$np2/redact.sh" 2>/dev/null); rc3=$?
bash "$REDACT" --max abc </dev/null >/dev/null 2>&1; rc2=$?
[ "$rc" -eq 3 ] && [ -z "$out" ] && [ "$rc3" -eq 3 ] && [ -z "$out2" ] && [ "$rc2" -eq 2 ] \
  && pass "T7.i 패턴 부재·문법 오류 rc3·인자 오류 rc2" || fail "T7.i" "rc=$rc rc3=$rc3 rc2=$rc2"

# T7.j jq 부재 — --max 는 rc 3(fail-closed), --max 없으면 jq 불필요 (Q3)
nj="$TMP/nojq-bin"; mkdir -p "$nj"
for t in wc tr od awk sed mktemp tail head cat cp rm dirname; do ln -sf "$(command -v "$t")" "$nj/$t"; done
out=$(printf 'abcdef' | PATH="$nj" /bin/bash "$REDACT" --max 3 2>/dev/null); rc=$?
out2=$(printf 'abcdef' | PATH="$nj" /bin/bash "$REDACT" 2>/dev/null); rc2=$?
[ "$rc" -eq 3 ] && [ -z "$out" ] && [ "$rc2" -eq 0 ] && [ "$out2" = "abcdef" ] \
  && pass "T7.j jq 부재: --max rc3 · 무상한 통과" || fail "T7.j" "rc=$rc rc2=$rc2 out2=$out2"

# T7.k --last-line — 마스킹이 끝난 뒤 마지막 줄만 남긴다: 줄 자르기가 앞서면 여러 줄 private 구간이 샌다 (FR-6·AC-4 선행)
in=$(printf 'a %sS1\nS2%s end' "$PRIV_O" "$PRIV_C")
out=$(printf '%s\n' "$in" | bash "$REDACT" --last-line 2>/dev/null)
[ "$out" = " end" ] && pass "T7.k --last-line 마스킹 뒤 마지막 줄" || fail "T7.k" "out=$out"

# T7.l 한 줄에 private 태그·PEM 블록이 수만 개여도 선형 시간 (AC-7) — 구간 제거 루프가 매번 나머지를 되복사하면 이차(실측 3.2만 개 60초 초과)
bounded() { if command -v perl >/dev/null 2>&1; then perl -e 'alarm 20; exec @ARGV' "$@"; else "$@"; fi; }
pv="$TMP/pv.txt"; yes "${PRIV_O}PRIVPAYLOAD${PRIV_C} k" | head -c 600000 | tr -d '\n' > "$pv"   # 개행 없는 한 줄
t0=$(date +%s); out=$(bounded bash "$REDACT" < "$pv" 2>/dev/null); rc=$?; t1=$(date +%s)
pe="$TMP/pe.txt"; yes "$PEM_B abc $PEM_E k" | head -c 900000 | tr -d '\n' > "$pe"
t2=$(date +%s); out2=$(bounded bash "$REDACT" < "$pe" 2>/dev/null); rc2=$?; t3=$(date +%s)
ok=1
[ "$rc" -eq 0 ] && [ $((t1-t0)) -le 5 ] || ok=0
case "$out" in *PRIVPAYLOAD*) ok=0 ;; esac
[ "$rc2" -eq 0 ] && [ $((t3-t2)) -le 3 ] || ok=0
case "$out2" in *abc*) ok=0 ;; esac
[ "$ok" -eq 1 ] && pass "T7.l 한 줄 태그·PEM 수만 개 선형 시간" || fail "T7.l" "rc=$rc rc2=$rc2 sec1=$((t1-t0)) sec2=$((t3-t2))"

# T7.m 따옴표 값 — 이스케이프 따옴표 뒤 꼬리·닫는 따옴표 없는 값(잘린 붙여넣기)도 마스킹, 플레이스홀더·짧은 약한 키 값은 불변 (AC-2·AC-9 보강, Phase C 지적)
qin=$(printf '%s\n' \
  'password: "has \"esc\" ZQtail"' \
  '{"password":"p\"w ZQjson","user":"bob"}' \
  'password: "ZQunterminated' \
  "token: \"${VQ}" \
  "pass""word='ZQsingle" \
  'redis://:ZQonlypass@host' \
  'password: "abc\"ZQesc2' \
  'password: "\nZQbs' \
  'password: "$TOKEN"' \
  'password: "{{KEY}}"' \
  'token: "abcd"')
qout=$(printf '%s' "$qin" | bash "$REDACT" 2>/dev/null)
ok=1
for v in ZQtail ZQjson ZQunterminated "$VQ" ZQsingle ZQonlypass ZQesc2 ZQbs; do case "$qout" in *"$v"*) ok=0 ;; esac; done
case "$qout" in *'"user":"bob"'*) ;; *) ok=0 ;; esac
case "$qout" in *'password: "$TOKEN"'*'password: "{{KEY}}"'*'token: "abcd"'*) ;; *) ok=0 ;; esac
[ "$(printf '%s' "$qout" | bash "$REDACT" 2>/dev/null)" = "$qout" ] || ok=0
[ "$ok" -eq 1 ] && pass "T7.m 따옴표 값 이스케이프·미닫힘 마스킹" || fail "T7.m" "out=$qout"

# T7.n --max 값 누락 → rc 2 (무한 루프 아님) — bash 3.2 에서 $#=1 일 때 shift 2 가 실패해 루프가 영원히 돈다 (Phase C 지적)
out=$(printf 'abc' | bounded bash "$REDACT" --max 2>/dev/null); rc=$?
[ "$rc" -eq 2 ] && [ -z "$out" ] && pass "T7.n --max 값 누락 rc2" || fail "T7.n" "rc=$rc"

# T7.o 슬래시 없는 호출(cd 후 bash redact.sh)·./ 상대 호출도 패턴 파일을 찾는다 — _src 해석의 두 분기 (verify fix loop 1: 한 줄 case 를 확장으로 바꾼 뒤 이 분기를 지키는 테스트가 없었다)
rd=$(dirname "$REDACT")
o1=$(cd "$rd" && printf 'k %s' "$K_AWS" | bash redact.sh 2>/dev/null); r1=$?
o2=$(cd "$rd" && printf 'k %s' "$K_AWS" | bash ./redact.sh 2>/dev/null); r2=$?
[ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$o1" = "k [REDACTED:aws]" ] && [ "$o2" = "k [REDACTED:aws]" ] \
  && pass "T7.o 슬래시 없는·./ 상대 호출" || fail "T7.o" "r1=$r1 o1=$o1 r2=$r2 o2=$o2"

# ── capture 훅 통합 (AC-4 · AC-6) ──
mk_work() { mkdir -p "$1/.specops"; (cd "$1" && git init -q && git -c user.email=t@t.t -c user.name=t commit --allow-empty -m init -q); echo x > "$1/r.sh"; (cd "$1" && git add r.sh); }
mk_tr() {  # $1=출력 파일 $2=마지막 사용자 프롬프트 — 사용자 발화 뒤에 Edit 이벤트
  jq -cn --arg t "$2" '{type:"user",message:{content:[{type:"text",text:$t}]}}' > "$1"
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"r.sh"}}]}}' >> "$1"
}

# T8.a 여러 줄 private 가 마지막 줄에서 닫히고 키·2000자 초과 한글이 마지막 줄에 있다 — 마스킹은 줄 자르기(tail -1) 앞이어야 한다 (AC-4)
w8="$TMP/w8"; mk_work "$w8"; mk_tr "$TMP/tr8a.jsonl" "앞줄 ${PRIV_O}비밀하나
비밀둘${PRIV_C} 끝 $K_AWS $(rep 2500 한)"
out=$(echo "{\"transcript_path\":\"$TMP/tr8a.jsonl\",\"cwd\":\"$w8\"}" | bash "$HOOK" 2>/dev/null)
P="$w8/.specops/pending-capture.jsonl"
pr=$(jq -r '.prompt' "$P" 2>/dev/null); len=$(jq -r '.prompt|length' "$P" 2>/dev/null)
ok=1
for v in 비밀하나 비밀둘 "$K_AWS"; do case "$pr" in *"$v"*) ok=0 ;; esac; done
case "$pr" in *"…[TRUNCATED]") ;; *) ok=0 ;; esac
[ "${len:-99999}" -le 2000 ] || ok=0
jq -e 'has("redact_failed")|not' "$P" >/dev/null 2>&1 || ok=0
echo "$out" | grep -q '"continue":true' || ok=0
[ "$ok" -eq 1 ] && pass "T8.a private 마지막 줄 닫힘·키·2000자 절단 (마스킹→줄→절단 순서)" || fail "T8.a" "len=$len out=$out pr=${pr:0:60}"

# T8.e 절단 경계 — 본문 1988자(=2000-표식 12)는 손실 없음이라 표식 없이 그대로, 1989자부터 절단 표식 포함 총 2000자 (AC-4 · 끝 개행 계수 off-by-one)
w8e="$TMP/w8e"; mk_work "$w8e"; mk_tr "$TMP/tr8e.jsonl" "$(rep 1988 한)"
echo "{\"transcript_path\":\"$TMP/tr8e.jsonl\",\"cwd\":\"$w8e\"}" | bash "$HOOK" >/dev/null 2>&1
Pe="$w8e/.specops/pending-capture.jsonl"
le1=$(jq -r '.prompt|length' "$Pe" 2>/dev/null); te1=$(jq -r '.prompt|endswith("…[TRUNCATED]")' "$Pe" 2>/dev/null)
w8f="$TMP/w8f"; mk_work "$w8f"; mk_tr "$TMP/tr8f.jsonl" "$(rep 1989 한)"
echo "{\"transcript_path\":\"$TMP/tr8f.jsonl\",\"cwd\":\"$w8f\"}" | bash "$HOOK" >/dev/null 2>&1
Pf="$w8f/.specops/pending-capture.jsonl"
le2=$(jq -r '.prompt|length' "$Pf" 2>/dev/null); te2=$(jq -r '.prompt|endswith("…[TRUNCATED]")' "$Pf" 2>/dev/null)
[ "$le1" = "1988" ] && [ "$te1" = "false" ] && [ "$le2" = "2000" ] && [ "$te2" = "true" ] \
  && pass "T8.e 1988자는 그대로·1989자는 절단 총 2000자" || fail "T8.e" "1988→len=$le1 trunc=$te1 · 1989→len=$le2 trunc=$te2"

# T8.b 평범한 프롬프트는 그대로 · 필드 집합 불변 (AC-4)
w8b="$TMP/w8b"; mk_work "$w8b"; mk_tr "$TMP/tr8b.jsonl" "이 버그 고쳐줘 commit 0123456789abcdef0123456789abcdef01234567"
echo "{\"transcript_path\":\"$TMP/tr8b.jsonl\",\"cwd\":\"$w8b\"}" | bash "$HOOK" >/dev/null 2>&1
Pb="$w8b/.specops/pending-capture.jsonl"
[ "$(jq -r '.prompt' "$Pb" 2>/dev/null)" = "이 버그 고쳐줘 commit 0123456789abcdef0123456789abcdef01234567" ] \
  && [ "$(jq -c 'keys' "$Pb" 2>/dev/null)" = '["fid","files","prompt","ts","type"]' ] \
  && pass "T8.b 평범한 프롬프트 불변·필드 집합 불변" || fail "T8.b" "$(cat "$Pb" 2>/dev/null | head -c 200)"

# T8.c 패턴 파일 없는 플러그인 사본 — prompt 비움 + redact_failed + 실패 로그 1줄(원문 없음) + continue:true (AC-6)
pl="$TMP/plug"; mkdir -p "$pl/hooks" "$pl/scripts/_internal"
cp "$PLUGIN/hooks/freecomment-capture.sh" "$PLUGIN/hooks/governance-lib.sh" "$pl/hooks/" 2>/dev/null
cp "$REDACT" "$pl/scripts/_internal/" 2>/dev/null   # 패턴 파일은 일부러 복사하지 않는다
w8c="$TMP/w8c"; mk_work "$w8c"; mk_tr "$TMP/tr8c.jsonl" "고쳐줘 $K_AWS"
out=$(echo "{\"transcript_path\":\"$TMP/tr8c.jsonl\",\"cwd\":\"$w8c\"}" | bash "$pl/hooks/freecomment-capture.sh" 2>/dev/null)
Pc="$w8c/.specops/pending-capture.jsonl"; L="$w8c/.specops/redact-failures.log"
ok=1
[ "$(jq -r '.prompt' "$Pc" 2>/dev/null)" = "" ] || ok=0
[ "$(jq -r '.redact_failed' "$Pc" 2>/dev/null)" = "true" ] || ok=0
[ "$(jq -r '.files[0]' "$Pc" 2>/dev/null)" = "r.sh" ] || ok=0
grep -q "$K_AWS" "$Pc" 2>/dev/null && ok=0
[ "$(wc -l < "$L" 2>/dev/null | tr -d ' ')" = "1" ] || ok=0
grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z freecomment-capture$' "$L" 2>/dev/null || ok=0
echo "$out" | grep -q '"continue":true' || ok=0
[ "$ok" -eq 1 ] && pass "T8.c 마스킹 불가 → prompt 폐기·redact_failed·로그 1줄" || fail "T8.c" "out=$out pend=$(head -c 160 "$Pc" 2>/dev/null)"

# T8.d 실패 로그가 symlink 면 write-through 거부 — 레코드는 남고 훅은 continue:true (#144 대칭)
w8d="$TMP/w8d"; od8="$TMP/outside8d"; mk_work "$w8d"; mkdir -p "$w8d/.specops" "$od8"
ln -s "$od8/leak.log" "$w8d/.specops/redact-failures.log"
mk_tr "$TMP/tr8d.jsonl" "고쳐줘 $K_AWS"
out=$(echo "{\"transcript_path\":\"$TMP/tr8d.jsonl\",\"cwd\":\"$w8d\"}" | bash "$pl/hooks/freecomment-capture.sh" 2>/dev/null)
echo "$out" | grep -q '"continue":true' && [ ! -e "$od8/leak.log" ] && [ -s "$w8d/.specops/pending-capture.jsonl" ] \
  && pass "T8.d 로그 symlink write 거부" || fail "T8.d" "out=$out leak=$([ -e "$od8/leak.log" ] && echo yes || echo no)"
# T9 관할 한정 — .specops 없는 저장소에서는 자유작업을 캡처하지 않는다.
#   왜: pending 을 쓰려고 .specops/ 를 만들면 그 저장소가 관할로 편입되고, 다음 세션 시작에
#   "미기록 자유작업" 처리 지시가 주입된다 — 플러그인을 쓰지 않는 저장소에서.
w9="$TMP/w9"; mkdir -p "$w9"
(cd "$w9" && git init -q && git -c user.email=test@specops.test -c user.name=test commit --allow-empty -m init -q)
echo "x" > "$w9/foo.sh"; (cd "$w9" && git add foo.sh)
printf '%s\n' \
  '{"type":"user","message":{"content":[{"type":"text","text":"이 버그 고쳐줘"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"foo.sh"}}]}}' > "$TMP/tr9.jsonl"
out=$(echo "{\"transcript_path\":\"$TMP/tr9.jsonl\",\"cwd\":\"$w9\"}" | bash "$HOOK" 2>/dev/null)
echo "$out" | grep -q '"continue":true' && [ ! -e "$w9/.specops" ] \
  && pass "T9.a .specops 부재 → 캡처 없음·디렉토리 미생성" || fail "T9.a" "out=$out .specops=$([ -e "$w9/.specops" ] && echo yes || echo no)"
# T9.b 대조 — 같은 입력에 .specops 만 있으면 캡처한다 (가드가 도입 저장소를 막지 않는다)
mkdir -p "$w9/.specops"
out=$(echo "{\"transcript_path\":\"$TMP/tr9.jsonl\",\"cwd\":\"$w9\"}" | bash "$HOOK" 2>/dev/null)
[ -s "$w9/.specops/pending-capture.jsonl" ] \
  && pass "T9.b .specops 존재 → 캡처" || fail "T9.b" "out=$out"
# T9.c 하위 디렉토리 cwd 세션 — 프로젝트 루트에 .specops 가 있으면 루트에 캡처한다 (중첩 디렉토리를 만들지 않는다)
w9c="$TMP/w9c"; mkdir -p "$w9c/.specops" "$w9c/src"
(cd "$w9c" && git init -q && git -c user.email=test@specops.test -c user.name=test commit --allow-empty -m init -q)
echo "x" > "$w9c/src/foo.sh"; (cd "$w9c" && git add src/foo.sh)
printf '%s\n' \
  '{"type":"user","message":{"content":[{"type":"text","text":"이 버그 고쳐줘"}]}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Edit\",\"input\":{\"file_path\":\"$w9c/src/foo.sh\"}}]}}" > "$TMP/tr9c.jsonl"
out=$(echo "{\"transcript_path\":\"$TMP/tr9c.jsonl\",\"cwd\":\"$w9c/src\"}" | CLAUDE_PROJECT_DIR="$w9c" bash "$HOOK" 2>/dev/null)
[ -s "$w9c/.specops/pending-capture.jsonl" ] && [ ! -e "$w9c/src/.specops" ] \
  && [ "$(jq -r '.files[0]' "$w9c/.specops/pending-capture.jsonl" 2>/dev/null)" = "src/foo.sh" ] \
  && pass "T9.c 하위 cwd → 루트에 캡처(경로는 루트 기준)" || fail "T9.c" "out=$out pend=$(cat "$w9c/.specops/pending-capture.jsonl" 2>/dev/null) nested=$([ -e "$w9c/src/.specops" ] && echo yes || echo no)"
# T10 캡처를 끌 수 있다 — 설정 파일 · 프로파일 (종전엔 이 훅만 킬스위치를 보지 않았다: 사용자 입력을 저장하는 훅인데)
w10="$TMP/w10"; mkdir -p "$w10/.specops"
(cd "$w10" && git init -q && git -c user.email=test@specops.test -c user.name=test commit --allow-empty -m init -q)
echo "x" > "$w10/foo.sh"; (cd "$w10" && git add foo.sh)
_in10="{\"transcript_path\":\"$TMP/tr9.jsonl\",\"cwd\":\"$w10\"}"
out=$(echo "$_in10" | SPECOPS_GOVERNANCE_PROFILE=minimal bash "$HOOK" 2>/dev/null)
echo "$out" | grep -q '"continue":true' && [ ! -e "$w10/.specops/pending-capture.jsonl" ] \
  && pass "T10.a 프로파일 minimal → 캡처 없음" || fail "T10.a" "out=$out"
out=$(echo "$_in10" | SPECOPS_GOVERNANCE_PROFILE=standard bash "$HOOK" 2>/dev/null)
[ ! -e "$w10/.specops/pending-capture.jsonl" ] && pass "T10.b 프로파일 standard → 캡처 없음" || fail "T10.b" "out=$out"
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
  printf 'hooks:\n  freecomment-capture: { enabled: false }\n' > "$w10/.specops/config.yaml"
  # 훅 프로세스의 cwd 는 그 저장소가 아니다 — 설정은 입력의 cwd 에서 읽어야 한다
  out=$(cd "$TMP" && echo "$_in10" | bash "$HOOK" 2>/dev/null)
  [ ! -e "$w10/.specops/pending-capture.jsonl" ] && pass "T10.c 설정 파일로 끔(훅 cwd 가 달라도) → 캡처 없음" || fail "T10.c" "out=$out"
  printf 'hooks:\n  pretool-governance: { enabled: false }\n' > "$w10/.specops/config.yaml"
  out=$(cd "$TMP" && echo "$_in10" | bash "$HOOK" 2>/dev/null)
  [ -s "$w10/.specops/pending-capture.jsonl" ] && pass "T10.d 다른 훅만 끈 설정 → 캡처는 그대로" || fail "T10.d" "out=$out"
  rm -f "$w10/.specops/config.yaml" "$w10/.specops/pending-capture.jsonl"
else
  echo "SKIP T10.c·d (python3+pyyaml 부재)"
fi
out=$(echo "$_in10" | bash "$HOOK" 2>/dev/null)
[ -s "$w10/.specops/pending-capture.jsonl" ] && pass "T10.e 대조 — 설정·프로파일 없음(기본) → 캡처" || fail "T10.e" "out=$out"
echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
