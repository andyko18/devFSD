#!/usr/bin/env bash
# test-verdict-board — AC-1~5 검증 (매트릭스·기호·재활용·읽기전용)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
VB="$PLUGIN/scripts/verdict-board.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT

mkdir -p "$TD/20260615-alpha" "$TD/20260101-beta" "$TD/memory"
cat > "$TD/20260615-alpha/evidence.md" <<'EOF'
## /verify — 2026-06-15T10:00:00Z
**결과**: PASS — AC 충족
## /integration-test — 2026-06-15T10:01:00Z
**결과**: SKIP
## /performance-test — 2026-06-15T10:02:00Z
**결과**: FAIL — 임계값 초과
EOF
# 20260101-beta: evidence.md 없음 (미실행)

out=$(bash "$VB" "$TD")

# T1.a AC-1/2: alpha verify=✅ integ=⏭ perf=❌
if echo "$out" | grep "20260615-alpha" | grep -q "✅" \
   && echo "$out" | grep "20260615-alpha" | grep -q "⏭" \
   && echo "$out" | grep "20260615-alpha" | grep -q "❌"; then
  PASS=$((PASS+1)); echo "PASS T1.a AC-1/2 alpha 매트릭스(✅⏭❌)"
else FAIL=$((FAIL+1)); echo "FAIL T1.a ($(echo "$out" | grep alpha))"; fi

# T1.b AC-2: beta(evidence 없음) → 미실행(verdict 기호 없음) — I-1 반영
if echo "$out" | grep -q "20260101-beta" && ! echo "$out" | grep "20260101-beta" | grep -qE "✅|⏭|❌"; then
  PASS=$((PASS+1)); echo "PASS T1.b AC-2 beta 미실행(verdict 없음)"
else FAIL=$((FAIL+1)); echo "FAIL T1.b ($(echo "$out" | grep beta))"; fi

# T1.c AC-4: 날짜순 최신 위 (alpha 20260615 > beta 20260101)
alpha_ln=$(echo "$out" | grep -n "20260615-alpha" | cut -d: -f1)
beta_ln=$(echo "$out" | grep -n "20260101-beta" | cut -d: -f1)
if [ -n "$alpha_ln" ] && [ -n "$beta_ln" ] && [ "$alpha_ln" -lt "$beta_ln" ]; then
  PASS=$((PASS+1)); echo "PASS T1.c AC-4 날짜순 최신 위"
else FAIL=$((FAIL+1)); echo "FAIL T1.c (alpha=$alpha_ln beta=$beta_ln)"; fi

# T1.d AC-4: memory 디렉토리(FID 형식 아님) skip
if ! echo "$out" | grep -q "^memory"; then
  PASS=$((PASS+1)); echo "PASS T1.d AC-4 비-FID 디렉토리 skip"
else FAIL=$((FAIL+1)); echo "FAIL T1.d memory 포함됨"; fi

# T1.e AC-5/AC-R-1: 읽기전용 + exit 0 (skip-tracker md5 불변)
m1=$(md5 -q "$PLUGIN/scripts/skip-tracker.sh"); bash "$VB" "$TD" >/dev/null; rc=$?; m2=$(md5 -q "$PLUGIN/scripts/skip-tracker.sh")
if [ $rc -eq 0 ] && [ "$m1" = "$m2" ]; then
  PASS=$((PASS+1)); echo "PASS T1.e AC-5/R-1 읽기전용 exit 0(skip-tracker 무손상)"
else FAIL=$((FAIL+1)); echo "FAIL T1.e (rc=$rc md5 $m1/$m2)"; fi

# T1.f AC-5: 빈 .specops graceful
empty=$(mktemp -d)
out2=$(bash "$VB" "$empty"); rc=$?
if [ $rc -eq 0 ] && echo "$out2" | grep -q "FID"; then
  PASS=$((PASS+1)); echo "PASS T1.f AC-5 빈 디렉토리 graceful(헤더만)"
else FAIL=$((FAIL+1)); echo "FAIL T1.f (rc=$rc)"; fi
rm -rf "$empty"

# T2: 구조화 상태 SoT 우선 + 계산형 STALE/PARTIAL/WAIVED 표시
PROJ=$(mktemp -d)
git -C "$PROJ" init -q
printf 'base\n' > "$PROJ/app.sh"
git -C "$PROJ" add app.sh
git -C "$PROJ" -c user.name=test -c user.email=test@example.com commit -qm init
mkdir -p "$PROJ/.specops/20260803-structured"
(cd "$PROJ" && bash "$PLUGIN/scripts/_internal/verification-state.sh" record 20260803-structured PASS)
out3=$(cd "$PROJ" && bash "$VB" "$PROJ/.specops")
if printf '%s' "$out3" | grep "20260803-structured" | grep -q "✅"; then
  PASS=$((PASS+1)); echo "PASS T2.a 구조화 PASS 표시"
