#!/usr/bin/env bash
# eval-lib.sh assertion 어휘·매트릭스 stub 단위 (토큰 0)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
# shellcheck disable=SC1091
source "$PLUGIN/scripts/tests/llm-eval/eval-lib.sh"
ck() { if [ "$2" = "$3" ]; then echo "PASS $1"; PASS=$((PASS+1)); else echo "FAIL $1 — exp '$3' got '$2'"; FAIL=$((FAIL+1)); fi; }

ck "T1 contains 포함→PASS" "$(eval::assert_contains 'hello world' 'world')" "PASS"
ck "T2 contains 부재→FAIL" "$(eval::assert_contains 'hello world' 'xyz')" "FAIL"
ck "T3 regex 매칭→PASS" "$(eval::assert_regex 'cost=0.42' '[0-9]+\.[0-9]+')" "PASS"
ck "T4 regex 미매칭→FAIL" "$(eval::assert_regex 'abc' '[0-9]+')" "FAIL"
ck "T5 cost_lt 미만→PASS" "$(eval::assert_cost_lt 0.3 0.5)" "PASS"
ck "T6 cost_lt 이상→FAIL" "$(eval::assert_cost_lt 0.7 0.5)" "FAIL"
ck "T7 rubric pass→PASS" "$(eval::assert_llm_rubric 'output rubric-pass yes' 'rubric' stub)" "PASS"
ck "T8 rubric fail→FAIL" "$(eval::assert_llm_rubric 'output no marker' 'rubric' stub)" "FAIL"
ck "T9 assert 디스패처 contains" "$(eval::assert contains 'foo bar' 'bar')" "PASS"
ck "T10 assert 미지 type→FAIL" "$(eval::assert unknown 'x' 'y')" "FAIL"

sj='{"type":"assistant","message":{"content":[{"type":"text","text":"안녕"}]}}
{"type":"result","total_cost_usd":0.12}'
ck "T11 extract_text" "$(printf '%s' "$sj" | eval::extract_text)" "안녕"
ck "T12 extract_cost" "$(printf '%s' "$sj" | eval::extract_cost)" "0.12"

tmp=$(mktemp -d)
cat > "$tmp/fx.jsonl" <<'EOS'
{"prompt":"p1","asserts":[{"type":"contains","value":"안녕"}]}
{"prompt":"p2","asserts":[{"type":"contains","value":"없음"}]}
EOS
out=$(EVAL_STUB_TEXT="안녕" eval::run_matrix "$tmp/fx.jsonl" stub-eval 2>/dev/null)
if printf '%s' "$out" | grep -qE "matrix: 2 rows 1 pass 1 fail"; then echo "PASS T13 run_matrix 집계"; PASS=$((PASS+1)); else echo "FAIL T13 ($out)"; FAIL=$((FAIL+1)); fi
rm -rf "$tmp"

# T14 빈 needle vacuous pass 차단 (Phase C Important)
ck "T14 contains 빈 needle→FAIL" "$(eval::assert_contains 'anything' '')" "FAIL"
# T15 비숫자 cost 조용한 0 강제 차단
ck "T15 cost_lt 비숫자→FAIL" "$(eval::assert_cost_lt abc 0.5)" "FAIL"

echo "==== Results: PASS=$PASS FAIL=$FAIL ===="
[ "$FAIL" -eq 0 ]
