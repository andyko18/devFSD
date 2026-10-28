#!/usr/bin/env bash
# meter-tokens.sh — FID 20261001-token-usage-metering (관측 전용 · fail-open)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
METER="$PLUGIN/scripts/_internal/meter-tokens.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq 필요"; exit 0; }

TD=$(mktemp -d) || exit 1
trap 'rm -rf "$TD"' EXIT
SID=11111111-2222-3333-4444-555555555555
FID=20261001-demo

# 합성 transcript 줄: _line <id> <model> <output> <ts> [input] [cache_read] [cache_write]
_line() {
  jq -nc --arg id "$1" --arg m "$2" --argjson o "$3" --arg ts "$4" \
    --argjson i "${5:-2}" --argjson cr "${6:-100}" --argjson cw "${7:-50}" \
    '{type:"assistant",timestamp:$ts,message:{id:$id,model:$m,usage:{input_tokens:$i,output_tokens:$o,cache_read_input_tokens:$cr,cache_creation_input_tokens:$cw}}}'
}
# fixture 환경: $TD/<name>/{work/.specops/$FID/metrics.jsonl(compact, fid-start 10:00:00Z), cfg/projects/-p/}
mk_env() {
  local d="$TD/$1"; rm -rf "$d"
  mkdir -p "$d/work/.specops/$FID" "$d/cfg/projects/-p"
  jq -nc --arg fid "$FID" '{schema_version:2,ts:"2026-09-30T10:00:00Z",fid:$fid,phase:"fid-start"}' \
    > "$d/work/.specops/$FID/metrics.jsonl"
  echo "$d"
}
# run_meter <envdir> [meter 인자...] — env 주입, stdout+stderr 합쳐 출력, rc 보존
run_meter() {
  local d="$1"; shift
  ( cd "$d/work" && CLAUDE_CONFIG_DIR="$d/cfg" CLAUDE_CODE_SESSION_ID="$SID" bash "$METER" "$FID" "$@" 2>&1 )
}
TOK() { echo "$1/work/.specops/$FID/tokens.jsonl"; }

# T1.a fid-start 부재 → transcript 를 열지 않고 무기록·exit 0·출력 없음 (AC-8)
d=$(mk_env t1a); : > "$d/work/.specops/$FID/metrics.jsonl"
out=$( cd "$d/work" && HOME=/nonexistent CLAUDE_CONFIG_DIR=/nonexistent CLAUDE_CODE_SESSION_ID="$SID" bash "$METER" "$FID" 2>&1 ); ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ] && [ ! -e "$(TOK "$d")" ]; then
  ok "T1.a fid-start 부재 → 무기록·exit 0·무출력"
else
  nope "T1.a" "ec=$ec out='$out'"
fi

# T1.b 잘못된 FID → exit 2·tokens.jsonl 부재
d=$(mk_env t1b)
( cd "$d/work" && bash "$METER" "BAD" >/dev/null 2>&1 ); ec=$?
if [ "$ec" -eq 2 ] && [ ! -e "$(TOK "$d")" ]; then ok "T1.b 잘못된 FID → exit 2"; else nope "T1.b" "ec=$ec"; fi

# T1.c FID 인자 없음 → exit 2
d=$(mk_env t1c)
( cd "$d/work" && bash "$METER" >/dev/null 2>&1 ); ec=$?
[ "$ec" -eq 2 ] && ok "T1.c FID 인자 없음 → exit 2" || nope "T1.c" "ec=$ec"

# mk_core <envdir> — 핵심 fixture: A(8,8,8,1008 · cr100 cw50) + B(10 · cr200 cw20) + synthetic 2줄 + 깨진 줄
mk_core() {
  local d="$1" f="$1/cfg/projects/-p/$SID.jsonl"
  {
    _line msg_A m1 8    2026-09-30T10:00:05.123Z 2 100 50
    _line msg_A m1 8    2026-09-30T10:00:05.200Z 2 100 50
    _line msg_A m1 8    2026-09-30T10:00:05.900Z 2 100 50
    _line msg_A m1 1008 2026-09-30T10:00:06.000Z 2 100 50
    _line msg_B m1 10   2026-09-30T10:00:07.000Z 2 200 20
    _line msg_S '<synthetic>' 9999 2026-09-30T10:00:08.000Z 2 100 50
    _line msg_S '<synthetic>' 9999 2026-09-30T10:00:08.500Z 2 100 50
    echo 'broken{'
  } > "$f"
}

# T2.a id별 4필드 최댓값 합산 + synthetic 제외(건수만) (AC-1)
d=$(mk_env t2a); mk_core "$d"
out=$(run_meter "$d"); ec=$?
if [ "$ec" -eq 0 ] && jq -e 'select(.agent=="main") |
     .output==1018 and .input==4 and .cache_read==300 and .cache_write==70 and .messages==2
     and .synthetic_excluded==1 and .dedupe=="max-per-message-id" and .model=="m1"' "$(TOK "$d")" >/dev/null 2>&1; then
  ok "T2.a id별 max 합산 + synthetic 제외(건수 1)"
else
  nope "T2.a" "ec=$ec out='$out' rec=$(cat "$(TOK "$d")" 2>/dev/null)"
fi

# T2.b --transcript 직접 지정(env 없이)도 동일 합계
d=$(mk_env t2b); mk_core "$d"
( cd "$d/work" && env -u CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR=/nonexistent bash "$METER" "$FID" --transcript "$d/cfg/projects/-p/$SID.jsonl" >/dev/null 2>&1 )
if jq -e 'select(.agent=="main") | .output==1018 and .messages==2' "$(TOK "$d")" >/dev/null 2>&1; then
  ok "T2.b --transcript 지정 동일 합계"
else
  nope "T2.b" "rec=$(cat "$(TOK "$d")" 2>/dev/null)"
fi

# mk_window <envdir> — 구간 fixture: P(1000·기준점 이전) S(7·같은 초) N(3) F(500·미래)
mk_window() {
  local f="$1/cfg/projects/-p/$SID.jsonl"
  {
    _line msg_P m1 1000 2026-09-30T09:59:59.900Z
    _line msg_S m1 7    2026-09-30T10:00:00.100Z
    _line msg_N m1 3    2026-09-30T10:05:00.000Z
    _line msg_F m1 500  2099-01-01T00:00:00.000Z
  } > "$f"
}

# T3.a 기준점 이전·미래 제외, 같은 초 포함 (AC-2)
d=$(mk_env t3a); mk_window "$d"; run_meter "$d" >/dev/null
if jq -e 'select(.agent=="main") | .messages==2 and .output==10 and .scope=="fid-window"' "$(TOK "$d")" >/dev/null 2>&1; then
  ok "T3.a 구간 경계(같은 초 포함·이전/미래 제외)"
else
  nope "T3.a" "rec=$(cat "$(TOK "$d")" 2>/dev/null)"
fi

