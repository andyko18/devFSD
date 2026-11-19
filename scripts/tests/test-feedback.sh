#!/usr/bin/env bash
# test-feedback.sh — scripts/feedback.sh (사용 요약·상태·초안·제출)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않는다
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
FB="$PLUGIN/scripts/feedback.sh"
ok() { PASS=$((PASS+1)); echo "PASS $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL $1 — ${2:-}"; }
has() { printf '%s' "$1" | grep -qF -- "$2"; }

T=$(mktemp -d) || exit 1; T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT

# ── 픽스처: 실제 하류 구조(.specops/<FID>/… + session-progress.md)를 흉내낸다. 금지 항목을 일부러 심는다 ──
#   금지 = FID 이름·요청 문장·파일 경로·프로젝트 이름·코드·차단된 명령 원문·리뷰 지적 본문
P="$T/SECRETPROJ"; S="$P/.specops"; mkdir -p "$P/backend" "$S"
TODAY=$(date +%Y%m%d); DASH=$(date +%Y-%m-%d)
B="$TODAY-alpha-basic"; F="$TODAY-bravo-full"; R="$TODAY-charlie-promoted"; Q="$TODAY-delta-quick"; OLD="20200101-old-full"
mkdir -p "$S/$B/reviews" "$S/$F/reviews" "$S/$R/basic-draft" "$S/$Q" "$S/$OLD"
echo "# spec SECRET_REQUEST_TEXT" > "$S/$B/spec.md"
echo "# spec" > "$S/$F/spec.md"; echo "# intent" > "$S/$F/intent.md"
echo "# spec" > "$S/$R/spec.md"; echo "# intent" > "$S/$R/intent.md"
echo "# tasks" > "$S/$Q/tasks.md"
echo "# spec" > "$S/$OLD/spec.md"; echo "# intent" > "$S/$OLD/intent.md"
echo "지적: SECRET_REVIEW_BODY src/secret/Path.java" > "$S/$B/reviews/T1-B-report.md"
echo "x" > "$S/$B/reviews/T1-C-report.md"; echo "x" > "$S/$F/reviews/T1-C-report.md"
cat > "$S/$F/friction-log.jsonl" <<EOF
{"ts":"2026-11-17T01:00:00Z","fid":"$F","rule_id":"R-1","principle":5,"severity":"block","evidence_snippet":"git commit -m SECRET_COMMAND /Users/secret/path","transcript_offset":0}
{"ts":"2026-11-17T02:00:00Z","fid":"$F","rule_id":"R-1","principle":5,"severity":"block","evidence_snippet":"x","transcript_offset":0}
{"ts":"2026-11-17T03:00:00Z","fid":"$F","rule_id":"R-2","principle":5,"severity":"warn","evidence_snippet":"x","transcript_offset":0}
EOF
cat > "$S/$F/metrics.jsonl" <<EOF
{"schema_version":2,"ts":"x","fid":"$F","task":null,"phase":"verify","model":null,"wall_ms":1,"retry_count":0,"fallback":false,"verdict":"PASS","finding_severity":null}
{"schema_version":2,"ts":"x","fid":"$F","task":null,"phase":"verify","model":null,"wall_ms":1,"retry_count":0,"fallback":false,"verdict":"FAIL","finding_severity":null}
{"schema_version":2,"ts":"x","fid":"$F","task":null,"phase":"governance-bypass","model":null,"wall_ms":null,"retry_count":0,"fallback":true,"verdict":null,"finding_severity":null}
EOF
cat > "$S/session-progress.md" <<EOF
# 진행 기록

## $F · SECRET_TITLE 풀 작업
- $DASH 10:40 /plan 완료 (plan.md SECRET_NOTE)
- $DASH 10:00 /specify 완료 (spec.md)

## $B · 기본 작업
- $DASH 09:30 /lifecycle DONE (/basic — SECRET_REQUEST_TEXT 커밋 abc1234)
- $DASH 09:10 /implement 완료 (주 세션)
- $DASH 09:00 /basic 시작 (SECRET_REQUEST_TEXT)

