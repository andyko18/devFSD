#!/usr/bin/env bash
# plan A/B 측정 하니스 — 집계 로직 stub 단위 테스트 (토큰 0)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "$0")/../../.." && pwd)
_T3B_BEFORE=$(cksum "$PLUGIN/scripts/tests/llm-eval/run-evals.sh" "$PLUGIN/scripts/tests/llm-eval/run-pressure-evals.sh" 2>/dev/null)
EVAL="$PLUGIN/scripts/tests/llm-eval"
FXDIR="$EVAL/plan-ab-fixtures"
RUNNER="$EVAL/run-plan-ab.sh"

# T1.a fixture 2개 구조 + defects jsonl 유효 + 3유형 분포
ok=1; tot_def=0; types=""
for d in cov-miss placeholder; do
  [ -f "$FXDIR/$d/plan.md" ] && [ -f "$FXDIR/$d/defects.jsonl" ] || ok=0
  if [ -f "$FXDIR/$d/defects.jsonl" ]; then
    while IFS= read -r l; do [ -z "$l" ] && continue; printf '%s' "$l" | jq -e . >/dev/null 2>&1 || ok=0; tot_def=$((tot_def+1)); types="$types $(printf '%s' "$l"|jq -r '.type')"; done < "$FXDIR/$d/defects.jsonl"
  fi
done
nt=$(printf '%s' "$types" | tr ' ' '\n' | grep -c . )
ut=$(printf '%s' "$types" | tr ' ' '\n' | sort -u | grep -c .)
if [ "$ok" = 1 ] && [ "$tot_def" -ge 4 ] && [ "$ut" -ge 3 ]; then
  PASS=$((PASS+1)); echo "PASS T1.a fixtures (defects=$tot_def types=$ut)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a (ok=$ok def=$tot_def ut=$ut)"
fi

# ── T2 집계 (stub, 토큰 0) ──
TD=$(mktemp -d)
# stub: STUB_PLAN N째 줄 {"detected":[...],"cost":N} → 검출 키워드 텍스트 + cost
cat > "$TD/stub.sh" <<'STUB'
#!/usr/bin/env bash
n=0; [ -f "$STUB_STATE" ] && n=$(cat "$STUB_STATE"); n=$((n+1)); printf '%s' "$n" > "$STUB_STATE"
line=$(sed -n "${n}p" "$STUB_PLAN"); [ -z "$line" ] && line=$(tail -1 "$STUB_PLAN")
det=$(printf '%s' "$line" | jq -r '.detected // [] | join(" / ")')
cost=$(printf '%s' "$line" | jq -r '.cost // 0')
jq -cn --arg d "$det" '{type:"assistant",message:{content:[{type:"text",text:("검출 결함: "+$d)}]}}'
jq -cn --argjson c "$cost" '{type:"result",subtype:"success",total_cost_usd:$c}'
STUB
chmod +x "$TD/stub.sh"
# 미니 fixture (defect 2개)
mkdir -p "$TD/fx/m1"
printf '# plan\n' > "$TD/fx/m1/plan.md"
printf '%s\n%s\n' '{"id":"d1","type":"coverage","locator":"AC-3 미매핑","desc":"x"}' '{"id":"d2","type":"type","locator":"명명 불일치","desc":"y"}' > "$TD/fx/m1/defects.jsonl"
export STUB_STATE="$TD/c" STUB_PLAN="$TD/p"

# T2.a A 1개 검출 + B 2개 검출 → recall A=1/2 B=2/2 (방식 A=1회, B=2회 호출)
# STUB_PLAN: 1=A출력, 2·3=B출력(2회) — A 1개, B 합쳐 2개
printf '%s\n%s\n%s\n' '{"detected":["AC-3 미매핑"],"cost":0.1}' '{"detected":["AC-3 미매핑"],"cost":0.2}' '{"detected":["명명 불일치"],"cost":0.2}' > "$TD/p"; : > "$TD/c"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD/fx" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -qE '방식 A: recall=1/2' && echo "$out" | grep -qE '방식 B: recall=2/2'; then
  PASS=$((PASS+1)); echo "PASS T2.a recall 집계"
else FAIL=$((FAIL+1)); echo "FAIL T2.a (rc=$rc out=$out)"; fi