# T3.b 구간 안 메시지 0건 → 0 레코드가 아니라 unmeasured 사유 레코드 (AC-10)
d=$(mk_env t3b)
{ _line msg_P m1 1000 2026-09-30T09:59:59.900Z; } > "$d/cfg/projects/-p/$SID.jsonl"
run_meter "$d" >/dev/null
if [ "$(/usr/bin/wc -l < "$(TOK "$d")" | tr -d ' ')" = 1 ] \
   && jq -e '.status=="unmeasured" and .reason=="no-messages-in-window" and (has("input")|not)' "$(TOK "$d")" >/dev/null 2>&1; then
  ok "T3.b 0건 → unmeasured(no-messages-in-window), 토큰 필드 없음"
else
  nope "T3.b" "rec=$(cat "$(TOK "$d")" 2>/dev/null)"
fi

# T3.c --since 수동 기준점 → scope since-manual (AC-12)
d=$(mk_env t3c); : > "$d/work/.specops/$FID/metrics.jsonl"; mk_window "$d"
run_meter "$d" --since 2026-09-30T10:00:00Z >/dev/null
if jq -e 'select(.agent=="main") | .scope=="since-manual" and .window_start=="2026-09-30T10:00:00Z" and .output==10' "$(TOK "$d")" >/dev/null 2>&1; then
  ok "T3.c --since → scope=since-manual"
else
  nope "T3.c" "rec=$(cat "$(TOK "$d")" 2>/dev/null)"
fi

# mk_sub <envdir> — 서브에이전트 2개(aaa: meta 있음 / bbb: meta 없음) + 겹치는 다른 세션 파일 1개
mk_sub() {
  local d="$1" sd="$1/cfg/projects/-p/$SID/subagents"
  mkdir -p "$sd"
  { _line msg_a1 m2 40 2026-09-30T10:01:00.000Z; _line msg_a2 m2 60 2026-09-30T10:02:00.000Z; } > "$sd/agent-aaa.jsonl"
  printf '{"agentType":"general-purpose","model":"sonnet"}' > "$sd/agent-aaa.meta.json"
  { _line msg_b1 m3 5 2026-09-30T10:03:00.000Z; } > "$sd/agent-bbb.jsonl"
  echo '{}' > "$d/cfg/projects/-p/other-session.jsonl"
}

# T4.a 서브에이전트 레코드: agent/model/agent_model, 메인과 분리 (AC-3)
d=$(mk_env t4a); mk_core "$d"; mk_sub "$d"; run_meter "$d" >/dev/null
T=$(TOK "$d")
if jq -e 'select(.agent=="general-purpose:aaa") | .model=="m2" and .agent_model=="sonnet" and .output==100 and .messages==2' "$T" >/dev/null 2>&1 \
   && jq -e 'select(.agent=="unknown:bbb") | .model=="m3" and .agent_model=="unknown" and .output==5' "$T" >/dev/null 2>&1 \
   && jq -e 'select(.agent=="main") | .output==1018' "$T" >/dev/null 2>&1; then
  ok "T4.a 서브에이전트 별도 레코드·meta 누락 unknown·메인 불변"
else
  nope "T4.a" "rec=$(cat "$T" 2>/dev/null)"
fi

# T4.b main 레코드의 overlap_other_sessions (mtime 이 구간 안인 다른 세션 파일 1개 — "최근 M분" 근사, 최대 1분 오차)
if jq -e 'select(.agent=="main") | .overlap_other_sessions==1' "$T" >/dev/null 2>&1; then
  ok "T4.b overlap_other_sessions=1"
else
  nope "T4.b" "rec=$(jq -c 'select(.agent=="main")' "$T" 2>/dev/null)"
fi

# T5.a 같은 호출 2회 → 레코드 수 불변, 값 교체 (AC-4)
d=$(mk_env t5a); mk_core "$d"; mk_sub "$d"
run_meter "$d" >/dev/null; n1=$(/usr/bin/wc -l < "$(TOK "$d")" | tr -d ' ')
run_meter "$d" >/dev/null; n2=$(/usr/bin/wc -l < "$(TOK "$d")" | tr -d ' ')
if [ "$n1" = "$n2" ] && [ "$n1" -ge 3 ]; then ok "T5.a 멱등 upsert (줄 수 $n1 불변)"; else nope "T5.a" "n1=$n1 n2=$n2"; fi

# T5.b 키 집합 정확 일치 + 원문 필드 부재
T=$(TOK "$d")
base='agent,cache_read,cache_write,dedupe,fid,input,messages,model,output,schema_version,scope,session,ts,window_end,window_start'
# jq keys 는 코드포인트 정렬 — 기대값도 같은 규칙으로 정렬해 "집합" 일치만 본다(순서 무관)
_ksort() { jq -rn --arg w "$1" '$w | split(",") | sort | join(",")'; }
want_main=$(_ksort "$base,overlap_other_sessions,synthetic_excluded"); want_sub=$(_ksort "$base,agent_model")
got_main=$(jq -r 'select(.agent=="main")|keys|join(",")' "$T"); got_sub=$(jq -r 'select(.agent=="general-purpose:aaa")|keys|join(",")' "$T")
# 원문 필드 검사는 -s any — 줄별 -e 는 마지막 레코드의 판정만 종료 코드에 남는다
if [ -n "$want_main" ] && [ "$got_main" = "$want_main" ] && [ "$got_sub" = "$want_sub" ] \
   && jq -se 'length >= 3 and (any(.[]; has("prompt") or has("content") or has("text") or has("message")) | not)' "$T" >/dev/null 2>&1; then
  ok "T5.b 키 집합 정확 일치·원문 필드 없음"
else
  nope "T5.b" "main=$got_main sub=$got_sub"
fi

# T5.c --session 으로 다른 세션 추가 → 두 세션 레코드 공존, 첫 세션 보존
SID2=22222222-3333-4444-5555-666666666666
{ _line msg_X m9 77 2026-09-30T10:10:00.000Z; } > "$d/cfg/projects/-p/$SID2.jsonl"
run_meter "$d" --session "$SID2" >/dev/null
if jq -e --arg s "$SID" 'select(.session==$s and .agent=="main")' "$T" >/dev/null 2>&1 \
   && jq -e --arg s "$SID2" 'select(.session==$s and .agent=="main" and .output==77)' "$T" >/dev/null 2>&1; then
  ok "T5.c --session 두 세션 공존"
else
  nope "T5.c" "sessions=$(jq -r '.session' "$T" | sort -u | tr '\n' ' ')"
fi

# T5.d 같은 id 의 여러 줄에서 input·cache_read·cache_write 도 달라질 때 4필드 모두 id별 최댓값 (AC-1·AC-4)
#   msg_D: 최댓값이 가운데 줄 — 첫 줄(.[0])·마지막 줄(.[-1]) 채택 변이와 구분된다
#     (i1 cr90 cw40 o5) → (i3 cr120 cw60 o7) → (i2 cr100 cw50 o6)  ⇒ max i3 cr120 cw60 o7
#   msg_E: 1줄 (i4 cr10 cw5 o1) — id 간 합산
d=$(mk_env t5d)
{
  _line msg_D m1 5 2026-09-30T10:00:10.000Z 1 90  40
  _line msg_D m1 7 2026-09-30T10:00:10.300Z 3 120 60
  _line msg_D m1 6 2026-09-30T10:00:10.600Z 2 100 50
  _line msg_E m1 1 2026-09-30T10:00:11.000Z 4 10  5
} > "$d/cfg/projects/-p/$SID.jsonl"
run_meter "$d" >/dev/null
if jq -e 'select(.agent=="main") |
     .input==7 and .output==8 and .cache_read==130 and .cache_write==65 and .messages==2' "$(TOK "$d")" >/dev/null 2>&1; then
  ok "T5.d id별 4필드 모두 max(가운데 줄 최댓값) 합산"
