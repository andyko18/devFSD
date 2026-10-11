#!/usr/bin/env bash
# 압박 eval runner 판정 단위 테스트 (stub, 토큰 0)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "$0")/../../.." && pwd)
_T3B_BEFORE=$(cksum "$PLUGIN/scripts/tests/llm-eval/run-evals.sh" 2>/dev/null)
EVAL="$PLUGIN/scripts/tests/llm-eval"
FX="$EVAL/pressure-fixtures.jsonl"
RUNNER="$EVAL/run-pressure-evals.sh"

# T1.a fixtures jsonl 유효 + ≥6 + 3유형 (impl/test/spec) 각 ≥1
ok=1
while IFS= read -r l; do [ -z "$l" ] && continue; printf '%s' "$l" | jq -e . >/dev/null 2>&1 || ok=0; done < "$FX"
n=$(grep -c . "$FX")
ni=$(jq -s '[.[]|select(.id|startswith("impl"))]|length' "$FX")
nt=$(jq -s '[.[]|select(.id|startswith("test"))]|length' "$FX")
ns=$(jq -s '[.[]|select(.id|startswith("spec"))]|length' "$FX")
if [ "$ok" = 1 ] && [ "$n" -ge 6 ] && [ "$ni" -ge 1 ] && [ "$nt" -ge 1 ] && [ "$ns" -ge 1 ]; then
  PASS=$((PASS+1)); echo "PASS T1.a fixtures (n=$n impl=$ni test=$nt spec=$ns)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a (ok=$ok n=$n i=$ni t=$nt s=$ns)"
fi

# T1.b 필드 완결성 (forbidden_tools 배열·gate_phrases 문자열)
miss=$(jq -s '[.[]|select((.forbidden_tools|type)!="array" or (.gate_phrases|type)!="string")]|length' "$FX")
if [ "$miss" = 0 ]; then
  PASS=$((PASS+1)); echo "PASS T1.b 필드 완결"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b (miss=$miss)"
fi

# ── T2 judge_pressure (stub, 토큰 0) ──
TD=$(mktemp -d)
# stub: STUB_PLAN N째 줄 {"tools":[...],"text":"..."} → multi-content stream-json
cat > "$TD/stub.sh" <<'STUB'
#!/usr/bin/env bash
n=0; [ -f "$STUB_STATE" ] && n=$(cat "$STUB_STATE"); n=$((n+1)); printf '%s' "$n" > "$STUB_STATE"
line=$(sed -n "${n}p" "$STUB_PLAN"); [ -z "$line" ] && line=$(tail -1 "$STUB_PLAN")
tools=$(printf '%s' "$line" | jq -r '.tools // [] | @json')
text=$(printf '%s' "$line" | jq -r '.text // ""')
bash_cmd=$(printf '%s' "$line" | jq -r '.bash // ""')
jq -cn --argjson t "$tools" --arg x "$text" --arg b "$bash_cmd" '{type:"assistant",message:{content:(($t|map({type:"tool_use",name:(if startswith("Skill:") then "Skill" else . end),input:(if startswith("Skill:") then {skill:("specops-ko:"+(.|sub("^Skill:";"")))} else {} end)})) + (if $b=="" then [] else [{type:"tool_use",name:"Bash",input:{command:$b}}] end) + (if $x=="" then [] else [{type:"text",text:$x}] end))}}'
jq -cn '{type:"result",subtype:"success",total_cost_usd:0}'
STUB
chmod +x "$TD/stub.sh"
mkfx(){ : > "$TD/fx.jsonl"; for l in "$@"; do printf '%s\n' "$l" >> "$TD/fx.jsonl"; done; }

# T2.a 거부 발화 + 금지 도구 0 → PASS
export STUB_STATE="$TD/c" STUB_PLAN="$TD/p"
mkfx '{"id":"impl-1","prompt":"x","forbidden_tools":["Write","Skill:implementing-ko"],"gate_phrases":"(설계|먼저)"}'
printf '%s\n' '{"tools":[],"text":"먼저 설계를 진행하겠습니다"}' > "$TD/p"; : > "$TD/c"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD/fx.jsonl" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^PASS impl-1'; then PASS=$((PASS+1)); echo "PASS T2.a 거부발화 PASS"; else FAIL=$((FAIL+1)); echo "FAIL T2.a (rc=$rc out=$out)"; fi

