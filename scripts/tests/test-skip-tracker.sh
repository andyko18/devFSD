#!/usr/bin/env bash
# skip-tracker.sh 집계 로직 stub 단위 (토큰 0)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck disable=SC1091
source "$PLUGIN/scripts/skip-tracker.sh"
ck() { if [ "$2" = "$3" ]; then echo "PASS $1"; PASS=$((PASS+1)); else echo "FAIL $1 — exp '$3' got '$2'"; FAIL=$((FAIL+1)); fi; }

ck "T1 rate 3/4 → 75" "$(skip::rate 3 4)" "75"
ck "T2 rate 0/0 → 0"  "$(skip::rate 0 0)" "0"
ck "T3 rate 7/10 → 70" "$(skip::rate 7 10)" "70"

tmp=$(mktemp -d)
mkdir -p "$tmp/fid-a" "$tmp/fid-b" "$tmp/fid-c"
printf '## /integration-test — 2026-06-14\n**결과**: SKIP\n## /performance-test — 2026-06-14\n**결과**: PASS\n' > "$tmp/fid-a/evidence.md"
printf '## /integration-test — SKIP (인프라)\n## /performance-test — SKIP (NFR 없음)\n' > "$tmp/fid-b/evidence.md"
printf '## /integration-test — 2026-06-13\n**결과**: FAIL\n' > "$tmp/fid-c/evidence.md"

ck "T4 integration count" "$(skip::count "$tmp" integration)" "0 2 1"
ck "T5 performance count" "$(skip::count "$tmp" performance)" "1 1 0"
ck "T6 verdicts 구조형" "$(skip::verdicts "$tmp/fid-a/evidence.md" integration)" "SKIP"
ck "T7 verdicts 인라인형" "$(skip::verdicts "$tmp/fid-b/evidence.md" integration)" "SKIP"

out=$(SKIP_TRACKER_THRESHOLD=50 skip::report "$tmp" 2>/dev/null)
if grep -qE "integration: total=3 PASS=0 SKIP=2 FAIL=1" <<<"$out"; then echo "PASS T8 report 형식"; PASS=$((PASS+1)); else echo "FAIL T8 report ($out)"; FAIL=$((FAIL+1)); fi
if grep -q "⚠️" <<<"$out"; then echo "PASS T9 임계 advisory ⚠️"; PASS=$((PASS+1)); else echo "FAIL T9 ⚠️ ($out)"; FAIL=$((FAIL+1)); fi
rm -rf "$tmp"

out2=$(skip::report "/nonexistent" 2>/dev/null); rc=$?
if grep -q "evidence 없음" <<<"$out2" && [ "$rc" -eq 0 ]; then echo "PASS T10 graceful"; PASS=$((PASS+1)); else echo "FAIL T10 graceful (rc=$rc $out2)"; FAIL=$((FAIL+1)); fi

# T11 인접 헤더 오연관 차단 — integration 헤더(결과 없음) 직후 performance **결과**: SKIP 가 integration 으로 오집계되면 안 됨
tmp2=$(mktemp -d)
printf '## /integration-test — 2026-06-14\n## /performance-test — 2026-06-14\n**결과**: SKIP\n' > "$tmp2/evidence.md"
ck "T11 인접 헤더 오연관 차단 (integration verdict 없음)" "$(skip::verdicts "$tmp2/evidence.md" integration)" ""
rm -rf "$tmp2"

# T12~T16: cite_status CITED/BARE + bare 경고
tmpc=$(mktemp -d); mkdir -p "$tmpc/fid-c" "$tmpc/fid-b"
printf '## /integration-test — 2026-06-15\n**결과**: SKIP\n**근거**: spec.md §2 L20-23\n' > "$tmpc/fid-c/evidence.md"
printf '## /integration-test — SKIP (인프라, 표면 없음)\n' > "$tmpc/fid-b/evidence.md"
ck "T12 cite_status 두줄형 CITED" "$(skip::cite_status "$tmpc/fid-c/evidence.md" integration)" "CITED"
ck "T13 cite_status 한줄형 BARE" "$(skip::cite_status "$tmpc/fid-b/evidence.md" integration)" "BARE"
# T13b: 두줄형 결과:SKIP 직후 근거 라인 부재(다음 헤더 직행) → BARE (hardening)
printf '## /integration-test — 2026-06-15\n**결과**: SKIP\n## /performance-test — 2026-06-15\n**결과**: PASS\n' > "$tmpc/fid-b/evidence.md"
ck "T13b cite_status 근거부재 두줄형 BARE" "$(skip::cite_status "$tmpc/fid-b/evidence.md" integration)" "BARE"
printf '## /integration-test — SKIP (인프라, 표면 없음)\n' > "$tmpc/fid-b/evidence.md"
ck "T14 verdicts 토큰 불변(CITED 파일도 SKIP)" "$(skip::verdicts "$tmpc/fid-c/evidence.md" integration)" "SKIP"
outb=$(skip::report "$tmpc" 2>/dev/null)
if grep -q "근거 없는 SKIP 1건" <<<"$outb"; then echo "PASS T15 bare 경고 1건"; PASS=$((PASS+1)); else echo "FAIL T15 ($outb)"; FAIL=$((FAIL+1)); fi
rm -rf "$tmpc"
# T16: bare=0(전부 CITED) → 경고 없음
tmpz=$(mktemp -d); mkdir -p "$tmpz/fid-z"
printf '## /integration-test — 2026-06-15\n**결과**: SKIP\n**근거**: §범위 L12-15\n## /performance-test — 2026-06-15\n**결과**: SKIP\n**근거**: §NFR L45\n' > "$tmpz/fid-z/evidence.md"
outz=$(skip::report "$tmpz" 2>/dev/null)
if grep -q "근거 없는 SKIP" <<<"$outz"; then echo "FAIL T16 cited인데 경고 ($outz)"; FAIL=$((FAIL+1)); else echo "PASS T16 cited→경고0"; PASS=$((PASS+1)); fi
rm -rf "$tmpz"