else
  nope "T5.d" "rec=$(jq -c 'select(.agent=="main")' "$(TOK "$d")" 2>/dev/null)"
fi

# T5.e 구간 밖 mtime 의 다른 세션 파일은 overlap 에서 제외 (기준점 2026-09-30T10:00Z 이전 mtime)
d=$(mk_env t5e); mk_core "$d"; mk_sub "$d"
echo '{}' > "$d/cfg/projects/-p/other-old.jsonl"
touch -t 202609290000 "$d/cfg/projects/-p/other-old.jsonl"
run_meter "$d" >/dev/null
if jq -e 'select(.agent=="main") | .overlap_other_sessions==1' "$(TOK "$d")" >/dev/null 2>&1; then
  ok "T5.e 구간 밖 mtime 세션 파일 제외 (overlap 1 유지)"
else
  nope "T5.e" "rec=$(jq -c 'select(.agent=="main")' "$(TOK "$d")" 2>/dev/null)"
fi

_one() { jq -c 'select(.status=="unmeasured")|.reason' "$1" 2>/dev/null | tr -d '"'; }

# T6.a env 부재 → exit 0·unmeasured(no-session-id)·무출력 (AC-5)
d=$(mk_env t6a); mk_core "$d"
out=$( cd "$d/work" && env -u CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR="$d/cfg" bash "$METER" "$FID" 2>&1 ); ec=$?
[ "$ec" -eq 0 ] && [ -z "$out" ] && [ "$(_one "$(TOK "$d")")" = "no-session-id" ] && ok "T6.a env 부재 → no-session-id" || nope "T6.a" "ec=$ec out='$out' rec=$(cat "$(TOK "$d")" 2>/dev/null)"

# T6.a2 같은 env 부재 호출 2회 → session "unknown" 레코드가 교체(1줄 유지) — _upsert 의 ${SID:-unknown}
( cd "$d/work" && env -u CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR="$d/cfg" bash "$METER" "$FID" >/dev/null 2>&1 )
n=$(/usr/bin/wc -l < "$(TOK "$d")" 2>/dev/null | tr -d ' ')
[ "$n" = 1 ] && jq -e '.session=="unknown"' "$(TOK "$d")" >/dev/null 2>&1 && ok "T6.a2 unknown 세션 멱등 (1줄)" || nope "T6.a2" "n=$n rec=$(cat "$(TOK "$d")" 2>/dev/null)"

# T6.b transcript 부재 → transcript-not-found
d=$(mk_env t6b)
out=$(run_meter "$d"); ec=$?
[ "$ec" -eq 0 ] && [ -z "$out" ] && [ "$(_one "$(TOK "$d")")" = "transcript-not-found" ] && ok "T6.b transcript 부재" || nope "T6.b" "ec=$ec out='$out' rec=$(cat "$(TOK "$d")" 2>/dev/null)"

# T6.c usage 없는 줄만 / T6.d 깨진 줄만 → no-messages-in-window
d=$(mk_env t6c); echo '{"type":"assistant","timestamp":"2026-09-30T10:01:00.000Z","message":{"id":"msg_n","model":"m1"}}' > "$d/cfg/projects/-p/$SID.jsonl"
out=$(run_meter "$d"); ec=$?
[ "$ec" -eq 0 ] && [ -z "$out" ] && [ "$(_one "$(TOK "$d")")" = "no-messages-in-window" ] && ok "T6.c usage 없음" || nope "T6.c" "rec=$(cat "$(TOK "$d")" 2>/dev/null)"
d=$(mk_env t6d); printf 'broken{\n{also broken\n' > "$d/cfg/projects/-p/$SID.jsonl"
out=$(run_meter "$d"); ec=$?
[ "$ec" -eq 0 ] && [ -z "$out" ] && [ "$(_one "$(TOK "$d")")" = "no-messages-in-window" ] && ok "T6.d 깨진 JSON" || nope "T6.d" "rec=$(cat "$(TOK "$d")" 2>/dev/null)"

# T6.e jq 부재(PATH 비움, /bin/bash 절대경로) → exit 0·무기록·무출력
d=$(mk_env t6e); mk_core "$d"; mkdir -p "$TD/empty"
out=$( cd "$d/work" && env PATH="$TD/empty" CLAUDE_CONFIG_DIR="$d/cfg" CLAUDE_CODE_SESSION_ID="$SID" /bin/bash "$METER" "$FID" 2>&1 ); ec=$?
[ "$ec" -eq 0 ] && [ -z "$out" ] && [ ! -e "$(TOK "$d")" ] && ok "T6.e jq 부재 → 무기록·무출력" || nope "T6.e" "ec=$ec out='$out'"

# T6.f(NFR-3) tokens.jsonl 이 symlink → 링크 유지·원본(victim) 불변·exit 0·무출력
#   victim 은 유효 JSON — 비 JSON 이면 검사 줄을 지워도 _upsert 의 jq 실패로 mv 전에 빠져 판별력이 없다
d=$(mk_env t6f); mk_core "$d"; echo '{"session":"victim"}' > "$TD/victim"; ln -s "$TD/victim" "$(TOK "$d")"
out=$(run_meter "$d"); ec=$?
[ "$ec" -eq 0 ] && [ -z "$out" ] && [ -L "$(TOK "$d")" ] && [ "$(cat "$TD/victim")" = '{"session":"victim"}' ] && ok "T6.f symlink 거부" || nope "T6.f" "ec=$ec link=$([ -L "$(TOK "$d")" ] && echo y || echo n) victim=$(cat "$TD/victim")"

# T6.g(NFR-3) FID 경로 이탈 → exit 2·무기록
d=$(mk_env t6g)
( cd "$d/work" && bash "$METER" '../x' >/dev/null 2>&1 ); ec=$?
[ "$ec" -eq 2 ] && ok "T6.g FID 검증 exit 2" || nope "T6.g" "ec=$ec"

# T6.h(AC-8 테스트 격리) fid-start 없음 + 읽을 수 없는 CLAUDE_CONFIG_DIR → 에러·출력·기록 없음·3초 이내
#   읽을 수 없는 디렉터리가 접근 시도를 드러내는 덫이다 — root 는 그대로 읽어 덫이 무력하므로 SKIP
if [ "$(id -u)" -eq 0 ]; then
  skip "T6.h fid-start 부재 → 접근 시도 없음 — root 로 실행 중(권한 검사 무의미)"
