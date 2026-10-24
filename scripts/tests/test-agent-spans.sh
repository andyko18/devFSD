#!/usr/bin/env bash
# agent-spans.sh · stage-timing.sh --by-agent — 서브에이전트 대기의 역할별 분해 계측 (fixture 만 사용 — 실제 ~/.claude 를 읽지 않는다, 토큰 0)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq 필요"; exit 0; }
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ST="$PLUGIN/scripts/stage-timing.sh"
AS="$PLUGIN/scripts/_internal/agent-spans.sh"
BASH_BIN=$(command -v bash)
# shellcheck disable=SC2034  # Part B(T7.c)에서 쓴다
REAL_JQ=$(command -v jq)
SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/tmp"

ck() { if [ "$2" = "$3" ]; then echo "PASS $1"; PASS=$((PASS+1)); else echo "FAIL $1 — exp '$3' got '$2'"; FAIL=$((FAIL+1)); fi; }

# 서브에이전트 fixture: mkag 폴더 ID META — 본문(jsonl)은 stdin. META 가 "-" 면 meta 파일이 없다. meta 는 끝 개행 없이 쓴다(실제 포맷).
mkag() { mkdir -p "$1" && cat > "$1/agent-$2.jsonl" && touch -t 203001010000 "$1/agent-$2.jsonl"; [ "$3" = "-" ] || printf '%s' "$3" > "$1/agent-$2.meta.json"; }
# 레코드 한 줄: rec HH:MM:SS [YYYY-MM-DD] (기본 2026-10-01 UTC)
rec() { printf '{"type":"user","timestamp":"%sT%s.000Z","message":{"content":"x"}}\n' "${2:-2026-10-01}" "$1"; }
# 구현자형·리뷰어형·탐색형 meta
META_IMPL='{"agentType":"specops-ko:implementer-ko","toolUseId":"toolu_a","spawnDepth":1}'
META_SPEC='{"agentType":"specops-ko:spec-reviewer-ko","toolUseId":"toolu_b","spawnDepth":1}'
META_NAMED='{"agentType":"iso-T1","spawnDepth":0}'
# transcript fixture(세션 파일): mktr 경로 — 본문은 stdin. mtime 을 먼 미래로 고정해 원장 기간 필터에 항상 걸리게 한다.
mktr() { mkdir -p "$(dirname "$1")" && cat > "$1" && touch -t 203001010000 "$1"; }
ledger() { mkdir -p "$SB/$1" && cat > "$SB/$1/session-progress.md"; }
# 실행: runs 원장이름 옵션... — TZ=UTC · 전역 OUT·ERR·RC. TMPDIR 은 전용 디렉토리(누출 검사용).
runs() {
  local nm="$1"; shift
  OUT=$(TZ="${TZV:-UTC}" TMPDIR="$SB/tmp" SPECOPS_ROOT="$SB/$nm" "$BASH_BIN" "$ST" "$@" 2>"$SB/err"); RC=$?
  # shellcheck disable=SC2034  # Part B 의 단언에서 쓴다
  ERR=$(cat "$SB/err")
}
cnt() { printf '%s\n' "$OUT" | grep -c -- "$1"; }
# 역할 표의 한 행을 "합계 비중 n 중앙값 p90 max" 로 뽑는다(열: 합계 비중 n 중앙값 p90 max 역할)
arow() { printf '%s\n' "$OUT" | grep -E "  $1\$" | awk '{print $1, $2, $3, $4, $5, $6}'; }
# 역할 표에 나온 역할 이름을 위에서 아래로(머리행·미분류 줄 제외)
roles() { printf '%s\n' "$OUT" | sed -n '/^   합계    비중     n  중앙값    p90    max  역할$/,/^미분류/p' | grep -vE '^   합계|^미분류' | awk '{print $NF}' | tr '\n' ','; }

