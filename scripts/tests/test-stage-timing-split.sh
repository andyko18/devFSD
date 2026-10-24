#!/usr/bin/env bash
# stage-timing.sh --split · transcript-turns.sh — 작업·사람·백그라운드 분리 계측 (fixture 만 사용 — 실제 ~/.claude 를 읽지 않는다, 토큰 0)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq 필요"; exit 0; }
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ST="$PLUGIN/scripts/stage-timing.sh"
TT="$PLUGIN/scripts/_internal/transcript-turns.sh"
BASH_BIN=$(command -v bash)
SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/tmp"

ck() { if [ "$2" = "$3" ]; then echo "PASS $1"; PASS=$((PASS+1)); else echo "FAIL $1 — exp '$3' got '$2'"; FAIL=$((FAIL+1)); fi; }

# transcript fixture 파일을 만든다: mktr 경로 — 본문은 stdin. mtime 을 먼 미래로 고정해 원장 기간 필터(mtime ≥ 원장 최초 날짜)에 항상 걸리게 한다.
mktr() { mkdir -p "$(dirname "$1")" && cat > "$1" && touch -t 203001010000 "$1"; }
# 원장 fixture: ledger 이름 — 본문은 stdin. SPECOPS_ROOT 로 쓸 디렉토리를 만든다.
ledger() { mkdir -p "$SB/$1" && cat > "$SB/$1/session-progress.md"; }
# 실행: runs 이름 [옵션...] — TZ=UTC · 원장 $SB/이름 · 전역 OUT·ERR·RC. TMPDIR 은 전용 디렉토리(누출 검사용).
runs() {
  local nm="$1"; shift
  OUT=$(TZ="${TZV:-UTC}" TMPDIR="$SB/tmp" SPECOPS_ROOT="$SB/$nm" "$BASH_BIN" "$ST" "$@" 2>"$SB/err"); RC=$?
  ERR=$(cat "$SB/err")
}
# 표에서 단계 행의 "합계 … 작업 사람 백그라운드 기타" 를 뽑는다(열: 합계 비중 n 중앙값 p90 max 작업 사람 백그라운드 기타 단계)
row() { printf '%s\n' "$OUT" | grep -E " $1\$" | awk '{print $1, $7, $8, $9, $10}'; }
cnt() { printf '%s\n' "$OUT" | grep -c -- "$1"; }