else
d=$(mk_env t6h); : > "$d/work/.specops/$FID/metrics.jsonl"; mkdir -p "$TD/noread"; chmod 000 "$TD/noread"
t0=$(date +%s)
out=$( cd "$d/work" && HOME=/nonexistent CLAUDE_CONFIG_DIR="$TD/noread" CLAUDE_CODE_SESSION_ID="$SID" bash "$METER" "$FID" 2>&1 ); ec=$?
t1=$(date +%s); chmod 755 "$TD/noread"
[ "$ec" -eq 0 ] && [ -z "$out" ] && [ ! -e "$(TOK "$d")" ] && [ $((t1 - t0)) -le 3 ] && ok "T6.h fid-start 부재 → 접근 시도 없음(출력·에러·기록 0)" || nope "T6.h" "ec=$ec out='$out' dt=$((t1 - t0)) rec=$(cat "$(TOK "$d")" 2>/dev/null)"
fi

# T6.i 기준점 파싱 실패(--since 비 ISO) → exit 0·무출력·unmeasured(bad-baseline)
d=$(mk_env t6i); mk_core "$d"
out=$(run_meter "$d" --since not-a-date); ec=$?
[ "$ec" -eq 0 ] && [ -z "$out" ] && [ "$(_one "$(TOK "$d")")" = "bad-baseline" ] && ok "T6.i 기준점 파싱 실패 → bad-baseline" || nope "T6.i" "ec=$ec out='$out' rec=$(cat "$(TOK "$d")" 2>/dev/null)"

# report 는 transcript 를 읽지 않는다 — config·HOME 을 없는 경로로 고정해 실행(조회 전용)
RUN_REPORT() { ( cd "$1/work" && HOME=/nonexistent CLAUDE_CONFIG_DIR=/nonexistent CLAUDE_CODE_SESSION_ID="$SID" bash "$METER" --report "${@:2}" 2>&1 ); }
_has() { printf '%s\n' "$1" | /usr/bin/grep -q -- "$2"; }
_hasx() { printf '%s\n' "$1" | /usr/bin/grep -qxF -- "$2"; }

# T7.a 단일 FID report: 헤더·행·TOTAL·한계 문구 (AC-9)
#   main(2msg i4 o1018 cr300 cw70) + aaa(2msg i4 o100 cr200 cw100) + bbb(1msg i2 o5 cr100 cw50)
#   ⇒ TOTAL 5 10 1123 600 220 — 한 열이라도 합산에서 빠지면 이 줄이 달라진다
d=$(mk_env t7a); mk_core "$d"; mk_sub "$d"; run_meter "$d" >/dev/null
out=$(RUN_REPORT "$d" "$FID"); ec=$?
rows=$(printf '%s\n' "$out" | /usr/bin/grep -c '^11111111  ')
if [ "$ec" -eq 0 ] && [ "$rows" = 3 ] \
   && _hasx "$out" 'SESSION  AGENT  MODEL  MESSAGES  INPUT  OUTPUT  CACHE_READ  CACHE_WRITE' \
   && _hasx "$out" '11111111  main  m1  2  4  1018  300  70' \
   && _hasx "$out" '11111111  general-purpose:aaa  m2  2  4  100  200  100' \
   && _hasx "$out" '11111111  unknown:bbb  m3  1  2  5  100  50' \
   && _hasx "$out" 'TOTAL  -  -  5  10  1123  600  220' \
   && _has "$out" '^※ 중복 제거: message.id 별 최댓값' \
   && _has "$out" '^※ advisor .*미포함' \
   && _hasx "$out" '※ 포함 세션: 11111111' \
   && _has "$out" '^※ 구간과 겹치는 다른 세션 1개 미포함'; then
  ok "T7.a 단일 FID report 구성(합계 표·중복 제거·advisor·포함 세션·겹침)"
else
  nope "T7.a" "ec=$ec rows=$rows out=$out"
fi

# T7.b FID 생략 → 헤더 없이 FID당 정확히 1줄, unmeasured 는 사유 표기, exit 0 (AC-11)
d2=$(mk_env t7b); FID2=20261001-other; mkdir -p "$d2/work/.specops/$FID2"
cp "$d/work/.specops/$FID/tokens.jsonl" "$d2/work/.specops/$FID/tokens.jsonl"
jq -nc --arg fid "$FID2" '{schema_version:1,ts:"2026-10-01T00:00:00Z",fid:$fid,session:"x",status:"unmeasured",reason:"no-messages-in-window"}' > "$d2/work/.specops/$FID2/tokens.jsonl"
out=$(RUN_REPORT "$d2"); ec=$?; n=$(printf '%s\n' "$out" | /usr/bin/wc -l | tr -d ' ')
if [ "$ec" -eq 0 ] && [ "$n" = 2 ] \
   && _hasx "$out" "$FID2  측정 안 됨 (no-messages-in-window)" \
   && _hasx "$out" "$FID  input=10 output=1123 cache_read=600 cache_write=220 sessions=1"; then
  ok "T7.b FID 생략 → FID당 1줄(합계 / 측정 안 됨 (사유))"
else
  nope "T7.b" "ec=$ec n=$n out=$out"
fi

# T7.c 기록 없는 FID → '측정 안 됨 (기록 없음)' (0 이 아님), exit 0
d3=$(mk_env t7c); out=$(RUN_REPORT "$d3" "$FID"); ec=$?
[ "$ec" -eq 0 ] && _hasx "$out" "$FID  측정 안 됨 (기록 없음)" && ! _has "$out" 'TOTAL' \
  && ok "T7.c 기록 없음 표기" || nope "T7.c" "ec=$ec out=$out"

# T7.d 다중 세션(--session) + 다중 서브에이전트 → TOTAL·포함 세션·FID 생략 요약이 두 세션을 합산
#   T7.a 값 + SID2 main(1msg i2 o77 cr100 cw50) ⇒ TOTAL 6 12 1200 700 270 · sessions=2
#   (겹침 수는 단언하지 않는다 — 두 번째 세션 레코드는 이미 포함된 첫 세션 파일도 세므로)
d4=$(mk_env t7d); mk_core "$d4"; mk_sub "$d4"; run_meter "$d4" >/dev/null
{ _line msg_X m9 77 2026-09-30T10:10:00.000Z; } > "$d4/cfg/projects/-p/$SID2.jsonl"
run_meter "$d4" --session "$SID2" >/dev/null
out=$(RUN_REPORT "$d4" "$FID"); sum=$(RUN_REPORT "$d4")
if _hasx "$out" 'TOTAL  -  -  6  12  1200  700  270' \
   && _hasx "$out" '22222222  main  m9  1  2  77  100  50' \
   && _hasx "$out" '※ 포함 세션: 11111111,22222222' \
   && [ "$sum" = "$FID  input=12 output=1200 cache_read=700 cache_write=270 sessions=2" ]; then
  ok "T7.d 다중 세션·서브에이전트 TOTAL·요약 합산"
else
  nope "T7.d" "out=$out sum=$sum"
fi

# T7.e report 는 조회 전용 — transcript 를 열지 않고(config 없는 경로) tokens.jsonl 도 바꾸지 않는다
cp "$(TOK "$d")" "$TD/t7e.before"
out=$(RUN_REPORT "$d" "$FID"); ec=$?
if [ "$ec" -eq 0 ] && cmp -s "$TD/t7e.before" "$(TOK "$d")" \
   && _hasx "$out" 'TOTAL  -  -  5  10  1123  600  220' && ! _has "$out" '측정 안 됨'; then
  ok "T7.e report 읽기 전용(transcript 미접근·기록 불변)"
