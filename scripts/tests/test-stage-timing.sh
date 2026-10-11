#!/usr/bin/env bash
# stage-timing.sh — FID 간 단계별 소요 집계 (fixture 원장은 SPECOPS_ROOT 로 주입, 토큰 0)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ST="$PLUGIN/scripts/stage-timing.sh"
SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT

ck() { if [ "$2" = "$3" ]; then echo "PASS $1"; PASS=$((PASS+1)); else echo "FAIL $1 — exp '$3' got '$2'"; FAIL=$((FAIL+1)); fi; }

# 원장 fixture 를 만든다: mkroot 이름 — 본문은 stdin. SPECOPS_ROOT 로 쓸 디렉토리를 출력한다.
mkroot() { mkdir -p "$SB/$1" && cat > "$SB/$1/session-progress.md" && printf '%s' "$SB/$1"; }
# 실행: run root [옵션...] — 전역 OUT·ERR·RC
run() {
  local root="$1"; shift
  OUT=$(SPECOPS_ROOT="$root" bash "$ST" "$@" 2>"$SB/err"); RC=$?
  ERR=$(cat "$SB/err")
}
# 표에서 단계 행의 "합계 비중 n 중앙값 p90 max" 를 뽑는다 (단계 이름은 행 끝)
row() { printf '%s\n' "$OUT" | grep -E "^ *[0-9]+ +[0-9.]+% .* $1\$" | awk '{print $1, $2, $3, $4, $5, $6}'; }

FX1=$(mkroot fx1 <<'EOF'
# Session Progress

## 20261001-aaa · A

- 2026-10-01 10:30 /plan 완료 (x)
- 2026-10-01 10:10 /clarify 완료 (x)
- 2026-10-01 10:00 /specify 완료 (x)

## 20261001-bbb · B

- 2026-10-02 09:10 /clarify 완료 (x)
- 2026-10-02 09:08 /specify 완료 (x)
EOF
)

# ── AC-1: 인접 차이 귀속·집계 ──
run "$FX1"
ck "T1.a rc=0" "$RC" "0"
ck "T1.b /clarify 완료: n=2 중앙값 2 p90 10 max 10 합계 12 비중 37.5%" "$(row '/clarify 완료')" "12 37.5% 2 2 10 10"
ck "T1.c /plan 완료: n=1 합계 20 비중 62.5%" "$(row '/plan 완료')" "20 62.5% 1 20 20 20"
FIRST=$(printf '%s\n' "$OUT" | grep -E '^ *[0-9]+ +[0-9.]+% ' | head -1 | awk '{print $NF" "$(NF-1)}')
ck "T1.d 합계 내림차순 — 첫 행이 /plan 완료" "$FIRST" "완료 /plan"
ck "T1.e 기준 행 없는 /specify 완료는 집계에 없음 + FID 경계 비교차" "$(printf '%s\n' "$OUT" | grep -cE '^ *[0-9]+ +[0-9.]+% .* /specify 완료$')" "0"

FX2=$(mkroot fx2 <<'EOF'
## 20261001-ccc · C

- 2026-10-01 09:01 /verify PASS (x)
- 2026-10-01 09:01 /implement DONE (x)
- 2026-10-01 08:59 /tasks 완료 (x)
EOF
)
run "$FX2"
ck "T1.f 08:59→09:01 = 2분(8진수 함정 없음) · 동일 분은 원장 순서 tiebreak(implement 2 · verify 0)" \
   "$(row '/implement DONE') | $(row '/verify PASS')" "2 100.0% 1 2 2 2 | 0 0.0% 1 0 0 0"

