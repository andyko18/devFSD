#!/usr/bin/env bash
# chain-stage eval — count_detected 판정 단위 테스트 (stub, 토큰 0)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "$0")/../../.." && pwd)
EVAL="$PLUGIN/scripts/tests/llm-eval"
RUNNER="$EVAL/run-chain-stage.sh"

# T1.a 탐지 — stub이 "AC-7" 출력 → recall=1/1
TD=$(mktemp -d); FX="$TD/decompose-covmiss"; mkdir -p "$FX"
printf '# plan\n1. T1 — 파서 (AC-1)\n2. T2 — 검증기 (AC-2)\n' > "$FX/plan.md"
printf '%s\n' '- AC-1 파서' '- AC-2 검증기' '- AC-7 미커버 항목' > "$FX/acceptance-criteria.md"
printf '%s\n' '{"id":"d1","locator":"AC-7","desc":"AC-7 미커버"}' > "$FX/defects.jsonl"
cat > "$TD/stub.sh" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "--version" ] && { echo "stub 0.0.1"; exit 0; }
jq -cn '{type:"assistant",message:{content:[{type:"text",text:"미커버: AC-7"}]}}'
jq -cn '{type:"result",subtype:"success",total_cost_usd:0}'
STUB
chmod +x "$TD/stub.sh"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q 'recall=1/1'; then PASS=$((PASS+1)); echo "PASS T1.a 탐지 recall=1/1"; else FAIL=$((FAIL+1)); echo "FAIL T1.a (rc=$rc out=$out)"; fi
rm -rf "$TD"

# T1.b 미탐지 — stub이 AC-7 미언급 → recall=0/1
TD=$(mktemp -d); FX="$TD/decompose-covmiss"; mkdir -p "$FX"
printf '# plan\n1. T1 (AC-1)\n' > "$FX/plan.md"
printf '%s\n' '- AC-1' '- AC-7 미커버' > "$FX/acceptance-criteria.md"
printf '%s\n' '{"id":"d1","locator":"AC-7","desc":"AC-7 미커버"}' > "$FX/defects.jsonl"
cat > "$TD/stub.sh" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "--version" ] && { echo "stub 0.0.1"; exit 0; }
jq -cn '{type:"assistant",message:{content:[{type:"text",text:"모든 AC 매핑됨"}]}}'
jq -cn '{type:"result",subtype:"success",total_cost_usd:0}'
STUB
chmod +x "$TD/stub.sh"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD" 2>&1); rc=$?
if echo "$out" | grep -q 'recall=0/1'; then PASS=$((PASS+1)); echo "PASS T1.b 미탐지 recall=0/1"; else FAIL=$((FAIL+1)); echo "FAIL T1.b (rc=$rc out=$out)"; fi
rm -rf "$TD"

# T1.c 이중가드 — locator가 plan.md 본문 등장 시 무효 (입력 누출 차단)
TD=$(mktemp -d); FX="$TD/decompose-covmiss"; mkdir -p "$FX"
printf '# plan\n1. T1 (AC-1)\n관련 AC: AC-7\n' > "$FX/plan.md"
printf '%s\n' '- AC-1' '- AC-7' > "$FX/acceptance-criteria.md"
printf '%s\n' '{"id":"d1","locator":"AC-7","desc":"본문 등장 — 무효"}' > "$FX/defects.jsonl"
cat > "$TD/stub.sh" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "--version" ] && { echo "stub 0.0.1"; exit 0; }
jq -cn '{type:"assistant",message:{content:[{type:"text",text:"미커버: AC-7"}]}}'
jq -cn '{type:"result",subtype:"success",total_cost_usd:0}'
STUB
chmod +x "$TD/stub.sh"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD" 2>&1); rc=$?
if echo "$out" | grep -q 'recall=0/1'; then PASS=$((PASS+1)); echo "PASS T1.c 이중가드 무효(본문 등장)"; else FAIL=$((FAIL+1)); echo "FAIL T1.c (rc=$rc out=$out)"; fi
rm -rf "$TD"

# T1.d claude 부재 SKIP + exit 0
out=$(CLAUDE_BIN=/nonexistent-claude bash "$RUNNER" "$EVAL/chain-stage-fixtures" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^SKIP'; then PASS=$((PASS+1)); echo "PASS T1.d CLI 부재 SKIP"; else FAIL=$((FAIL+1)); echo "FAIL T1.d (rc=$rc out=$out)"; fi

# T1.e fixture 무결성 — decompose-covmiss 3파일 + 미커버 AC가 plan.md 본문 미등장 + AC.md 등장
CFX="$EVAL/chain-stage-fixtures/decompose-covmiss"
loc=$(jq -r '.locator' "$CFX/defects.jsonl" 2>/dev/null | head -1)
if [ -f "$CFX/plan.md" ] && [ -f "$CFX/acceptance-criteria.md" ] && [ -f "$CFX/defects.jsonl" ] \
   && [ -n "$loc" ] \
   && ! grep -Fq "$loc" "$CFX/plan.md" \
   && grep -Fq "$loc" "$CFX/acceptance-criteria.md"; then
  PASS=$((PASS+1)); echo "PASS T1.e fixture 무결성 (loc=$loc plan미등장 AC.md등장)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.e (loc=$loc — plan.md 본문 등장 또는 파일 누락)"
fi

# T1.f 단어경계 — locator AC-7 이 출력의 AC-70 을 오매칭 안 함 (부분문자열 false-green 차단)
TD=$(mktemp -d); FX="$TD/decompose-covmiss"; mkdir -p "$FX"
printf '# plan\n1. T1 (AC-1)\n' > "$FX/plan.md"
printf '%s\n' '- AC-1' '- AC-7 미커버' > "$FX/acceptance-criteria.md"
printf '%s\n' '{"id":"d1","locator":"AC-7","desc":"AC-7 미커버"}' > "$FX/defects.jsonl"
cat > "$TD/stub.sh" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "--version" ] && { echo "stub 0.0.1"; exit 0; }
jq -cn '{type:"assistant",message:{content:[{type:"text",text:"미커버: AC-70 AC-71"}]}}'
jq -cn '{type:"result",subtype:"success",total_cost_usd:0}'
STUB
chmod +x "$TD/stub.sh"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD" 2>&1); rc=$?
if echo "$out" | grep -q 'recall=0/1'; then PASS=$((PASS+1)); echo "PASS T1.f 단어경계(AC-7≠AC-70)"; else FAIL=$((FAIL+1)); echo "FAIL T1.f (rc=$rc out=$out)"; fi
rm -rf "$TD"

echo "--- SUMMARY ---"; echo "PASS=$PASS FAIL=$FAIL"; exit $FAIL
