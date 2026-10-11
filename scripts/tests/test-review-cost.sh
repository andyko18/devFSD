#!/usr/bin/env bash
# review-cost.sh — plan-reviewer 비용·재dispatch 집계 (fixture 만 사용 — 실제 .specops·~/.claude 를 읽지 않는다, 토큰 0)
# run-all: serial — 합성 대형 입력(T9.c)의 시간 임계가 CPU 경합에 약하다
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
RCS_SH="$PLUGIN/scripts/review-cost.sh"
BASH_BIN=$(command -v bash)
SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/tmp" "$SB/home" "$SB/cfg"

ck() { if [ "$2" = "$3" ]; then echo "PASS $1"; PASS=$((PASS+1)); else echo "FAIL $1 — exp '$3' got '$2'"; FAIL=$((FAIL+1)); fi; }

# dispatch-log fixture: dl 이름 FID — 본문은 stdin. $SB/이름 이 곧 SPECOPS_ROOT 다.
dl() { mkdir -p "$SB/$1/$2" && cat > "$SB/$1/$2/dispatch-log.md"; }
# 행: pr 번호 판정 [비고] [단계] — 필드 2=번호 4=단계 6=판정 7=비고
pr() { printf '| %s | 2026-09-01T10:00:00+09:00 | %s | plan-reviewer-ko | %s | %s |\n' "$1" "${4:-plan-reviewer}" "$2" "${3:--}"; }
HDR='| # | 시각 | 단계 | 에이전트 | 판정 | 비고 |
|---|---|---|---|---|---|'
ledger() { mkdir -p "$SB/$1" && cat > "$SB/$1/session-progress.md"; }
# 실행: runs 이름 옵션... — TZ=UTC(TZV 로 변경) · HOME·CLAUDE_CONFIG_DIR 은 fixture 로 격리 · TMPDIR 은 전용 디렉토리(누출 검사용)
runs() {
  local nm="$1"; shift
  OUT=$(TZ="${TZV:-UTC}" TMPDIR="$SB/tmp" HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/cfg" SPECOPS_ROOT="$SB/$nm" "$BASH_BIN" "$RCS_SH" "$@" 2>"$SB/err"); RC=$?
  # shellcheck disable=SC2034  # Part B 의 단언에서 쓴다
  ERR=$(cat "$SB/err")
}
cnt() { printf '%s\n' "$OUT" | grep -cF -- "$1"; }
# 표의 한 행을 "라운드 첫 끝 Crit Imp wall분" 으로
trow() { printf '%s\n' "$OUT" | awk -v f="$1" '$1 == f { print $2, $3, $4, $5, $6, $7 }'; }
# 표의 FID 순서(헤더 제외 — 날짜로 시작하는 첫 열만)
order() { printf '%s\n' "$OUT" | awk '$1 ~ /^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-/ { printf "%s,", $1 }'; }
# wall 줄을 뺀 라운드 요약(wall 유무와 무관해야 하는 줄)
core() { printf '%s\n' "$OUT" | grep -E '^(FID [0-9]+개|첫 라운드 FAIL|마지막 판정|도입|  20[0-9]{4}  FID)'; }

# ══ AC-1: dispatch-log plan-reviewer 행 파싱·판정 정규화 ══
dl a1 20260901-ord <<EOF
$HDR
$(pr 3 PASS)
$(pr 1 FAIL 'Critical 1')
$(pr 2 '**FAIL**' 'Important 2')
EOF
dl a1 20260902-star <<EOF
$HDR
$(pr 1 '**PASS**')
EOF
dl a1 20260903-arrow <<EOF
$HDR
$(pr 1 'FAIL→PASS')
$(pr 2 ABORT)
EOF
dl a1 20260904-misc <<EOF
$HDR
$(pr 1 PROCEED)
$(pr 2 —)
| 3 | 2026-09-01T10:00:00+09:00 | plan-reviewer | DEFERRED | — | Phase 2 batch |
$(pr 4 ABORT)
$(pr 1 PASS - A:T1)
$(pr 2 FAIL - End-loaded-B)
$(pr 3 PASS - 외부 critic)
plan-reviewer FAIL 2회 후 PASS — 산문 줄(파이프로 시작하지 않는다)
| 1 | x | plan-reviewer |
| 5 | 2026-09-01T10:00:00+09:00 | plan-reviewer | FAIL |
note: | 1 | 2026-09-01T10:00:00+09:00 | plan-reviewer | plan-reviewer-ko | FAIL | x |
EOF
dl a1 notes <<EOF
$HDR
$(pr 1 PASS)
EOF
mkdir -p "$SB/a1/20260905-empty"; : > "$SB/a1/20260905-empty/dispatch-log.md"
runs a1
ck "T1.a 라운드 FID 3개(ord·star·arrow) · 분포 1회 2·3회 1 · 평균 1.67 · rc=0 — 기타만 있는 FID(misc)·비 FID 폴더(notes)·빈 파일은 FID 수에 안 든다" "$RC|$(printf '%s\n' "$OUT" | grep -F 'FID 3개')" "0|FID 3개 · 라운드 분포 1회 2 · 3회 1 — 평균 1.67"
ck "T1.b 첫 라운드 FAIL 2/3(ord·arrow) · 마지막 판정 PASS 2/3(ord·star) — arrow 의 FAIL→PASS 는 FAIL" "$(cnt '첫 라운드 FAIL 2/3 (67%)')|$(cnt '마지막 판정 PASS 2/3 (67%)')" "1|1"
ck "T1.c 기타 행은 5건(ABORT 1 + PROCEED·—·DEFERRED·ABORT) — 단계가 A:T1·End-loaded-B·외부 critic 인 행·산문 줄·열이 모자란 줄은 어디에도 세지 않는다" "$(cnt '기타 행 5건')" "1"
ck "T1.d 표: ord 는 번호 3·1·2 순서로 기록돼도 번호 오름차순이라 첫 FAIL·끝 PASS · star **PASS** 는 PASS · arrow 는 1라운드 FAIL/FAIL · 기타 전용 FID·비 FID 폴더는 표에 없다" "$(trow 20260901-ord)|$(trow 20260902-star)|$(trow 20260903-arrow)|$(cnt 20260904-misc)$(cnt notes)" "3 FAIL PASS 1 2 -|1 PASS PASS 0 0 -|1 FAIL FAIL 0 0 -|00"
dl a1b 20260905-nonnum <<EOF
$HDR
$(pr x FAIL)
$(pr y PASS)
EOF
dl a1b 20260906-dup <<EOF
$HDR
$(pr 2 PASS)
$(pr 2 FAIL)
$(pr 1 FAIL)
EOF
runs a1b
ck "T1.e 번호가 숫자가 아니면 파일 순서(FAIL→PASS) · 같은 번호는 파일 순서 유지(번호 1 FAIL → 2 PASS → 2 FAIL)" "$(trow 20260905-nonnum)|$(trow 20260906-dup)" "2 FAIL PASS 0 0 -|3 FAIL FAIL 0 0 -"

# ══ AC-2: FID 요약 ══
dl a2 20260901-f1 <<EOF
$HDR
$(pr 1 PASS)
EOF
dl a2 20260902-f2 <<EOF
$HDR
$(pr 1 FAIL)
EOF
dl a2 20260903-f3 <<EOF
$HDR
$(pr 1 FAIL)
$(pr 2 PASS)
EOF
dl a2 20260904-f4 <<EOF
$HDR
$(pr 1 FAIL)
$(pr 2 PASS)
EOF
dl a2 20260905-f5 <<EOF
$HDR
$(pr 1 FAIL)
$(pr 2 FAIL)
$(pr 3 PASS)
EOF
dl a2 20260906-f6 <<EOF
$HDR
$(pr 1 FAIL)
$(pr 2 FAIL)
EOF
runs a2
ck "T2.a 요약: FID 6개 · 분포 1회 2·2회 3·3회 1 · 평균 1.83(11/6)" "$(printf '%s\n' "$OUT" | grep -F 'FID 6개')" "FID 6개 · 라운드 분포 1회 2 · 2회 3 · 3회 1 — 평균 1.83"
ck "T2.b 첫 라운드 FAIL 5/6(83%) · 마지막 판정 PASS 4/6(67%) — f2~f6 가 첫 FAIL, f1·f3·f4·f5 가 끝 PASS" "$(cnt '첫 라운드 FAIL 5/6 (83%)')|$(cnt '마지막 판정 PASS 4/6 (67%)')" "1|1"
ck "T2.c 표 순서(wall 없음 → 라운드 내림차순, 동률은 FID 이름 내림차순)와 첫·끝 열" "$(order)|$(trow 20260905-f5)|$(trow 20260906-f6)|$(trow 20260901-f1)" "20260905-f5,20260906-f6,20260904-f4,20260903-f3,20260902-f2,20260901-f1,|3 FAIL PASS 0 0 -|2 FAIL FAIL 0 0 -|1 PASS PASS 0 0 -"
runs a2 --top 3
ck "T2.d --top 3 이면 표 3행(위 3개 FID)" "$(order)" "20260905-f5,20260906-f6,20260904-f4,"

# ══ AC-3: Critical/Important 숫자 ══
dl a3 20260901-c1 <<EOF
$HDR
$(pr 1 FAIL 'Critical 2 · Important 3(범위 CANARY-N1)')
$(pr 2 PASS 'Important 7 CANARY-N5')
EOF
dl a3 20260902-c2 <<EOF
$HDR
$(pr 1 FAIL 'Important 1(CANARY-N2) · Minor 5')
EOF
dl a3 20260903-c3 <<EOF
$HDR
$(pr 1 FAIL 'Critical: 1건, Important 4건')
EOF
dl a3 20260904-c4 <<EOF
$HDR
$(pr 1 FAIL '범위 오류 — 재작성 CANARY-N3')
EOF
dl a3 20260905-c5 <<EOF
$HDR
$(pr 1 FAIL 'Important 2 … Important 9 CANARY-N4')
EOF
runs a3
ck "T3.a 합계: Critical 3(2+1) · Important 10(3+1+4+2 — 첫 매치만, PASS 행의 7 은 안 쓴다) · 숫자 읽힌 FAIL 행 4/5" "$(printf '%s\n' "$OUT" | grep -F 'Critical 합')" "FAIL 행 Critical 합 3 · Important 합 10 (숫자 읽힌 FAIL 행 4/5)"
ck "T3.b 숫자 못 읽은 FAIL 행 1건(c4) — 비고의 비숫자 텍스트(CANARY-N*·재작성)는 stdout·stderr 에 0건" "$(cnt '숫자 못 읽은 FAIL 행 1건')|$(printf '%s\n%s\n' "$OUT" "$ERR" | grep -c -e 'CANARY-N' -e '재작성')" "1|0"
ck "T3.c 표의 FID 별 Crit·Imp: c1 은 2·3 · c3 은 1·4 · c4 는 0·0" "$(trow 20260901-c1 | awk '{print $4, $5}')|$(trow 20260903-c3 | awk '{print $4, $5}')|$(trow 20260904-c4 | awk '{print $4, $5}')" "2 3|1 4|0 0"
dl a3b 20260901-w6 <<EOF
$HDR
$(pr 1 FAIL 'Critical abcde7 · Imp')
EOF
dl a3b 20260902-w7 <<EOF
$HDR
$(pr 1 FAIL 'Critical abcdef7 · Imp')
EOF
runs a3b
ck "T3.d 키워드와 숫자 사이 비숫자는 6자까지(공백 포함 6자 abcde7 은 읽고 7자 abcdef7 은 못 읽는다)" "$(printf '%s\n' "$OUT" | grep -F 'Critical 합')|$(cnt '숫자 못 읽은 FAIL 행 1건')" "FAIL 행 Critical 합 7 · Important 합 0 (숫자 읽힌 FAIL 행 1/2)|1"

dl a3c 20260901-n1 <<EOF
$HDR
$(pr 1 FAIL 'Critical (see below) 2 … Critical 4 · Important (none)')
EOF
runs a3c
ck "T3.e 키워드의 첫 출현 뒤에 6자 안의 숫자가 없으면 다음 출현에서 읽는다(Critical 4 · Important 는 못 읽음 → 읽힌 행 1/1)" "$(printf '%s\n' "$OUT" | grep -F 'Critical 합')" "FAIL 행 Critical 합 4 · Important 합 0 (숫자 읽힌 FAIL 행 1/1)"
dl a3p 20260901-p1 <<EOF
$HDR
$(pr 1 FAIL 'Critical 2 | Important 3 · Minor 1')
EOF
dl a3p 20260902-p2 <<EOF
$HDR
$(pr 1 FAIL 'Important 4 | 비숫자 CANARY-PIPE | Critical 1')
EOF
dl a3p 20260903-p3 <<EOF
$HDR
$(pr 1 FAIL 'Critical 5 · Important 6')
EOF
dl a3p 20260904-p4 <<EOF
$HDR
$(pr 1 FAIL '서술 | 숫자 없음 | 끝')
EOF
runs a3p
ck "T3.f 비고 안의 | 를 넘어 읽는다: Critical 합 8(2+1+5) · Important 합 13(3+4+6) · 읽힌 행 3/4 · 못 읽은 행 1건 · 비숫자 본문(CANARY-PIPE)은 출력에 없다" "$(printf '%s\n' "$OUT" | grep -F 'Critical 합')|$(cnt '숫자 못 읽은 FAIL 행 1건')|$(printf '%s\n%s\n' "$OUT" "$ERR" | grep -c 'CANARY-PIPE')" "FAIL 행 Critical 합 8 · Important 합 13 (숫자 읽힌 FAIL 행 3/4)|1|0"
dl a3q 20260901-q1 <<EOF
$HDR
| 1 | 2026-09-01T10:00:00+09:00 | plan-reviewer | plan-reviewer-ko | FAIL | Critical 1 | Important 2
EOF
runs a3q
ck "T3.g 끝 파이프가 없는 행도 마지막 칸까지 이어 읽는다(Critical 1 · Important 2)" "$(printf '%s\n' "$OUT" | grep -F 'Critical 합')" "FAIL 행 Critical 합 1 · Important 합 2 (숫자 읽힌 FAIL 행 1/1)"
dl a3r 20260901-r1 <<EOF
$HDR
$(pr 1 FAIL 'Important 1|2 · Critical 3')
EOF
runs a3r
ck "T3.h 칸을 이을 때 구분자(|)를 유지한다: 'Important 1|2' 는 12 가 아니라 1 로 읽는다" "$(printf '%s\n' "$OUT" | grep -F 'Critical 합')" "FAIL 행 Critical 합 3 · Important 합 1 (숫자 읽힌 FAIL 행 1/1)"

# ══ AC-4: 도입 전후·--since ══
dl a4 20260801-a <<EOF
$HDR
$(pr 1 FAIL)
$(pr 2 PASS)
EOF
dl a4 20260808-b <<EOF
$HDR
$(pr 1 PASS)
EOF
dl a4 20260809-c <<EOF
$HDR
$(pr 1 FAIL)
$(pr 2 FAIL)
$(pr 3 PASS)
EOF
dl a4 20260901-d <<EOF
$HDR
$(pr 1 FAIL)
EOF
runs a4
ck "T4.a 기본(20260809): 도입 전(a·b) FID 2 · FAIL 1(50%) · 평균 1.50 / 도입 후(c·d) FID 2 · FAIL 2(100%) · 평균 2.00" "$(printf '%s\n' "$OUT" | grep -F '도입 전(')|$(printf '%s\n' "$OUT" | grep -F '도입 후(')" "도입 전(20260809 미만): FID 2 · 첫 라운드 FAIL 1 (50%) · 평균 라운드 1.50|도입 후(20260809 이상): FID 2 · 첫 라운드 FAIL 2 (100%) · 평균 라운드 2.00"
runs a4 --predispatch-date 20260901
ck "T4.b --predispatch-date 20260901: 전(a·b·c) FID 3 · FAIL 2(67%) · 평균 2.00 / 후(d) FID 1 · FAIL 1(100%) · 평균 1.00" "$(printf '%s\n' "$OUT" | grep -F '도입 전(')|$(printf '%s\n' "$OUT" | grep -F '도입 후(')" "도입 전(20260901 미만): FID 3 · 첫 라운드 FAIL 2 (67%) · 평균 라운드 2.00|도입 후(20260901 이상): FID 1 · 첫 라운드 FAIL 1 (100%) · 평균 라운드 1.00"
runs a4 --since 20260809
ck "T4.c --since 20260809: 전체 요약·표·전후 비교 모두 c·d 만 — FID 2개 · 도입 전 FID 0개 · 후 FID 2 · 표에 a·b 없음" "$(printf '%s\n' "$OUT" | grep -F 'FID 2개')|$(cnt '도입 전 FID 0개')|$(printf '%s\n' "$OUT" | grep -F '도입 후(')|$(cnt 20260801-a)$(cnt 20260808-b)" "FID 2개 · 라운드 분포 1회 1 · 3회 1 — 평균 2.00|1|도입 후(20260809 이상): FID 2 · 첫 라운드 FAIL 2 (100%) · 평균 라운드 2.00|00"
runs a4 --since 20260902
ck "T4.d --since 가 모든 FID 를 거르면(0개) 오류가 아니라 사실 줄 · rc=0" "$RC|$(cnt 'plan-reviewer 행 없음')" "0|1"

# ══ AC-11: 월별 첫 라운드 FAIL ══
dl a11 20260801-m1 <<EOF
$HDR
$(pr 1 FAIL)
EOF
dl a11 20260815-m2 <<EOF
$HDR
$(pr 1 FAIL)
$(pr 2 PASS)
EOF
dl a11 20260820-m3 <<EOF
$HDR
$(pr 1 PASS)
EOF
dl a11 20260901-m4 <<EOF
$HDR
$(pr 1 FAIL)
EOF
dl a11 20260902-m5 <<EOF
$HDR
$(pr 1 PASS)
EOF
dl a11 20260903-m6 <<EOF
$HDR
$(pr 1 PROCEED)
EOF
runs a11
ck "T11.a 월별 줄: 제목 + 202608 FID 3 · FAIL 2(67%) / 202609 FID 2 · FAIL 1(50%) 월 오름차순 — 기타 행만 있는 FID(m6)는 제외" "$(cnt '월별 첫 라운드 FAIL (FID 이름 날짜 접두 기준 · 표본 n 병기)')|$(printf '%s\n' "$OUT" | grep -E '^  20[0-9]{4}  FID' | tr '\n' '|')" "1|  202608  FID 3 · 첫 라운드 FAIL 2 (67%)|  202609  FID 2 · 첫 라운드 FAIL 1 (50%)|"
runs a11 --since 20260901
ck "T11.b --since 20260901 이면 202609 월만 나온다" "$(printf '%s\n' "$OUT" | grep -E '^  20[0-9]{4}  FID' | tr '\n' '|')" "  202609  FID 2 · 첫 라운드 FAIL 1 (50%)|"

# ══ AC-12: 첫 라운드 FAIL 심각도 분해 ══
dl a12 20260901-s1 <<EOF
$HDR
$(pr 1 FAIL 'Critical 1 · Important 2')
EOF
dl a12 20260902-s2 <<EOF
$HDR
$(pr 1 FAIL 'Critical 2 · Important 1')
EOF
dl a12 20260903-s3 <<EOF
$HDR
$(pr 1 FAIL 'Important 3 · Minor 4')
EOF
dl a12 20260904-s4 <<EOF
$HDR
$(pr 1 FAIL 'Critical 0 · Important 0 · Minor 3')
EOF
dl a12 20260905-s5 <<EOF
$HDR
$(pr 1 FAIL '서술만 있음')
EOF
runs a12
ck "T12.a 심각도 분해: Critical≥1 2/5(40%) · Important 만 1/5(20%) · 둘 다 0 1/5(20%) · 읽지 못함 1/5(20%) — 네 구간의 합 = 분모" "$(printf '%s\n' "$OUT" | grep -F '심각도')" "첫 라운드 FAIL 심각도: Critical≥1 2/5 (40%) · Important 만 1/5 (20%) · 둘 다 0 1/5 (20%) · 읽지 못함 1/5 (20%)"
dl a12b 20260901-z1 <<EOF
$HDR
$(pr 1 FAIL 'Critical 0 · Minor 2')
$(pr 2 PASS)
EOF
dl a12b 20260902-z2 <<EOF
$HDR
$(pr 1 PASS)
EOF
dl a12b 20260903-z3 <<EOF
$HDR
$(pr 1 FAIL 'Critical 2 · Important 0')
$(pr 2 PASS)
EOF
runs a12b
ck "T12.b Critical 0 만 읽히고 Important 는 못 읽은 첫 FAIL(z1)은 '둘 다 0' 이 아니라 '읽지 못함' · 심각도는 마지막이 아니라 첫 라운드 기준(z3 는 첫 라운드 Critical 2)" "$(printf '%s\n' "$OUT" | grep -F '심각도')" "첫 라운드 FAIL 심각도: Critical≥1 1/2 (50%) · Important 만 0/2 (0%) · 둘 다 0 0/2 (0%) · 읽지 못함 1/2 (50%)"
dl a12c 20260901-y1 <<EOF
$HDR
$(pr 1 PASS)
EOF
runs a12c
ck "T12.c 첫 라운드 FAIL 이 0건이면 심각도 줄이 '첫 라운드 FAIL 없음'" "$(cnt '첫 라운드 FAIL 없음')|$(cnt '심각도')" "1|0"

# ── Part B: wall 귀속·옵션·부재·프라이버시·읽기 전용 ──
# Part B 는 서브에이전트 fixture 를 jq(agent-spans.sh)로 읽는다 — jq 가 없으면 Part A 결과만 보고하고 끝낸다(Part A 는 jq 없이 돈다)
if ! command -v jq >/dev/null 2>&1; then echo "SKIP: Part B 는 jq 필요"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]; exit; fi
# 서브에이전트 fixture: mkag 폴더 ID META — 본문(jsonl)은 stdin. META 가 "-" 면 meta 파일이 없다. meta 는 끝 개행 없이 쓴다(실제 포맷).
mkag() { mkdir -p "$1" && cat > "$1/agent-$2.jsonl" && touch -t 203001010000 "$1/agent-$2.jsonl"; [ "$3" = "-" ] || printf '%s' "$3" > "$1/agent-$2.meta.json"; }
# 레코드 한 줄: rec HH:MM:SS [YYYY-MM-DD] (기본 2026-09-01 UTC) — KST 로컬은 +9시간
rec() { printf '{"type":"user","timestamp":"%sT%s.000Z","message":{"content":"x"}}\n' "${2:-2026-09-01}" "$1"; }
META_PLAN='{"agentType":"specops-ko:plan-reviewer-ko","toolUseId":"toolu_p","spawnDepth":1}'
META_SPEC='{"agentType":"specops-ko:spec-reviewer-ko","toolUseId":"toolu_s","spawnDepth":1}'