TIE=$(mkroot tie <<'EOF'
## 20261001-ggg · G

- 2026-10-01 10:05 /plan 완료 (x)
- 2026-10-01 10:04 /plan SKIP (x)
- 2026-10-01 10:03 /m 완료 (x)
- 2026-10-01 10:02 /a 완료 (x)
- 2026-10-01 10:01 /z 완료 (x)
- 2026-10-01 10:00 /specify 완료 (x)
EOF
)
run "$TIE"
ck "T1.g 합계 동률(각 1분)이면 단계 이름 바이트 순 — 삽입 순서·로케일과 무관" \
   "$(printf '%s\n' "$OUT" | grep -E '^ *[0-9]+ +[0-9.]+% ' | awk '{print $(NF-1)" "$NF}' | tr '\n' ',')" "/a 완료,/m 완료,/plan SKIP,/plan 완료,/z 완료,"

# 단일 키 1500구간 — 간격은 결정적 LCG(x·75+74 mod 65537, 곱이 2^53 미만이라 awk 3종 동일)로 0~599분(방치 상한 720 이하).
# 값 범위를 넓혀 중복을 줄인다 — 0~49 처럼 좁으면 덜 정렬된 배열(예: 간격 1 패스 누락)도 분위수가 우연히 맞는다(변이 실측).
# 기대값은 생성한 간격 목록을 sort -n 으로 정렬해 nearest-rank 순위로 뽑는다(구현의 정렬·분위수 코드와 독립).
# 시각은 2026-01-01 00:00 기준 분 오프셋을 월 길이 표(2026 평년)로 월·일·시·분에 나눠 쓴다 — 구현의 일수 산술과 독립.
# 총합이 365일 미만이어야 2026년 안에 머문다(아래 단언). 원장 규약대로 최신 행이 위.
LARGE="$SB/large"; mkdir -p "$LARGE"
awk -v gapf="$SB/large-gaps" 'BEGIN {
  split("31 28 31 30 31 30 31 31 30 31 30 31", ML, " ")
  x = 1; t[0] = 0
  for (i = 1; i <= 1500; i++) { x = (x * 75 + 74) % 65537; g = x % 600; t[i] = t[i - 1] + g; print g > gapf }
  print "## 20261001-large · L\n"
  for (i = 1500; i >= 0; i--) {
    dd = int(t[i] / 1440); mo = 1
    while (mo < 12 && dd >= ML[mo]) { dd -= ML[mo]; mo++ }
    printf "- 2026-%02d-%02d %02d:%02d %s (x)\n", mo, dd + 1, int((t[i] % 1440) / 60), t[i] % 60, (i > 0 ? "/x 완료" : "/start 완료")
  }
}' > "$LARGE/session-progress.md"
LG_SORTED=$(sort -n "$SB/large-gaps")
LG_SUM=$(awk '{ s += $1 } END { print s }' "$SB/large-gaps")
LG_MED=$(printf '%s\n' "$LG_SORTED" | sed -n '750p')    # ceil(0.50 × 1500) = 750 번째
LG_P90=$(printf '%s\n' "$LG_SORTED" | sed -n '1350p')   # ceil(0.90 × 1500) = 1350 번째
LG_MAX=$(printf '%s\n' "$LG_SORTED" | tail -1)
run "$LARGE"
ck "T1.h 단일 키 1500구간: 합계·n·중앙값·p90·max 가 독립 계산(sort -n + nearest-rank)과 일치 · 총합 365일 미만" \
   "$(row '/x 완료')|$(( LG_SUM < 365 * 1440 ))" "$LG_SUM 100.0% 1500 $LG_MED $LG_P90 $LG_MAX|1"

# ── AC-2: 방치 구간 ──
FX3=$(mkroot fx3 <<'EOF'
## 20261001-ddd · D

- 2026-10-02 10:05 /verify PASS (x)
- 2026-10-02 10:00 /implement DONE (x)
- 2026-10-01 10:00 /tasks 완료 (x)
EOF
)
run "$FX3"
ck "T2.a 기본 상한: 1440분 구간은 통계에서 제외, /verify PASS 5분만" "$(row '/verify PASS')" "5 100.0% 1 5 5 5"
ck "T2.b 제외 줄: 1건 합 1440분" "$(printf '%s\n' "$OUT" | grep -c '방치 구간 제외 1건 (합 1440분)')" "1"
ck "T2.c 제외 구간의 단계는 표에 없음" "$(printf '%s\n' "$OUT" | grep -cE '^ *[0-9]+ +[0-9.]+% .* /implement DONE$')" "0"
run "$FX3" --gap-cap-min 2000
ck "T2.d 상한 2000: 포함 — /implement DONE 합계 1440" "$(row '/implement DONE')" "1440 99.7% 1 1440 1440 1440"
ck "T2.e 상한 2000: 제외 0건 표시" "$(printf '%s\n' "$OUT" | grep -c '방치 구간 제외 0건 (합 0분)')" "1"