# T2.b 토큰 합산 — A=0.1, B=0.2+0.2=0.4 (AC-3)
if echo "$out" | grep -qE '방식 A:.*\$0\.10' && echo "$out" | grep -qE '방식 B:.*\$0\.40'; then
  PASS=$((PASS+1)); echo "PASS T2.b 토큰 합산"
else FAIL=$((FAIL+1)); echo "FAIL T2.b (out=$out)"; fi

# T2.c 비교 결론 라인 (AC-5)
if echo "$out" | grep -qE '검출차|비용배수|B-A'; then
  PASS=$((PASS+1)); echo "PASS T2.c 비교 결론"
else FAIL=$((FAIL+1)); echo "FAIL T2.c (out=$out)"; fi

# T2.d claude 부재 → SKIP + exit 0 (AC-4)
out=$(CLAUDE_BIN=/nonexistent bash "$RUNNER" "$FXDIR" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^SKIP: claude CLI 부재'; then
  PASS=$((PASS+1)); echo "PASS T2.d SKIP"
else FAIL=$((FAIL+1)); echo "FAIL T2.d (rc=$rc out=$out)"; fi

# T2.e 입력 누출 방지 — defect locator 가 plan 본문에 있어도 방식 출력에만 매칭 (count_detected $1=출력)
# 본문에 "명명 불일치" 넣되 stub 출력엔 없음 → 미검출이어야 (입력 누출 시 오검출)
printf '# plan 명명 불일치 본문등장\n' > "$TD/fx/m1/plan.md"
printf '%s\n%s\n%s\n' '{"detected":["AC-3 미매핑"],"cost":0.1}' '{"detected":["AC-3 미매핑"],"cost":0.1}' '{"detected":["AC-3 미매핑"],"cost":0.1}' > "$TD/p"; : > "$TD/c"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD/fx" 2>&1)
if echo "$out" | grep -qE '방식 A: recall=1/2'; then
  PASS=$((PASS+1)); echo "PASS T2.e 입력 누출 방지 (본문 키워드 미검출)"
else FAIL=$((FAIL+1)); echo "FAIL T2.e (out=$out)"; fi

# T2.f count_detected 본문 가드 — locator 가 plan 본문에도 등장하면 stub 가 인용해도 검출 무효 (측정 무결성)
# m1 defects: d1="AC-3 미매핑"(본문 비등장) d2="명명 불일치"(본문 등장). stub 둘 다 인용해도 d2 무효 → recall=1/2
printf '# plan 명명 불일치 본문등장\n' > "$TD/fx/m1/plan.md"
printf '%s\n%s\n%s\n' '{"detected":["AC-3 미매핑 / 명명 불일치"],"cost":0.1}' '{"detected":["AC-3 미매핑 / 명명 불일치"],"cost":0.1}' '{"detected":["AC-3 미매핑 / 명명 불일치"],"cost":0.1}' > "$TD/p"; : > "$TD/c"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD/fx" 2>&1)
if echo "$out" | grep -qE '방식 A: recall=1/2'; then
  PASS=$((PASS+1)); echo "PASS T2.f 본문 가드 (인용해도 본문등장 locator 무효)"
else FAIL=$((FAIL+1)); echo "FAIL T2.f (out=$out)"; fi
rm -rf "$TD"; unset STUB_STATE STUB_PLAN

# ── T3 문서·무손상 ──
if grep -q 'run-plan-ab.sh' "$PLUGIN/scripts/README.md"; then
  PASS=$((PASS+1)); echo "PASS T3.a 문서 등재"
else FAIL=$((FAIL+1)); echo "FAIL T3.a"; fi
# T3.b 기존 eval 무손상 — 스위트 실행 전후 checksum 비교 (HEAD 대비 diff 는 정당한 미커밋 수정도 FAIL 시키는 자기참조 결함 — FID 20260702-llm-smoke-ci 에서 전환)
_t3b_after=$(cksum "$PLUGIN/scripts/tests/llm-eval/run-evals.sh" "$PLUGIN/scripts/tests/llm-eval/run-pressure-evals.sh" 2>/dev/null)
if [ "$_t3b_after" = "$_T3B_BEFORE" ]; then
  PASS=$((PASS+1)); echo "PASS T3.b 기존 eval 무손상 (실행 전후 checksum 동일)"
else FAIL=$((FAIL+1)); echo "FAIL T3.b 스위트 실행이 eval 파일 변경"; fi

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