# ══ AC-5: wall 귀속 — 원장 plan 창 [시작−60초, 끝+120초] ══
ledger w5 <<EOF
## 20260901-fida · A

- 2026-09-01 10:30 /plan 완료 (x)
- 2026-09-01 10:10 /clarify 완료 (x)
- 2026-09-01 10:00 /clarify 완료 (x)
- 2026-09-01 09:50 /specify 완료 (x)

## 20260901-fidb · B

- 2026-09-01 10:50 /plan 완료 (x)
- 2026-09-01 10:20 /clarify 완료 (x)
EOF
dl w5 20260901-fida <<EOF
$HDR
$(pr 1 FAIL)
$(pr 2 PASS)
EOF
dl w5 20260901-fidb <<EOF
$HDR
$(pr 1 PASS)
EOF
W5="$SB/w5td/s1/subagents"
{ rec 01:05:00; rec 01:15:00; } | mkag "$W5" a1 "$META_PLAN"
{ rec 01:12:00; rec 01:17:00; } | mkag "$W5" a2 "$META_PLAN"
{ rec 01:40:00; rec 01:48:00; } | mkag "$W5" b1 "$META_PLAN"
{ rec 01:25:00; rec 01:31:00; } | mkag "$W5" am "$META_PLAN"
{ rec 03:00:00; rec 03:04:00; } | mkag "$W5" no "$META_PLAN"
{ rec 01:06:00; rec 01:16:00; } | mkag "$W5" sp "$META_SPEC"
{ rec 00:59:00; rec 01:02:00; } | mkag "$W5" m60 "$META_PLAN"
{ rec 00:58:59; rec 01:00:59; } | mkag "$W5" m61 "$META_PLAN"
{ rec 01:06:00; rec 01:16:00; } | mkag "$W5" old "$META_PLAN"; touch -t 200001010000 "$W5/agent-old.jsonl"
TZV=Asia/Seoul runs w5 --transcript-dir "$SB/w5td"
ck "T5.a wall 줄: 에이전트 7개(spec-reviewer 제외) 중 귀속 4(A 3·B 1) · 모호 1(두 창 겹침) · 미귀속 2(창 밖·−61초) — FID 합 26분 · 라운드당 6.5분" "$RC|$(printf '%s\n' "$OUT" | grep -F 'wall:')" "0|wall: 에이전트 7개 중 귀속 4 · 모호 1 · 미귀속 2 — FID 합 26분 · 라운드당 평균 6.5분"
ck "T5.b 표: wall 내림차순 A(18분 = 10+5+3, −60초 에이전트 포함) → B(8분) · 시작은 /clarify 시각(09:50 /specify 가 아님)" "$(order)|$(trow 20260901-fida)|$(trow 20260901-fidb)" "20260901-fida,20260901-fidb,|2 FAIL PASS 0 0 18|1 PASS PASS 0 0 8"
TZV=Asia/Seoul runs w5 --transcript-dir "$SB/w5td" --top 1
ck "T5.c --top 1 이면 A 한 행만" "$(order)" "20260901-fida,"
TZV=UTC runs w5 --transcript-dir "$SB/w5td"
ck "T5.d 로컬 시각 기준: TZ=UTC 로 돌리면 원장(로컬 10시대)과 서브에이전트(UTC 01시대)가 어긋나 귀속 0 · 미귀속 7(TZ 를 무시하지 않는다)" "$(printf '%s\n' "$OUT" | grep -F 'wall:' | sed 's/—.*//')" "wall: 에이전트 7개 중 귀속 0 · 모호 0 · 미귀속 7 "
ledger w5b <<EOF
## 20260901-fidc · C