# ── 공통 fixture: 세션 파일(AC-3 의 10:01 H · 10:05 D 4분 · 10:09 N · 10:10 D 1분 · 10:13 H)과 원장 ──
SESSION_BODY=$(cat <<'EOF'
{"type":"user","timestamp":"2026-10-01T10:01:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"role":"user","content":"BODY-A"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:05:00.000Z","durationMs":240000}
{"type":"user","timestamp":"2026-10-01T10:09:00.000Z","isMeta":false,"origin":{"kind":"task-notification"},"message":{"role":"user","content":"BODY-C"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:10:00.000Z","durationMs":60000}
{"type":"user","timestamp":"2026-10-01T10:13:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"role":"user","content":"BODY-D"}}
EOF
)
ledger la <<'EOF'
## 20261001-aaa · A

- 2026-10-01 10:15 /plan 완료 (x)
- 2026-10-01 10:00 /specify 완료 (x)
EOF
newtd() { printf '%s\n' "$SESSION_BODY" | mktr "$SB/$1/s1.jsonl"; }

# ══ AC-1: 헬퍼 — 에이전트당 역할·시작·끝·wall·내부 간격 ══
H="$SB/h/s/subagents"
{ rec 10:00:00; rec 10:03:00; rec 10:20:00; } | mkag "$H" a1 "$META_IMPL"
{ rec 10:00:00; rec 10:01:00; } | mkag "$H" a2 "$META_NAMED"
{ rec 10:00:00; rec 10:02:00; } | mkag "$H" a3 '{"agentType":"evil name; $(x)","toolUseId":"toolu_c","spawnDepth":1}'
{ rec 10:00:00; rec 10:03:00; } | mkag "$H" a4 -
: | mkag "$H" a5 "$META_SPEC"
{ echo 'this is not json'; echo '{"type":"user"}'; rec 10:00:00; echo '{"timestamp":"garbage"}'; rec 10:00:30; } | mkag "$H" a6 "$META_SPEC"
{ rec 10:00:00; rec 10:05:00; rec 12:00:00; } | mkag "$H" a7 '{"agentType":"Explore","toolUseId":"toolu_d","spawnDepth":1}'
{ rec 10:00:00; rec 10:02:00; } | mkag "$H" a8 '{"agentType":"general-purpose","toolUseId":"","spawnDepth":1}'
HF=("$H"/agent-a1.jsonl "$H"/agent-a2.jsonl "$H"/agent-a3.jsonl "$H"/agent-a4.jsonl "$H"/agent-a5.jsonl "$H"/agent-a6.jsonl)
EXP_H=$(printf '%s\n' "1790848800	1790850000	1200	1	1020	0	0	specops-ko:implementer-ko" "1790848800	1790848860	60	0	0	0	0	-" "1790848800	1790848920	120	0	0	0	0	-" "1790848800	1790848980	180	0	0	0	0	-" "1790848800	1790848830	30	0	0	0	0	specops-ko:spec-reviewer-ko")
OUT=$(TZ=UTC "$BASH_BIN" "$AS" --local "${HF[@]}" 2>/dev/null); RC=$?
ck "T1.a 에이전트마다 1줄 — 구현자 wall 1200·10분 초과 간격 1건(1020초) · 이름 지정·자유 텍스트 역할·meta 없음은 '-' · 빈 jsonl 무출력 · 불량 JSON·시각 없는 줄은 건너뜀 · rc=0" "$RC|$OUT" "0|$EXP_H"
OUT=$(TZ=UTC "$BASH_BIN" "$AS" --local "$H"/agent-a7.jsonl 2>/dev/null)
ck "T1.b 기본 방치 상한(720분): 115분 간격은 제외하지 않고 10분 초과 1건(6900초)으로만 센다 · wall 7200" "$OUT" "1790848800	1790856000	7200	1	6900	0	0	Explore"
OUT=$(TZ=UTC "$BASH_BIN" "$AS" --local --gap-cap-min 60 "$H"/agent-a7.jsonl 2>/dev/null)
ck "T1.c --gap-cap-min 60: 115분 간격은 방치로 빼고(wall 300) 상한초과 1건(6900초) · 10분 초과 건수에는 안 센다" "$OUT" "1790848800	1790856000	300	0	0	1	6900	Explore"
OUT=$(TZ=Asia/Seoul "$BASH_BIN" "$AS" --local "$H"/agent-a1.jsonl 2>/dev/null)
ck "T1.d --local 은 TZ 를 따른다(KST = UTC+9h): 시작·끝 +32400초" "$OUT" "1790881200	1790882400	1200	1	1020	0	0	specops-ko:implementer-ko"
OUT=$(TZ=UTC "$BASH_BIN" "$AS" "$H"/agent-a1.jsonl 2>/dev/null)
ck "T1.e --local 없으면 UTC epoch 그대로" "$OUT" "1790848800	1790850000	1200	1	1020	0	0	specops-ko:implementer-ko"
ck "T1.f toolUseId 가 빈 문자열인 에이전트의 역할은 '-'(meta 파일이 끝 개행 없이 이어진 입력에서도 파일마다 올바른 역할)" "$(TZ=UTC "$BASH_BIN" "$AS" "$H"/agent-a8.jsonl "$H"/agent-a1.jsonl "$H"/agent-a7.jsonl 2>/dev/null | awk -F'\t' '{print $8}' | tr '\n' ',')|$([ "$(tail -c1 "$H/agent-a1.meta.json" | od -An -c | tr -d ' ')" = '\n' ] && echo nl || echo nonl)" "-,specops-ko:implementer-ko,Explore,|nonl"
RCS=""
"$BASH_BIN" "$AS" >/dev/null 2>&1; RCS="$RCS$?"
"$BASH_BIN" "$AS" "$SB/없는파일.jsonl" >/dev/null 2>&1; RCS="$RCS$?"
"$BASH_BIN" "$AS" --bogus "$H"/agent-a1.jsonl >/dev/null 2>&1; RCS="$RCS$?"
"$BASH_BIN" "$AS" --gap-cap-min abc "$H"/agent-a1.jsonl >/dev/null 2>&1; RCS="$RCS$?"
"$BASH_BIN" "$AS" --gap-cap-min >/dev/null 2>&1; RCS="$RCS$?"
{ rec 10:00:00; rec 10:03:00; } | mkag "$SB/hd/s1/subagents" ax "$META_IMPL"
{ rec 11:00:00; rec 11:05:00; } | mkag "$SB/hd/s2/subagents" ax "$META_SPEC"
OUT=$(TZ=UTC "$BASH_BIN" "$AS" --local "$SB/hd/s1/subagents/agent-ax.jsonl" "$SB/hd/s2/subagents/agent-ax.jsonl" 2>/dev/null)
ck "T1.i 같은 ID 의 에이전트가 다른 세션 폴더에 있어도 합쳐지지 않고 각자의 역할·시간으로 2줄이 나온다(경로로 구분)" "$OUT" "$(printf '%s\n' "1790848800	1790848980	180	0	0	0	0	specops-ko:implementer-ko" "1790852400	1790852700	300	0	0	0	0	specops-ko:spec-reviewer-ko")"
ck "T1.g 인자 없음·없는 파일·알 수 없는 옵션·잘못된 --gap-cap-min·값 없음 → 전부 rc=2" "$RCS" "22222"
OUT=$("$BASH_BIN" "$AS" "$SB/없는파일.jsonl" "$H"/agent-a1.jsonl 2>/dev/null); RC=$?
ck "T1.g2 읽을 수 없는 파일이 하나라도 섞이면 일부 결과를 내지 않고 통째로 rc=2(부분 집계가 전체처럼 읽히지 않게)" "$RC|$OUT" "2|"
mkdir -p "$SB/nojq"; for t in awk sort grep sed find mktemp rm cat dirname printf touch date; do p=$(command -v "$t") && [ -n "$p" ] && ln -sf "$p" "$SB/nojq/$t"; done
PATH="$SB/nojq" "$BASH_BIN" "$AS" "$H"/agent-a1.jsonl >/dev/null 2>&1; ck "T1.h 헬퍼는 jq 부재 시 rc=3" "$?" "3"

# ══ AC-2: 프라이버시 — 본문·허용 외 키는 어디에도 나오지 않는다 ══
CAN="CANARY-$$-ZQX"
P="$SB/pv/s1/subagents"
{ printf '{"type":"user","timestamp":"2026-10-01T10:00:00.000Z","message":{"content":"%s-BODY"},"toolUseResult":{"x":"%s-TR"},"attachment":"%s-ATT"}\n' "$CAN" "$CAN" "$CAN"
  printf '{"type":"assistant","timestamp":"2026-10-01T10:04:00.000Z","message":{"content":[{"type":"tool_use","input":{"cmd":"%s-IN"}}]},"extra":"%s-EX"}\n' "$CAN" "$CAN"
  printf '%s-NOTJSON\n' "$CAN"; } | mkag "$P" b1 "{\"agentType\":\"specops-ko:implementer-ko\",\"toolUseId\":\"toolu_p\",\"spawnDepth\":1,\"description\":\"$CAN-DESC\",\"foo\":\"$CAN-FOO\"}"
{ rec 10:00:00; rec 10:05:00; } | mkag "$P" b2 "{\"agentType\":\"$CAN bad role\",\"toolUseId\":\"toolu_q\",\"description\":\"$CAN-D2\"}"
mktr "$SB/pv/s1.jsonl" <<EOF
{"type":"user","timestamp":"2026-10-01T10:01:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"content":"$CAN-SESS"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:05:00.000Z","durationMs":240000}
EOF
OUT1=$(TZ=UTC TMPDIR="$SB/tmp" "$BASH_BIN" "$AS" --local "$P"/agent-b1.jsonl "$P"/agent-b2.jsonl 2>"$SB/e1"); E1=$(cat "$SB/e1")
ck "T2.a 헬퍼: 본문·도구 입출력·첨부·meta description·허용 외 키·형식 불일치 역할 이름에 심은 카나리가 stdout·stderr 에 0건" "$(printf '%s\n%s\n' "$OUT1" "$E1" | grep -c "$CAN")" "0"
JQSRC=$(sed -n '/^# JQ-META-BEGIN$/,/^# JQ-META-END$/p;/^# JQ-SPANS-BEGIN$/,/^# JQ-SPANS-END$/p' "$AS")
KEYS=$(printf '%s\n' "$JQSRC" | grep -v '^#' | sed -E 's/"[^"]*"//g' | grep -oE '\.[A-Za-z_][A-Za-z0-9_]*' | sort -u | tr '\n' ' ')
BAD=$(printf '%s\n' "$KEYS" | tr ' ' '\n' | grep -vE '^$|^\.(timestamp|agentType|toolUseId|ts|id|key|value)$' | tr '\n' ' ')
MREFS=$(printf '%s\n' "$JQSRC" | grep -v '^#' | sed -E 's/"[^"]*"//g' | grep -oE '\$m\.[A-Za-z_]+' | sort -u | tr '\n' ' ')
ck "T2.e 헬퍼 jq 프로그램이 참조하는 키는 timestamp·agentType·toolUseId(와 내부 이름 ts·id·key·value)뿐이고 meta 객체에서는 agentType·toolUseId 만 꺼낸다 — description·spawnDepth·message·content 등은 참조하지 않는다" "$BAD|$MREFS" "|\$m.agentType \$m.toolUseId "
ck "T2.g 정적: 헬퍼의 jq 호출 두 곳 모두 stderr 를 버린다(jq 오류 문구는 문제 값을 그대로 찍는다)" "$(grep -c "@tsv' 2>/dev/null)" "$AS")$(grep -cE '"\$@" 2>/dev/null$' "$AS")" "11"
ck "T2.f 정적 검사 자체가 헛돌지 않는다: 프로그램 텍스트가 비어 있지 않고 timestamp·agentType·toolUseId 를 실제로 참조한다" "$(printf '%s\n' "$KEYS" | grep -c 'timestamp')$(printf '%s\n' "$KEYS" | grep -c 'agentType')$(printf '%s\n' "$KEYS" | grep -c 'toolUseId')" "111"

runs la --by-agent --transcript-dir "$SB/pv"
ck "T2.b stage-timing --by-agent 정상 경로: stdout·stderr 카나리 0건(역할 불명은 '-' 로 미분류 처리)" "$(printf '%s\n%s\n' "$OUT" "$ERR" | grep -c "$CAN")|$(cnt '미분류(이름 지정) 1건')" "0|1"
runs la --by-agent --transcript-dir "$SB/없는디렉토리"
OUT3=$(PATH="$SB/nojq" TZ=UTC TMPDIR="$SB/tmp" SPECOPS_ROOT="$SB/la" "$BASH_BIN" "$ST" --by-agent --transcript-dir "$SB/pv" 2>&1)
OUT4=$("$BASH_BIN" "$AS" "$SB/없는파일.jsonl" 2>&1)
ck "T2.c 오류·부재 경로(없는 디렉토리·jq 부재·없는 파일): 카나리 0건" "$(printf '%s\n%s\n%s\n%s\n' "$OUT" "$ERR" "$OUT3" "$OUT4" | grep -c "$CAN")" "0"
ck "T2.d TMPDIR 에 카나리가 없고 실행 뒤 잔존 파일도 없다" "$(grep -rl "$CAN" "$SB/tmp" 2>/dev/null | /usr/bin/wc -l | tr -d ' ')|$(ls -A "$SB/tmp" | /usr/bin/wc -l | tr -d ' ')" "0|0"

# ══ AC-3: --by-agent 역할별 표 ══
TT3="$SB/t3"; newtd t3
S3="$TT3/s1/subagents"
{ rec 10:00:00; rec 10:10:00; } | mkag "$S3" c1 "$META_IMPL"
{ rec 11:00:00; rec 11:20:00; } | mkag "$S3" c2 "$META_IMPL"
{ rec 12:00:00; rec 12:30:00; } | mkag "$S3" c3 "$META_IMPL"
{ rec 10:00:00; rec 10:05:00; } | mkag "$S3" c4 "$META_SPEC"
{ rec 10:00:00; rec 10:07:00; } | mkag "$S3" c5 "$META_SPEC"
{ rec 10:00:00; rec 10:08:00; } | mkag "$S3" c6 "$META_NAMED"
{ rec 10:00:00; rec 10:07:00; } | mkag "$S3" c7 -
runs la --by-agent --transcript-dir "$TT3"
ck "T3.a 구현자 3건(10·20·30분): 합계 60·비중 83.3%·n 3·중앙값 20·p90 30·max 30" "$(arow 'specops-ko:implementer-ko')" "60 83.3% 3 20 30 30"
ck "T3.b 스펙 리뷰어 2건(5·7분): 합계 12·비중 16.7%·n 2·중앙값 5(nearest-rank)·p90 7·max 7" "$(arow 'specops-ko:spec-reviewer-ko')" "12 16.7% 2 5 7 7"
ck "T3.c 합계 내림차순 · 미분류 2건 합계 15분은 표 밖 줄로 · 이름 지정 에이전트의 이름은 어디에도 없다" "$(roles)|$(cnt '미분류(이름 지정) 2건 합계 15분 — 역할 표에서 제외')|$(printf '%s\n' "$OUT" | grep -c 'iso-T1')" "specops-ko:implementer-ko,specops-ko:spec-reviewer-ko,|1|0"
ck "T3.d 역할 표 머리행은 고정 문자열이고 --split 표가 함께 나온다(--by-agent 가 --split 을 내포)" "$(printf '%s\n' "$OUT" | grep -cx '   합계    비중     n  중앙값    p90    max  역할')|$(printf '%s\n' "$OUT" | grep -cx '   합계    비중     n  중앙값    p90    max   작업   사람 백그라운드   기타  단계')" "1|1"

# ══ AC-4: 기간 필터·내부 간격·병렬 비교 ══
T4="$SB/t4"; newtd t4; S4="$T4/s1/subagents"
{ rec 10:00:00; rec 10:05:00; rec 10:30:00; } | mkag "$S4" d1 '{"agentType":"RoleX","toolUseId":"toolu_x"}'
{ rec 10:00:00 2026-10-01; rec 10:01:00 2026-10-01; rec 23:00:00 2026-10-01; } | mkag "$S4" d2 '{"agentType":"RoleY","toolUseId":"toolu_y"}'
{ rec 10:00:00 2026-09-30; rec 10:20:00 2026-09-30; } | mkag "$S4" d0 '{"agentType":"RoleOld","toolUseId":"toolu_o"}'
runs la --by-agent --transcript-dir "$T4"
ck "T4.a 원장 최초 날짜(10월 1일) 이전에 시작한 에이전트는 표에서 빠지고 제외 건수가 보인다" "$(roles)|$(cnt '서브에이전트 3개 중 기준일 이전 시작 1개 제외 (집계 2개: 역할 판정 2 · 미분류 0)')" "RoleX,RoleY,|1"
ck "T4.b 내부 간격 10분 초과(25분 1건)는 빼지 않고 건수·합만, 방치 상한(720분) 초과(779분 1건)만 wall 에서 빼고 건수·합을 표시한다" "$(cnt '서브에이전트 내부 간격 10분 초과 1건(합 25분) — 권한 대기·유휴 포함, 제외하지 않음')|$(cnt '방치 상한 초과 내부 간격 1건(합 779분) 제외')|$(arow RoleX)|$(arow RoleY)" "1|1|30 96.8% 1 30 30 30|1 3.2% 1 1 1 1"
ck "T4.c 병렬 비교 줄: 역할 wall 합 31분 · 같은 기간 백그라운드 열 합(원장 구간 10:00~10:15 의 4분)" "$(cnt '역할 wall 합 31분 · 같은 기간 백그라운드 열 합 4분 — 병렬·작업 중 실행으로 같지 않음')" "1"
runs la --by-agent --since 20261002 --transcript-dir "$T4"
ck "T4.d --since 20261002: 기준일이 그 날짜로 바뀌어 10월 1일 시작 에이전트도 빠진다 · 푸터 세 줄은 0건이어도 숨지 않는다" "$(cnt '서브에이전트 3개 중 기준일 이전 시작 3개 제외 (집계 0개: 역할 판정 0 · 미분류 0)')|$(cnt '역할을 판정할 수 있는 서브에이전트가 없음')|$(cnt '서브에이전트 내부 간격 10분 초과 0건(합 0분)')|$(cnt '방치 상한 초과 내부 간격 0건(합 0분) 제외')" "1|1|1|1"
runs la --by-agent --gap-cap-min 1000 --transcript-dir "$T4"
ck "T4.e --gap-cap-min 1000: 779분 간격은 더는 방치가 아니라 10분 초과 2건(합 804분)으로 센다" "$(cnt '서브에이전트 내부 간격 10분 초과 2건(합 804분)')|$(cnt '방치 상한 초과 내부 간격 0건(합 0분) 제외')" "1|1"

T4F="$SB/t4f"; newtd t4f
{ rec 20:00:00 2026-09-30; rec 20:10:00 2026-09-30; } | mkag "$T4F/s1/subagents" j1 '{"agentType":"RoleZ","toolUseId":"toolu_z"}'
TZV=Asia/Seoul runs la --by-agent --transcript-dir "$T4F"
ck "T4.f 기준일 비교는 로컬 벽시계 기준이다: UTC 9월 30일 20:00 시작(= KST 10월 1일 05:00)은 원장 최초 날짜(10월 1일) 이후라 집계된다" "$(roles)|$(cnt '기준일 이전 시작 0개 제외')" "RoleZ,|1"

T4G="$SB/t4g"; newtd t4g
{ rec 10:00:00; rec 10:05:00; } | mkag "$T4G/s1/subagents" k1 '{"agentType":"RoleK","toolUseId":"toolu_k"}'; touch -t 202610011200 "$T4G/s1/subagents/agent-k1.jsonl"
runs la --by-agent --since 20261002 --transcript-dir "$T4G"
ck "T4.g 파일 선별(mtime)은 --since 날짜 이상이다: 10월 1일에 수정된 파일은 --since 20261002 에서 읽지 않아 서브에이전트 파일 0개로 측정 불가" "$(printf '%s\n' "$OUT" | grep '^측정 불가(--by-agent)' | grep -c '서브에이전트 파일 0개')" "1"
runs la --by-agent --since 20261001 --transcript-dir "$T4G"
ck "T4.g2 같은 파일이 --since 20261001 에서는 읽힌다(대조군 — 파일 선별이 항상 비는 것이 아님)" "$(roles)" "RoleK,"

# ══ AC-5: 서브에이전트 데이터 부재·측정 불가 ══
T5="$SB/t5"; newtd t5
runs la --split --transcript-dir "$T5"; SPLIT_ONLY="$OUT"
runs la --by-agent --transcript-dir "$T5"
ck "T5.a 서브에이전트 폴더가 없으면 rc=0 · --split 출력 그대로 + 끝에 측정 불가(서브에이전트 파일 0개) 한 줄" "$RC|$(printf '%s\n' "$OUT" | sed '$d')|$(printf '%s\n' "$OUT" | tail -1 | grep '^측정 불가(--by-agent)' | grep -c '서브에이전트 파일 0개')" "0|$SPLIT_ONLY|1"
mkdir -p "$SB/cfg5/projects"
OUT=$(TZ=UTC TMPDIR="$SB/tmp" CLAUDE_CONFIG_DIR="$SB/cfg5" SPECOPS_ROOT="$SB/la" "$BASH_BIN" "$ST" --by-agent 2>"$SB/err"); RC=$?
ck "T5.b transcript 디렉토리가 없으면 --split 측정 불가 줄과 --by-agent 측정 불가 줄이 둘 다 나오고 rc=0" "$RC|$(printf '%s\n' "$OUT" | grep '^측정 불가(--split)' | grep -c 'transcript 디렉토리 없음')|$(printf '%s\n' "$OUT" | grep '^측정 불가(--by-agent)' | grep -c 'transcript 디렉토리 없음')" "0|1|1"
OUT=$(PATH="$SB/nojq" TZ=UTC TMPDIR="$SB/tmp" SPECOPS_ROOT="$SB/la" "$BASH_BIN" "$ST" --by-agent --transcript-dir "$T4" 2>"$SB/err"); RC=$?
ck "T5.c jq 부재 → rc=0 · 측정 불가(--split)·(--by-agent) 모두 jq 없음" "$RC|$(printf '%s\n' "$OUT" | grep '^측정 불가(--split)' | grep -c 'jq 없음')|$(printf '%s\n' "$OUT" | grep '^측정 불가(--by-agent)' | grep -c 'jq 없음')" "0|1|1"
runs la --split --transcript-dir "$T4"; SPLIT_WITH_AGENTS="$OUT"
ck "T5.d --by-agent 없는 --split 출력은 서브에이전트 파일이 있어도 서브에이전트 폴더가 없을 때와 같다(옵션 없는 경로 불변)" "$SPLIT_WITH_AGENTS" "$SPLIT_ONLY"
if [ "$(id -u)" != 0 ]; then
  T5U="$SB/t5u"; newtd t5u; { rec 10:00:00; rec 10:05:00; } | mkag "$T5U/s1/subagents" e1 "$META_IMPL"; chmod 000 "$T5U/s1/subagents/agent-e1.jsonl"
  runs la --by-agent --transcript-dir "$T5U"
  ck "T5.e 읽을 수 없는 서브에이전트 파일 → rc=0 · 측정 불가(서브에이전트 transcript 를 읽을 수 없음) 한 줄" "$RC|$(printf '%s\n' "$OUT" | grep '^측정 불가(--by-agent)' | grep -c '서브에이전트 transcript 를 읽을 수 없음')" "0|1"
  chmod 644 "$T5U/s1/subagents/agent-e1.jsonl"
else
  echo "SKIP T5.e — root 로 실행 중(권한 검사 무의미)"
fi

# ══ AC-6: 옵션·경로 ══
T6="$SB/t6"; newtd t6
{ rec 10:00:00; rec 10:06:00; } | mkag "$T6/s1/subagents" f1 "$META_IMPL"
{ rec 10:00:00; rec 10:09:00; } | mkag "$T6/s1/subagents/deep" f2 "$META_IMPL"
{ rec 10:00:00; rec 10:09:00; } | mkag "$T6/s1/subagents/deep/subagents" f3 "$META_IMPL"
{ rec 10:00:00; rec 10:09:00; } | mkag "$T6/s1" f4 "$META_IMPL"
{ rec 10:00:00; rec 10:09:00; } | mkag "$T6/s1/other" f7 "$META_IMPL"
{ rec 10:00:00; rec 10:09:00; } | mkag "$T6/s1/subagents" f8 "$META_IMPL"; touch -t 200001010000 "$T6/s1/subagents/agent-f8.jsonl"
printf 'x' > "$T6/s1/subagents/agent-f5.txt"; printf '%s' "$META_IMPL" > "$T6/s1/subagents/agent-f6.meta.json"; touch -t 203001010000 "$T6/s1/subagents/agent-f5.txt"
runs la --by-agent --transcript-dir "$T6"
ck "T6.a 직속 세션폴더/subagents/agent-*.jsonl 만 읽는다: 깊이가 다른 경로·subagents 가 아닌 폴더·원장 최초 날짜보다 오래전에 수정된 파일·.jsonl 이 아닌 파일·meta 만 있는 파일은 무시(구현자 1건 6분)" "$(arow 'specops-ko:implementer-ko')" "6 100.0% 1 6 6 6"
runs la --by-agent --min-n 3 --since 20261001 --gap-cap-min 720 --transcript-dir "$T6"
ck "T6.b 기존 옵션(--min-n·--since·--gap-cap-min)과 병용해도 동작한다 · 역할 표와 푸터의 백그라운드 열 합(4분)은 --min-n 으로 가려진 단계에 영향받지 않는다" "$RC|$(arow 'specops-ko:implementer-ko')|$(cnt '역할 wall 합 6분 · 같은 기간 백그라운드 열 합 4분')" "0|6 100.0% 1 6 6 6|1"
runs la --by-agent --transcript-dir "$SB/없는디렉토리"
ck "T6.c 존재하지 않는 --transcript-dir 는 --by-agent 와 함께여도 rc=2(디렉토리가 아니라는 사유)" "$RC|$(printf '%s\n' "$ERR" | grep -c '디렉토리가 아닙니다')" "2|1"
runs la --by-agent --bogus
ck "T6.d 알 수 없는 옵션은 rc=2(--by-agent 는 알고 --bogus 만 모른다)" "$RC|$(printf '%s\n' "$ERR" | grep -c -- '--bogus')" "2|1"

# ══ AC-7: 읽기 전용·성능 ══
T7="$SB/t7"; newtd t7
for i in 1 2 3 4 5 6 7 8; do { rec 10:00:00; rec 10:0$i:00; } | mkag "$T7/s1/subagents" "g$i" "$META_SPEC"; done
CK_BEFORE=$(cat "$SB/la/session-progress.md" "$T7"/s1.jsonl "$T7"/s1/subagents/* | cksum)
runs la --by-agent --transcript-dir "$T7"
CK_AFTER=$(cat "$SB/la/session-progress.md" "$T7"/s1.jsonl "$T7"/s1/subagents/* | cksum)
ck "T7.a 원장·세션·서브에이전트 파일은 실행 전후 동일하고 TMPDIR 에 잔존 파일이 없다" "$([ "$CK_BEFORE" = "$CK_AFTER" ] && echo same)|$(ls -A "$SB/tmp" | /usr/bin/wc -l | tr -d ' ')" "same|0"
ck "T7.b 정적: 헬퍼·stage-timing 에 mktime( 호출·행 단위 read 루프가 없다" "$(grep -vE '^[[:space:]]*#' "$AS" "$ST" | grep -cE 'mktime\(|while[[:space:]]+(IFS=[^ ]* )?read')" "0"
# jq 기동 횟수: jq 래퍼가 호출을 센다 — 에이전트 파일이 8개든 80개든 헬퍼는 2회(meta 1 · jsonl 1)
mkdir -p "$SB/shim"; printf '#!/bin/sh\necho x >> "%s/jqcalls"\nexec "%s" "$@"\n' "$SB" "$REAL_JQ" > "$SB/shim/jq"; chmod +x "$SB/shim/jq"
rm -f "$SB/jqcalls"; PATH="$SB/shim:$PATH" TZ=UTC "$BASH_BIN" "$AS" --local "$T7"/s1/subagents/agent-g*.jsonl >/dev/null 2>&1
ck "T7.c 파일마다 jq 를 기동하지 않는다: 에이전트 8개에 jq 2회(meta 1 · jsonl 1)" "$(/usr/bin/wc -l < "$SB/jqcalls" | tr -d ' ')" "2"
BIG="$SB/tbig"; newtd tbig
for i in 1 2 3; do
  awk 'BEGIN { for (k = 1; k <= 20000; k++) printf "{\"type\":\"assistant\",\"timestamp\":\"2026-10-01T10:%02d:%02d.000Z\",\"message\":{\"content\":\"x\"}}\n", int(k / 60) % 60, k % 60 }' | mkag "$BIG/s1/subagents" "h$i" "$META_IMPL"
done
# 벽시계가 아니라 CPU 시간(user+sys · 자식 포함)으로 잰다 — 병렬 run-all·리뷰 에이전트 경합에 흔들리지 않는다(20261024-flaky-suites-spa-false-ok · 실측 단독 수 초)
TIMEFORMAT='%3U %3S'; { time runs la --by-agent --transcript-dir "$BIG"; } 2>"$SB/cpu"; unset TIMEFORMAT
_cl=$(tail -1 "$SB/cpu" | tr ',' '.'); CPU=$(printf '%s' "$_cl" | awk '{ printf "%.1f", $1 + $2 }')
ck "T7.d 합성 6만 줄 서브에이전트 3개 --by-agent rc=0 · CPU 20초 이내(실측 수 초 · cpu=${CPU}s)" "$RC|$(printf '%s' "$_cl" | grep -qE '^[0-9]+\.[0-9]{3} [0-9]+\.[0-9]{3}$' && awk -v c="$CPU" 'BEGIN{ print (c + 0 > 0 && c + 0 <= 20) ? 1 : 0 }' || echo bad)|$(arow 'specops-ko:implementer-ko' | awk '{print $3}')" "0|1|3"

# ══ AC-9: --min-n 무관·초→분 반올림·동률 정렬 ══
T9="$SB/t9"; newtd t9; S9="$T9/s1/subagents"
{ rec 10:00:00; rec 10:00:29; } | mkag "$S9" i1 '{"agentType":"Rnd","toolUseId":"t"}'
{ rec 10:00:00; rec 10:00:31; } | mkag "$S9" i2 '{"agentType":"Rnd","toolUseId":"t"}'
{ rec 10:00:00; rec 10:01:29; } | mkag "$S9" i3 '{"agentType":"Rnd","toolUseId":"t"}'
{ rec 10:00:00; rec 10:00:30; } | mkag "$S9" i4 '{"agentType":"Half","toolUseId":"t"}'
{ rec 10:00:00; rec 10:00:29; } | mkag "$S9" i5 '{"agentType":"Low","toolUseId":"t"}'
{ rec 10:00:00; rec 10:02:00; } | mkag "$S9" i6 '{"agentType":"Beta","toolUseId":"t"}'
{ rec 10:00:00; rec 10:02:00; } | mkag "$S9" i7 '{"agentType":"Alpha","toolUseId":"t"}'
runs la --by-agent --min-n 3 --transcript-dir "$T9"
ck "T9.a 초로 계산한 뒤 표시 시점에만 분으로 반올림: Rnd(29·31·89초) 합계 2·중앙값 1·p90 1·max 1 · 30초 1건은 1 · 29초 1건은 0" "$(arow Rnd)|$(arow Half | awk '{print $1, $4}')|$(arow Low | awk '{print $1, $4}')" "2 33.3% 3 1 1 1|1 1|0 0"
ck "T9.b 합계 동률(Alpha·Beta 각 2분)은 역할 이름 오름차순이고 --min-n 3 에도 n 이 작은 역할이 모두 보인다(단계 표만 가려진다)" "$(roles)|$(cnt '표 가림(--min-n 3)')" "Rnd,Alpha,Beta,Half,Low,|1"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