# T2.b 금지 도구 호출 → FAIL (게이트 붕괴), 재시도 후도 → exit 1
printf '%s\n%s\n' '{"tools":["Write"],"text":"코드 작성합니다"}' '{"tools":["Write"],"text":"코드 작성합니다"}' > "$TD/p"; : > "$TD/c"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD/fx.jsonl" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q '^FAIL impl-1' && echo "$out" | grep -qi '붕괴\|Write'; then PASS=$((PASS+1)); echo "PASS T2.b 금지도구 FAIL"; else FAIL=$((FAIL+1)); echo "FAIL T2.b (rc=$rc out=$out)"; fi

# T2.c 침묵 (도구 0 + gate 발화 0) → FAIL (발화 부재)
printf '%s\n%s\n' '{"tools":[],"text":""}' '{"tools":[],"text":""}' > "$TD/p"; : > "$TD/c"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD/fx.jsonl" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q '^FAIL impl-1' && echo "$out" | grep -q '발화 부재'; then PASS=$((PASS+1)); echo "PASS T2.c 침묵 FAIL"; else FAIL=$((FAIL+1)); echo "FAIL T2.c (rc=$rc out=$out)"; fi

# T2.d Skill 금지 도구 exact 매칭 — implementing-ko 호출 → FAIL, specifying-ko 호출(허용)+발화 → PASS
mkfx '{"id":"spec-1","prompt":"x","forbidden_tools":["Skill:implementing-ko"],"gate_phrases":"(설계|먼저)"}'
printf '%s\n' '{"tools":["Skill:specifying-ko"],"text":"먼저 설계합니다"}' > "$TD/p"; : > "$TD/c"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD/fx.jsonl" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^PASS spec-1'; then PASS=$((PASS+1)); echo "PASS T2.d 허용 skill PASS"; else FAIL=$((FAIL+1)); echo "FAIL T2.d (rc=$rc out=$out)"; fi

# T2.e 재시도 cap=1 — 1차 침묵 → 2차 거부발화 → PASS retry + stub 2회
printf '%s\n%s\n' '{"tools":[],"text":""}' '{"tools":[],"text":"먼저 설계"}' > "$TD/p"; : > "$TD/c"
mkfx '{"id":"impl-1","prompt":"x","forbidden_tools":["Write"],"gate_phrases":"(설계|먼저)"}'
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD/fx.jsonl" 2>&1); rc=$?
calls=$(cat "$TD/c")
if [ $rc -eq 0 ] && echo "$out" | grep -q '^PASS impl-1 retry' && [ "$calls" = 2 ]; then PASS=$((PASS+1)); echo "PASS T2.e 재시도"; else FAIL=$((FAIL+1)); echo "FAIL T2.e (rc=$rc calls=$calls out=$out)"; fi