- 2026-09-01 11:20 /plan 완료 (x)
- 2026-09-01 11:15 /plan 완료 (x)
- 2026-09-01 11:00 /specify 완료 (x)
EOF
dl w5b 20260901-fidc <<EOF
$HDR
$(pr 1 PASS)
EOF
{ rec 02:10:00; rec 02:14:29; } | mkag "$SB/w5btd/s1/subagents" c1 "$META_PLAN"
{ rec 02:22:00; rec 02:25:30; } | mkag "$SB/w5btd/s1/subagents" c2 "$META_PLAN"
{ rec 02:22:01; rec 02:24:01; } | mkag "$SB/w5btd/s1/subagents" c3 "$META_PLAN"
TZV=Asia/Seoul runs w5b --transcript-dir "$SB/w5btd"
ck "T5.e /clarify 행이 없으면 /specify 행이 시작 · /plan 행이 둘이면 가장 늦은 시각이 끝(+120초 = 11:22:00 시작은 귀속, 11:22:01 은 미귀속) · 초는 합친 뒤 분으로 반올림(269+210=479초 → 8분)" "$(trow 20260901-fidc)|$(printf '%s\n' "$OUT" | grep -F 'wall:')" "1 PASS PASS 0 0 8|wall: 에이전트 3개 중 귀속 2 · 모호 0 · 미귀속 1 — FID 합 8분 · 라운드당 평균 4.0분"
dl w5b 20260901-fidx <<EOF
$HDR
$(pr 1 FAIL)
$(pr 2 FAIL)
$(pr 3 PASS)
EOF
dl w5b 20260901-fidy <<EOF
$HDR
$(pr 1 PASS)
EOF
TZV=Asia/Seoul runs w5b --transcript-dir "$SB/w5btd"
ck "T5.h 표 정렬은 행 단위다: wall 이 있는 행(fidc 8분)이 먼저, wall 이 없는 행끼리는 라운드 내림차순(fidx 3회 → fidy 1회)" "$(order)" "20260901-fidc,20260901-fidx,20260901-fidy,"
ledger w5s <<EOF
## 20260902-fidd · D