## $R · 승격
- $DASH 08:12 /demo DONE (x)
- $DASH 08:00 /basic 시작 (x)

## $Q · quick
- $DASH 07:05 /lifecycle DONE (/quick-fix)
- $DASH 07:00 /quick-fix 시작 (x)

## $OLD · 옛 작업
- 2020-01-01 10:30 /lifecycle DONE (x)
- 2020-01-01 10:00 /specify 완료 (x)

## 활용 방법
- 예: \`2026-04-20 12:00 /analyze BLOCK (analysis.md)\`
EOF
_fb() { (cd "$P" && bash "$FB" "$@" 2>&1); }

# ── F1 사용 요약 — 갈래·끝냄·소요·중단 지점·차단·검증·리뷰 ──
out=$(_fb summary); rc=$?
[ "$rc" = 0 ] && has "$out" "- 작업 수: 4" && ok "F1.a 최근 30일 — 오늘 작업 4건만 센다(2020 작업 제외)" || no "F1.a" "rc=$rc $out"
has "$out" "| 기본 | 1 | 1 | 1 | 30 |" && ok "F1.b 기본: 1건 · 끝냄 1 · 소요 30분(09:00→09:30)" || no "F1.b" "$out"
has "$out" "| 풀 | 1 | 1 | 0 | 40 |" && ok "F1.c 풀: 끝내지 못함 · 40분" || no "F1.c" "$out"
has "$out" "| 기본→풀 승격 | 1 | 1 | 0 | 12 |" && ok "F1.d 승격(basic-draft 폴더가 있다)은 따로 센다" || no "F1.d" "$out"
has "$out" "| quick-fix | 1 | 1 | 1 | 5 |" && ok "F1.e quick-fix(명세 없이 태스크 문서만)" || no "F1.e" "$out"
has "$out" '| `/plan` | 1 |' && has "$out" '| `/demo` | 1 |' && ok "F1.f 끝내지 못한 작업의 마지막 단계 — 명령 이름만" || no "F1.f" "$out"
has "$out" "| R-1 | block | 2 |" && has "$out" "| R-2 | warn | 1 |" && ok "F1.g 규칙별 차단·경고 횟수" || no "F1.g" "$out"
has "$out" "검증 실행: 통과 1 · 실패 1" && has "$out" "훅 우회(BYPASS): 1" && has "$out" "리뷰 보고서: 스펙 1 · 코드 2" && ok "F1.h 검증·우회·리뷰 보고서 수" || no "F1.h" "$out"
out0=$(_fb summary --days 0)
has "$out0" "- 작업 수: 5" && has "$out0" "| 풀 | 2 | 2 | 1 |" && ok "F1.i --days 0 = 전체(2020 작업 포함)" || no "F1.i" "$out0"
out=$(_fb summary --days x); rc=$?
[ "$rc" = 2 ] && ok "F1.j --days 에 숫자가 아니면 rc 2" || no "F1.j" "rc=$rc $out"

# ── F2 하위 폴더에서 불러도 저장소 최상위의 .specops 를 찾는다 (12회차 평가: 하위 폴더에서 스크립트끼리 판정이 갈렸다) ──
cat > "$T/mk.sh" <<'MK'
cd "$1" && git init -q -b main . && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
MK
bash "$T/mk.sh" "$P"
out=$(cd "$P/backend" && bash "$FB" summary 2>&1); rc=$?
[ "$rc" = 0 ] && has "$out" "- 작업 수: 4" && ok "F2.a 하위 폴더 호출 → 최상위 .specops" || no "F2.a" "rc=$rc $out"
E="$T/empty"; mkdir -p "$E"
out=$(cd "$E" && bash "$FB" summary 2>&1); rc=$?
[ "$rc" = 3 ] && has "$out" ".specops 가 없다" && ok "F2.b .specops 없음 → rc 3 + 안내(만들지 않는다)" || no "F2.b" "rc=$rc $out"
[ ! -e "$E/.specops" ] && ok "F2.c 요약은 아무것도 만들지 않는다" || no "F2.c"

# ── F3 ★ 공개하면 안 되는 것이 summary·context 에 실리지 않는다 ──
#   변이: evidence_snippet 을 출력에 더하거나, 단계 이름 대신 진행 줄 전체를 내거나, FID 를 표에 넣으면 여기서 떨어진다.
all="$(_fb summary --days 0)
$(_fb context)"
leak=""
for w in SECRET_REQUEST_TEXT SECRET_TITLE SECRET_NOTE SECRET_COMMAND SECRET_REVIEW_BODY SECRETPROJ "/Users/secret" "Path.java" "abc1234" alpha-basic bravo-full charlie-promoted delta-quick old-full "$T"; do
  has "$all" "$w" && leak="$leak $w"
done
[ -z "$leak" ] && ok "F3.a ★ 요약·상태에 작업 이름·요청 문장·경로·프로젝트 이름·명령 원문·리뷰 본문이 없다" || no "F3.a" "새어 나감:$leak"
# 한글·영문 낱말이 든 줄은 정해진 틀뿐이다 — 틀 밖의 자유 글이 한 줄도 없어야 한다
free=$(printf '%s\n' "$all" | grep -vE '^(#|$|\||- (플러그인 버전|환경|기간|작업 수|검증 실행|훅 우회|리뷰 보고서|최근 작업의 갈래|최근 작업의 마지막 단계|최근 차단 규칙)|끝냄·소요는 진행 기록이|worktree 에서 불렀다|없음$)' || true)
[ -z "$free" ] && ok "F3.b 출력 줄은 전부 정해진 틀이다(자유 글 0줄)" || no "F3.b" "$free"

# ── F3.c~ ★ 손으로 고친·깨진 기록 — 읽은 글자를 그대로 내보내는 자리가 없다(목록에 있는 이름만, 나머지는 `(기타)`) ──
#   변이: _stage_safe·_rule_safe·_sev_safe 호출을 빼거나 KNOWN_* 검사를 통과로 바꾸면 여기서 떨어진다(독립 리뷰가 낸 변이 4종).
A="$T/adv"; AS="$A/.specops"; mkdir -p "$AS"
AF="$TODAY-adv-one"; AG="$TODAY-adv-two"; mkdir -p "$AS/$AF/reviews" "$AS/$AG" "$T/outside"
echo "# spec" > "$AS/$AF/spec.md"; echo "# spec" > "$AS/$AG/spec.md"
: > "$AS/$AF/reviews/SECRETFILE-B-report.md"
cat > "$AS/session-progress.md" <<EOF
## $AF · x
- $DASH 10:00 /secretword 진행 (x)
## $AG · x
- $DASH 11:00 /a/b/c/secretpath 진행 (x)
- $DASH 10:30 /cmd;rm 진행 (x)
## $AF · 같은 작업의 둘째 절
- $DASH 09:00 /plan 완료 (x)
EOF
cat > "$AS/$AF/friction-log.jsonl" <<EOF
{"ts":"2026-11-17T01:00:00Z","fid":"x","rule_id":"SECRETRULE","principle":5,"severity":"block","evidence_snippet":"x","transcript_offset":0}
{"ts":"TS SECRETTS","fid":"x","rule_id":"R-1","principle":5,"severity":"secretsev","evidence_snippet":"x","transcript_offset":0}
{"severity":"block","rule_id":"../../etc/SECRETPATH","ts":"2026-11-17T02:00:00Z"}
{"ts":"2026-11-17T04:00:00Z","fid":"x","rule_id":"R-1","principle":5,"severity":"secretsev","evidence_snippet":"x","transcript_offset":0}
{"ts":"2026-11-17T03:00:00Z","fid":"x","rule_id":"R-2","principle":5,"severity":"block","evidence_snippet":"x \"rule_id\":\"INJECTED\"","transcript_offset":0}
not json SECRETGARBAGE
EOF
echo '{"ts":"2026-11-17T09:00:00Z","fid":"x","rule_id":"OUTSIDELEAK","principle":5,"severity":"block","evidence_snippet":"x","transcript_offset":0}' > "$T/outside/friction-log.jsonl"
echo "# spec" > "$T/outside/spec.md"
ln -s "$T/outside" "$AS/$TODAY-adv-link"
_adv() { (cd "$A" && bash "$FB" "$@" 2>&1); }
adv="$(_adv summary --days 0)
$(_adv context)"
leak=""
for w in secretword secretpath "cmd" SECRETRULE SECRETTS secretsev SECRETPATH INJECTED SECRETGARBAGE OUTSIDELEAK SECRETFILE adv-one adv-two adv-link; do
  has "$adv" "$w" && leak="$leak $w"
done
[ -z "$leak" ] && ok "F3.c ★ 가짜 단계·규칙·종류·시각·링크 폴더·파일 이름이 출력에 없다" || no "F3.c" "새어 나감:$leak
$adv"
has "$adv" '| `(기타)` | 2 |' && ok "F3.d 목록에 없는 단계는 (기타) 로 센다" || no "F3.d" "$adv"
has "$adv" "| (기타) | block |" && has "$adv" "| R-1 | (기타) | 1 |" && has "$adv" "| R-2 | block | 1 |" && ok "F3.e 목록에 없는 규칙·종류는 (기타) · 아는 규칙은 그대로" || no "F3.e" "$adv"
has "$adv" "- 작업 수: 2" && ok "F3.f 링크로 된 작업 폴더는 세지 않는다(바깥을 읽지 않는다)" || no "F3.f" "$adv"
has "$adv" "| 기본 | 2 | 2 | 0 | 45 |" && ok "F3.g 같은 작업의 절이 둘이어도 한 작업으로 합친다(09:00~10:00 = 60분 · 30분 → 중앙 45)" || no "F3.g" "$adv"
free=$(printf '%s\n' "$adv" | grep -vE '^(#|$|\||- (플러그인 버전|환경|기간|작업 수|검증 실행|훅 우회|리뷰 보고서|최근 작업의 갈래|최근 작업의 마지막 단계|최근 차단 규칙)|끝냄·소요는 진행 기록이|worktree 에서 불렀다|없음$)' || true)
[ -z "$free" ] && ok "F3.h 깨진 기록에서도 출력 줄은 전부 정해진 틀이다" || no "F3.h" "$free"
# jq 가 없을 때의 읽기 경로도 같은 약속을 지킨다
NOJQ="$T/nojq"; mkdir -p "$NOJQ"
for b in bash sh awk sed grep sort uniq head tail cut tr cat ls date uname mktemp rm mkdir dirname basename git wc printf; do
  p=$(command -v "$b" 2>/dev/null) && [ -x "$p" ] && ln -sf "$p" "$NOJQ/$b"
done
advn=$(cd "$A" && PATH="$NOJQ" bash "$FB" summary --days 0 2>&1)
leak=""
for w in SECRETRULE SECRETTS secretsev SECRETPATH INJECTED SECRETGARBAGE OUTSIDELEAK; do has "$advn" "$w" && leak="$leak $w"; done
[ -z "$leak" ] && has "$advn" "| R-2 | block | 1 |" && ok "F3.i jq 없이도 같은 약속(정해진 필드 순서의 줄만 읽는다)" || no "F3.i" "새어 나감:$leak
$advn"

# ── F4 상태 ──
out=$(_fb context)
has "$out" "최근 작업의 갈래: 풀" && has "$out" '마지막 단계: `/plan`' && ok "F4.a 맨 위(최근) 작업의 갈래와 마지막 단계" || no "F4.a" "$out"
has "$out" "최근 차단 규칙(최대 5): R-1 R-1" && ok "F4.b 최근 차단 규칙 번호(경고는 빼고)" || no "F4.b" "$out"
out=$(cd "$E" && bash "$FB" context 2>&1); rc=$?
[ "$rc" = 0 ] && has "$out" "플러그인 버전:" && has "$out" "(기록 없음)" && ok "F4.c .specops 가 없어도 버전·환경은 낸다" || no "F4.c" "rc=$rc $out"

# ── F5 초안 ──
out=$(_fb draft "승인 질문이 두 번 나와 번거로웠다"); rc=$?
d=$(printf '%s\n' "$out" | sed -n 's/^DRAFT: //p')
[ "$rc" = 0 ] && [ -f "$d" ] && ok "F5.a 초안 파일을 만든다" || no "F5.a" "rc=$rc $out"
case "$d" in "$S/feedback/"*) ok "F5.b 초안은 .specops/feedback/ 아래(저장소에 실리지 않는 곳)" ;; *) no "F5.b" "$d" ;; esac
body=$(cat "$d" 2>/dev/null)
has "$body" "title: [feedback] 승인 질문이 두 번 나와 번거로웠다" && has "$body" "## 겪은 일" && has "$body" "## 상태" && ! has "$body" "## 사용 요약" \
  && ok "F5.c 제목 줄 · 겪은 일 · 상태 (요약은 청할 때만)" || no "F5.c" "$body"
has "$out" "공개 저장소" && ok "F5.d 올라갈 곳이 공개 저장소임을 알린다" || no "F5.d" "$out"
! has "$out" "WARN:" && ok "F5.e 깨끗한 본문에는 경고가 없다" || no "F5.e" "$out"
out=$(_fb draft "느렸다" --summary); d2=$(printf '%s\n' "$out" | sed -n 's/^DRAFT: //p')
has "$(cat "$d2" 2>/dev/null)" "## 사용 요약" && ok "F5.f --summary 면 사용 요약을 붙인다" || no "F5.f" "$out"
out=$(_fb draft "로그는 /Users/me/proj/x.log 에 있다 https://corp.example/y me@corp.example token=abcd1234")
n=$(printf '%s\n' "$out" | grep -c '^WARN:')
[ "$n" = 4 ] && ok "F5.g ★ 본문의 경로·주소·메일·비밀 값을 각각 경고한다(4건)" || no "F5.g" "n=$n $out"
out=$(_fb draft "   "); rc=$?
[ "$rc" = 2 ] && ok "F5.h 빈 본문 → rc 2" || no "F5.h" "rc=$rc $out"
out=$(_fb draft 'a `touch '"$T"'/pwned` $(touch '"$T"'/pwned2) b'); rc=$?
[ "$rc" = 0 ] && [ ! -e "$T/pwned" ] && [ ! -e "$T/pwned2" ] && ok "F5.i 본문 속 백틱·\$( ) 는 실행되지 않는다" || no "F5.i" "rc=$rc"
long=$(printf '가%.0s' $(seq 1 100))
out=$(_fb draft "$long"); d3=$(printf '%s\n' "$out" | sed -n 's/^DRAFT: //p')
t=$(sed -n '1s/^title: \[feedback\] //p' "$d3")
#   글자 단위로 잘랐으면 "가" 60개 + … 이고, UTF-8 로케일이 없는 환경이면 자르지 않는다 — 어느 쪽이든 글자가 반으로 갈리지 않는다
want60="$(printf '가%.0s' $(seq 1 60))…"
{ [ "$t" = "$want60" ] || [ "$t" = "$long" ]; } && ok "F5.j 긴 본문의 제목은 60자에서 글자 단위로 자른다(한글이 반으로 갈리지 않는다)" || no "F5.j" "$t"
out=$(_fb draft "같은 초 하나"); da=$(printf '%s\n' "$out" | sed -n 's/^DRAFT: //p')
out=$(_fb draft "같은 초 둘"); db=$(printf '%s\n' "$out" | sed -n 's/^DRAFT: //p')
[ "$da" != "$db" ] && has "$(cat "$da")" "같은 초 하나" && ok "F5.l 같은 초에 만든 초안이 앞 초안을 덮지 않는다" || no "F5.l" "$da $db"
out=$(cd "$E" && bash "$FB" draft "설치가 안 됐다" 2>&1); rc=$?
d4=$(printf '%s\n' "$out" | sed -n 's/^DRAFT: //p')
[ "$rc" = 0 ] && [ -f "$d4" ] && [ ! -e "$E/.specops" ] && ok "F5.k .specops 가 없으면 임시 폴더에 쓴다(.specops 를 만들지 않는다)" || no "F5.k" "rc=$rc $out"
rm -f "$d4"

[ "$(cat "$S/feedback/.gitignore" 2>/dev/null)" = "*" ] && ok "F5.m ★ 초안 폴더에 .gitignore(*)를 둔다 — .specops 를 추적하는 프로젝트에서 초안이 커밋되지 않는다" || no "F5.m"
cat > "$T/st.sh" <<'ST'
cd "$1" && git add -A >/dev/null 2>&1; git status --porcelain | grep -c 'feedback/.*\.md' || true
ST
[ "$(bash "$T/st.sh" "$P")" = 0 ] && ok "F5.n git add -A 를 해도 초안이 실리지 않는다" || no "F5.n" "$(bash "$T/st.sh" "$P")"
out=$(_fb draft "- 목록으로 시작하는 본문"); rc=$?
[ "$rc" = 0 ] && has "$(cat "$(printf '%s\n' "$out" | sed -n 's/^DRAFT: //p')")" "- 목록으로 시작하는 본문" && ok "F5.o '-' 로 시작하는 본문도 본문이다" || no "F5.o" "rc=$rc $out"
out=$(printf "it's \`x\` \$(touch %s/pwned3) \"q\"\n둘째 줄" "$T" | (cd "$P" && bash "$FB" draft --stdin 2>&1)); rc=$?
ds=$(printf '%s\n' "$out" | sed -n 's/^DRAFT: //p')
[ "$rc" = 0 ] && has "$(cat "$ds")" "it's \`x\`" && has "$(cat "$ds")" "둘째 줄" && [ ! -e "$T/pwned3" ] && ok "F5.p --stdin — 작은따옴표·백틱·여러 줄 본문을 그대로 받는다" || no "F5.p" "rc=$rc $out"
out=$(cd "$E" && bash "$FB" draft "요약 없이도" --summary 2>&1); rc=$?
dq=$(printf '%s\n' "$out" | sed -n 's/^DRAFT: //p')
[ "$rc" = 0 ] && has "$(cat "$dq" 2>/dev/null)" "(사용 요약 없음" && has "$(cat "$dq")" "## 상태" && ok "F5.q ★ .specops 없이 --summary 여도 초안을 끝까지 쓴다(요약 자리에 안내)" || no "F5.q" "rc=$rc $out"
case "$dq" in "$E"/*) no "F5.r" "$dq" ;; *) [ "$(ls -ld "$(dirname "$dq")" | cut -c1-10)" = "drwx------" ] && ok "F5.r .specops 없을 때의 초안 폴더는 나만 읽는다(700)" || no "F5.r" "$(ls -ld "$(dirname "$dq")")" ;; esac
rm -rf "$(dirname "$dq")"
out=$(_fb draft "작업 20261117-secret-task 에서 10.0.0.12 로 postgres://u:p@db/x 접속, Bearer abcdefghijklmnop")
n=$(printf '%s\n' "$out" | grep -c '^WARN:')
[ "$n" = 4 ] && ok "F5.s 작업 이름(FID)·IP·접속 문자열·Bearer 값을 경고한다" || no "F5.s" "n=$n $out"
out=$(_fb draft "risk-assessment-for-customer-tokens 문서를 고쳤다")
! has "$out" "WARN:" && ok "F5.t 하이픈으로 이은 긴 낱말은 비밀 값이 아니다(sk- 오탐 없음)" || no "F5.t" "$out"
out=$(cd "$P" && FEEDBACK_REPO='--web x' bash "$FB" draft "x" 2>&1); rc=$?
[ "$rc" = 2 ] && has "$out" "owner/name" && ok "F5.u 저장소 이름이 꼴이 아니면 rc 2" || no "F5.u" "rc=$rc $out"

# ── F6 제출 — gh 를 가짜로 바꿔 실제 이슈를 만들지 않는다 ──
BIN="$T/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  "auth status") exit "${GH_AUTH_RC:-0}" ;;
  "issue create")
    while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$GH_LOG.body"; shift; done
    case " $* " in *" --label "*) [ "${GH_LABEL_RC:-0}" = 0 ] || { echo "could not add label: feedback not found" >&2; exit 1; } ;; esac
    [ "${GH_CREATE_RC:-0}" = 0 ] && { echo "Creating issue in o/r"; echo "https://github.com/o/r/issues/1"; }; exit "${GH_CREATE_RC:-0}" ;;
esac
GH
chmod +x "$BIN/gh"; export GH_LOG="$T/gh.log"; : > "$GH_LOG"
out=$(cd "$P" && PATH="$BIN:$PATH" bash "$FB" submit "$d" 2>&1); rc=$?
[ "$rc" = 0 ] && has "$out" "SUBMITTED: https://github.com/o/r/issues/1" && ok "F6.a gh 로 올리고 이슈 주소를 낸다" || no "F6.a" "rc=$rc $out"
has "$(cat "$GH_LOG")" "issue create --repo github.com/andyko18/devFSD --title [feedback] 승인 질문이 두 번 나와 번거로웠다" && has "$(cat "$GH_LOG")" "auth status --hostname github.com" && has "$(cat "$GH_LOG")" "--label feedback" && ok "F6.b 저장소·제목을 넘긴다" || no "F6.b" "$(cat "$GH_LOG")"
bf=$(cat "$GH_LOG.body" 2>/dev/null)
has "$bf" "## 겪은 일" && ! has "$bf" "title: " && ok "F6.c 본문 파일에는 제목 줄이 없다" || no "F6.c" "$bf"
[ ! -e "$d" ] && ok "F6.k 올린 초안은 남기지 않는다" || no "F6.k"
d=$(_fb draft "승인 질문이 두 번 나와 번거로웠다" | sed -n 's/^DRAFT: //p')
: > "$GH_LOG"
out=$(cd "$P" && PATH="$BIN:$PATH" GH_AUTH_RC=1 bash "$FB" submit "$d" 2>&1); rc=$?
[ "$rc" = 4 ] && has "$out" "MANUAL: https://github.com/andyko18/devFSD/issues/new?template=feedback.md" && has "$out" "MANUAL-FILE: $d" && [ -f "$d" ] \
  && ok "F6.d 로그인 안 됨 → rc 4 + 직접 올릴 주소와 초안 경로" || no "F6.d" "rc=$rc $out"
! grep -q "issue create" "$GH_LOG" && ok "F6.e 로그인 안 됐으면 올리기를 시도하지 않는다" || no "F6.e" "$(cat "$GH_LOG")"
case "$out" in *"title="*|*"body="*) no "F6.f" "주소에 본문이 실렸다: $out" ;; *) ok "F6.f ★ 직접 올릴 주소에 제목·본문을 싣지 않는다(양식 이름만)" ;; esac
out=$(cd "$P" && PATH="$BIN:$PATH" GH_CREATE_RC=1 bash "$FB" submit "$d" 2>&1); rc=$?
[ "$rc" = 4 ] && has "$out" "MANUAL:" && ok "F6.g gh 가 실패해도 rc 4 + 직접 올릴 주소" || no "F6.g" "rc=$rc $out"
out=$(cd "$P" && PATH="$BIN:$PATH" GH_LABEL_RC=1 bash "$FB" submit "$d" 2>&1); rc=$?
[ "$rc" = 0 ] && has "$out" "SUBMITTED: https://" && ok "F6.l 라벨이 없는 저장소면 라벨 없이 한 번 더 올린다" || no "F6.l" "rc=$rc $out"
d=$(_fb draft "사내 저장소로" | sed -n 's/^DRAFT: //p')
out=$(cd "$P" && PATH="$BIN:$PATH" FEEDBACK_REPO=ghe.corp.example/me/fork bash "$FB" submit "$d" 2>&1)
has "$(cat "$GH_LOG")" "--repo ghe.corp.example/me/fork" && has "$(cat "$GH_LOG")" "auth status --hostname ghe.corp.example" && ok "F6.h FEEDBACK_REPO 로 올릴 저장소·호스트를 바꾼다(사내 GitHub)" || no "F6.h" "$(cat "$GH_LOG")"
printf 'root:x:0:0\n' > "$T/passwd-like"
out=$(cd "$P" && PATH="$BIN:$PATH" bash "$FB" submit "$T/passwd-like" 2>&1); rc=$?
[ "$rc" = 2 ] && has "$out" "초안이 아니다" && ok "F6.m ★ draft 가 만든 초안이 아닌 파일은 올리지 않는다" || no "F6.m" "rc=$rc $out"
d=$(_fb draft "깨끗한 본문" | sed -n 's/^DRAFT: //p')
printf '\n/Users/me/secret/path 에서 났다\n' > "$T/ins"; sed -i.bak "/^## 겪은 일$/r $T/ins" "$d"
out=$(cd "$P" && PATH="$BIN:$PATH" bash "$FB" submit "$d" 2>&1)
has "$out" "WARN: 본문에 파일 경로" && ok "F6.n 올리기 직전에 본문을 한 번 더 본다(초안을 손으로 고친 경우)" || no "F6.n" "$out"
out=$(_fb submit "$T/none.md"); rc=$?
[ "$rc" = 2 ] && ok "F6.i 초안 파일이 없으면 rc 2" || no "F6.i" "rc=$rc $out"
out=$(_fb nope); rc=$?
[ "$rc" = 2 ] && has "$out" "사용법" && ok "F6.j 모르는 하위 명령 → rc 2 + 사용법" || no "F6.j" "rc=$rc $out"

# ── F7 명령 문서 ↔ 스크립트 계약 ──
C="$PLUGIN/commands/feedback.md"
grep -q '^disable-model-invocation: true$' "$C" && ! grep -q '^user-invocable' "$C" && ok "F7.a /feedback 은 메뉴에 보이고 사용자가 부를 때만 돈다(모델이 스스로 부르지 않는다)" || no "F7.a"
for w in 'feedback.sh summary' 'feedback.sh draft --stdin' 'feedback.sh submit' 'DRAFT:' 'WARN:' 'REPO:' 'SUBMITTED:' 'MANUAL:' 'MANUAL-FILE:' '공개 저장소'; do
  grep -qF -- "$w" "$C" || { no "F7.b" "명령 문서에 '$w' 없음"; w=""; break; }
done
[ -n "$w" ] && ok "F7.b 명령 문서가 스크립트의 출력 줄·하위 명령을 전부 가리킨다"
grep -q '확인 없이 올리기' "$C" && grep -q '\[y/수정/파일만\]' "$C" && ok "F7.c 올리기 전 확인과 '파일만' 출구가 적혀 있다" || no "F7.c"
[ -f "$PLUGIN/.github/ISSUE_TEMPLATE/feedback.md" ] && grep -q '^labels: feedback' "$PLUGIN/.github/ISSUE_TEMPLATE/feedback.md" && ok "F7.d 이슈 양식(feedback.md)이 있다" || no "F7.d"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