else
  nope "T7.e" "ec=$ec out=$out rec=$(cat "$(TOK "$d")" 2>/dev/null)"
fi

# ── T8 verify 러너 배선 (AC-6·AC-13) ─────────────────────────────────────────
FIDW=20260101-wiring   # 도입 cutoff 이전 날짜 — 신규 게이트(intent 등)가 fixture 를 막지 않게
mk_plugin() {
  local p="$TD/plugin"; rm -rf "$p"; mkdir -p "$p/scripts"
  cp -R "$PLUGIN/scripts/_internal" "$p/scripts/_internal"
  cp -R "$PLUGIN/scripts/dag" "$p/scripts/dag"   # extract-test-commands.sh 가 ../dag/parse-dag.sh 를 source
  echo "$p"
}
# mk_vwork <name> <cmd-script> [nofidstart] — tasks.md 에 해당 dummy 한 줄, fid-start(compact) 기록
mk_vwork() {
  local w="$TD/$1"; rm -rf "$w"; mkdir -p "$w/.specops/$FIDW" "$w/scripts/tests"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$w/scripts/tests/dummy-pass.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$w/scripts/tests/dummy-fail.sh"
  printf -- '- [ ] **스텝 4**: 실행: `bash scripts/tests/%s`\n' "$2" > "$w/.specops/$FIDW/tasks.md"
  if [ "${3:-}" = nofidstart ]; then
    jq -nc '{phase:"risk-profile",ts:"2026-09-30T10:00:00Z"}' > "$w/.specops/$FIDW/metrics.jsonl"
  else
    jq -nc '{phase:"fid-start",ts:"2026-09-30T10:00:00Z"}' > "$w/.specops/$FIDW/metrics.jsonl"
  fi
  echo "$w"
}
# mk_stub <marker> <tail-cmd> — meter 자리를 대체: marker touch + stdout·stderr 에 'meter-stub' 출력 후 <tail-cmd>
#   (출력이 있어야 배선의 >/dev/null 2>&1 이 빠졌을 때 누출이 보인다 — 무출력 stub 은 그 변이를 못 잡는다)
mk_stub() {
  printf '#!/usr/bin/env bash\ntouch "%s/%s"\necho meter-stub-out\necho meter-stub-err >&2\n%s\n' \
    "$TD" "$1" "$2" > "$P/scripts/_internal/meter-tokens.sh"
}

# T8.a 정적 배선: bounded_run 5 + fid-start 가드 (AC-6)
RV="$PLUGIN/scripts/_internal/run-verification.sh"
if /usr/bin/grep -q 'bounded_run 5 bash "\$METER_SH"' "$RV" && /usr/bin/grep -q '"phase":"fid-start"' "$RV"; then
  ok "T8.a 배선 문자열(bounded_run 5·fid-start 가드)"; else nope "T8.a" "미배선"; fi

# T8.b meter 를 sleep stub 으로 교체 — 호출됐는지(marker)와 5초 상한·verdict·stamp 불변·출력 무누출 (AC-13·AC-6)
P=$(mk_plugin)
mk_stub meter-ran 'sleep 30'
W=$(mk_vwork vw1 dummy-pass.sh); rm -f "$TD/meter-ran"
t0=$(date +%s); out=$( cd "$W" && bash "$P/scripts/_internal/run-verification.sh" "$FIDW" 2>"$TD/vw1.err" ); ec=$?; t1=$(date +%s)
if [ -e "$TD/meter-ran" ] && [ "$ec" -eq 0 ] && [ $((t1 - t0)) -lt 12 ] \
   && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] \
   && ! printf '%s\n' "$out" | /usr/bin/grep -qiE 'meter|Terminated' \
   && ! /usr/bin/grep -qiE 'meter|Terminated' "$TD/vw1.err" \
   && [ "$(/usr/bin/grep -c 'RUN-VERIFICATION-RESULT: PASS' "$W/.specops/$FIDW/evidence.md")" = 1 ]; then
  ok "T8.b meter 호출됨·5초 상한 후 VERIFY: PASS·rc 0·PASS stamp·meter 출력 없음"
else
  nope "T8.b" "ran=$([ -e "$TD/meter-ran" ] && echo y || echo n) ec=$ec dt=$((t1 - t0)) out='$out' err=$(/usr/bin/grep -iE 'meter|Terminated' "$TD/vw1.err")"
fi

# T8.c meter 가 exit 1 이어도 PASS 경로 불변
mk_stub meter-ran2 'exit 1'
W=$(mk_vwork vw2 dummy-pass.sh); rm -f "$TD/meter-ran2"
out=$( cd "$W" && bash "$P/scripts/_internal/run-verification.sh" "$FIDW" 2>/dev/null ); ec=$?
[ -e "$TD/meter-ran2" ] && [ "$ec" -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] \
  && ok "T8.c meter exit 1 → verdict 불변" || nope "T8.c" "ec=$ec out='$out'"

# T8.d verify FAIL 경로: rc 1·stderr VERIFY: FAIL·evidence stamp 불변·출력 무누출 (AC-6)
W=$(mk_vwork vw3 dummy-fail.sh); rm -f "$TD/meter-ran2"
( cd "$W" && bash "$P/scripts/_internal/run-verification.sh" "$FIDW" >"$TD/vw3.out" 2>"$TD/vw3.err" ); ec=$?
if [ "$ec" -eq 1 ] && /usr/bin/grep -q 'VERIFY: FAIL' "$TD/vw3.err" \
   && /usr/bin/grep -q 'RUN-VERIFICATION-RESULT: FAIL' "$W/.specops/$FIDW/evidence.md" \
   && [ -e "$TD/meter-ran2" ] && ! /usr/bin/grep -qiE 'meter|Terminated' "$TD/vw3.err" "$TD/vw3.out"; then
  ok "T8.d FAIL 경로 불변(rc 1·stderr·stamp)·meter 호출됨"
else
  nope "T8.d" "ec=$ec err=$(head -3 "$TD/vw3.err") leak=$(/usr/bin/grep -iE 'meter|Terminated' "$TD/vw3.err" "$TD/vw3.out")"
fi

# T8.e fid-start 가드: metrics.jsonl 에 fid-start 가 없는 FID(=기존 스위트 fixture)는 meter 호출 자체가 없다 (AC-6)
W=$(mk_vwork vw4 dummy-pass.sh nofidstart); rm -f "$TD/meter-ran2"
out=$( cd "$W" && bash "$P/scripts/_internal/run-verification.sh" "$FIDW" 2>/dev/null ); ec=$?
if [ ! -e "$TD/meter-ran2" ] && [ "$ec" -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ]; then
  ok "T8.e fid-start 부재 FID → meter 비호출·verdict 불변"
else
  nope "T8.e" "ran=$([ -e "$TD/meter-ran2" ] && echo y || echo n) ec=$ec out='$out'"
fi