- 2026-09-02 13:20 /plan 완료 (x)
- 2026-09-02 13:00 /clarify 완료 (x)

## 20260901-fida · A

- 2026-09-01 10:30 /plan 완료 (x)
- 2026-09-01 10:00 /clarify 완료 (x)
EOF
dl w5s 20260901-fida <<EOF
$HDR
$(pr 1 PASS)
EOF
dl w5s 20260902-fidd <<EOF
$HDR
$(pr 1 FAIL)
$(pr 2 PASS)
EOF
{ rec 01:05:00; rec 01:15:00; } | mkag "$SB/w5std/s1/subagents" a1 "$META_PLAN"
{ rec 04:05:00 2026-09-02; rec 04:11:00 2026-09-02; } | mkag "$SB/w5std/s1/subagents" d1 "$META_PLAN"
TZV=Asia/Seoul runs w5s --transcript-dir "$SB/w5std" --since 20260902
ck "T5.f --since 20260902: 이전 FID(A)에 귀속될 에이전트는 표·합에서 빠지고 건수만 밝힌다" "$(printf '%s\n' "$OUT" | grep -F 'wall:')|$(order)" "wall: 에이전트 1개 중 귀속 1 · 모호 0 · 미귀속 0 — FID 합 6분 · 라운드당 평균 6.0분 · since 이전 FID 귀속 1개 제외|20260902-fidd,"
ledger w5n <<EOF
## 20260901-fida · A

