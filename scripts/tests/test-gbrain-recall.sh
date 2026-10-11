#!/usr/bin/env bash
# run-all: serial — T2.g 가 1000건 recall 을 < 2000ms 로 잰다(CPU 경합 시 초과)
# scripts/gbrain-recall.sh 검증 — GBRAIN_FILE 격리 fixture
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$PLUGIN/scripts/gbrain-recall.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
export GBRAIN_FILE="$TD/learnings.jsonl"

cat > "$GBRAIN_FILE" <<'EOF'
{"ts":"t1","fid":"f1","insight":"drift guard 자동화 release footer 동기화","tags":["release","drift-guard"]}
{"ts":"t2","fid":"f2","insight":"stdin 격리 sandbox 필수 headless 실행","tags":["llm-eval","sandbox"]}
{"ts":"t3","fid":"f3","insight":"공통 키워드 alpha 교훈 첫번째","tags":["alpha"]}
broken json line
{"ts":"t5","fid":"f5","insight":"공통 키워드 alpha 교훈 두번째","tags":["alpha"]}
EOF

# T2.a 관련 질의 → 매칭 출력 (release 토큰 → f1) + jsonl 원형 보존 (AC-10: fid/insight jq 추출 가능)
out=$(bash "$SCRIPT" "release footer 자동화"); rc=$?
top_fid=$(printf '%s\n' "$out" | head -1 | jq -r '.fid' 2>/dev/null)
if [ $rc -eq 0 ] && [ "$top_fid" = "f1" ]; then
  PASS=$((PASS+1)); echo "PASS T2.a 토큰 중첩 매칭 + jsonl 원형"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.a (rc=$rc top=$top_fid out=$out)"
fi

# T2.b 무관 질의 → 출력 0 + exit 0
out=$(bash "$SCRIPT" "kubernetes ingress"); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then
  PASS=$((PASS+1)); echo "PASS T2.b 무관 질의 → 빈 출력"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.b (rc=$rc out=$out)"
fi

# T2.c 깨진 jsonl 라인 skip — 전체 실패 없음 (FR-6)
out=$(bash "$SCRIPT" "alpha"); rc=$?
if [ $rc -eq 0 ] && ! echo "$out" | grep -q 'broken'; then
  PASS=$((PASS+1)); echo "PASS T2.c 깨진 라인 skip"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.c (rc=$rc out=$out)"
fi

# T2.d 동점 시 최신 (후순 라인) 우선 — alpha 동점 f3/f5 → f5 가 1순위 (AC-3)
top_fid=$(bash "$SCRIPT" "alpha" | head -1 | jq -r '.fid' 2>/dev/null)
if [ "$top_fid" = "f5" ]; then
  PASS=$((PASS+1)); echo "PASS T2.d 동점 최신 우선"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.d (top=$top_fid)"
fi

# T2.e --top 1 → 1건만
n=$(bash "$SCRIPT" "alpha" --top 1 | grep -c . || true)
if [ "$n" = "1" ]; then
  PASS=$((PASS+1)); echo "PASS T2.e --top 상한"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.e (n=$n)"
fi

# T2.f GBRAIN_FILE 부재 → 출력 0 + exit 0 (AC-4 env 격리 + graceful)
out=$(GBRAIN_FILE="$TD/nope.jsonl" bash "$SCRIPT" "release"); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then
  PASS=$((PASS+1)); echo "PASS T2.f 파일 부재 graceful"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.f (rc=$rc out=$out)"
fi

# T2.g NFR-1 — 합성 1000건 fixture: rc=0 + 실행 < 2s
BIG="$TD/big.jsonl"
awk 'BEGIN { for (i = 1; i <= 1000; i++) printf "{\"ts\":\"t%d\",\"fid\":\"bf%d\",\"insight\":\"성능 검증 perf bulk 항목 %d\",\"tags\":[\"perf\"]}\n", i, i, i }' > "$BIG"
now_ms() { perl -MTime::HiRes=time -e 'printf("%d", time()*1000)'; }
t0=$(now_ms)
out=$(GBRAIN_FILE="$BIG" bash "$SCRIPT" "perf 검증"); rc=$?
t1=$(now_ms)
elapsed=$((t1 - t0))
if [ $rc -eq 0 ] && [ "$elapsed" -lt 2000 ]; then
  PASS=$((PASS+1)); echo "PASS T2.g 1000건 rc=0 + ${elapsed}ms < 2000ms"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.g (rc=$rc elapsed=${elapsed}ms)"
fi

# T2.h 비객체 유효 JSON (스칼라) 라인 → 빈 줄 처리, 라인번호 오프셋 보존 — 후속 fid 정합
MIX="$TD/mixed.jsonl"
cat > "$MIX" <<'EOF'
123
"plain scalar text"
{"ts":"m3","fid":"m3","insight":"오프셋 검증 offsetcheck 토큰","tags":["offset"]}
EOF
out=$(GBRAIN_FILE="$MIX" bash "$SCRIPT" "offsetcheck" 2>/dev/null); rc=$?
top_fid=$(printf '%s\n' "$out" | head -1 | jq -r '.fid' 2>/dev/null)
if [ $rc -eq 0 ] && [ "$top_fid" = "m3" ]; then
  PASS=$((PASS+1)); echo "PASS T2.h 스칼라 JSON 라인 오프셋 보존"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.h (rc=$rc top=$top_fid out=$out)"
fi

# T2.i --top 비숫자 → exit 1 + 빈 stdout (lexical 비교 silent 상한 무시 차단)
out=$(bash "$SCRIPT" "alpha" --top abc 2>/dev/null); rc=$?
if [ $rc -eq 1 ] && [ -z "$out" ]; then
  PASS=$((PASS+1)); echo "PASS T2.i --top 비숫자 거부"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.i (rc=$rc out=$out)"