EDGE=$(mkroot edge <<'EOF'
## 20261001-hhh · H

- 2026-10-01 10:21 /c 완료 (x)
- 2026-10-01 10:10 /b 완료 (x)
- 2026-10-01 10:00 /a 완료 (x)
EOF
)
run "$EDGE" --gap-cap-min 10
ck "T2.f 경계값: 정확히 상한(10분)은 포함, 상한+1(11분)은 제외" \
   "$(row '/b 완료')|$(printf '%s\n' "$OUT" | grep -cE '^ *[0-9]+ +[0-9.]+% .* /c 완료$')|$(printf '%s\n' "$OUT" | grep -c '방치 구간 제외 1건 (합 11분)')" "10 100.0% 1 10 10 10|0|1"

# ── AC-3: 머리말·가림·집계 불가 ──
FX4=$(mkroot fx4 <<'EOF'
## 20261001-aaa · A

- 2026-10-01 10:30 /plan 완료 (x)
- 2026-10-01 10:10 /clarify 완료 (x)
- 2026-10-01 10:00 /specify 완료 (x)

## 20261001-bbb · B

- 2026-10-02 09:10 /clarify 완료 (x)
- 2026-10-02 09:08 /specify 완료 (x)

## 20261001-eee · E

- 2026-10-03 08:00 /specify 완료 (x)
EOF
)
run "$FX4" --min-n 2
for kw in '완료시각 인접 차이' '분 해상도' '대기 포함 경과 시간' 'FID 경계 미교차' 'DST'; do
  ck "T3.a 머리말 키워드: $kw" "$(printf '%s\n' "$OUT" | grep -c "$kw")" "1"
done
ck "T3.b --min-n 2: /plan 완료(n=1) 가림, 가린 단계 수 표시" "$(printf '%s\n' "$OUT" | grep -c '표 가림(--min-n 2) 1단계')" "1"
ck "T3.c 가려진 단계는 표에 없음" "$(printf '%s\n' "$OUT" | grep -cE '^ *[0-9]+ +[0-9.]+% .* /plan 완료$')" "0"
ck "T3.d 집계 불가 표시: FID 첫 행 3개 · 행 1개뿐인 FID 1개" "$(printf '%s\n' "$OUT" | grep -c 'FID 첫 행 3개는 기준 행이 없어 집계에 없음 (행 1개뿐인 FID 1개)')" "1"

ck "T3.e 표 머리행은 한글 표시 폭에 맞춰 정렬된 고정 문자열" "$(printf '%s\n' "$OUT" | grep -E '단계$' | head -1)" "   합계    비중     n  중앙값    p90    max  단계"
ck "T3.f since 없음이면 FID 첫 행 줄에 since 제외 절이 붙지 않음 · 불일치 행 0건 표시" \
   "$(printf '%s\n' "$OUT" | grep -c 'since 이전에 끝난')|$(printf '%s\n' "$OUT" | grep -c '형식 불일치·범위 밖 행 0건은 무시됨 (집계 제외)')" "0|1"