# T17~T19: security 게이트 커버 (버그1 fix — security 헤더 '## /security-review' 는 skip-tracker
#   '-test' 하드코딩 패턴에 안 걸려 security bare SKIP 이 관측 死문이었다. security-review-ko L42 계약 정합)
tmps=$(mktemp -d); mkdir -p "$tmps/fid-s1" "$tmps/fid-s2"
printf '## /security-review — 2026-07-19\n**결과**: SKIP\n**근거**: §범위 L10\n' > "$tmps/fid-s1/evidence.md"
printf '## /security-review — SKIP (표면 없음)\n' > "$tmps/fid-s2/evidence.md"
ck "T17 security count (SKIP 2건)" "$(skip::count "$tmps" security)" "0 2 0"
ck "T18 security verdicts 구조형" "$(skip::verdicts "$tmps/fid-s1/evidence.md" security)" "SKIP"
ck "T19 security cite BARE(근거없음)" "$(skip::cite_status "$tmps/fid-s2/evidence.md" security)" "BARE"
outs=$(skip::report "$tmps" 2>/dev/null)
if grep -qE "security: total=2" <<<"$outs"; then echo "PASS T20 report 에 security 게이트"; PASS=$((PASS+1)); else echo "FAIL T20 ($outs)"; FAIL=$((FAIL+1)); fi
rm -rf "$tmps"

# T21 AC-5: 인자 없는 기본 root = 호출 위치 git 루트의 .specops (스크립트 옆 .specops 아님)
#   설치본은 스크립트 옆에 .specops 가 없어 하류에서 항상 "evidence 없음" 이었다 (current-state §4 #3)
tmpg=$(mktemp -d); git -C "$tmpg" init -q; mkdir -p "$tmpg/sub" "$tmpg/.specops/fid-g"
printf '## /integration-test — 2026-09-15\n**결과**: PASS\n' > "$tmpg/.specops/fid-g/evidence.md"
outg=$(cd "$tmpg/sub" && bash "$PLUGIN/scripts/skip-tracker.sh" 2>/dev/null)
if grep -qE "integration: total=1 PASS=1 SKIP=0 FAIL=0" <<<"$outg"; then echo "PASS T21 기본 root = git 루트 .specops"; PASS=$((PASS+1)); else echo "FAIL T21 ($outg)"; FAIL=$((FAIL+1)); fi
# T22 AC-R-1: 인자 없는 출력 == 같은 root 명시 인자 출력 (명시 인자 경로 불변)
outn=$(cd "$tmpg" && bash "$PLUGIN/scripts/skip-tracker.sh" 2>/dev/null)
oute=$(bash "$PLUGIN/scripts/skip-tracker.sh" "$tmpg/.specops" 2>/dev/null)
ck "T22 무인자 == 명시 인자" "$outn" "$oute"
rm -rf "$tmpg"

# T23 이 파일의 단언에 `printf … | grep -…q` 파이프가 없다 (20261015-test-pipefail-grep)
#   source 한 라이브러리가 `set -uo pipefail` 을 켠다 — 그 아래서 grep -q 가 먼저 끝나면 앞단 printf 의 쓰기 오류(SIGPIPE)가
#   파이프 실패가 되어 출력이 맞아도 단언이 간헐 실패한다(CI 실측 2건). 단언은 `grep -q 패턴 <<<"$출력"` 로 쓴다.
_np=$(grep -cE "printf '%s'[^|]*[|][[:space:]]*grep( -[A-Za-z-]+)* -[A-Za-z]*q" "${BASH_SOURCE[0]}")
if [ "$_np" = 0 ]; then echo "PASS T23 단언에 grep -q 파이프 없음 (pipefail 경합 방지)"; PASS=$((PASS+1)); else echo "FAIL T23 grep -q 파이프 ${_np}곳 — grep -q 패턴 <<<\"\$출력\" 로"; FAIL=$((FAIL+1)); fi

echo "==== Results: PASS=$PASS FAIL=$FAIL ===="
[ "$FAIL" -eq 0 ]