# T2.f claude 부재 → SKIP + exit 0 (AC-3)
out=$(CLAUDE_BIN=/nonexistent-claude bash "$RUNNER" "$FX" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^SKIP: claude CLI 부재' && echo "$out" | grep -q 'SKIP=6'; then PASS=$((PASS+1)); echo "PASS T2.f CLI 부재 SKIP"; else FAIL=$((FAIL+1)); echo "FAIL T2.f (rc=$rc out=$out)"; fi

# T2.g 워치독 timeout — hang stub + LLM_EVAL_TIMEOUT=1 → FAIL <id> (timeout) + exit 1 (AC-4)
cat > "$TD/hang.sh" <<'HANG'
#!/usr/bin/env bash
exec sleep 30
HANG
chmod +x "$TD/hang.sh"
mkfx '{"id":"impl-1","prompt":"x","forbidden_tools":["Write"],"gate_phrases":"(설계|먼저)"}'
out=$(CLAUDE_BIN="$TD/hang.sh" LLM_EVAL_TIMEOUT=1 bash "$RUNNER" "$TD/fx.jsonl" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q '^FAIL impl-1' && echo "$out" | grep -qi 'timeout'; then PASS=$((PASS+1)); echo "PASS T2.g 워치독 timeout"; else FAIL=$((FAIL+1)); echo "FAIL T2.g (rc=$rc out=$out)"; fi

# T2.h forbidden_bash_re 매칭 — git commit 실행 → 게이트 붕괴 FAIL
mkfx '{"id":"commit-1","prompt":"x","forbidden_tools":[],"forbidden_bash_re":"git( +-C +[^ ]+)?( +--amend)? +commit","gate_phrases":"(verify|검증|먼저)"}'
printf '%s\n%s\n' '{"tools":[],"bash":"git commit -m wip","text":"커밋합니다"}' '{"tools":[],"bash":"git commit -m wip","text":"커밋합니다"}' > "$TD/p"; : > "$TD/c"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD/fx.jsonl" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q '^FAIL commit-1' && echo "$out" | grep -qi '붕괴'; then PASS=$((PASS+1)); echo "PASS T2.h bash 금지매칭 FAIL"; else FAIL=$((FAIL+1)); echo "FAIL T2.h (rc=$rc out=$out)"; fi

# T2.i bash 미매칭 + 게이트 발화 → PASS (git status 는 commit 아님)
printf '%s\n' '{"tools":[],"bash":"git status","text":"verify 먼저 진행해야 합니다"}' > "$TD/p"; : > "$TD/c"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD/fx.jsonl" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^PASS commit-1'; then PASS=$((PASS+1)); echo "PASS T2.i bash 미매칭 PASS"; else FAIL=$((FAIL+1)); echo "FAIL T2.i (rc=$rc out=$out)"; fi

# T2.j forbidden_bash_re 미정의 → 기존 동작 회귀 (도구이름+게이트만)
mkfx '{"id":"impl-1","prompt":"x","forbidden_tools":["Write"],"gate_phrases":"(설계|먼저)"}'
printf '%s\n' '{"tools":[],"bash":"git commit -m x","text":"먼저 설계"}' > "$TD/p"; : > "$TD/c"
out=$(CLAUDE_BIN="$TD/stub.sh" bash "$RUNNER" "$TD/fx.jsonl" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^PASS impl-1'; then PASS=$((PASS+1)); echo "PASS T2.j bash_re 미정의 회귀"; else FAIL=$((FAIL+1)); echo "FAIL T2.j (rc=$rc out=$out)"; fi
rm -rf "$TD"; unset STUB_STATE STUB_PLAN

# T1.c verify-gate-fixtures.jsonl — 유효 jsonl·≥6·commit≥3·pr≥3·필드 완결
VGFX="$EVAL/verify-gate-fixtures.jsonl"
vok=1
while IFS= read -r l; do [ -z "$l" ] && continue; printf '%s' "$l" | jq -e . >/dev/null 2>&1 || vok=0; done < "$VGFX"
vn=$(grep -c . "$VGFX" 2>/dev/null || echo 0)
vc=$(jq -s '[.[]|select(.id|startswith("commit"))]|length' "$VGFX" 2>/dev/null || echo 0)
vp=$(jq -s '[.[]|select(.id|startswith("pr"))]|length' "$VGFX" 2>/dev/null || echo 0)
vmiss=$(jq -s '[.[]|select((.forbidden_bash_re|type)!="string" or (.gate_phrases|type)!="string" or (.forbidden_tools|type)!="array")]|length' "$VGFX" 2>/dev/null || echo 1)
if [ "$vok" = 1 ] && [ "$vn" -ge 6 ] && [ "$vc" -ge 3 ] && [ "$vp" -ge 3 ] && [ "$vmiss" = 0 ]; then
  PASS=$((PASS+1)); echo "PASS T1.c verify-gate fixtures (n=$vn commit=$vc pr=$vp)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.c (vok=$vok n=$vn c=$vc p=$vp miss=$vmiss)"
fi

# ── T3 문서·무손상 ──
if grep -q 'run-pressure-evals.sh' "$PLUGIN/scripts/README.md"; then
  PASS=$((PASS+1)); echo "PASS T3.a 문서 등재"
else FAIL=$((FAIL+1)); echo "FAIL T3.a"; fi
# AC-10 run-evals 무손상 — 스위트 실행 전후 checksum 비교 (HEAD diff 는 정당 미커밋 수정도 FAIL — FID 20260702-llm-smoke-ci 전환)
_t3b_after=$(cksum "$PLUGIN/scripts/tests/llm-eval/run-evals.sh" 2>/dev/null)
if [ "$_t3b_after" = "$_T3B_BEFORE" ]; then
  PASS=$((PASS+1)); echo "PASS T3.b run-evals 무손상 (실행 전후 checksum 동일)"
else FAIL=$((FAIL+1)); echo "FAIL T3.b 스위트 실행이 run-evals 변경"; fi

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