# FID 섹션 안의 형식 불일치 행(커맨드가 / 로 시작 안 함)·시각 범위 밖 행(24:00)은 건수만 세고 집계에서 뺀다.
# FID 가 아닌 섹션의 "- " 행은 원장 행이 아니므로 세지 않는다.
BAD=$(mkroot bad <<'EOF'
## 활용 방법

- 이 줄은 FID 섹션 밖이라 세지 않는다

## 20261001-iii · I

- 2026-10-01 11:00 /c 완료 (x)
- 2026-10-01 24:00 /b 완료 (x)
- 2026-10-01 10:30 implementer-ko Task 1 완료 (x)
- 2026-10-01 10:00 /a 완료 (x)
EOF
)
run "$BAD"
ck "T3.g 형식 불일치 1 + 범위 밖 1 = 2건 표시(FID 밖 행 미포함)" "$(printf '%s\n' "$OUT" | grep -c '형식 불일치·범위 밖 행 2건은 무시됨 (집계 제외)')" "1"
ck "T3.h 범위 밖 행은 방치 구간으로 흡수되지 않고 건너뛴다(/a 10:00 → /c 11:00 = 60분)" \
   "$(row '/c 완료')|$(printf '%s\n' "$OUT" | grep -c '방치 구간 제외 0건 (합 0분)')|$(printf '%s\n' "$OUT" | grep -cE '^ *-?[0-9]+ +-?[0-9.]+% .* /b 완료$')" "60 100.0% 1 60 60 60|1|0"

# ── AC-4: 옵션·rc ──
run "$SB/없는-디렉토리"
ck "T4.a 원장 부재 → rc=2 · stderr 사유 · stdout 비어 있음" "$RC|$(printf '%s' "$ERR" | grep -c '원장 없음')|$OUT" "2|1|"
run "$FX1" --bogus
ck "T4.b 알 수 없는 옵션 → rc=2" "$RC|$(printf '%s' "$OUT")" "2|"
run "$FX1" --gap-cap-min abc
ck "T4.c 숫자 아닌 --gap-cap-min → rc=2" "$RC|$(printf '%s' "$OUT")" "2|"
run "$FX1" --since 2026-10-01
ck "T4.d --since 형식 오류 → rc=2" "$RC|$(printf '%s' "$OUT")" "2|"
run "$FX1" --min-n 0
ck "T4.e --min-n 0 → rc=2" "$RC|$(printf '%s' "$OUT")" "2|"
run "$FX1" --since
ck "T4.f 값 없는 옵션 → rc=2" "$RC|$(printf '%s' "$OUT")" "2|"
ONE=$(mkroot one <<'EOF'
## 20261001-fff · F

- 2026-10-01 10:00 /specify 완료 (x)
EOF
)
run "$ONE"
ck "T4.g 행 1개뿐 → rc=0 · '집계할 구간 없음' 사실 표시(원장 부재와 구별)" "$RC|$(printf '%s\n' "$OUT" | grep -c '집계할 구간 없음')" "0|1"
run "$FX1" --since 20261002
ck "T4.h --since 20261002: 도착 행 날짜가 기준일 이상인 구간만(bbb /clarify 2분)" "$(row '/clarify 완료')|$(printf '%s\n' "$OUT" | grep -cE '^ *[0-9]+ +[0-9.]+% .* /plan 완료$')" "2 100.0% 1 2 2 2|0"
ck "T4.j --since 20261002: since 이전에 끝난 FID(aaa)는 대상에서 빼고 그 수를 같은 줄에 표시" \
   "$(printf '%s\n' "$OUT" | grep -c 'FID 첫 행 1개는 기준 행이 없어 집계에 없음 (행 1개뿐인 FID 0개) · since 이전에 끝난 FID 1개 제외')" "1"
# since 가 FID 중간에 걸친다 — 첫 행(10-01)은 since 이전, 마지막 행(10-02)은 이후. "끝난" 판정은 마지막 행 날짜라 대상이다.
MID=$(mkroot mid <<'EOF'
## 20261001-mid · M

- 2026-10-02 00:10 /b 완료 (x)
- 2026-10-01 23:50 /a 완료 (x)
EOF
)
run "$MID" --since 20261002
ck "T4.m since 가 FID 중간에 걸치면 대상(마지막 행 기준) — 자정 넘김 20분 · 제외 0개" \
   "$(row '/b 완료')|$(printf '%s\n' "$OUT" | grep -c 'FID 첫 행 1개는 기준 행이 없어 집계에 없음 (행 1개뿐인 FID 0개) · since 이전에 끝난 FID 0개 제외')" "20 100.0% 1 20 20 20|1"