else FAIL=$((FAIL+1)); echo "FAIL T2.a ($out3)"; fi

printf 'changed\n' >> "$PROJ/app.sh"
out3=$(cd "$PROJ" && bash "$VB" "$PROJ/.specops")
if printf '%s' "$out3" | grep "20260803-structured" | grep -q "⚠"; then
  PASS=$((PASS+1)); echo "PASS T2.b 코드 변경 → STALE 표시"
else FAIL=$((FAIL+1)); echo "FAIL T2.b ($out3)"; fi
git -C "$PROJ" restore app.sh

(cd "$PROJ" && bash "$PLUGIN/scripts/_internal/verification-state.sh" record 20260803-structured PARTIAL)
out3=$(cd "$PROJ" && bash "$VB" "$PROJ/.specops")
if printf '%s' "$out3" | grep "20260803-structured" | grep -q "🟡"; then
  PASS=$((PASS+1)); echo "PASS T2.c PARTIAL 표시"
else FAIL=$((FAIL+1)); echo "FAIL T2.c ($out3)"; fi

# ★ 만료일은 **상대 날짜**로 만든다. 미래 날짜를 하드코딩하면 그 시각이 지나는 순간
#   WAIVED 가 NOT_RUN 으로 계산돼 스위트가 스스로 터진다 — 2026-08-10 실발화:
#   "2026-08-10T00:00:00Z" 가 자정에 만료돼 본 스위트와 test-verdict-board 가 동시에 FAIL 했다.
#   (프로덕션은 정상 — verification-state.sh 가 조회 시점에 만료를 계산하는 게 설계다.)
_future=$(date -u -v+1d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+1 day" +%Y-%m-%dT%H:%M:%SZ)
(cd "$PROJ" && bash "$PLUGIN/scripts/_internal/verification-state.sh" record 20260803-structured WAIVED \
  --waiver-reason "승인된 예외" --waiver-approved-by "owner@example.com" \
  --waiver-expires-at "$_future")
out3=$(cd "$PROJ" && bash "$VB" "$PROJ/.specops")
if printf '%s' "$out3" | grep "20260803-structured" | grep -q "◻"; then
  PASS=$((PASS+1)); echo "PASS T2.d WAIVED 표시"
else FAIL=$((FAIL+1)); echo "FAIL T2.d ($out3)"; fi
rm -rf "$PROJ"

# T3 AC-6: sec 열 · 헤더 없음 '·' · 판정 불가 '?' · evidence 없음은 전 칸 '-'
mkdir -p "$TD/20260915-bsec" "$TD/20260915-csec"
printf '## /verify — d\n**결과**: PASS\n## /integration-test — d\n**결과**: PASS\n## /performance-test — d\n**결과**: PASS\n' > "$TD/20260915-bsec/evidence.md"
printf '## /security-review — d\n본문만\n## /integration-test — d\n**결과**: PASS\n' > "$TD/20260915-csec/evidence.md"
out4=$(bash "$VB" "$TD")
if printf '%s\n' "$out4" | head -1 | grep -qw "sec"; then PASS=$((PASS+1)); echo "PASS T3.a sec 열 헤더"; else FAIL=$((FAIL+1)); echo "FAIL T3.a ($(printf '%s\n' "$out4" | head -1))"; fi
if printf '%s\n' "$out4" | grep "20260915-bsec" | grep -q "·"; then PASS=$((PASS+1)); echo "PASS T3.b 헤더 없음 ·"; else FAIL=$((FAIL+1)); echo "FAIL T3.b ($(printf '%s\n' "$out4" | grep bsec))"; fi
if printf '%s\n' "$out4" | grep "20260915-csec" | grep -q "?"; then PASS=$((PASS+1)); echo "PASS T3.c 판정 불가 ?"; else FAIL=$((FAIL+1)); echo "FAIL T3.c ($(printf '%s\n' "$out4" | grep csec))"; fi
if ! printf '%s\n' "$out4" | grep "20260101-beta" | grep -qE "·|\?"; then PASS=$((PASS+1)); echo "PASS T3.d evidence 없음 전 칸 -"; else FAIL=$((FAIL+1)); echo "FAIL T3.d ($(printf '%s\n' "$out4" | grep beta))"; fi
# T3.e FR-8: 인자 없는 기본 root = 호출 위치 git 루트 .specops
PG="$TD/pg"; mkdir -p "$PG"; git -C "$PG" init -q; mkdir -p "$PG/sub" "$PG/.specops/20260915-gitroot"
printf '## /verify — d\n**결과**: PASS\n' > "$PG/.specops/20260915-gitroot/evidence.md"
if (cd "$PG/sub" && bash "$VB") | grep -q "20260915-gitroot"; then PASS=$((PASS+1)); echo "PASS T3.e 기본 root git 루트"; else FAIL=$((FAIL+1)); echo "FAIL T3.e"; fi
rm -rf "$PG"

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