- 2026-09-01 10:30 /plan 완료 (x)
- 2026-09-01 10:00 /clarify 완료 (x)
EOF
dl w5n 20260901-fida <<EOF
$HDR
$(pr 1 PASS)
EOF
{ echo '{"type":"user"}'; echo 'x'; } | mkag "$SB/w5ntd/s1/subagents" n1 "$META_PLAN"
{ echo '{"type":"user"}'; } | mkag "$SB/w5ntd/s1/subagents" n2 "$META_PLAN"
TZV=Asia/Seoul runs w5n --transcript-dir "$SB/w5ntd"
ck "T5.i 서브에이전트 파일은 있지만 시각 있는 레코드가 없으면 rc=0 · wall 측정 불가 한 줄 · 가짜 '에이전트 0개 중' 줄 없음 · 라운드 줄은 그대로" "$RC|$(cnt 'wall 측정 불가(시각 있는 서브에이전트 0개)')|$(cnt '에이전트 0개 중')|$(cnt 'FID 1개')" "0|1|0|1"
mkdir -p "$SB/w5z"; cp -R "$SB/w5s/." "$SB/w5z/"
dl w5z 20260903-fide <<EOF
$HDR
$(pr 1 FAIL)
EOF
TZV=Asia/Seoul runs w5z --transcript-dir "$SB/w5std" --since 20260903
ck "T5.j --since 로 귀속 에이전트가 전부 빠지면(총계 0 · 제외 2) 측정 불가가 아니라 제외 건수를 밝힌 종전 wall 줄을 낸다" "$(printf '%s\n' "$OUT" | grep -F 'wall:')|$(cnt 'wall 측정 불가')" "wall: 에이전트 0개 중 귀속 0 · 모호 0 · 미귀속 0 — FID 합 0분 · 라운드당 평균 0.0분 · since 이전 FID 귀속 2개 제외|0"