# ── T9 거버넌스 격리·propagation·문서·doc-lock (AC-7) ─────────────────────────
# T9.a 거버넌스 격리: hooks/ 어디에도 meter-tokens·tokens.jsonl 참조 없음 (AC-7)
if ! /usr/bin/grep -rqE 'meter-tokens|tokens\.jsonl' "$PLUGIN/hooks"; then ok "T9.a hooks/ 비참조"; else nope "T9.a" "hooks 에 참조 존재"; fi
# T9.a2 판별력: hooks 임시 사본에 문자열 주입하면 탐지된다
mkdir -p "$TD/hk"; cp -R "$PLUGIN/hooks/." "$TD/hk/"; echo '# meter-tokens' >> "$TD/hk/session-start.sh"
/usr/bin/grep -rqE 'meter-tokens|tokens\.jsonl' "$TD/hk" && ok "T9.a2 격리 검사 판별력" || nope "T9.a2" "주입을 못 잡음"
# T9.b propagation 레코드
/usr/bin/grep -q '"id": *"token-metering"' "$PLUGIN/scripts/_internal/propagation-matrix.jsonl" && ok "T9.b propagation 레코드" || nope "T9.b" "미등록"
# T9.c README 절
/usr/bin/grep -q '^## meter-tokens.sh' "$PLUGIN/scripts/README.md" && ok "T9.c README 절" || nope "T9.c" "미작성"
# T9.d doc-lock: 이 스위트 추가로 CLAUDE.md·.githooks/pre-push 의 suite-count 잠금 줄이 실측과 일치해야 한다.
#   수치를 리터럴로 박지 않고 검사기에 위임한다 — 리터럴이면 다음 스위트 추가 때 이 기능 스위트가 오탐 red 가 되고,
#   그 줄 자체가 check-doc-numbers 의 무마커 수치로 잡힌다. DOC_NUMBERS_ROOT 는 이 호출에만 prefix,
#   훅 git env 는 서브셸에서만 뗀다(test-doc-numbers.sh 와 같은 호출 — pre-push 안 run-all 에서 공허 통과 방지).
dn_out=$( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE; DOC_NUMBERS_ROOT="$PLUGIN" bash "$PLUGIN/scripts/_internal/check-doc-numbers.sh" 2>&1 ); dn_rc=$?
if [ "$dn_rc" -eq 0 ] && printf '%s\n' "$dn_out" | /usr/bin/grep -q '^DOC-NUMBERS: OK (suite-count='; then
  ok "T9.d doc-lock suite-count 일치(CLAUDE.md·pre-push)"
else
  nope "T9.d" "rc=$dn_rc $(printf '%s\n' "$dn_out" | /usr/bin/grep 'DOC-NUMBERS: FAIL' | head -3)"
fi

# ── T10 Phase C 지적 반영 (AC-5·AC-6·AC-9) ─────────────────────────────────────
# T10.a usage 타입 방어: 이상값 줄마다 고유 id — max 가 이상값을 가리지 못하게 한다.
#   제외(usage 비객체): msg_str(문자열)·msg_nul(null)·msg_arr(배열)·msg_mstr(.message 가 문자열)
#   포함·숫자 아님→0: msg_tstr(4필드 전부 문자열) — 메시지로는 센다(messages 에 1 기여)
#   포함·음수→0: msg_neg(o -5 · i 1, 이 id 의 유일한 줄) — 토큰 수는 정의상 0 이상이라 음수는 형식 이상으로 본다
#   같은 id 공존: msg_V2 유효 줄(o20) + 문자열 토큰 줄(o "999") — 미방어 jq 는 max 에서 문자열을 숫자보다 크게 친다
#   ⇒ messages 4(V1·tstr·neg·V2) · input 2+0+1+3=6 · output 10+0+0+20=30 · cache_read 100+0+0+200=300 · cache_write 50+0+0+20=70
d=$(mk_env t10a)
{
  _line msg_V1 m1 10 2026-09-30T10:01:00.000Z 2 100 50
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-30T10:01:01.000Z","message":{"id":"msg_str","model":"m1","usage":"x"}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-30T10:01:02.000Z","message":{"id":"msg_nul","model":"m1","usage":null}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-30T10:01:03.000Z","message":{"id":"msg_arr","model":"m1","usage":[1,2]}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-30T10:01:04.000Z","message":"msg_mstr"}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-30T10:01:05.000Z","message":{"id":"msg_tstr","model":"m1","usage":{"input_tokens":"5","output_tokens":"7","cache_read_input_tokens":"1","cache_creation_input_tokens":"2"}}}'
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-30T10:01:06.000Z","message":{"id":"msg_neg","model":"m1","usage":{"input_tokens":1,"output_tokens":-5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
  _line msg_V2 m1 20 2026-09-30T10:01:07.000Z 3 200 20
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-30T10:01:07.500Z","message":{"id":"msg_V2","model":"m1","usage":{"input_tokens":"9","output_tokens":"999","cache_read_input_tokens":"9","cache_creation_input_tokens":"9"}}}'
} > "$d/cfg/projects/-p/$SID.jsonl"
out=$(run_meter "$d"); ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ] && [ -z "$(_one "$(TOK "$d")")" ] \
   && jq -e 'select(.agent=="main") |
        .messages==4 and .input==6 and .output==30 and .cache_read==300 and .cache_write==70' "$(TOK "$d")" >/dev/null 2>&1; then
  ok "T10.a usage 타입 이상(비객체·문자열·음수) 줄 혼재 → 유효 줄만 집계·사유 오기록 없음"
else
  nope "T10.a" "ec=$ec out='$out' rec=$(cat "$(TOK "$d")" 2>/dev/null)"
fi

# T10.b FID 디렉토리 부재 + --since → stderr·stdout 무출력·exit 0·디렉토리 재생성 없음 (AC-5)
d=$(mk_env t10b); mk_core "$d"; rm -rf "$d/work/.specops/$FID"
out=$(run_meter "$d" --since 2026-09-30T10:00:00Z); ec=$?
if [ "$ec" -eq 0 ] && [ -z "$out" ] && [ ! -e "$d/work/.specops/$FID" ]; then
  ok "T10.b FID 디렉토리 부재 + --since → 무출력·exit 0"
else
  nope "T10.b" "ec=$ec out='$out'"
fi

# T10.c 가드 결합 잠금 (AC-6): record-metric.sh 의 **실제 출력 줄**이 run-verification 가드 문자열에 매치해야 한다.
#   가드 문자열은 run-verification.sh 에서 추출 — 한쪽 직렬화·가드가 바뀌면 여기서 갈라진다.
#   추출 실패 시 grep -q "" 는 모든 줄에 매치하므로(공허 통과) 비어 있지 않고 fid-start 를 담는지 먼저 본다.
guard=$(sed -n "s/.*grep -q '\\([^']*\\)' \"\\.specops\\/\\\$FID\\/metrics\\.jsonl\".*/\\1/p" "$RV" | head -1)
mkdir -p "$TD/rm10"
( cd "$TD/rm10" && SPECOPS_ROOT="$TD/rm10/.specops" bash "$PLUGIN/scripts/_internal/record-metric.sh" --fid "$FID" --phase fid-start >/dev/null 2>&1 ); rmrc=$?
case "$guard" in *fid-start*) g_ok=1 ;; *) g_ok=0 ;; esac
if [ "$g_ok" = 1 ] && [ "$rmrc" -eq 0 ] && /usr/bin/grep -q -- "$guard" "$TD/rm10/.specops/$FID/metrics.jsonl"; then
  ok "T10.c record-metric fid-start 실출력 ↔ run-verification 가드 문자열 결합"