EMPTY=$(mkroot empty <<'EOF'
# Session Progress (행 없음)
EOF
)
run "$EMPTY"
ck "T4.i 행이 아예 없는 원장 → rc=0 · 구간 없음 표시" "$RC|$(printf '%s\n' "$OUT" | grep -c '집계할 구간 없음')" "0|1"
run "$FX1" --gap-cap-min 99999999999999999999
ck "T4.k 거대 --gap-cap-min 은 원문 그대로 표시(awk 구현별 수치 표기 차이 없음) · 비교는 정상(구간 포함)" \
   "$RC|$(printf '%s\n' "$OUT" | grep -c '방치 상한 99999999999999999999분')|$(row '/plan 완료')" "0|1|20 62.5% 1 20 20 20"
BSROOT=$(printf '%s\n' '## 20261001-jjj · J' '' '- 2026-10-01 10:05 /b 완료 (x)' '- 2026-10-01 10:00 /a 완료 (x)' | mkroot 'bs\nx')
run "$BSROOT"
ck "T4.l 원장 경로의 역슬래시는 이스케이프 해석 없이 원문 표시" "$(printf '%s\n' "$OUT" | grep -cF "원장: $BSROOT/session-progress.md · FID 1개")" "1"

# ── AC-5: 읽기 전용 · 정적 규약 · 성능 · 로케일 ──
BEFORE="$(cksum < "$FX1/session-progress.md")|$(git -C "$PLUGIN" status --porcelain 2>/dev/null | cksum)"
run "$FX1"
AFTER="$(cksum < "$FX1/session-progress.md")|$(git -C "$PLUGIN" status --porcelain 2>/dev/null | cksum)"
ck "T5.a 실행 전후 원장 바이트·git status 동일(읽기 전용)" "$AFTER" "$BEFORE"
ck "T5.b mktime 호출 없음(BSD awk 에 없다)" "$(grep -cE 'mktime *\(' "$ST")" "0"
ck "T5.c 행 단위 read 루프 없음(외부 프로세스 줄 스폰 금지)" "$(grep -cE 'while +(IFS= +)?(-r +)?read' "$ST")" "0"
OUT_DEFAULT="$OUT"
# stdout 만 비교한다 — 로케일이 없는 러너(Ubuntu CI)에선 bash 가 stderr 에 setlocale 경고를 내고 C 로 되돌아가므로 이 단언은 best-effort 보험이고, 실질 잠금은 T1.g(동률 정렬)다.
OUT_KO=$(LANG=ko_KR.UTF-8 LC_ALL=ko_KR.UTF-8 SPECOPS_ROOT="$FX1" bash "$ST" 2>/dev/null)
ck "T5.d 로케일을 바꿔도 출력 동일(LC_ALL 고정 — 동률 정렬 비교가 로케일 의존이라 T1.g 와 함께 잠근다)" "$OUT_KO" "$OUT_DEFAULT"
BIG="$SB/big"; mkdir -p "$BIG"
awk 'BEGIN {
  print "# Session Progress"
  for (f = 1; f <= 350; f++) {
    printf "\n## 202610%02d-big%d · B\n\n", (f % 28) + 1, f
    for (r = 10; r >= 1; r--) printf "- 2026-10-%02d %02d:%02d /step%d 완료 (x)\n", (f % 28) + 1, 9 + int(r / 6), (r * 7) % 60, r
  }
}' > "$BIG/session-progress.md"
T0=$(date +%s)
run "$BIG"
T1=$(date +%s)
ck "T5.e 3500행 원장 집계 rc=0 · 3초 이내(NFR-1 은 1초 — CPU 경합 여유)" "$RC|$(( T1 - T0 <= 3 ))" "0|1"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