# ── 공통 fixture: AC-3 transcript (10:01 H · 10:05 D 4분 · 10:09 N · 10:10 D 1분 · 10:13 H) ──
mktr "$SB/td1/s1.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-01T10:01:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"role":"user","content":"BODY-A"}}
{"type":"assistant","timestamp":"2026-10-01T10:03:00.000Z","message":{"content":[{"type":"text","text":"BODY-B"}]}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:05:00.000Z","durationMs":240000}
{"type":"user","timestamp":"2026-10-01T10:09:00.000Z","isMeta":false,"origin":{"kind":"task-notification"},"message":{"role":"user","content":"BODY-C"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:10:00.000Z","durationMs":60000}
{"type":"user","timestamp":"2026-10-01T10:13:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"role":"user","content":"BODY-D"}}
EOF

# ══ AC-1: 헬퍼 추출·분류 ══
mktr "$SB/h1.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-01T10:00:30.000Z","isMeta":false,"origin":{"kind":"weird-kind"},"message":{"content":"x"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:00:20.000Z","durationMs":12345}
{"type":"user","timestamp":"2026-10-01T10:00:10.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"content":"x"}}
{"type":"user","timestamp":"2026-10-01T10:00:11.000Z","isMeta":false,"message":{"content":"x"}}
{"type":"user","timestamp":"2026-10-01T10:00:12.000Z","isMeta":false,"origin":{"kind":"task-notification"},"message":{"content":"x"}}
{"type":"user","timestamp":"2026-10-01T10:00:13.000Z","isMeta":true,"origin":{"kind":"human"},"message":{"content":"x"}}
{"type":"user","timestamp":"2026-10-01T10:00:14.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"content":[{"type":"tool_result","content":"x"}]}}
{"type":"user","timestamp":"2026-10-01T10:00:15.000Z","isMeta":false,"isSidechain":true,"origin":{"kind":"human"},"message":{"content":"x"}}
{"type":"user","isMeta":false,"origin":{"kind":"human"},"message":{"content":"x"}}
this line is not json
{"type":"system","subtype":"other","timestamp":"2026-10-01T10:00:16.000Z","durationMs":5}
{"type":"assistant","timestamp":"2026-10-01T10:00:17.000Z","message":{"content":"x"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:00:18.000Z"}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:00:19.000Z","durationMs":-7}
EOF
EXP1=$(printf '%s\n' "1790848810	H	0" "1790848811	U	0" "1790848812	N	0" "1790848818	D	0" "1790848819	D	0" "1790848820	D	12345" "1790848830	U	0")
OUT1=$(TZ=UTC "$BASH_BIN" "$TT" "$SB/h1.jsonl"); RC1=$?
ck "T1.a 허용 필드만으로 D·H·N·U 분류·시간순 정렬 · 제외 대상(isMeta·도구결과·사이드체인·시각 없음·불량 JSON·다른 subtype·assistant) 무출력 · rc=0" "$RC1|$OUT1" "0|$EXP1"
EXP2=$(printf '%s\n' "$EXP1" "0	F	0" "1790848860	H	0" "1790849100	D	240000" "1790849340	N	0" "1790849400	D	60000" "1790849580	H	0")
OUT2=$("$BASH_BIN" "$TT" "$SB/h1.jsonl" "$SB/td1/s1.jsonl")
ck "T1.b 두 파일: 파일마다 시간순 정렬 + 둘째 파일 앞에 F 경계 한 줄(파일 사이에만)" "$OUT2" "$EXP2"
OUT3=$("$BASH_BIN" "$TT" "$SB/td1/s1.jsonl"); ck "T1.c 파일 하나면 F 없음" "$(printf '%s\n' "$OUT3" | grep -c $'\tF\t')" "0"
"$BASH_BIN" "$TT" >/dev/null 2>&1; R_A=$?; "$BASH_BIN" "$TT" "$SB/없는파일.jsonl" >/dev/null 2>&1; R_B=$?; "$BASH_BIN" "$TT" --bogus "$SB/h1.jsonl" >/dev/null 2>&1; R_C=$?
ck "T1.d 인자 없음·없는 파일·알 수 없는 옵션 → rc=2" "$R_A|$R_B|$R_C" "2|2|2"
OUT_KST=$(TZ=Asia/Seoul "$BASH_BIN" "$TT" --local "$SB/td1/s1.jsonl" | head -1 | cut -f1); OUT_UTC=$(TZ=UTC "$BASH_BIN" "$TT" --local "$SB/td1/s1.jsonl" | head -1 | cut -f1)
dd() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%d", a - b }'; }   # 빈 값이어도 산술 오류로 단언이 사라지지 않게 awk 로 뺀다
ck "T1.e --local 은 TZ 를 따른다(KST = UTC+9h)" "$(dd "$OUT_KST" "$OUT_UTC")" "32400"
mktr "$SB/tz.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-01-15T12:00:00.000Z","durationMs":1}
{"type":"system","subtype":"turn_duration","timestamp":"2026-07-15T12:00:00.000Z","durationMs":1}
EOF
TZLINES=$(TZ=America/New_York "$BASH_BIN" "$TT" --local "$SB/tz.jsonl" | cut -f1); W0=$(TZ=UTC "$BASH_BIN" "$TT" "$SB/tz.jsonl" | cut -f1)
ck "T1.f DST: 뉴욕 겨울 -5h · 여름 -4h" "$(dd "$(echo "$TZLINES" | sed -n 1p)" "$(echo "$W0" | sed -n 1p)")|$(dd "$(echo "$TZLINES" | sed -n 2p)" "$(echo "$W0" | sed -n 2p)")" "-18000|-14400"

# durationMs 상한: 7일(604800000)까지는 그대로, 초과·터무니없는 값은 0 — 깨진 큰 값이 구간 버킷 루프를 폭주시키지 않게
mktr "$SB/dur.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:00:01.000Z","durationMs":604800000}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:00:02.000Z","durationMs":604800001}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:00:03.000Z","durationMs":1000000000000000}
EOF
ck "T1.g durationMs 상한: 7일 경계는 유지 · 초과·1e15 는 0" "$("$BASH_BIN" "$TT" "$SB/dur.jsonl" | cut -f3 | tr '\n' ',')" "604800000,0,0,"

# ══ AC-2: 프라이버시 — 본문·키 값·불량 값 어디에도 카나리가 새지 않는다 ══
mktr "$SB/tdc/c1.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-01T10:01:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"role":"user","content":"CANARY-BODY"},"toolUseResult":"CANARY-TOOL","attachment":{"x":"CANARY-ATT"}}
{"type":"assistant","timestamp":"2026-10-01T10:03:00.000Z","message":{"content":[{"type":"text","text":"CANARY-ASSIST"},{"type":"tool_use","input":{"cmd":"CANARY-INPUT"}}]}}
{"type":"user","timestamp":"2026-10-01T10:04:00.000Z","isMeta":false,"message":{"content":[{"type":"tool_result","content":"CANARY-RESULT"}]}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:05:00.000Z","durationMs":240000,"extra":"CANARY-EXTRA"}
{"type":"user","timestamp":"2026-10-01T10:09:00.000Z","isMeta":false,"origin":{"kind":"CANARY-KIND"},"message":{"content":"CANARY-BODY2"}}
{"type":"system","subtype":"CANARY-SUBTYPE","timestamp":"2026-10-01T10:10:00.000Z","durationMs":60000}
{"type":"user","timestamp":"CANARY-TS","isMeta":false,"origin":{"kind":"human"},"message":{"content":"CANARY-BODY3"}}
{"type":"user","timestamp":"2026-10-01T10:11:00.000Z","durationMs":"CANARY-DUR","isMeta":false,"origin":{"kind":"human"},"message":{"content":"x"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:12:00.000Z","durationMs":"CANARY-DURMS"}
{"CANARY-BROKEN": "json line without closing
EOF
ledger lc <<'EOF'
## 20261001-aaa · A

- 2026-10-01 10:15 /plan 완료 (x)
- 2026-10-01 10:00 /specify 완료 (x)
EOF
HOUT=$(TZ=UTC TMPDIR="$SB/tmp" "$BASH_BIN" "$TT" --local "$SB/tdc/c1.jsonl" 2>"$SB/herr"); HERR=$(cat "$SB/herr")
runs lc --split --transcript-dir "$SB/tdc"; SOUT="$OUT"; SERR="$ERR"
runs lc --split --transcript-dir "$SB/없는디렉토리"; EOUT="$OUT"; EERR="$ERR"
ck "T2.a 카나리가 헬퍼 stdout·stderr 에 0건" "$(printf '%s%s' "$HOUT" "$HERR" | grep -c CANARY)" "0"
ck "T2.b 카나리가 stage-timing stdout·stderr 에 0건(정상·오류 경로)" "$(printf '%s%s%s%s' "$SOUT" "$SERR" "$EOUT" "$EERR" | grep -c CANARY)" "0"
ck "T2.c 임시 디렉토리에 카나리 0건 · 임시 파일 잔존 0건" "$(grep -rl CANARY "$SB/tmp" 2>/dev/null | wc -l | tr -d ' ')|$(ls -A "$SB/tmp" | wc -l | tr -d ' ')" "0|0"
JQP=$(sed -n '/^# JQ-PROGRAM-BEGIN/,/^# JQ-PROGRAM-END/p' "$TT")
BADKEYS=$(printf '%s\n' "$JQP" | grep -oE '\.[A-Za-z_][A-Za-z0-9_]*' | sort -u | grep -vxE '\.(type|subtype|timestamp|durationMs|isMeta|isSidechain|origin|kind|message|content|cur|buf|out|key|value)' | tr '\n' ' ')
ck "T2.d 헬퍼 jq 프로그램은 허용 키 외를 참조하지 않는다(내부 상태 이름 제외)" "$BADKEYS" ""
ck "T2.e message.content 는 타입 검사로만 쓴다" "$(printf '%s\n' "$JQP" | grep -c 'message\.content')|$(printf '%s\n' "$JQP" | grep -c 'message\.content | type')" "1|1"

# ══ AC-3: --split 분해 정확 ══
ledger l3a <<'EOF'
## 20261001-aaa · A

- 2026-10-01 10:15 /plan 완료 (x)
- 2026-10-01 10:00 /specify 완료 (x)
EOF
runs l3a --split --transcript-dir "$SB/td1"
ck "T3.a 예1: wall 15 = 작업 5 + 사람 3 + 백그라운드 4 + 기타 3" "$(row '/plan 완료')" "15 5 3 4 3"
ledger l3b <<'EOF'
## 20261001-aaa · A

- 2026-10-01 10:15 /c 완료 (x)
- 2026-10-01 10:07 /b 완료 (x)
- 2026-10-01 10:00 /a 완료 (x)
EOF
runs l3b --split --transcript-dir "$SB/td1"
ck "T3.b 예2(경계 걸침 비례 배분): /b 7 = 4+0+2+1 · /c 8 = 1+3+2+2" "$(row '/b 완료')|$(row '/c 완료')" "7 4 0 2 1|8 1 3 2 2"
ck "T3.c 머리행은 한글 표시 폭에 맞춰 정렬된 고정 문자열(열 이름: 작업·사람·백그라운드·기타 — 모델 열 없음)" "$(printf '%s\n' "$OUT" | grep -E '단계$' | head -1)" "   합계    비중     n  중앙값    p90    max   작업   사람 백그라운드   기타  단계"
ck "T3.d 머리말: 작업 정의(모델 추론 + 도구 실행 포함)·게이트 구분 없음·동시 세션·본문 비열람" "$(cnt '작업 = 에이전트 턴 진행 시간(모델 추론 + 도구 실행 포함)')$(cnt '게이트(질문) 구분 없음')$(cnt '동시 세션 이중 계상 가능')$(cnt '본문은 읽지 않음')" "1111"
ck "T3.e 푸터: 배분 합·transcript 조각 합" "$(cnt '배분 합(분): 작업 5 · 사람 3 · 백그라운드 4 · 기타 3 (기타 중 미분류 0분 · 미분류 트리거 0건)')|$(cnt 'transcript 조각 합(분): 작업 5 · 사람 3 · 백그라운드 4 · 미분류 0')" "1|1"
# TZ: KST 로컬 원장(= UTC+9) 과 transcript(UTC) 조인
ledger l3k <<'EOF'
## 20261001-aaa · A

- 2026-10-01 19:15 /plan 완료 (x)
- 2026-10-01 19:00 /specify 완료 (x)
EOF
TZV=Asia/Seoul runs l3k --split --transcript-dir "$SB/td1"
ck "T3.f TZ=Asia/Seoul: 로컬 원장 19:00~19:15 가 UTC transcript 10:00~10:15 와 같은 분해" "$(row '/plan 완료')" "15 5 3 4 3"
ledger l3n <<'EOF'
## 20261001-aaa · A

- 2026-10-01 06:15 /plan 완료 (x)
- 2026-10-01 06:00 /specify 완료 (x)
EOF
TZV=America/New_York runs l3n --split --transcript-dir "$SB/td1"
ck "T3.g TZ=America/New_York(10월 EDT -4h): 로컬 06:00~06:15 = UTC 10:00~10:15" "$(row '/plan 완료')" "15 5 3 4 3"

# ══ AC-4: 방치·겹침·미분류·누락·범위 밖 ══
mktr "$SB/td4/s1.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:05:00.000Z","durationMs":60000}
{"type":"user","timestamp":"2026-10-01T22:05:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"content":"x"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T22:10:00.000Z","durationMs":60000}
{"type":"user","timestamp":"2026-10-01T22:15:00.000Z","isMeta":false,"message":{"content":"x"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T22:20:00.000Z","durationMs":60000}
{"type":"user","timestamp":"2026-10-01T22:22:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"content":"x"}}
EOF
ledger l4a <<'EOF'
## 20261001-aaa · A

- 2026-10-01 22:30 /z 완료 (x)
- 2026-10-01 10:00 /a 완료 (x)
EOF
runs l4a --split --transcript-dir "$SB/td4" --gap-cap-min 2000
ck "T4.a 상한 2000분: 12시간(720분) 유휴가 사람 열에 포함 — wall 750 = 작업 3 + 사람 722 + 백그라운드 0 + 기타 25" "$(row '/z 완료')" "750 3 722 0 25"
ck "T4.b 미분류(U) 5분·1건은 기타에 합산되고 푸터에 따로 표시 · 모든 트리거가 직전 turn_duration 을 가져 누락 0건" "$(cnt '기타 중 미분류 5분 · 미분류 트리거 1건')|$(cnt '직전 turn_duration 없이 시작한 트리거 0건')" "1|1"
runs l4a --split --transcript-dir "$SB/td4" --gap-cap-min 700
ck "T4.c 상한 700분: 원장 구간(750분)이 방치로 제외돼 행이 없고, transcript 유휴 720분은 푸터에 방치 제외(사람 1건 720분)로 표시" "$(row '/z 완료')|$(cnt '방치 상한 초과 유휴(transcript, 통계 제외): 사람 1건 720분')|$(cnt '방치 구간 제외 1건 (합 750분)')" "|1|1"
# 겹침: 같은 시간대에 모델 작업이 겹치는 두 세션
mktr "$SB/td4o/a.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:08:00.000Z","durationMs":480000}
EOF
mktr "$SB/td4o/b.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:08:00.000Z","durationMs":480000}
EOF
ledger l4o <<'EOF'
## 20261001-aaa · A

- 2026-10-01 10:10 /b 완료 (x)
- 2026-10-01 10:00 /a 완료 (x)
EOF
runs l4o --split --transcript-dir "$SB/td4o"
ck "T4.d 겹침: 두 세션 작업 16분이 wall 10분에 들어와 기타 0 · 겹침 1구간 표시 · 해당 행 끝에 [겹침 1] 표식" "$(row '/b 완료 \[겹침 1\]')|$(cnt '겹침 1구간')" "10 16 0 0 0|1"
# 직전 D 없는 트리거 · transcript 범위 밖 구간
mktr "$SB/td4n/n.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-01T10:02:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"content":"x"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:05:00.000Z","durationMs":120000}
{"type":"user","timestamp":"2026-10-01T10:06:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"content":"x"}}
{"type":"user","timestamp":"2026-10-01T10:06:30.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"content":"x"}}
EOF
ledger l4n <<'EOF'
## 20261001-aaa · A

- 2026-10-01 11:00 /late 완료 (x)
- 2026-10-01 10:30 /mid 완료 (x)
- 2026-10-01 10:00 /a 완료 (x)
EOF
runs l4n --split --transcript-dir "$SB/td4n"
ck "T4.e 직전 turn_duration 없이 시작한 트리거 2건(세션 시작·두 번째 연속 트리거) 표시" "$(cnt '직전 turn_duration 없이 시작한 트리거 2건')" "1"
ck "T4.f transcript 범위 밖 구간(10:30→11:00 = 30분)이 푸터에 표시되고 기타에 포함" "$(cnt '범위 밖 구간 1건(합 30분)')|$(row '/late 완료')" "1|30 0 0 0 30"

# 세션 간 짝짓기 금지: 파일 a 의 마지막 D 와 파일 b 의 첫 사람 프롬프트(1시간 뒤)를 엮으면 가짜 사람 대기 60분이 생긴다
mktr "$SB/td4s/a.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:05:00.000Z","durationMs":60000}
EOF
mktr "$SB/td4s/b.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-01T11:05:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"content":"x"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T11:06:00.000Z","durationMs":60000}
EOF
ledger l4s <<'EOF'
## 20261001-aaa · A

- 2026-10-01 11:30 /z 완료 (x)
- 2026-10-01 10:00 /a 완료 (x)
EOF
runs l4s --split --transcript-dir "$SB/td4s"
ck "T4.g 파일(세션) 사이를 짝짓지 않는다: 사람 0 · 작업 2 · 기타 88 · 파일 b 의 첫 트리거는 직전 D 없음 1건" "$(row '/z 완료')|$(cnt '직전 turn_duration 없이 시작한 트리거 1건')" "90 2 0 0 88|1"
# 동시 세션의 소폭 겹침(30초 — 원장 시각 분 절삭·turn_duration 시작 시각 오차 수준)은 겹침이 아니다: 비례 축소해 열 합 = wall
mktr "$SB/td4t/a.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:05:00.000Z","durationMs":300000}
EOF
mktr "$SB/td4t/b.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:05:00.000Z","durationMs":30000}
EOF
ledger l4t <<'EOF'
## 20261001-aaa · A

- 2026-10-01 10:05 /b 완료 (x)
- 2026-10-01 10:00 /a 완료 (x)
EOF
runs l4t --split --transcript-dir "$SB/td4t"
ck "T4.h ±60초 허용오차: 작업 330초가 wall 300초에 들어와도(30초 초과) 겹침 0 · 작업 5 · 기타 0(열 합 = wall)" "$(row '/b 완료')|$(cnt '겹침 0구간')" "5 5 0 0 0|1"
# 방치 상한 경계: 유휴가 정확히 상한(720분)이면 포함, 원장 구간도 정확히 720분이면 포함
ledger l4e <<'EOF'
## 20261001-aaa · A

- 2026-10-01 22:00 /z 완료 (x)
- 2026-10-01 10:00 /a 완료 (x)
EOF
runs l4e --split --transcript-dir "$SB/td4"
ck "T4.i 방치 경계: 유휴 720분(= 상한)은 포함 — 구간 720 = 작업 1 + 사람 715 + 백그라운드 0 + 기타 4" "$(row '/z 완료')|$(cnt '방치 상한 초과 유휴(transcript, 통계 제외): 사람 0건')" "720 1 715 0 4|1"

# 동시 세션: 한 세션의 작업 9분 + 다른 세션의 작업 1분 = wall 10분(겹침 아님), 그 사이 다른 세션의 미분류 유휴 8분은 기타(0)를 넘을 수 없다
mktr "$SB/td4u/a.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:10:00.000Z","durationMs":540000}
EOF
mktr "$SB/td4u/b.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:01:00.000Z","durationMs":60000}
{"type":"user","timestamp":"2026-10-01T10:09:00.000Z","isMeta":false,"message":{"content":"x"}}
EOF
ledger l4u <<'EOF'
## 20261001-aaa · A

- 2026-10-01 10:10 /b 완료 (x)
- 2026-10-01 10:00 /a 완료 (x)
EOF
runs l4u --split --transcript-dir "$SB/td4u"
ck "T4.j 작업 합 = wall 이면 겹침이 아니고(미분류 유휴는 기타의 일부), 기타 중 미분류는 그 구간 기타를 넘지 않는다 — 작업 10 · 기타 0 · 미분류 0분 · 트리거 1건" "$(row '/b 완료')|$(cnt '겹침 0구간')|$(cnt '기타 중 미분류 0분 · 미분류 트리거 1건')" "10 10 0 0 0|1|1"

# 같은 세션의 누적 turn_duration: 알림으로 재개된 턴의 durationMs 가 앞 턴 시작부터 누적되면 구간이 직전 턴을 덮는다.
#   한 세션의 턴은 순차라 겹칠 수 없다 — 직전 턴 끝(10:05)으로 잘라 10:05~10:10 = 5분만 센다(자르지 않으면 작업 13 = 4분 이중).
mktr "$SB/td4k/s1.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:05:00.000Z","durationMs":240000}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:10:00.000Z","durationMs":540000}
EOF
ledger l4k <<'EOF'
## 20261001-aaa · A

- 2026-10-01 10:20 /b 완료 (x)
- 2026-10-01 10:00 /a 완료 (x)
EOF
runs l4k --split --transcript-dir "$SB/td4k"
ck "T4.k 같은 세션 누적 turn_duration 은 직전 턴 끝으로 절단: 작업 9(4+5) · 기타 11 · 겹침 0구간" "$(row '/b 완료')|$(cnt '겹침 0구간')" "20 9 0 0 11|1"
# 두 턴 사이에 트리거(알림)가 끼면: 한 턴은 그 턴을 연 트리거보다 앞서 시작할 수 없다 — 둘째 턴을 직전 트리거(10:09)로 잘라
#   10:09~10:10 = 1분만 작업으로 센다(직전 턴 끝으로만 자르면 백그라운드 10:05~10:09 와 4분 이중).
mktr "$SB/td4l/s1.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-01T10:01:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"content":"x"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:05:00.000Z","durationMs":240000}
{"type":"user","timestamp":"2026-10-01T10:09:00.000Z","isMeta":false,"origin":{"kind":"task-notification"},"message":{"content":"x"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:10:00.000Z","durationMs":540000}
EOF
runs l4k --split --transcript-dir "$SB/td4l"
ck "T4.l 트리거 뒤 누적 turn_duration 은 직전 트리거로 절단: 작업 5(4+1) · 백그라운드 4 · 기타 11 · 겹침 0구간" "$(row '/b 완료')|$(cnt '겹침 0구간')" "20 5 0 4 11|1"

# ══ AC-5: 측정 불가 graceful · 옵션 없는 출력 불변 ══
ledger l5 <<'EOF'
## 20261001-aaa · A

- 2026-10-01 10:30 /plan 완료 (x)
- 2026-10-01 10:10 /clarify 완료 (x)
- 2026-10-01 10:00 /specify 완료 (x)

## 20261001-bbb · B

- 2026-10-02 09:10 /clarify 완료 (x)
- 2026-10-02 09:08 /specify 완료 (x)
EOF
runs l5
BASE_OUT="$OUT"
GOLDEN=$(cat <<'EOF'
=== 단계별 소요 집계 (stage-timing) ===
측정: 완료시각 인접 차이 · 분 해상도(0 = 1분 미만) · 사람 대기 포함 경과 시간(작업량 아님)
      FID 경계 미교차 · 도착 행의 단계에 귀속 · DST·타임존 변경 경계 ±60분 오차 가능
원장: LEDGER · FID 2개 · 구간 3건(통계 3 · 방치 제외 0) · 방치 상한 720분 · since 없음

   합계    비중     n  중앙값    p90    max  단계
     20   62.5%     1      20     20     20  /plan 완료
     12   37.5%     2       2     10     10  /clarify 완료

방치 구간 제외 0건 (합 0분) — 위 통계에 불포함
FID 첫 행 2개는 기준 행이 없어 집계에 없음 (행 1개뿐인 FID 0개)
형식 불일치·범위 밖 행 0건은 무시됨 (집계 제외)
EOF
)
ck "T5.a 옵션 없는 출력이 변경 전 스크립트의 출력과 바이트 동일(golden — 원장 경로 줄만 정규화)" "$(printf '%s\n' "$BASE_OUT" | sed "s|$SB/l5/session-progress.md|LEDGER|")" "$GOLDEN"
mkdir -p "$SB/cfg5/projects"
OUT=$(TZ=UTC TMPDIR="$SB/tmp" CLAUDE_CONFIG_DIR="$SB/cfg5" SPECOPS_ROOT="$SB/l5" "$BASH_BIN" "$ST" --split 2>"$SB/err"); RC=$?
ck "T5.b 기본 경로 transcript 디렉토리 부재 → rc=0 · 기존 표 유지 · 끝에 측정 불가 사유 한 줄" "$RC|$(printf '%s\n' "$OUT" | grep '^측정 불가(--split)' | grep -c 'transcript 디렉토리 없음')|$(printf '%s\n' "$OUT" | sed '$d' | sed "s|$SB/l5/session-progress.md|LEDGER|")" "0|1|$GOLDEN"
mkdir -p "$SB/td0"; runs l5 --split --transcript-dir "$SB/td0"
ck "T5.c 세션 0개 디렉토리 → rc=0 · 측정 불가(세션 파일 0개) 한 줄" "$RC|$(printf '%s\n' "$OUT" | grep '^측정 불가(--split)' | grep -c '원장 기간과 겹치는 세션 파일 0개')" "0|1"
mkdir -p "$SB/tdold"; mktr "$SB/tdold/old.jsonl" < "$SB/td1/s1.jsonl"; touch -t 200001010000 "$SB/tdold/old.jsonl"; runs l5 --split --transcript-dir "$SB/tdold"
ck "T5.d 원장 최초 날짜보다 오래전에 수정된 세션은 읽지 않는다 → 세션 파일 0개" "$(printf '%s\n' "$OUT" | grep '^측정 불가(--split)' | grep -c '원장 기간과 겹치는 세션 파일 0개')" "1"
# jq 부재: 필요한 도구만 심볼릭 링크한 PATH (bash 자체는 전체 경로로 호출)
mkdir -p "$SB/nojq"; for t in awk sort grep sed find mktemp rm cat dirname printf touch date; do p=$(command -v "$t") && [ -n "$p" ] && ln -sf "$p" "$SB/nojq/$t"; done
OUT=$(PATH="$SB/nojq" TZ=UTC TMPDIR="$SB/tmp" SPECOPS_ROOT="$SB/l5" "$BASH_BIN" "$ST" --split --transcript-dir "$SB/td1" 2>"$SB/err"); RC=$?
ck "T5.e jq 부재 → rc=0 · 측정 불가(jq 없음) 한 줄 · 기존 표 유지" "$RC|$(printf '%s\n' "$OUT" | grep '^측정 불가(--split)' | grep -c 'jq 없음')|$(printf '%s\n' "$OUT" | sed '$d' | sed "s|$SB/l5/session-progress.md|LEDGER|")" "0|1|$GOLDEN"
OUT=$(PATH="$SB/nojq" "$BASH_BIN" "$TT" "$SB/td1/s1.jsonl" 2>/dev/null); RC=$?; ck "T5.f 헬퍼는 jq 부재 시 rc=3" "$RC" "3"

# 읽을 수 없는 세션 파일: 헬퍼 rc 2 가 파이프 뒤에서 삼켜져 "조각 없음" 으로 보이면 안 된다 — 측정 불가 사유로 보고(root 는 권한 검사가 무의미해 건너뜀)
if [ "$(id -u)" -ne 0 ]; then
  mktr "$SB/tdperm/p.jsonl" < "$SB/td1/s1.jsonl"; chmod 000 "$SB/tdperm/p.jsonl"
  runs l5 --split --transcript-dir "$SB/tdperm"; chmod 644 "$SB/tdperm/p.jsonl"
  ck "T5.g 읽을 수 없는 세션 파일 → rc=0 · 측정 불가(transcript 를 읽을 수 없음) · 기존 표 유지" "$RC|$(printf '%s\n' "$OUT" | grep '^측정 불가(--split)' | grep -c 'transcript 를 읽을 수 없음')|$(printf '%s\n' "$OUT" | sed '$d' | sed "s|$SB/l5/session-progress.md|LEDGER|")" "0|1|$GOLDEN"
else
  echo "SKIP T5.g — root 로 실행 중(권한 검사 무의미)"
fi

# ══ AC-6: 옵션·rc·경로 해석 ══
runs l5 --transcript-dir "$SB/td1"; ck "T6.a --split 없이 --transcript-dir → rc=2" "$RC|$OUT" "2|"
runs l5 --split --transcript-dir "$SB/없는디렉토리"; ck "T6.b 존재하지 않는 --transcript-dir → rc=2 · stdout 비어 있음" "$RC|$OUT|$(printf '%s' "$ERR" | grep -c '디렉토리가 아닙니다')" "2||1"
runs l5 --split --transcript-dir; ck "T6.c 값 없는 --transcript-dir → rc=2" "$RC|$OUT" "2|"
ROOT6="$SB/proj 6.x"; mkdir -p "$ROOT6/.specops"; cp "$SB/l3a/session-progress.md" "$ROOT6/.specops/session-progress.md"
ENC=$(cd "$ROOT6" && pwd -P | sed 's/[^A-Za-z0-9]/-/g'); mktr "$SB/cfg6/projects/$ENC/s1.jsonl" < "$SB/td1/s1.jsonl"
mktr "$SB/cfg6/projects/$ENC/sub/subagents/x.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:08:00.000Z","durationMs":480000}
EOF
OUT=$(TZ=UTC TMPDIR="$SB/tmp" CLAUDE_CONFIG_DIR="$SB/cfg6" SPECOPS_ROOT="$ROOT6/.specops" "$BASH_BIN" "$ST" --split 2>"$SB/err"); RC=$?
ck "T6.d CLAUDE_CONFIG_DIR + 원장 루트 실경로(비영숫자→-)로 디렉토리를 찾고 직속 jsonl 만 읽는다(하위 subagents 제외) · stderr 비어 있음" "$RC|$(row '/plan 완료')|$(wc -c < "$SB/err" | tr -d ' ')" "0|15 5 3 4 3|0"
ck "T6.e 인코딩 규칙 — 실제 관측 이름(슬래시·점이 -, 선두 - 유지)" "$(printf '%s' '/Users/andyko/Project/0.Claude/specops-ko' | sed 's/[^A-Za-z0-9]/-/g')" "-Users-andyko-Project-0-Claude-specops-ko"
runs l3a --split --transcript-dir "$SB/td1" --since 20261001 --min-n 1 --gap-cap-min 720
ck "T6.f --since·--min-n·--gap-cap-min 은 --split 과 함께 동작한다" "$RC|$(row '/plan 완료')" "0|15 5 3 4 3"

# 비ASCII 경로: Claude Code 의 치환 규칙(바이트/문자 단위)이 미검증이라 두 후보를 모두 시도한다 — UTF-8 로케일이 없는 환경은 건너뜀
UTF8LOC=""
for L in C.UTF-8 en_US.UTF-8; do [ "$(LC_ALL=$L locale charmap 2>/dev/null)" = "UTF-8" ] && { UTF8LOC=$L; break; }; done
if [ -n "$UTF8LOC" ]; then
  ROOT7="$SB/프로젝트 7"; mkdir -p "$ROOT7/.specops"; cp "$SB/l3a/session-progress.md" "$ROOT7/.specops/session-progress.md"
  PH7=$(cd "$ROOT7" && pwd -P)
  ENC_BY=$(printf '%s' "$PH7" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g'); ENC_CH=$(printf '%s' "$PH7" | LC_ALL=$UTF8LOC sed 's/[^A-Za-z0-9]/-/g')
  ck "T6.g 전제: 한글 경로는 바이트 단위와 문자 단위 인코딩이 서로 다르다" "$([ "$ENC_BY" != "$ENC_CH" ] && echo differ || echo same)" "differ"
  mktr "$SB/cfg7a/projects/$ENC_CH/s1.jsonl" < "$SB/td1/s1.jsonl"
  OUT=$(TZ=UTC TMPDIR="$SB/tmp" CLAUDE_CONFIG_DIR="$SB/cfg7a" SPECOPS_ROOT="$ROOT7/.specops" "$BASH_BIN" "$ST" --split 2>"$SB/err"); RC=$?
  ck "T6.h 문자 단위로 치환된 디렉토리도 찾는다(바이트 단위 후보가 없을 때)" "$RC|$(row '/plan 완료')" "0|15 5 3 4 3"
  mktr "$SB/cfg7b/projects/$ENC_BY/s1.jsonl" < "$SB/td1/s1.jsonl"
  OUT=$(TZ=UTC TMPDIR="$SB/tmp" CLAUDE_CONFIG_DIR="$SB/cfg7b" SPECOPS_ROOT="$ROOT7/.specops" "$BASH_BIN" "$ST" --split 2>"$SB/err"); RC=$?
  ck "T6.i 바이트 단위로 치환된 디렉토리도 찾는다" "$RC|$(row '/plan 완료')" "0|15 5 3 4 3"
else
  echo "SKIP T6.g~i — UTF-8 로케일(C.UTF-8·en_US.UTF-8) 없음"
fi

# ══ AC-10 (20261011-friction-key-transcript-dirs): worktree 합집합 · --transcript-dir 반복 ══
# 저장소 + 링크 worktree 1개. 각 경로를 인코딩한 projects 디렉토리에 세션 1개씩 — 두 세션이 서로 다른 구간을 덮는다.
R10="$SB/r10"; mkdir -p "$R10" && (cd "$R10" && git init -q && git -c user.name=t -c user.email=t@e.com commit -q --allow-empty -m init && git worktree add -q "$SB/r10-wt" -b wt 2>/dev/null)
mkdir -p "$R10/.specops"
ledger r10x <<'EOF'
## 20261001-aaa · A

- 2026-10-01 10:30 /tasks 완료 (x)
- 2026-10-01 10:15 /plan 완료 (x)
- 2026-10-01 10:00 /specify 완료 (x)
EOF
cp "$SB/r10x/session-progress.md" "$R10/.specops/session-progress.md"
ENC_A=$(cd "$R10" && pwd -P | sed 's/[^A-Za-z0-9]/-/g'); ENC_W=$(cd "$SB/r10-wt" && pwd -P | sed 's/[^A-Za-z0-9]/-/g')
mktr "$SB/cfg10/projects/$ENC_A/s1.jsonl" < "$SB/td1/s1.jsonl"          # 10:00~10:15 구간을 덮는다
mktr "$SB/cfg10/projects/$ENC_W/s2.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-01T10:16:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"role":"user","content":"BODY-E"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:26:00.000Z","durationMs":600000}
{"type":"user","timestamp":"2026-10-01T10:30:00.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"role":"user","content":"BODY-F"}}
EOF
mktr "$SB/cfg10/projects/$ENC_W/sub/subagents/agent-w.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:20:00.000Z","durationMs":120000}
EOF
r10() { OUT=$(TZ=UTC TMPDIR="$SB/tmp" CLAUDE_CONFIG_DIR="$SB/cfg10" SPECOPS_ROOT="$R10/.specops" "$BASH_BIN" "$ST" "$@" 2>"$SB/err"); RC=$?; ERR=$(cat "$SB/err"); }
r10 --split
ck "T10.a 자동 탐지가 저장소+worktree 두 디렉토리를 읽는다 → 머리에 '2개 읽음' · 두 세션의 구간이 모두 분류(worktree 쪽 작업 10 · 사람 4 — 기타는 이벤트 없는 1분뿐)" "$RC|$(cnt 'transcript 디렉토리 2개 읽음')|$(row '/plan 완료')|$(row '/tasks 완료')" "0|1|15 5 3 4 3|15 10 4 0 1"
r10 --split --transcript-dir "$SB/cfg10/projects/$ENC_A" --transcript-dir "$SB/cfg10/projects/$ENC_W"
ck "T10.b --transcript-dir 반복 지정 → 합집합(2개 읽음) · 같은 결과" "$RC|$(cnt 'transcript 디렉토리 2개 읽음')|$(row '/tasks 완료')" "0|1|15 10 4 0 1"
r10 --split --transcript-dir "$SB/cfg10/projects/$ENC_A"
ck "T10.c 단일 지정은 종전과 같다 — 그 디렉토리만(1개 읽음) · worktree 세션 구간은 기타" "$RC|$(cnt 'transcript 디렉토리 1개 읽음')|$(row '/tasks 완료')" "0|1|15 0 0 0 15"
r10 --split --transcript-dir "$SB/cfg10/projects/$ENC_A" --transcript-dir "$SB/없는디렉토리"
ck "T10.d 반복 지정 중 하나라도 없으면 종전 오류(rc=2 · 디렉토리가 아닙니다)" "$RC|$(printf '%s' "$ERR" | grep -c '디렉토리가 아닙니다')" "2|1"
r10 --by-agent
ck "T10.e --by-agent 도 두 디렉토리의 subagents/ 를 읽는다(worktree 쪽 에이전트 2분 집계)" "$RC|$(printf '%s\n' "$OUT" | grep -c '서브에이전트 1개')" "0|1"
mkdir -p "$SB/r10-wt/.specops" && cp "$SB/r10x/session-progress.md" "$SB/r10-wt/.specops/session-progress.md"
OUT=$(TZ=UTC TMPDIR="$SB/tmp" CLAUDE_CONFIG_DIR="$SB/cfg10" SPECOPS_ROOT="$SB/r10-wt/.specops" "$BASH_BIN" "$ST" --split 2>"$SB/err"); RC=$?
ck "T10.g 루트가 worktree 목록에 다시 나와도(후보 3개 중 중복 2) 중복 없이 2개" "$RC|$(cnt 'transcript 디렉토리 2개 읽음')" "0|1"
mv "$SB/cfg10/projects/$ENC_W" "$SB/cfg10/gone-w"; r10 --split   # 삭제 대신 옮긴다(픽스처 보존 · 위험 판정기의 destructive_fs 낱말 회피가 아니라 실제로 지우지 않는다)
ck "T10.f worktree 의 인코딩 디렉토리가 없으면 '대응 디렉토리 없는 worktree 1개' 를 적고 나머지는 읽는다" "$RC|$(cnt 'transcript 디렉토리 1개 읽음')|$(cnt '대응 디렉토리 없는 worktree 1개')" "0|1|1"
# T10.h 저장소 경로에 글롭 문자(repo[ab])가 있고 형제 repoa·repob 가 있어도 루트가 후보에서 사라지지 않는다
mkdir -p "$SB/g/repo[ab]/.specops" "$SB/g/repoa" "$SB/g/repob"
cp "$SB/r10x/session-progress.md" "$SB/g/repo[ab]/.specops/session-progress.md"
ENC_G=$(cd "$SB/g/repo[ab]" && pwd -P | sed 's/[^A-Za-z0-9]/-/g')
mktr "$SB/cfgG/projects/$ENC_G/s1.jsonl" < "$SB/td1/s1.jsonl"
OUT=$(TZ=UTC TMPDIR="$SB/tmp" CLAUDE_CONFIG_DIR="$SB/cfgG" SPECOPS_ROOT="$SB/g/repo[ab]/.specops" "$BASH_BIN" "$ST" --split 2>"$SB/err"); RC=$?
ck "T10.h 경로의 글롭 문자가 후보 분할에서 해석되지 않는다 → 1개 읽음 · 없는 worktree 0개" "$RC|$(cnt 'transcript 디렉토리 1개 읽음')|$(cnt '대응 디렉토리 없는 worktree 0개')" "0|1|1"
# T10.i 루트 디렉토리만 없고 worktree 디렉토리는 있을 때 — 루트가 목록에 두 번 나와도 없는 쪽은 1개로 센다
mktr "$SB/cfgI/projects/$ENC_W/s2.jsonl" < "$SB/cfg10/gone-w/s2.jsonl"
OUT=$(TZ=UTC TMPDIR="$SB/tmp" CLAUDE_CONFIG_DIR="$SB/cfgI" SPECOPS_ROOT="$R10/.specops" "$BASH_BIN" "$ST" --split 2>"$SB/err"); RC=$?
ck "T10.i 후보를 실경로로 먼저 중복 제거한 뒤 센다 → 1개 읽음 · 없는 worktree 1개" "$RC|$(cnt 'transcript 디렉토리 1개 읽음')|$(cnt '대응 디렉토리 없는 worktree 1개')" "0|1|1"

# ══ AC-7: 읽기 전용 · 정적 규약 · 성능 ══
BEFORE="$(cksum < "$SB/l3a/session-progress.md")|$(cat "$SB/td1/s1.jsonl" | cksum)|$(ls -A "$SB/tmp" | wc -l | tr -d ' ')"
runs l3a --split --transcript-dir "$SB/td1"
AFTER="$(cksum < "$SB/l3a/session-progress.md")|$(cat "$SB/td1/s1.jsonl" | cksum)|$(ls -A "$SB/tmp" | wc -l | tr -d ' ')"
ck "T7.a 실행 전후 원장·transcript 바이트 동일 · 임시 파일 잔존 0" "$AFTER" "$BEFORE"
ck "T7.b mktime 호출·행 단위 read 루프 없음(헬퍼·stage-timing)" "$(cat "$ST" "$TT" | grep -cE 'mktime *\(|while +(IFS= +)?(-r +)?read')" "0"
# 합성 대형 입력: 3 파일 × 20,000 줄
for i in 1 2 3; do awk -v f="$i" 'BEGIN { for (k = 0; k < 10000; k++) { t = 36000 + k * 7; printf "{\"type\":\"user\",\"timestamp\":\"2026-10-01T%02d:%02d:%02d.000Z\",\"isMeta\":false,\"origin\":{\"kind\":\"human\"},\"message\":{\"content\":\"x\"}}\n{\"type\":\"system\",\"subtype\":\"turn_duration\",\"timestamp\":\"2026-10-01T%02d:%02d:%02d.000Z\",\"durationMs\":3000}\n", int(t/3600)%24, int(t%3600/60), t%60, int((t+3)/3600)%24, int((t+3)%3600/60), (t+3)%60 } }' > "$SB/big$i.jsonl"; mktr "$SB/tdbig/b$i.jsonl" < "$SB/big$i.jsonl"; done
ledger lbig <<'EOF'
## 20261001-aaa · A

- 2026-10-01 23:59 /z 완료 (x)
- 2026-10-01 10:00 /a 완료 (x)
EOF
# 벽시계가 아니라 CPU 시간(user+sys · 자식 포함)으로 잰다 — 병렬 run-all·리뷰 에이전트 경합에 흔들리지 않는다(20261024-flaky-suites-spa-false-ok · 실측 단독 수 초)
TIMEFORMAT='%3U %3S'; { time runs lbig --split --transcript-dir "$SB/tdbig" --gap-cap-min 2000; } 2>"$SB/cpu"; unset TIMEFORMAT
_cl=$(tail -1 "$SB/cpu" | tr ',' '.'); CPU=$(printf '%s' "$_cl" | awk '{ printf "%.1f", $1 + $2 }')
ck "T7.c 합성 6만 줄 transcript 3개 --split rc=0 · CPU 20초 이내(실측 수 초 · cpu=${CPU}s)" "$RC|$(printf '%s' "$_cl" | grep -qE '^[0-9]+\.[0-9]{3} [0-9]+\.[0-9]{3}$' && awk -v c="$CPU" 'BEGIN{ print (c + 0 > 0 && c + 0 <= 20) ? 1 : 0 }' || echo bad)" "0|1"

# ══ AC-9: 열 합 = wall 불변식(겹침 없는 행) · 이름 ══
mktr "$SB/td9/s1.jsonl" <<'EOF'
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:03:20.000Z","durationMs":200000}
{"type":"user","timestamp":"2026-10-01T10:05:10.000Z","isMeta":false,"origin":{"kind":"task-notification"},"message":{"content":"x"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:06:40.000Z","durationMs":90000}
{"type":"user","timestamp":"2026-10-01T10:11:00.000Z","isMeta":false,"message":{"content":"x"}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-10-01T10:12:35.000Z","durationMs":95000}
{"type":"user","timestamp":"2026-10-01T10:16:20.000Z","isMeta":false,"origin":{"kind":"human"},"message":{"content":"x"}}
EOF
ledger l9 <<'EOF'
## 20261001-aaa · A

- 2026-10-01 10:20 /x 완료 (x)
- 2026-10-01 10:13 /x 완료 (x)
- 2026-10-01 10:07 /x 완료 (x)
- 2026-10-01 10:02 /x 완료 (x)
- 2026-10-01 10:00 /s 완료 (x)
EOF
runs l9 --split --transcript-dir "$SB/td9"
SUMS=$(printf '%s\n' "$OUT" | grep -E ' /x 완료$' | awk '{print ($1 == $7 + $8 + $9 + $10) ? "OK" : "BAD:" $0}')
ck "T9.a 겹침 없는 행에서 작업+사람+백그라운드+기타 = 합계(초 단위 조각을 큰 나머지법으로 분 반올림)" "$SUMS|$(cnt '겹침 0구간')" "OK|1"
ck "T9.b 열 합 불변식의 정확한 값: 작업 6 · 사람 4 · 백그라운드 2 · 기타 8 (초 조각 385·225·110·480 → 큰 나머지법)" "$(row '/x 완료')" "20 6 4 2 8"
ck "T9.c 미분류(U) 260초·1건은 기타에 합산되고 푸터에 4분·1건으로 표시 · 머리행에 모델 열이 없다" "$(cnt '기타 중 미분류 4분 · 미분류 트리거 1건')|$(printf '%s\n' "$OUT" | grep -E '단계$' | grep -c 모델)" "1|0"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