else
  nope "T10.c" "guard='$guard' rmrc=$rmrc line=$(cat "$TD/rm10/.specops/$FID/metrics.jsonl" 2>/dev/null)"
fi

# T10.d 임시 파일 잔존 0 — 전용 TMPDIR 에서 meter-tokens.* 만 센다(bounded_run 의 specops-bounded.* 는 대상 아님)
#   (i) TERM 경로: _unmeasured 의 jq 를 shim 으로 붙잡아 두고 bounded_run 1 로 죽인다 — rc 124 로 TERM 경로를 실제로 탔음을 확인.
#       bounded_run 은 TERM 을 두 번 보낸다(그룹 → pid). 신호→exit trap 이 없으면 두 번째 TERM 이 EXIT trap 의 rm 전에
#       셸을 죽이는 경쟁이 생긴다(실측 15회 중 4회 잔존) — 확률적이라 3회 반복해 판별력을 올린다.
#   (ii) 정상 경로 4종: 성공·transcript-not-found·bad-baseline·no-messages-in-window
source "$PLUGIN/scripts/_internal/run-bounded.sh"
REALJQ=$(command -v jq)
mkdir -p "$TD/shim" "$TD/tmp10" "$TD/tmp10n"
printf '#!/bin/bash\ncase "$*" in *unmeasured*) sleep 4 ;; esac\nexec "%s" "$@"\n' "$REALJQ" > "$TD/shim/jq"; chmod +x "$TD/shim/jq"
d=$(mk_env t10d); brc=124; left=0
for _k in 1 2 3; do
  ( cd "$d/work" && export TMPDIR="$TD/tmp10" PATH="$TD/shim:$PATH" CLAUDE_CONFIG_DIR="$d/cfg" CLAUDE_CODE_SESSION_ID="$SID" \
      && bounded_run 1 bash "$METER" "$FID" >/dev/null 2>&1 ); r=$?
  [ "$r" -eq 124 ] || brc=$r
  n=$(find "$TD/tmp10" "$d/work/.specops/$FID" -name 'meter-tokens.*' -o -name 'tokens.jsonl.tmp.*' 2>/dev/null | /usr/bin/wc -l | tr -d ' ')
  left=$((left + n))
done
d1=$(mk_env t10d1); mk_core "$d1"; d2=$(mk_env t10d2); d3=$(mk_env t10d3); mk_core "$d3"
d4=$(mk_env t10d4); { _line msg_P m1 1000 2026-09-30T09:59:59.900Z; } > "$d4/cfg/projects/-p/$SID.jsonl"
for e in "$d1" "$d2" "$d4"; do TMPDIR="$TD/tmp10n" run_meter "$e" >/dev/null; done
TMPDIR="$TD/tmp10n" run_meter "$d3" --since not-a-date >/dev/null
leftn=$(find "$TD/tmp10n" -name 'meter-tokens.*' 2>/dev/null | /usr/bin/wc -l | tr -d ' ')
if [ "$brc" -eq 124 ] && [ "$left" = 0 ] && [ "$leftn" = 0 ] \
   && [ -n "$(_one "$(TOK "$d2")")" ] && [ "$(_one "$(TOK "$d3")")" = bad-baseline ]; then
  ok "T10.d 임시 파일 잔존 0 (TERM 경로·정상 4경로)"
else
  nope "T10.d" "brc=$brc left=$left leftn=$leftn files=$(find "$TD/tmp10" "$TD/tmp10n" -name 'meter-tokens.*' 2>/dev/null | tr '\n' ' ')"
fi

# T10.f 신호 중복 도착(bounded_run 의 그룹→pid TERM 두 번)에도 임시 파일 잔존 0 — 20261004
#   Ubuntu CI T10.d `left=2` 의 기전: 두 번째 TERM 이 첫 신호의 exit 처리 중(EXIT trap 의 rm 시작 전)에 도착하면 nested exit 로 rm 이
#   생략돼 임시 파일 2개가 남는다. 실제 meter-tokens.sh 는 외부 자식(shim jq)을 기다리는 동안 두 TERM 이 합쳐져 창이 좁아 결정적으로 못 만든다 —
#   그래서 product 의 EXIT trap 줄·신호 trap 줄을 **그대로 추출**해 builtin wait 로 대기하는 피해 셸에 이식하고 TERM 을 연속 두 번 보낸다
#   (창이 넓어져 핸들러 원복 변이에서 bash 3.2 다수 잔존). 공허 통과 방지: 줄 추출이 비면 FAIL · 임시 파일 2개가 생긴 회차(armed)가 전 회차여야 한다.
_ext_exit=$(sed -n "/^  trap 'rm -f .*' EXIT$/p" "$METER" | sed -n 1p)
_ext_sig=$(sed -n "/^  trap '.*' HUP; trap '.*' INT; trap '.*' TERM$/p" "$METER" | sed -n 1p)
_ign_n=$(printf '%s\n' "$_ext_sig" | grep -o 'trap "" HUP INT TERM' | /usr/bin/wc -l | tr -d ' ')   # HUP·INT·TERM 핸들러 모두 추가 신호를 무시하는지(3)
mkdir -p "$TD/tmp10f"
{ printf '#!/usr/bin/env bash\nset -u\nNEWREC=""; NR=""; UPTMP=""\n'; printf '%s\n' "$_ext_exit" "$_ext_sig"
  printf 'NEWREC=$(mktemp "$TMPDIR/mt.XXXXXX"); NR=$(mktemp "$TMPDIR/mt.XXXXXX")\nsleep 30 & wait $!\n'; } > "$TD/victim10f.sh"
_model_left=0; _model_bad=0; _model_armed=0; _model_n=20
if [ -n "$_ext_exit" ] && [ -n "$_ext_sig" ]; then
  for _k in $(seq 1 "$_model_n"); do
    rm -f "$TD/tmp10f"/mt.* 2>/dev/null
    set -m; TMPDIR="$TD/tmp10f" bash "$TD/victim10f.sh" >/dev/null 2>&1 & _p=$!; set +m
    _w=0; while [ "$(find "$TD/tmp10f" -name 'mt.*' 2>/dev/null | /usr/bin/wc -l | tr -d ' ')" -lt 2 ] && [ "$_w" -lt 200 ]; do sleep 0.05; _w=$((_w + 1)); done
    [ "$(find "$TD/tmp10f" -name 'mt.*' 2>/dev/null | /usr/bin/wc -l | tr -d ' ')" -ge 2 ] && _model_armed=$((_model_armed + 1))
    kill -TERM "$_p" 2>/dev/null; kill -TERM "$_p" 2>/dev/null
    { wait "$_p"; } 2>/dev/null; _r=$?
    [ "$_r" -eq 143 ] || _model_bad=$((_model_bad + 1))
    kill -KILL -- "-$_p" 2>/dev/null
    _model_left=$((_model_left + $(find "$TD/tmp10f" -name 'mt.*' 2>/dev/null | /usr/bin/wc -l | tr -d ' ')))
  done