ledger w5r <<EOF
## 20260901-fida · A

- 2026-09-01 10:30 /plan 완료 (x)
- 2026-09-01 10:00 /clarify 완료 (x)
EOF
dl w5r 20260901-fida <<EOF
$HDR
$(pr 1 PASS)
EOF
{ rec 01:05:00; rec 01:15:00; } | mkag "$SB/w5rtd/s1/subagents" a1 "$META_PLAN"
{ rec 01:12:00; rec 01:17:00; } | mkag "$SB/w5rtd/s1/subagents" a9 '{"agentType":"specops-ko:plan-reviewer-ko","toolUseId":"","spawnDepth":0}'
{ rec 01:13:00; rec 01:18:00; } | mkag "$SB/w5rtd/s1/subagents" a8 '{"agentType":"plan-reviewer-ko","toolUseId":"toolu_q","spawnDepth":1}'
TZV=Asia/Seoul runs w5r --transcript-dir "$SB/w5rtd"
ck "T5.g 역할은 agent-spans 가 판정한다: meta 에 plan-reviewer-ko 가 있어도 toolUseId 가 비면 역할 '-' 라 세지 않고(a9), 네임스페이스 없는 이름은 센다(a8) — 에이전트 2개(10+5분) 귀속" "$(printf '%s\n' "$OUT" | grep -F 'wall:')" "wall: 에이전트 2개 중 귀속 2 · 모호 0 · 미귀속 0 — FID 합 15분 · 라운드당 평균 7.5분"

# ══ AC-6: 옵션·rc·transcript 디렉토리 해석 ══
BADS=""
bad() { runs a2 "$@"; BADS="$BADS$RC:${#OUT}:${ERR:+e},"; }
bad --since 2026-09-01; bad --since abc; bad --since; bad --predispatch-date 1; bad --predispatch-date
bad --top 0; bad --top x; bad --top -1; bad --top; bad --bogus
bad --transcript-dir "$SB/없는디렉토리"; bad --transcript-dir "$SB/a2/20260901-f1/dispatch-log.md"; bad --transcript-dir
ck "T6.a 잘못된 값·값 누락·알 수 없는 옵션·없는 디렉토리·파일을 준 --transcript-dir 13가지 모두 rc=2 · stdout 비어 있음 · 사유는 stderr" "$BADS" "2:0:e,2:0:e,2:0:e,2:0:e,2:0:e,2:0:e,2:0:e,2:0:e,2:0:e,2:0:e,2:0:e,2:0:e,2:0:e,"
TZV=Asia/Seoul runs w5 --since 20260901 --top 1 --transcript-dir "$SB/w5td" --predispatch-date 20260901
ck "T6.b 옵션 병용(--since --top --transcript-dir --predispatch-date)이 동작한다" "$RC|$(order)|$(cnt '도입 전 FID 0개 (20260901 미만)')|$(cnt 'wall: 에이전트 7개')" "0|20260901-fida,|1|1"
mkdir -p "$SB/proj/.specops"; cp -R "$SB/w5/." "$SB/proj/.specops/"
PHYS=$(cd "$SB/proj" && pwd -P); ENC=$(printf '%s' "$PHYS" | sed 's/[^A-Za-z0-9]/-/g')
mkdir -p "$SB/cfg/projects/$ENC"; cp -Rp "$SB/w5td/." "$SB/cfg/projects/$ENC/"
TZV=Asia/Seoul runs proj/.specops
ck "T6.c --transcript-dir 없이: CLAUDE_CONFIG_DIR/projects/<원장 루트 실경로의 비영숫자→-> 를 기본으로 찾는다(stage-timing.sh 와 같은 규칙)" "$RC|$(printf '%s\n' "$OUT" | grep -F 'wall:' | sed 's/—.*//')" "0|wall: 에이전트 7개 중 귀속 4 · 모호 1 · 미귀속 2 "