fi

# T2.j 한글 단독 질의 매칭 (Linux mawk byte semantics CI 포착용)
top_fid=$(bash "$SCRIPT" "동기화" | head -1 | jq -r '.fid' 2>/dev/null)
if [ "$top_fid" = "f1" ]; then
  PASS=$((PASS+1)); echo "PASS T2.j 한글 단독 질의 매칭"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.j (top=$top_fid)"
fi

# === confidence tiebreak (AC-3/R-2) ===
# 역순 배치(high=line1, low=line2) — NR-desc 만으로는 low(line2)가 위로 와야 하므로
# cw 키(-k2)를 회귀로 제거하면 FAIL 하는 변별적 가드. cw tiebreak 작동 시에만 high 우선.
gd=$(mktemp -d) || exit 1; gf="$gd/learnings.jsonl"
printf '%s\n' '{"ts":"t","fid":"f","insight":"공통토큰 인사이트 높음","tags":["x"],"confidence":"high"}' >> "$gf"
printf '%s\n' '{"ts":"t","fid":"f","insight":"공통토큰 인사이트 낮음","tags":["x"],"confidence":"low"}' >> "$gf"
out=$(GBRAIN_FILE="$gf" bash "$PLUGIN/scripts/gbrain-recall.sh" "공통토큰 인사이트" --top 2 2>/dev/null)
first=$(printf '%s' "$out" | head -1 | jq -r '.confidence')
[ "$first" = "high" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: AC-3 tiebreak high 우선 아님 ($first)"; }
printf '%s\n' '{"ts":"t","fid":"f","insight":"공통토큰 노conf","tags":["x"]}' >> "$gf"
GBRAIN_FILE="$gf" bash "$PLUGIN/scripts/gbrain-recall.sh" "공통토큰" --top 3 >/dev/null 2>&1 && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: AC-R-2 graceful"; }
rm -rf "$(dirname "$gf")"

# === 탭 포함 insight 스코어 무회귀 (AC-R-2 — Phase C Important #1) ===
# insight 에 리터럴 탭 → 탭 이후 토큰도 스코어링돼야 함 (jq $txt 탭 평탄화).
# 회귀(gsub 제거) 시 -F'\t' 가 탭 이후를 $3+ 로 밀어 미매칭 → FAIL 하는 변별적 가드.
gd=$(mktemp -d) || exit 1; gf="$gd/learnings.jsonl"
printf '%s\n' '{"ts":"t","fid":"f","insight":"alpha\tbetagamma keyword","tags":["x"]}' >> "$gf"
out=$(GBRAIN_FILE="$gf" bash "$PLUGIN/scripts/gbrain-recall.sh" "betagamma" --top 1 2>/dev/null)
[ -n "$out" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: AC-R-2 탭 이후 토큰 스코어 누락(회귀)"; }
rm -rf "$(dirname "$gf")"

# === 로케일 고르기 (FID 20261011-script-pipe-grep) ===
# UTF-8 이 아닌 로케일에서 스크립트는 `locale -a` 목록에 C.UTF-8(또는 C.utf8)이 있으면 그것을, 없으면 en_US.UTF-8 을 고른다.
# 종전의 `locale -a | grep -q` 는 pipefail 아래에서, grep 이 첫 일치에서 끝난 뒤 locale 이 SIGPIPE 로 죽어 "있는데도 없다" 로
#   읽었다(macOS 실측 50회 중 50회). 가짜 locale 을 PATH 앞에 두어 목록을 파이프 버퍼(64KB)보다 길게 만들고(환경과 무관하게
#   그 경합을 만든다), 스크립트가 고른 값은 실행 흔적(bash -x)으로 본다.
ld="$TD/fakebin"; mkdir -p "$ld"
_fake_locale() {  # <앞줄…> → 그 줄들을 먼저 쓰고 이어서 약 120KB 를 쓰는 locale
  {
    printf '#!/bin/sh\n'
    for _l in "$@"; do printf 'echo %s\n' "$_l"; done
    printf '%s\n' "awk 'BEGIN { for (i = 0; i < 6000; i++) print \"xx_YY.ISO8859-\" i }'"
  } > "$ld/locale"
  chmod +x "$ld/locale"
}
_picked() {  # → 스크립트가 고른 LC_ALL 값 (고르지 않았으면 빈 문자열)
  LC_ALL=C LANG=C PS4='+ ' PATH="$ld:$PATH" bash -x "$SCRIPT" "alpha" 2>&1 >/dev/null | sed -n 's/^+ export LC_ALL=//p'
}
_fake_locale C C.UTF-8 POSIX
_lbad=""
for _li in 1 2 3 4 5; do _lp=$(_picked); [ "$_lp" = "C.UTF-8" ] || _lbad="$_lbad [$_lp]"; done
if [ -z "$_lbad" ]; then
  PASS=$((PASS+1)); echo "PASS T3.a 로케일 목록에 C.UTF-8 이 있으면 그것을 고른다 (5회 반복 · 목록 약 120KB)"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.a C.UTF-8 이 목록에 있는데 다른 값을 골랐다:$_lbad"
fi
_fake_locale C C.utf8 POSIX
_lp=$(_picked)
if [ "$_lp" = "C.UTF-8" ]; then
  PASS=$((PASS+1)); echo "PASS T3.b glibc 표기(C.utf8)도 같은 것으로 읽는다"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.b (고른 값='$_lp')"
fi
_fake_locale C POSIX
_lp=$(_picked)
if [ "$_lp" = "en_US.UTF-8" ]; then
  PASS=$((PASS+1)); echo "PASS T3.c 목록에 C.UTF-8 이 없으면 en_US.UTF-8 로 떨어진다"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.c (고른 값='$_lp')"
fi

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