fi
if [ -n "$_ext_exit" ] && [ -n "$_ext_sig" ] && [ "$_ign_n" = 3 ] && [ "$_model_armed" = "$_model_n" ] && [ "$_model_left" = 0 ] && [ "$_model_bad" = 0 ]; then
  ok "T10.f 연속 TERM ${_model_n}회(product 핸들러 줄 이식 모형) → 임시 파일 잔존 0 · 종료 코드 143 · HUP/INT/TERM 핸들러 모두 추가 신호 무시"
else nope "T10.f" "추출 exit='$_ext_exit' sig='$_ext_sig' 무시핸들러수=$_ign_n armed=$_model_armed/$_model_n 잔존=$_model_left 종료코드이상=$_model_bad"; fi
# T10.g 핸들러 계약 보존 — 실제 meter-tokens.sh 에 TERM·INT·HUP 하나씩(그룹+pid 동시) → 종료 코드 143·130·129 · 잔존 0
#   INT·HUP 가 진입 시 무시된 환경(nohup·INT 무시 부모)에서는 bash 가 그 신호의 trap 을 걸지 못한다 — 사전 프로브(같은 방식으로 띄운 셸이 자기에게 신호를 쏴 살아남는지)로
#   판별해 그 신호의 단언은 SKIP 한다(환경 의존 새 플레이크를 심지 않는다). TERM 은 항상 단언한다. armed(임시 파일 2개가 생긴 뒤 신호)도 확인한다.
_sig_ignored() {  # <시그널> → 0=진입 시 무시됨(trap 불가)
  local sg="$1" of="$TD/ign10g.$1" _p
  rm -f "$of"; set -m
  ( exec bash -c 'kill -'"$sg"' $$; sleep 0.3; echo alive' >"$of" 2>/dev/null ) &
  _p=$!; set +m; { wait "$_p"; } 2>/dev/null
  [ "$(cat "$of" 2>/dev/null)" = alive ]
}
_sigrun() {  # <시그널> → "잔존수 종료코드 armed"
  local sg="$1" _p _w _r df left armed=0
  df=$(mk_env "t10g$sg"); rm -f "$TD/tmp10f"/meter-tokens.* 2>/dev/null
  set -m
  ( cd "$df/work" && export TMPDIR="$TD/tmp10f" PATH="$TD/shim:$PATH" CLAUDE_CONFIG_DIR="$df/cfg" CLAUDE_CODE_SESSION_ID="$SID" \
      && exec bash "$METER" "$FID" >/dev/null 2>&1 ) &
  _p=$!; set +m
  _w=0; while [ "$(find "$TD/tmp10f" -name 'meter-tokens.*' 2>/dev/null | /usr/bin/wc -l | tr -d ' ')" -lt 2 ] && [ "$_w" -lt 200 ]; do sleep 0.05; _w=$((_w + 1)); done
  [ "$(find "$TD/tmp10f" -name 'meter-tokens.*' 2>/dev/null | /usr/bin/wc -l | tr -d ' ')" -ge 2 ] && armed=1
  kill -"$sg" -- "-$_p" "$_p" 2>/dev/null
  { wait "$_p"; } 2>/dev/null; _r=$?
  left=$(find "$TD/tmp10f" -name 'meter-tokens.*' 2>/dev/null | /usr/bin/wc -l | tr -d ' ')
  echo "$left $_r $armed"
}
_g=$(_sigrun TERM)
if [ "$_g" = "0 143 1" ]; then ok "T10.g TERM 종료 코드 143 · 임시 파일 잔존 0 (armed)"; else nope "T10.g" "TERM 잔존·종료코드·armed='$_g'"; fi
for _sg in INT:130 HUP:129; do
  _name=${_sg%%:*}; _want=${_sg##*:}
  if _sig_ignored "$_name"; then skip "T10.g $_name — 진입 시 무시된 환경(nohup·$_name 무시 부모)이라 trap 불가: 종료 코드 단언 생략"
  else
    _g=$(_sigrun "$_name")
    if [ "$_g" = "0 $_want 1" ]; then ok "T10.g $_name 종료 코드 $_want · 임시 파일 잔존 0 (armed)"; else nope "T10.g" "$_name 잔존·종료코드·armed='$_g' (기대 '0 $_want 1')"; fi
  fi
done

# T10.e 손상된 tokens.jsonl report → stderr 무출력·exit 0·"읽을 수 없음" 표기(거짓 "측정 안 됨 (사유 없음)" 아님) (AC-9)
#   FID 지정·생략 두 모드 모두 — 생략 모드에서도 그 FID 는 정확히 1줄
d=$(mk_env t10e); mk_core "$d"; run_meter "$d" >/dev/null; echo 'broken{' >> "$(TOK "$d")"
want="$FID  읽을 수 없음 (tokens.jsonl 손상 — 파일 삭제 후 재측정)"
out=$( cd "$d/work" && HOME=/nonexistent CLAUDE_CONFIG_DIR=/nonexistent bash "$METER" --report "$FID" 2>"$TD/t10e.err" ); ec=$?
sum=$( cd "$d/work" && HOME=/nonexistent CLAUDE_CONFIG_DIR=/nonexistent bash "$METER" --report 2>"$TD/t10e2.err" ); ec2=$?
if [ "$ec" -eq 0 ] && [ "$ec2" -eq 0 ] && [ ! -s "$TD/t10e.err" ] && [ ! -s "$TD/t10e2.err" ] \
   && [ "$out" = "$want" ] && [ "$sum" = "$want" ] && ! _has "$out" '사유 없음'; then
  ok "T10.e 손상 tokens.jsonl report → '읽을 수 없음'·stderr 0·exit 0"
else
  nope "T10.e" "ec=$ec/$ec2 out='$out' sum='$sum' err=$(cat "$TD/t10e.err" "$TD/t10e2.err" 2>/dev/null | head -2)"
fi
# T10.e2 유효 JSON 이지만 객체가 아닌 줄(5) — jq 파싱은 통과하나 레코드가 아니다. 같은 표기·stderr 0
d=$(mk_env t10e2); mk_core "$d"; run_meter "$d" >/dev/null; echo '5' >> "$(TOK "$d")"
out=$( cd "$d/work" && HOME=/nonexistent CLAUDE_CONFIG_DIR=/nonexistent bash "$METER" --report "$FID" 2>"$TD/t10e3.err" ); ec=$?
if [ "$ec" -eq 0 ] && [ ! -s "$TD/t10e3.err" ] && [ "$out" = "$want" ]; then
  ok "T10.e2 객체 아닌 줄 → '읽을 수 없음'·stderr 0"
else
  nope "T10.e2" "ec=$ec out='$out' err=$(head -2 "$TD/t10e3.err" 2>/dev/null)"
fi

finish