# ══ AC-7: 부재는 오류가 아니라 사실 ══
TZV=Asia/Seoul runs w5 --transcript-dir "$SB/w5td"; CORE_FULL=$(core)
TZV=Asia/Seoul runs w5
A_RC=$RC; A_CORE=$(core); A_WALL=$(cnt 'wall 측정 불가(transcript 디렉토리 없음')
mkdir -p "$SB/emptytd"
TZV=Asia/Seoul runs w5 --transcript-dir "$SB/emptytd"
B_RC=$RC; B_CORE=$(core); B_WALL=$(cnt 'wall 측정 불가(서브에이전트 파일 0개')
mkdir -p "$SB/nojq"; for t in awk sort grep sed find mktemp rm cat dirname; do p=$(command -v "$t") && [ -n "$p" ] && ln -sf "$p" "$SB/nojq/$t"; done
OUT=$(PATH="$SB/nojq" TZ=Asia/Seoul TMPDIR="$SB/tmp" HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/cfg" SPECOPS_ROOT="$SB/w5" "$BASH_BIN" "$RCS_SH" --transcript-dir "$SB/w5td" 2>/dev/null); C_RC=$?
C_CORE=$(core); C_WALL=$(cnt 'wall 측정 불가(jq 없음')
ck "T7.a transcript 디렉토리 없음 · 서브에이전트 파일 0개 · jq 없음 — 모두 rc=0 이고 라운드·FAIL·전후 비교·월별 줄은 wall 이 있을 때와 같다" "$A_RC$B_RC$C_RC|$([ "$A_CORE" = "$CORE_FULL" ] && [ "$B_CORE" = "$CORE_FULL" ] && [ "$C_CORE" = "$CORE_FULL" ] && echo same)|$([ -n "$CORE_FULL" ] && echo nonempty)" "000|same|nonempty"
ck "T7.b wall 자리에 사유가 한 줄로 표시된다(transcript 디렉토리 없음 · 서브에이전트 파일 0개 · jq 없음)" "$A_WALL$B_WALL$C_WALL" "111"
mkdir -p "$SB/w7d"; cp -R "$SB/w5/." "$SB/w7d/"
ledger w7d <<EOF
## 20260901-fida · A

- 2026-09-01 10:00 /specify 완료 (x)
EOF
TZV=Asia/Seoul runs w7d --transcript-dir "$SB/w5td"
D_RC=$RC; D_CORE=$(core); D_WALL=$(cnt 'wall 측정 불가(원장 plan 창 없음)')
mkdir -p "$SB/w7e"; cp -R "$SB/w5/." "$SB/w7e/"; rm -f "$SB/w7e/session-progress.md"
TZV=Asia/Seoul runs w7e --transcript-dir "$SB/w5td"
ck "T7.c 원장에 plan 창이 없거나 원장 자체가 없어도 rc=0 · 라운드 줄은 같고 사유(원장 plan 창 없음 · 원장 없음)가 표시된다" "$D_RC$RC|$([ "$D_CORE" = "$CORE_FULL" ] && [ "$(core)" = "$CORE_FULL" ] && echo same)|$D_WALL$(cnt 'wall 측정 불가(원장 없음)')" "00|same|11"
dl e0 20260901-x <<EOF
$HDR
$(pr 1 PASS - A:T1)
$(pr 2 PASS - End-loaded-B)
EOF
runs e0
E0=$RC; E0_N=$(cnt 'plan-reviewer 행 없음'); E0_TBL=$(cnt '비용 상위')
mkdir -p "$SB/e1"; cp "$SB/w5/session-progress.md" "$SB/e1/"
TZV=Asia/Seoul runs e1 --transcript-dir "$SB/w5td"
E1=$RC; E1_N=$(cnt 'plan-reviewer 행 없음'); E1_BOGUS=$(cnt '라운드 분포')
mkdir -p "$SB/e2"; runs e2
ck "T7.d plan-reviewer 행이 0건이면(다른 단계 행만 · 서브에이전트·원장만 있음 · 빈 \$SPECOPS) rc=0 으로 사실 줄만 — 표·분포·가짜 FID 줄 없음" "$E0|$E0_N|$E0_TBL|$E1|$E1_N|$E1_BOGUS|$RC|$(cnt 'plan-reviewer 행 없음')" "0|1|0|0|1|0|0|1"
runs 없는루트
ck "T7.e \$SPECOPS 디렉토리가 없으면 rc=2 · stdout 비어 있음 · 사유는 stderr" "$RC|${#OUT}|${ERR:+e}" "2|0|e"
# awk 가 실패하면(구현 차이·읽기 불가) 빈 결과가 정상 집계로 위장되지 않는다 — 특정 awk 프로그램만 실패하게 하는 shim(FAILPAT 이 인자에 있으면 rc 3)
mkdir -p "$SB/shimawk"; REAL_AWK=$(command -v awk)
printf '#!/bin/sh\ncase "$*" in *"$FAILPAT"*) echo "shim awk failure" >&2; exit 3 ;; esac\nexec "$REAL_AWK" "$@"\n' > "$SB/shimawk/awk"; chmod +x "$SB/shimawk/awk"
shimrun() {
  local pat="$1" nm="$2"; shift 2
  OUT=$(FAILPAT="$pat" REAL_AWK="$REAL_AWK" PATH="$SB/shimawk:$PATH" TZ=Asia/Seoul TMPDIR="$SB/tmp" HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/cfg" SPECOPS_ROOT="$SB/$nm" "$BASH_BIN" "$RCS_SH" "$@" 2>"$SB/err"); RC=$?; ERR=$(cat "$SB/err")
}
shimrun 'function numafter' w5 --transcript-dir "$SB/w5td"; F1="$RC:${#OUT}:$(printf '%s' "$ERR" | grep -c '파싱 실패')"
shimrun 'sp[fid]' w5 --transcript-dir "$SB/w5td"; F2="$RC:$([ "$(core)" = "$CORE_FULL" ] && echo same):$(cnt 'wall 측정 불가(원장 파싱 실패)')"
shimrun 'ws[$1]' w5 --transcript-dir "$SB/w5td"; F3="$RC:$([ "$(core)" = "$CORE_FULL" ] && echo same):$(cnt 'wall 측정 불가(귀속 계산 실패)')"
shimrun 'nfid++' w5 --transcript-dir "$SB/w5td"; F4="$RC:${#OUT}"
ck "T7.f awk 실패는 삼키지 않는다: 파서 실패 → rc 2 · 원장 창 실패·귀속 계산 실패 → rc 0 + 사유 줄 + 라운드 줄은 그대로 · 보고 awk 실패 → 0 이 아닌 rc 와 빈 stdout" "$F1|$F2|$F3|$F4" "2:0:1|0:same:1|0:same:1|3:0"

# ══ AC-8: 프라이버시 — 보고서·본문은 어디에도 나오지 않는다 ══
CAN="CANARY-$$-ZQX"
dl p8 20260901-fida <<EOF
$HDR
$(pr 1 FAIL "Critical 1 · Important 2 · $CAN-NOTE")
$(pr 2 PASS "$CAN-NOTE2")
$(pr 3 ABORT "$CAN-NOTE3")
EOF
mkdir -p "$SB/p8/20260901-fida/reviews"; printf '%s-REPORT\n' "$CAN" > "$SB/p8/20260901-fida/reviews/T1-C-report.md"; printf '%s-PRB\n' "$CAN" > "$SB/p8/20260901-fida/reviews/plan-review-1.md"
cp "$SB/w5/session-progress.md" "$SB/p8/"
{ printf '{"type":"user","timestamp":"2026-09-01T01:05:00.000Z","message":{"content":"%s-BODY"},"toolUseResult":{"x":"%s-TR"}}\n' "$CAN" "$CAN"; printf '{"type":"assistant","timestamp":"2026-09-01T01:15:00.000Z","message":{"content":"%s-IN"}}\n' "$CAN"; } | mkag "$SB/p8td/s1/subagents" x1 "{\"agentType\":\"specops-ko:plan-reviewer-ko\",\"toolUseId\":\"toolu_p\",\"description\":\"$CAN-DESC\"}"
mkdir -p "$SB/shim" "$SB/keep"
printf '#!/bin/sh\nfor a in "$@"; do [ -f "$a" ] && cp "$a" "'"$SB"'/keep/$(basename "$a").$$.$RANDOM" 2>/dev/null; done\nexec /bin/rm "$@"\n' > "$SB/shim/rm"; chmod +x "$SB/shim/rm"
ALL=""
OUT=$(PATH="$SB/shim:$PATH" TZ=Asia/Seoul TMPDIR="$SB/tmp" HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/cfg" SPECOPS_ROOT="$SB/p8" "$BASH_BIN" "$RCS_SH" --transcript-dir "$SB/p8td" 2>"$SB/err"); RC=$?; ERR=$(cat "$SB/err")
P_WALL=$(printf '%s\n' "$OUT" | grep -cF 'wall: 에이전트 1개 중 귀속 1')
ALL="$OUT$ERR"
runs p8 --bogus; ALL="$ALL$OUT$ERR"
runs p8없음; ALL="$ALL$OUT$ERR"
TZV=Asia/Seoul runs p8; ALL="$ALL$OUT$ERR"
ck "T8.a 정상(wall 귀속 포함)·오류·부재 경로 모두 stdout·stderr 에 카나리 0건 — 보고서 파일·비고 본문·서브에이전트 본문·meta description 모두(fixture 가 카나리를 실제로 품고 있고 wall 이 실제로 귀속됐음도 확인)" "$(printf '%s' "$ALL" | grep -c "$CAN")|$(grep -rl "$CAN" "$SB/p8" "$SB/p8td" | /usr/bin/wc -l | tr -d ' ')|$P_WALL" "0|5|1"
ck "T8.b 실행 중 임시 파일(삭제 직전에 복사해 둔 것)에도 카나리가 없고 임시 파일이 실제로 만들어졌으며 실행 뒤 TMPDIR 에 잔존이 없다" "$(cat "$SB/keep"/* 2>/dev/null | grep -c "$CAN")|$([ "$(ls -A "$SB/keep" | /usr/bin/wc -l | tr -d ' ')" -ge 3 ] && echo made)|$(ls -A "$SB/tmp" | /usr/bin/wc -l | tr -d ' ')" "0|made|0"
ck "T8.c 정적: 스크립트에 reviews 경로·본문을 읽는 키워드가 없다(읽는 입력은 dispatch-log·원장·agent-spans 출력뿐) — 그리고 jq 를 직접 호출하지 않는다(헬퍼 경유)" "$(grep -c 'reviews' "$RCS_SH")|$(grep -vE '^[[:space:]]*#' "$RCS_SH" | grep -cE '(\||\$\(|^)[[:space:]]*jq[[:space:]]')" "0|0"

# ══ AC-9: 읽기 전용·성능·정적 규약 ══
ALLF() { find "$SB/w5" "$SB/w5td" -type f | sort | xargs cksum; }
CK_BEFORE=$(ALLF)
TZV=Asia/Seoul runs w5 --transcript-dir "$SB/w5td"
CK_AFTER=$(ALLF)
ck "T9.a dispatch-log·원장·서브에이전트 파일은 실행 전후 동일하고 TMPDIR 에 잔존 파일이 없다" "$([ -n "$CK_BEFORE" ] && [ "$CK_BEFORE" = "$CK_AFTER" ] && echo same)|$(ls -A "$SB/tmp" | /usr/bin/wc -l | tr -d ' ')" "same|0"
ck "T9.b 정적: 스크립트에 mktime( 호출·행 단위 read 루프가 없다" "$(grep -vE '^[[:space:]]*#' "$RCS_SH" | grep -cE 'mktime\(|while[[:space:]]+(IFS=[^ ]* )?read')" "0"
mkdir -p "$SB/big"; : > "$SB/big/session-progress.md"
for i in $(seq 1 400); do
  f=$(printf '2026%02d%02d-big%03d' $((i % 12 + 1)) $((i % 28 + 1)) "$i")
  mkdir -p "$SB/big/$f"
  { echo "$HDR"; pr 1 FAIL 'Critical 1 · Important 2'; pr 2 FAIL 'Important 3'; pr 3 PASS; pr 1 PASS - A:T1; pr 4 ABORT; } > "$SB/big/$f/dispatch-log.md"
  printf '## %s · big\n\n- 2026-09-01 10:30 /plan 완료 (x)\n- 2026-09-01 10:00 /clarify 완료 (x)\n\n' "$f" >> "$SB/big/session-progress.md"
done
for i in $(seq 1 150); do { rec 01:05:00; rec 01:15:00; } | mkag "$SB/bigtd/s$i/subagents" "g$i" "$META_PLAN"; done
T0=$SECONDS
TZV=Asia/Seoul runs big --transcript-dir "$SB/bigtd"
T1=$SECONDS
ck "T9.c 합성 대형 입력(FID 400개 · 라운드 1200행 · 서브에이전트 150개)이 rc=0 · 20초 이내(CPU 경합 여유 — 실측 수 초. 10초 상한 M-1 은 verify 가 실환경으로 잰다)" "$RC|$(printf '%s\n' "$OUT" | grep -cF 'FID 400개')|$([ $((T1 - T0)) -le 20 ] && echo fast)" "0|1|fast"

# ══ AC-10: 문서 ══
SEC=$(awk '/^## review-cost.sh/ { on = 1; next } /^## / { on = 0 } on' "$PLUGIN/scripts/README.md")
kw() { if printf '%s\n' "$SEC" | grep -qF -- "$1"; then printf y; else printf n; fi; }
ck "T10.a README 에 review-cost 절이 있고 사용법·해석 주의(표본 n·인과가 아니다·plan 창 조인)·한계(사유 클래스 불가·행 기록 누락)·프라이버시(카나리)가 적혀 있다" "$(kw 'bash scripts/review-cost.sh')$(kw '표본 n')$(kw '인과가 아니다')$(kw '조인')$(kw '클래스')$(kw '누락')$(kw '카나리')" "yyyyyyy"
SEC2=$(awk '/^## review-cost.sh/ { on = 1; next } /^## / { on = 0 } on' "$PLUGIN/scripts/README.md")
kw2() { if printf '%s\n' "$SEC2" | grep -qF -- "$1"; then printf y; else printf n; fi; }
ck "T10.b README 한계는 코드와 일치한다: 해결된 두 문장(비고 | 열 밀림 · 에이전트 0개 중)은 없고 mtime 모집단 문장은 남아 있다" "$(kw2 '비고 안에 `|` 가 있으면')$(kw2 '`에이전트 0개 중` 으로 표시')$(kw2 '원장 최초 행 날짜 이후에 수정된')" "nny"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
