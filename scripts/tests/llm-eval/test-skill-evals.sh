#!/usr/bin/env bash
# skill 별 활성화·행동 eval — 데이터 스키마·pilot 6개 커버리지·파서·stub·러너 판정 (stub 전용, 토큰 0)
# 20260929-skill-behavior-eval AC-1~AC-7
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
LE="$PLUGIN/scripts/tests/llm-eval"
# shellcheck disable=SC1091
source "$LE/eval-lib.sh"
# shellcheck disable=SC1091
source "$LE/skill-evals-lib.sh"
ok()   { echo "PASS $1"; PASS=$((PASS+1)); }
nope() { echo "FAIL $1 — $2"; FAIL=$((FAIL+1)); }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── 픽스처: 가짜 skills 루트 + 유효 데이터 쌍 ──
ROOT="$TMP/skills-root"; mkdir -p "$ROOT/fake-a"; : > "$ROOT/fake-a/SKILL.md"
_valid_trigger() {  # <skill>
  jq -n --arg s "$1" '{skill:$s,
    should_trigger:[{id:"pos-1",query:"기능 만들어줘"}],
    should_not_trigger:[{id:"neg-1",query:"2+2 는?"}]}'
}
_valid_evals() {  # <skill>
  jq -n --arg s "$1" '{skill:$s,
    cases:[{id:"e-1",prompt:"기능 만들어줘",asserts:[{type:"regex",value:"설계"},{type:"cost_lt",value:"2.0"}]}]}'
}
_mk() {  # <dir> <trigger json> <evals json> → 데이터 디렉터리 생성
  mkdir -p "$1"; printf '%s\n' "$2" > "$1/trigger-queries.json"; printf '%s\n' "$3" > "$1/evals.json"
}
_expect_fail() {  # <id> <kind> <file> <사유 부분문자열>
  local out rc
  out=$(skill_evals::check "$2" "$3" "$ROOT"); rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qF -- "$4"; then ok "$1"; else nope "$1" "rc=$rc out='$out' (기대 사유 '$4')"; fi
}
# T1 (AC-1) 스키마 계약
V="$TMP/v/fake-a"; _mk "$V" "$(_valid_trigger fake-a)" "$(_valid_evals fake-a)"
if skill_evals::check trigger "$V/trigger-queries.json" "$ROOT" >/dev/null \
   && skill_evals::check evals "$V/evals.json" "$ROOT" >/dev/null; then ok "T1.a 유효 쌍 통과"; else nope "T1.a" "유효 쌍이 거부됨"; fi

D="$TMP/m1/fake-a"; _mk "$D" "$(_valid_trigger fake-a | jq '.should_not_trigger=[]')" "$(_valid_evals fake-a)"
_expect_fail "T1.b ① 빈 should_not_trigger" trigger "$D/trigger-queries.json" "should_not_trigger 비어 있음"
D="$TMP/m2/fake-a"; _mk "$D" "$(_valid_trigger fake-a | jq 'del(.skill)')" "$(_valid_evals fake-a)"
_expect_fail "T1.c ② skill 필드 누락" trigger "$D/trigger-queries.json" "skill 필드 누락"
D="$TMP/m3/fake-a"; _mk "$D" "$(_valid_trigger fake-a | jq '.should_not_trigger[0].id="pos-1"')" "$(_valid_evals fake-a)"
_expect_fail "T1.d ③ id 중복" trigger "$D/trigger-queries.json" "id 중복: pos-1"
D="$TMP/m4/fake-a"; _mk "$D" "$(_valid_trigger fake-a)" "$(_valid_evals fake-a | jq '.cases[0].asserts[0].type="equals"')"
_expect_fail "T1.e ④ 어휘 밖 assert type" evals "$D/evals.json" "미지 assert type: equals"
D="$TMP/m5/fake-a"; _mk "$D" "$(_valid_trigger fake-a)" "$(_valid_evals fake-a | jq '.cases[0].asserts[0].value=""')"
_expect_fail "T1.f ⑤ 빈 assert value" evals "$D/evals.json" "빈 assert value"
D="$TMP/m6/fake-a"; _mk "$D" "$(_valid_trigger fake-b)" "$(_valid_evals fake-a)"
_expect_fail "T1.g ⑥ skill 필드≠디렉터리" trigger "$D/trigger-queries.json" "skill 필드(fake-b) ≠ 디렉터리(fake-a)"
D="$TMP/m7/ghost-x"; _mk "$D" "$(_valid_trigger ghost-x)" "$(_valid_evals ghost-x)"
_expect_fail "T1.h ⑦ 실존하지 않는 skill" trigger "$D/trigger-queries.json" "실존하지 않는 skill: ghost-x"
D="$TMP/m8/fake-a"; mkdir -p "$D"; printf '{"skill": "fake-a",\n' > "$D/evals.json"
_expect_fail "T1.i ⑧ JSON 파싱 불가" evals "$D/evals.json" "JSON 파싱 불가"
D="$TMP/m9/fake-a"; _mk "$D" "$(_valid_trigger fake-a)" "$(_valid_evals fake-a | jq '.cases[0].agent="../x"')"
_expect_fail "T10.s1 agent 경로 순회 거절" evals "$D/evals.json" "agent 형식 오류: ../x"
D="$TMP/m10/fake-a"; _mk "$D" "$(_valid_trigger fake-a)" "$(_valid_evals fake-a | jq '.cases[0].agent=""')"
_expect_fail "T10.s2 agent 빈 문자열 거절" evals "$D/evals.json" "agent 형식 오류: "
D="$TMP/m11/fake-a"; _mk "$D" "$(_valid_trigger fake-a)" "$(_valid_evals fake-a | jq '.cases[0].agent="Bad_Name"')"
_expect_fail "T10.s3 agent 대문자·밑줄 거절" evals "$D/evals.json" "agent 형식 오류: Bad_Name"
D="$TMP/m12/fake-a"; _mk "$D" "$(_valid_trigger fake-a)" "$(_valid_evals fake-a | jq '.cases[0].agent="fake-agent-2"')"
if skill_evals::check evals "$D/evals.json" "$ROOT" >/dev/null; then ok "T10.s4 유효 agent 통과"; else nope "T10.s4" "유효 agent 가 거부됨"; fi
D="$TMP/m13/fake-a"; _mk "$D" "$(_valid_trigger fake-a)" "$(_valid_evals fake-a | jq '.cases[0].agent="ok\n"')"
_expect_fail "T10.s5 agent 끝 개행 거절(jq 의 ^…$ 는 끝 개행을 허용하므로 \A…\z)" evals "$D/evals.json" "agent 형식 오류: ok"
# T3 (AC-3) 스트림 전체 Skill 호출 파서
s0='{"type":"assistant","message":{"content":[{"type":"text","text":"안녕"}]}}'
s1='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"specifying-ko"}}]}}'
s2='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"advisor-ko"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"이어서"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"specops-ko:karpathy-ko"}}]}}'
[ -z "$(printf '%s\n' "$s0" | eval::all_skills)" ] && ok "T3.a 호출 0건 → 빈 출력" || nope "T3.a" "빈 출력 아님"
[ "$(printf '%s\n' "$s1" | eval::all_skills)" = "specifying-ko" ] && ok "T3.b 1건" || nope "T3.b" "1건 파싱 실패"
got=$(printf '%s\n' "$s2" | eval::all_skills | paste -sd, -)
[ "$got" = "advisor-ko,specops-ko:karpathy-ko" ] && ok "T3.c 2건 순서 유지" || nope "T3.c" "got='$got'"

# T4 (AC-4) stub 다중 호출 + 하위호환
_stub() {  # <plan 행> → stub stdout
  printf '%s\n' "$1" > "$TMP/plan4.jsonl"; rm -f "$TMP/state4"
  STUB_PLAN="$TMP/plan4.jsonl" STUB_STATE="$TMP/state4" bash "$LE/stub-claude.sh" -p x
}
o=$(_stub '{"skills":["advisor-ko","karpathy-ko"]}')
[ "$(printf '%s\n' "$o" | eval::all_skills | paste -sd, -)" = "advisor-ko,karpathy-ko" ] \
  && [ "$(printf '%s\n' "$o" | tail -1 | jq -r .type)" = "result" ] && ok "T4.a skills 배열 → 2건 순서 + result" || nope "T4.a" "$o"
o=$(_stub '{"skill":"specifying-ko","args":"x"}')
[ "$(printf '%s\n' "$o" | jq -r 'select(.type=="assistant")|.message.content[0].input|"\(.skill)|\(.args)"')" = "specifying-ko|x" ] \
  && [ "$(printf '%s\n' "$o" | grep -c .)" -eq 2 ] && ok "T4.b 기존 skill 형식 무변경" || nope "T4.b" "$o"
o=$(_stub '{"text":"안녕"}')
[ "$(printf '%s\n' "$o" | eval::extract_text)" = "안녕" ] && [ "$(printf '%s\n' "$o" | grep -c .)" -eq 2 ] \
  && ok "T4.c 기존 text 형식 무변경" || nope "T4.c" "$o"
# T2 (AC-2) pilot 6개 커버리지 — 실 트리 읽기 전용 (20260930-skill-eval-expand: 3 → 6)
for s in specifying-ko karpathy-ko advisor-ko systematic-debugging-ko tdd-ko analyzing-ko implementing-ko; do
  d="$LE/skills/$s"
  if skill_evals::check trigger "$d/trigger-queries.json" "$PLUGIN/skills" >/dev/null \
     && skill_evals::check evals "$d/evals.json" "$PLUGIN/skills" >/dev/null \
     && [ "$(jq '.should_trigger|length' "$d/trigger-queries.json")" -ge 3 ] \
     && [ "$(jq '.should_not_trigger|length' "$d/trigger-queries.json")" -ge 3 ] \
     && [ "$(jq '.cases|length' "$d/evals.json")" -ge 3 ]; then
    ok "T2.$s pilot 두 파일 · 양성≥3 · 음성≥3 · case≥3"
  else nope "T2.$s" "pilot 데이터 누락·스키마 위반·개수 부족 ($d)"; fi
done
bad=""; n=0
for d in "$LE"/skills/*/; do
  [ -d "$d" ] || continue
  n=$((n+1))
  for k in trigger evals; do
    f="$d/trigger-queries.json"; [ "$k" = evals ] && f="$d/evals.json"
    skill_evals::check "$k" "$f" "$PLUGIN/skills" >/dev/null || bad="$bad $(basename "$d")/$k"
  done
done
[ "$n" -ge 6 ] && [ -z "$bad" ] && ok "T2.all skills/ 전 디렉터리($n) 스키마 통과" || nope "T2.all" "디렉터리 ${n}개 · 위반:$bad"
# 에코 가드 — contains/regex 는 프롬프트 자신에 매칭되면 안 된다(질문 단어를 되받기만 해도 PASS 하는 변별력 0 assert 차단)
echo_bad=""
for d in "$LE"/skills/*/; do
  [ -f "$d/evals.json" ] || continue
  while IFS= read -r c; do
    p=$(printf '%s' "$c" | jq -r .prompt)
    while IFS= read -r a; do
      t=$(printf '%s' "$a" | jq -r .type); v=$(printf '%s' "$a" | jq -r '.value|tostring')
      case "$t" in contains|regex) [ "$(eval::assert "$t" "$p" "$v")" = PASS ] && echo_bad="$echo_bad $(basename "$d")/$(printf '%s' "$c" | jq -r .id)" ;; esac
    done < <(printf '%s' "$c" | jq -c '.asserts[]')
  done < <(jq -c '.cases[]' "$d/evals.json")
done
[ -z "$echo_bad" ] && ok "T2.echo assert 가 프롬프트 자신에 매칭되지 않음" || nope "T2.echo" "프롬프트 에코로 통과하는 assert:$echo_bad"
# ── T5·T6 러너 픽스처: 실존 skill(karpathy-ko) 1개 · 양성 1 · 음성 1 · case 1 ──
DATA="$TMP/data"; mkdir -p "$DATA/karpathy-ko"
jq -n '{skill:"karpathy-ko",should_trigger:[{id:"pos-1",query:"q1"}],should_not_trigger:[{id:"neg-1",query:"q2"}]}' > "$DATA/karpathy-ko/trigger-queries.json"
jq -n '{skill:"karpathy-ko",cases:[{id:"e-1",prompt:"p1",asserts:[{type:"contains",value:"설계"}]}]}' > "$DATA/karpathy-ko/evals.json"
cat > "$TMP/rec-claude" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMP/args.log"
exec bash "$LE/stub-claude.sh" "\$@"
EOF
chmod +x "$TMP/rec-claude"
_run() {  # <plan 행들(\n)> <env 할당...> -- <러너 인자...> → 러너 stdout (rc 는 RUN_RC)
  printf '%b\n' "$1" > "$TMP/plan.jsonl"; shift
  rm -f "$TMP/state" "$TMP/args.log"
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  RUN_OUT=$(env -u ANTHROPIC_API_KEY -u SKILL_EVAL_MODE -u LLM_EVAL_RUNS -u SKILL_EVAL_INJECT -u SKILL_EVAL_AGENTS_DIR -u SKILL_EVAL_EFFORT -u SKILL_EVAL_MODEL -u CLAUDE_CODE_EFFORT_LEVEL -u LLM_EVAL_JUDGE_MODEL -u SKILL_EVAL_CASES \
    CLAUDE_BIN="$TMP/rec-claude" STUB_PLAN="$TMP/plan.jsonl" STUB_STATE="$TMP/state" \
    SKILL_EVAL_DIR="$DATA" "${envs[@]+"${envs[@]}"}" bash "$LE/run-skill-evals.sh" "$@" 2>&1); RUN_RC=$?
}
_line() { printf '%s\n' "$RUN_OUT" | grep -F -- "  $1  " | head -1; }

# T5 (AC-5) 러너 판정·모드·경계
_run '{"skills":["advisor-ko","karpathy-ko"]}\n{"skills":["advisor-ko","karpathy-ko"]}' -- --trigger
_line pos-1 | grep -q 'PASS' && ok "T5.a ① 양성 — 두 번째 호출도 PASS" || nope "T5.a" "$RUN_OUT"
_line neg-1 | grep -q 'FAIL' && ok "T5.b ② 음성 — 두 번째 호출된 대상 FAIL" || nope "T5.b" "$RUN_OUT"
_run '{"skills":["karpathy-ko"]}\n{"skills":["advisor-ko"]}' -- --trigger
_line neg-1 | grep -q 'PASS' && ok "T5.c ③ 음성 — 다른 skill 만 호출 PASS" || nope "T5.c" "$RUN_OUT"
_run '{"text":"먼저 설계를 봅니다"}' -- --evals
_line e-1 | grep -q 'PASS' && ok "T5.d ④ eval asserts 만족 PASS" || nope "T5.d" "$RUN_OUT"
_run '{"text":"바로 코드 작성"}' -- --evals
_line e-1 | grep -q 'FAIL' && ok "T5.e ④ eval asserts 불만족 FAIL" || nope "T5.e" "$RUN_OUT"
_run '{"skills":["karpathy-ko"]}' ANTHROPIC_API_KEY=k -- --trigger
if [ "$(printf '%s\n' "$RUN_OUT" | grep -c '^MODE=isolated  ')" -eq 2 ] \
   && grep -qF -- '--bare' "$TMP/args.log" && grep -qF -- "--plugin-dir $PLUGIN" "$TMP/args.log"; then
  ok "T5.f ⑤ 키 설정 → MODE=isolated + --bare --plugin-dir"; else nope "T5.f" "$RUN_OUT / $(cat "$TMP/args.log")"; fi
_run '{"skills":["karpathy-ko"]}' -- --trigger
if [ "$(printf '%s\n' "$RUN_OUT" | grep -c '^MODE=routed  ')" -eq 2 ] \
   && printf '%s' "$RUN_OUT" | grep -q 'isolated 불가(ANTHROPIC_API_KEY 부재)' \
   && ! grep -q -- '--bare' "$TMP/args.log" && ! grep -q -- '--plugin-dir' "$TMP/args.log"; then
  ok "T5.g ⑤ 키 미설정 → MODE=routed + 폴백 고지 + 격리 인자 없음"; else nope "T5.g" "$RUN_OUT"; fi
_run '{"skills":["karpathy-ko"]}' ANTHROPIC_API_KEY=k SKILL_EVAL_MODE=routed -- --trigger
if [ "$(printf '%s\n' "$RUN_OUT" | grep -c '^MODE=routed  ')" -eq 2 ] && ! grep -q -- '--bare' "$TMP/args.log" \
   && ! grep -q -- '--plugin-dir' "$TMP/args.log"; then
  ok "T5.h ⑤ SKILL_EVAL_MODE=routed 강제"; else nope "T5.h" "$RUN_OUT"; fi
_run '{}' CLAUDE_BIN="$TMP/no-such-claude" -- --trigger
printf '%s' "$RUN_OUT" | grep -q '^SKIP: claude CLI 부재' && [ "$RUN_RC" -eq 0 ] \
  && ok "T5.i ⑥ CLI 부재 → SKIP · rc 0" || nope "T5.i" "rc=$RUN_RC $RUN_OUT"
_run '{}' -- --trigger advisor-ko
printf '%s' "$RUN_OUT" | grep -q 'advisor-ko  -  SKIP(데이터 파일 부재' && [ "$RUN_RC" -eq 0 ] \
  && ok "T5.j ⑦ 데이터 부재 → SKIP(사유)" || nope "T5.j" "rc=$RUN_RC $RUN_OUT"
_run '{"skills":["advisor-ko"]}\n{"skills":["karpathy-ko"]}' -- --trigger
printf '%s' "$RUN_OUT" | grep -qE '^SKILL-EVAL: mode=routed trigger pass=0 fail=2 skip=0 cost=\$[0-9.]+$' && [ "$RUN_RC" -eq 0 ] \
  && ok "T5.k 요약줄 형식 · 전부 FAIL 이어도 rc 0" || nope "T5.k" "rc=$RUN_RC $RUN_OUT"

_run '{}' -- 
[ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q '^사용: ' && ok "T5.l 인자 없음 → 사용법 · rc 0 (FR-8)" || nope "T5.l" "rc=$RUN_RC $RUN_OUT"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/dead-claude"; chmod +x "$TMP/dead-claude"
_run '{}' CLAUDE_BIN="$TMP/dead-claude" -- --trigger
if _line neg-1 | grep -q 'SKIP(error' && _line pos-1 | grep -q 'SKIP(error' \
   && printf '%s' "$RUN_OUT" | grep -q 'pass=0 fail=0 skip=2'; then
  ok "T5.m result 이벤트 없음 → SKIP(error) — 음성이 PASS 로 위장되지 않음"; else nope "T5.m" "$RUN_OUT"; fi
# T5.t~x (20260930-skill-eval-tool-lock) — 조사·우회 도구 차단 인자 · MCP 비활성 · SKIP(error) stderr 부착
DENY='--allowedTools Skill --disallowedTools Bash Read Glob Grep Agent Edit Write NotebookEdit WebFetch WebSearch ToolSearch'
_run '{"skills":["karpathy-ko"]}' -- --trigger
_n=$(grep -c . "$TMP/args.log"); _d=$(grep -cF -- "$DENY" "$TMP/args.log")
_run '{"skills":["karpathy-ko"]}' ANTHROPIC_API_KEY=k -- --trigger
_ni=$(grep -c . "$TMP/args.log"); _di=$(grep -cF -- "$DENY" "$TMP/args.log")
if [ "$_n" -eq 2 ] && [ "$_d" -eq 2 ] && [ "$_ni" -eq 2 ] && [ "$_di" -eq 2 ]; then
  ok "T5.t routed·isolated 모든 호출에 조사·우회 도구 차단 인자"; else nope "T5.t" "routed $_d/$_n · isolated $_di/$_ni"; fi
_run '{"skills":["karpathy-ko"]}' -- --trigger; _m=$(grep -cF -- '--strict-mcp-config' "$TMP/args.log")
_run '{"skills":["karpathy-ko"]}' ANTHROPIC_API_KEY=k -- --trigger; _mi=$(grep -cF -- '--strict-mcp-config' "$TMP/args.log")
[ "$_m" -eq 2 ] && [ "$_mi" -eq 2 ] && ok "T5.x routed·isolated 모든 호출에 --strict-mcp-config (MCP 우회 차단)" || nope "T5.x" "routed $_m/2 · isolated $_mi/2"
printf '#!/usr/bin/env bash\nprintf "boom: rate limited\\nsecond line\\n" >&2\nexit 1\n' > "$TMP/err-claude"; chmod +x "$TMP/err-claude"
_run '{}' CLAUDE_BIN="$TMP/err-claude" -- --trigger
if _line pos-1 | grep -qF 'SKIP(error: result 이벤트 없음 — 실행 실패) — stderr: boom: rate limited' \
   && _line neg-1 | grep -qF '— stderr: boom: rate limited' && ! printf '%s' "$RUN_OUT" | grep -qF 'second line' \
   && printf '%s' "$RUN_OUT" | grep -q 'pass=0 fail=0 skip=2'; then
  ok "T5.u SKIP(error) 에 claude stderr 첫 줄 부착 · skip 으로 집계"; else nope "T5.u" "$RUN_OUT"; fi
printf '#!/usr/bin/env bash\nprintf "%%0200d\\n" 0 | tr 0 x >&2\nexit 1\n' > "$TMP/long-claude"; chmod +x "$TMP/long-claude"
_run '{}' CLAUDE_BIN="$TMP/long-claude" -- --trigger
_line pos-1 | grep -qE -- '— stderr: x{120}$' && ok "T5.v stderr 첫 줄 120자 상한" || nope "T5.v" "$(_line pos-1 | tail -c 60)"
_run '{}' CLAUDE_BIN="$TMP/dead-claude" -- --trigger
_line pos-1 | grep -qE 'SKIP\(error: result 이벤트 없음 — 실행 실패\)$' && ok "T5.w stderr 없는 실패 → 기존 문구 그대로(부착 없음)" || nope "T5.w" "$(_line pos-1)"
# T5.y~ak (20260930-skill-eval-fixture-repo · cp-note) — 공유 픽스처 repo 를 커밋한 sandbox · 부재 시 종전 · 원본 무변경
FIX="$TMP/fixture"; mkdir -p "$FIX/src"; printf 'a\n' > "$FIX/src/a.js"; printf 'b\n' > "$FIX/b.py"
_fix_before=$(cd "$FIX" && find . | LC_ALL=C sort)
cat > "$TMP/git-claude" <<EOF
#!/usr/bin/env bash
{ printf 'tracked=%s\n' "\$(git ls-files | LC_ALL=C sort | paste -sd, -)"; printf 'dirty=%s\n' "\$(git status --porcelain | grep -c .)"; printf 'commits=%s\n' "\$(git rev-list --count HEAD 2>/dev/null || echo 0)"; } >> "$TMP/git.log"
exec bash "$LE/stub-claude.sh" "\$@"
EOF
chmod +x "$TMP/git-claude"
rm -f "$TMP/git.log"; _run '{"skills":["karpathy-ko"]}' CLAUDE_BIN="$TMP/git-claude" SKILL_EVAL_FIXTURE="$FIX" -- --trigger
if [ "$(grep -c '^tracked=CLAUDE.md,b.py,src/a.js$' "$TMP/git.log")" -eq 2 ] && [ "$(grep -c '^dirty=0$' "$TMP/git.log")" -eq 2 ]; then
  ok "T5.y 픽스처 커밋 sandbox — 픽스처·CLAUDE.md tracked · git status clean"; else nope "T5.y" "$(tr '\n' ' ' < "$TMP/git.log")"; fi
printf '%s' "$RUN_OUT" | grep -q 'pass=1 fail=1 skip=0' && ok "T5.z 픽스처 경로에서도 판정·요약 형식 불변" || nope "T5.z" "$RUN_OUT"
rm -f "$TMP/git.log"; _run '{"skills":["karpathy-ko"]}' CLAUDE_BIN="$TMP/git-claude" SKILL_EVAL_FIXTURE="$TMP/no-such-fixture" -- --trigger
if [ "$(grep -c '^tracked=$' "$TMP/git.log")" -eq 2 ] && [ "$(grep -c '^commits=0$' "$TMP/git.log")" -eq 2 ]; then
  ok "T5.aa 픽스처 부재 → 종전 빈 sandbox(커밋 0 · tracked 없음)"; else nope "T5.aa" "$(tr '\n' ' ' < "$TMP/git.log")"; fi
[ "$(cd "$FIX" && find . | LC_ALL=C sort)" = "$_fix_before" ] && ok "T5.ab 원본 픽스처 무변경(.git·CLAUDE.md·.specops 미생성)" || nope "T5.ab" "$(cd "$FIX" && find . | tr '\n' ' ')"
# 적대적 사용자 전역 git 설정(실패 훅 · templateDir 훅 · 전역 gitignore 에 CLAUDE.md) 에서도 커밋이 성립해야 한다
mkdir -p "$TMP/hostile/hooks" "$TMP/hostile/tpl/hooks"
printf '#!/bin/sh\nexit 1\n' > "$TMP/hostile/hooks/pre-commit"; cp "$TMP/hostile/hooks/pre-commit" "$TMP/hostile/tpl/hooks/pre-commit"
chmod +x "$TMP/hostile/hooks/pre-commit" "$TMP/hostile/tpl/hooks/pre-commit"; printf 'CLAUDE.md\n' > "$TMP/hostile/ignore"
mkdir -p "$TMP/hostile/tpl/info"; printf '*.py\n' > "$TMP/hostile/tpl/info/exclude"   # templateDir 가 복사하는 info/exclude — excludesFile 로는 못 덮는다
printf '[core]\n\thooksPath = %s\n\texcludesFile = %s\n[init]\n\ttemplateDir = %s\n[commit]\n\tgpgsign = true\n[gpg]\n\tprogram = false\n' \
  "$TMP/hostile/hooks" "$TMP/hostile/ignore" "$TMP/hostile/tpl" > "$TMP/hostile/gitconfig"
rm -f "$TMP/git.log"; _run '{"skills":["karpathy-ko"]}' CLAUDE_BIN="$TMP/git-claude" SKILL_EVAL_FIXTURE="$FIX" GIT_CONFIG_GLOBAL="$TMP/hostile/gitconfig" \
  GIT_INDEX_FILE="$TMP/hostile/stray-index" -- --trigger
if [ "$(grep -c '^tracked=CLAUDE.md,b.py,src/a.js$' "$TMP/git.log")" -eq 2 ] && [ "$(grep -c '^dirty=0$' "$TMP/git.log")" -eq 2 ]; then
  ok "T5.ad 적대적 git 환경(실패 훅·templateDir 훅·info/exclude·전역 gitignore·서명·GIT_INDEX_FILE 누출)에도 픽스처 커밋 성립"; else nope "T5.ad" "$(tr '\n' ' ' < "$TMP/git.log")"; fi
[ ! -e "$TMP/hostile/stray-index" ] && ok "T5.ae 호출자 GIT_INDEX_FILE 이 가리키는 곳에 index 미생성(sandbox 밖 무접촉)" || nope "T5.ae" "stray index 생성됨"
# 커밋 실패는 무음이면 안 된다 — 빈 sandbox 로 강등됐다는 NOTE 를 1회 낸다(Phase C Important 1)
mkdir -p "$TMP/failgit"; _realgit=$(command -v git)
printf '#!/usr/bin/env bash\ncase " $* " in *" commit "*) exit 1 ;; esac\nexec "%s" "$@"\n' "$_realgit" > "$TMP/failgit/git"; chmod +x "$TMP/failgit/git"
_run '{"skills":["karpathy-ko"]}' SKILL_EVAL_FIXTURE="$FIX" PATH="$TMP/failgit:$PATH" -- --trigger
if [ "$(printf '%s\n' "$RUN_OUT" | grep -c '^NOTE: 픽스처 커밋 실패')" -eq 1 ] && printf '%s' "$RUN_OUT" | grep -q 'pass=1 fail=1 skip=0'; then
  ok "T5.af 픽스처 커밋 실패 → NOTE 1회 · 판정 경로 불변"; else nope "T5.af" "$RUN_OUT"; fi
_run '{"skills":["karpathy-ko"]}' SKILL_EVAL_FIXTURE="$FIX" -- --trigger
printf '%s' "$RUN_OUT" | grep -q '^NOTE: 픽스처' && nope "T5.ag" "성공인데 NOTE: $RUN_OUT" || ok "T5.ag 픽스처 커밋 성공 → NOTE 없음"
# 복사 실패·빈 픽스처도 무음이면 안 된다(20260930-skill-eval-fixture-cp-note) — 원인별 NOTE 를 run 당 1회 낸다
# 픽스처 경로가 인자에 있을 때만 실패하고 그 밖의 cp 는 진짜 cp 로 넘긴다 — 무관한 cp 가 늘어도 이 단언이 흔들리지 않게(root 에서도 재현: chmod 000 은 root 에 무력)
mkdir -p "$TMP/failcp"; _realcp=$(command -v cp)
printf '#!/usr/bin/env bash\ncase "$*" in *"%s"*) exit 1 ;; esac\nexec "%s" "$@"\n' "$FIX" "$_realcp" > "$TMP/failcp/cp"; chmod +x "$TMP/failcp/cp"
_run '{"skills":["karpathy-ko"]}' SKILL_EVAL_FIXTURE="$FIX" PATH="$TMP/failcp:$PATH" -- --trigger
if [ "$(printf '%s\n' "$RUN_OUT" | grep -c '^NOTE: 픽스처 복사 실패')" -eq 1 ] && printf '%s' "$RUN_OUT" | grep -q 'pass=1 fail=1 skip=0'; then
  ok "T5.ai cp 실패 → NOTE 픽스처 복사 실패 1회 · 판정 요약 불변"; else nope "T5.ai" "$RUN_OUT"; fi
mkdir -p "$TMP/emptyfix"
_run '{"skills":["karpathy-ko"]}' SKILL_EVAL_FIXTURE="$TMP/emptyfix" -- --trigger
if [ "$(printf '%s\n' "$RUN_OUT" | grep -c '^NOTE: 픽스처가 비어 있음')" -eq 1 ] && printf '%s' "$RUN_OUT" | grep -q 'pass=1 fail=1 skip=0'; then
  ok "T5.aj 빈 픽스처 → NOTE 픽스처가 비어 있음 1회 · 판정 요약 불변"; else nope "T5.aj" "$RUN_OUT"; fi
# 복사 실패와 커밋 실패가 겹치면 근본 원인(복사 실패) 하나만, 그것도 1회 — 우선순위 가드 잠금
_run '{"skills":["karpathy-ko"]}' SKILL_EVAL_FIXTURE="$FIX" PATH="$TMP/failcp:$TMP/failgit:$PATH" -- --trigger
if [ "$(printf '%s\n' "$RUN_OUT" | grep -c '^NOTE: 픽스처')" -eq 1 ] && printf '%s\n' "$RUN_OUT" | grep -q '^NOTE: 픽스처 복사 실패'; then
  ok "T5.ak 복사 실패+커밋 실패 겹침 → 복사 실패 NOTE 하나만"; else nope "T5.ak" "$RUN_OUT"; fi
# 픽스처에 .git 이 있어도 sandbox 의 git 에 섞이지 않는다(Phase C Important 2 — cp -R 이 .git 을 병합해 HEAD 가 바뀌던 결함)
FIXG="$TMP/fixture-git"; mkdir -p "$FIXG"; printf 'g\n' > "$FIXG/g.js"
git -C "$FIXG" init -q; git -C "$FIXG" -c user.email=x@x -c user.name=x -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q --allow-empty -m "foreign-fixture-commit"
cat > "$TMP/head-claude" <<EOF
#!/usr/bin/env bash
{ printf 'history=%s\n' "\$(git log --format=%s 2>/dev/null | paste -sd, -)"; printf 'tracked=%s\n' "\$(git ls-files | LC_ALL=C sort | paste -sd, -)"; } >> "$TMP/head.log"
exec bash "$LE/stub-claude.sh" "\$@"
EOF
chmod +x "$TMP/head-claude"; rm -f "$TMP/head.log"
_run '{"skills":["karpathy-ko"]}' CLAUDE_BIN="$TMP/head-claude" SKILL_EVAL_FIXTURE="$FIXG" -- --trigger
if [ "$(grep -c '^history=fixture$' "$TMP/head.log")" -eq 2 ] && [ "$(grep -c '^tracked=CLAUDE.md,g.js$' "$TMP/head.log")" -eq 2 ] && [ -d "$FIXG/.git" ]; then
  ok "T5.ah 픽스처의 .git 은 sandbox 에 섞이지 않음(이력=fixture 커밋 1개 · 원본 .git 보존)"; else nope "T5.ah" "$(tr '\n' ' ' < "$TMP/head.log")"; fi
_rf="$PLUGIN/scripts/tests/llm-eval/skill-eval-fixture-repo"
if [ -f "$_rf/src/auth.js" ] && [ -f "$_rf/src/orders/discount.js" ] && [ -f "$_rf/src/export/csv.js" ] && [ -f "$_rf/tests/test_counter.py" ] \
   && [ -z "$(find "$_rf" -name '*.sh' 2>/dev/null)" ] && [ ! -e "$_rf/.git" ]; then
  ok "T5.ac 실 픽스처 — 질의가 언급하는 파일 존재 · .sh·.git 없음"; else nope "T5.ac" "$(find "$_rf" -type f 2>/dev/null | tr '\n' ' ')"; fi
printf '#!/usr/bin/env bash\nsleep 5\n' > "$TMP/slow-claude"; chmod +x "$TMP/slow-claude"
_run '{}' CLAUDE_BIN="$TMP/slow-claude" LLM_EVAL_TIMEOUT=1 -- --evals
_line e-1 | grep -q 'SKIP(timeout)' && ok "T5.n 시간 초과 → SKIP(timeout)" || nope "T5.n" "$RUN_OUT"
WTO=$((1000 + $$ % 8000))   # 실행별 고유 timeout — 같은 머신의 동시 실행과 pgrep 가 섞이지 않게
_run '{"skills":["karpathy-ko"]}' LLM_EVAL_TIMEOUT="$WTO" -- --trigger
sleep 1
# 워치독 서브셸은 부모 러너의 argv 를 물려받는다(실측) — 러너 경로로 잔존을 센다. 고정 sleep 대신 기한부 대기(병렬 run-all 경합)
_wd=0; _n=0
while :; do _wd=$(pgrep -f "$LE/run-skill-evals.sh" | grep -c .); [ "$_wd" -eq 0 ] || [ "$_n" -ge 6 ] && break; sleep 1; _n=$((_n + 1)); done
_orph=$(pgrep -fx "sleep $WTO" | grep -c .)
if [ "$_orph" -eq 0 ] && [ "$_wd" -eq 0 ]; then ok "T5.o 정상 종료 후 워치독 sleep 고아 0 · 워치독 서브셸 잔존 0 (≤6s)"
else nope "T5.o" "고아 sleep $WTO ${_orph}개 · 워치독 서브셸 ${_wd}개 (6s 후)"
  pkill -fx "sleep $WTO"; pkill -f "$LE/run-skill-evals.sh"; fi
mkdir -p "$TMP/data2/karpathy-ko"
jq -n '{skill:"karpathy-ko",should_trigger:[{id:"pos-1",query:"a\\b\tc"}],should_not_trigger:[{id:"neg-1",query:"q"}]}' > "$TMP/data2/karpathy-ko/trigger-queries.json"
_run '{"skills":["karpathy-ko"]}' SKILL_EVAL_DIR="$TMP/data2" -- --trigger
head -1 "$TMP/args.log" | grep -qF -- "$(printf -- '-p a\\b\tc ')" && ok "T5.p 질의의 백슬래시·탭을 그대로 전달" \
  || nope "T5.p" "$(head -1 "$TMP/args.log")"
# macOS mktemp 는 존재하지 않는 TMPDIR 를 무시하고 기본 경로로 폴백한다(실측) — PATH shim 으로 `mktemp -d` 만 실패시킨다
CWD5Q="$TMP/cwd5q"; mkdir -p "$CWD5Q" "$TMP/failbin"; printf '{"skills":["karpathy-ko"]}\n' > "$TMP/plan.jsonl"; rm -f "$TMP/state"
printf '#!/usr/bin/env bash\ncase " $* " in *" -d "*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v mktemp)" > "$TMP/failbin/mktemp"
chmod +x "$TMP/failbin/mktemp"
RUN_OUT=$( cd "$CWD5Q" && env -u ANTHROPIC_API_KEY -u SKILL_EVAL_MODE -u LLM_EVAL_RUNS -u SKILL_EVAL_EFFORT -u SKILL_EVAL_MODEL -u CLAUDE_CODE_EFFORT_LEVEL -u SKILL_EVAL_CASES PATH="$TMP/failbin:$PATH" \
  CLAUDE_BIN="$TMP/rec-claude" STUB_PLAN="$TMP/plan.jsonl" STUB_STATE="$TMP/state" SKILL_EVAL_DIR="$DATA" \
  bash "$LE/run-skill-evals.sh" --trigger 2>&1 ); RUN_RC=$?
if _line pos-1 | grep -q 'SKIP(error' && [ ! -e "$CWD5Q/.git" ] && [ ! -e "$CWD5Q/CLAUDE.md" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "T5.q mktemp 실패 → SKIP(error) · 호출자 cwd 에 .git·CLAUDE.md 미생성 · rc 0"
else nope "T5.q" "rc=$RUN_RC cwd=[$(ls -A "$CWD5Q" | tr '\n' ' ')] $RUN_OUT"; fi
# 신호 정리형 워치독 재유입 방지 — flag 폴링 블록(run-pressure-evals run_once 와 동형) 고정 문자열 검사
_rc_body=$(sed -n '/^eval::run_claude()/,/^}/p' "$LE/eval-lib.sh")
if printf '%s' "$_rc_body" | grep -qF 'n=0; while [ "$n" -lt "$lim" ]; do [ -e "$flag" ] || exit 0; sleep 1; n=$((n + 1)); done' \
   && printf '%s' "$_rc_body" | grep -qF 'rm -f "$flag"' && ! printf '%s' "$_rc_body" | grep -qF 'sp=$!'; then
  ok "T5.s eval::run_claude 워치독 = flag 폴링 (신호 정리형 부재)"
else nope "T5.s" "eval::run_claude 에 flag 폴링 블록 부재 또는 신호 정리형 워치독 잔존"; fi

# T6 (AC-7) isolated 미확인 표기 + 단발 실행
_run '{"skills":["advisor-ko"]}\n{"skills":["karpathy-ko"]}' ANTHROPIC_API_KEY=k LLM_EVAL_RUNS=3 -- --trigger
printf '%s' "$RUN_OUT" | grep -q '^SKILL-EVAL: mode=isolated(unverified) trigger ' \
  && ok "T6.a 키 설정 → mode=isolated(unverified)" || nope "T6.a" "$RUN_OUT"
[ "$(cat "$TMP/state" 2>/dev/null)" = "2" ] && ok "T6.b 전부 FAIL + LLM_EVAL_RUNS=3 에도 호출 2회(재시도·N-run 없음)" \
  || nope "T6.b" "stub 호출 $(cat "$TMP/state" 2>/dev/null)회"
_run '{"text":"x"}' -- --evals
printf '%s' "$RUN_OUT" | grep -q '^SKILL-EVAL: mode=routed evals ' && [ "$(cat "$TMP/state")" = "1" ] \
  && ok "T6.c 키 미설정 → mode=routed · evals 호출 1회" || nope "T6.c" "$RUN_OUT"
# T8 (20260930-eval-llm-judge) 진짜 llm_rubric 채점기 · 러너 통합 · 보정 — stub 전용, 토큰 0
JUDGE_VERDICT=""; JUDGE_REASON=""; JUDGE_COST=""   # 구현이 없을 때 unbound variable 로 스위트가 중단되지 않고 단언이 개별 FAIL 하게
_judge() {  # <plan 행(JSON 한 줄)> [bin] → JUDGE_* 전역 (서브셸 밖 직접 호출)
  printf '%s\n' "$1" > "$TMP/jplan.jsonl"; rm -f "$TMP/jstate" "$TMP/args.log"
  STUB_PLAN="$TMP/jplan.jsonl" STUB_STATE="$TMP/jstate" eval::judge_rubric "${2:-$TMP/rec-claude}" "응답본문" "기준문안" 30
}
_judge '{"text":"VERDICT: PASS\n근거 한 줄","cost":0.1}'
[ "$JUDGE_VERDICT" = PASS ] && [ "$JUDGE_REASON" = "근거 한 줄" ] && [ "$JUDGE_COST" = 0.1 ] \
  && ok "T8.a VERDICT: PASS 파싱 · 근거 첫 줄 · 비용" || nope "T8.a" "$JUDGE_VERDICT|$JUDGE_REASON|$JUDGE_COST"
_judge '{"text":"VERDICT: FAIL\n범위를 넘겼다"}'
[ "$JUDGE_VERDICT" = FAIL ] && [ "$JUDGE_REASON" = "범위를 넘겼다" ] && ok "T8.b VERDICT: FAIL 파싱" || nope "T8.b" "$JUDGE_VERDICT|$JUDGE_REASON"
_judge '{"text":"`VERDICT: PASS`\n근거"}'; _f1="$JUDGE_VERDICT"; _judge '{"text":"**VERDICT: FAIL**\n근거"}'; _f2="$JUDGE_VERDICT"
[ "$_f1" = PASS ] && [ "$_f2" = FAIL ] && ok "T8.a2 백틱·굵게로 감싼 첫 줄도 형식 차이로 보고 판정 (의미는 엄격 일치)" || nope "T8.a2" "$_f1|$_f2"
# (20261003-eval-debt AC-3) 대괄호로 감싼 첫 줄도 앞뒤 대칭으로 벗겨 판정 (그 밖의 모호한 첫 줄은 종전대로 ERROR)
_judge '{"text":"[VERDICT: PASS]\n근거"}'; _b1="$JUDGE_VERDICT"; _judge '{"text":"[VERDICT: FAIL]\n근거"}'; _b2="$JUDGE_VERDICT"
_judge '{"text":"[VERDICT: PASS] 그러나 FAIL 일 수도"}'; _b3="$JUDGE_VERDICT"
[ "$_b1" = PASS ] && [ "$_b2" = FAIL ] && [ "$_b3" = ERROR ] && ok "T8.am 대괄호 감쌈 [VERDICT: PASS|FAIL] 판정 · 대괄호 뒤 산문은 여전히 ERROR" || nope "T8.am" "$_b1|$_b2|$_b3"
# (AC-4) 근거 줄 없는 PASS 는 ERROR (증거 없는 통과) · FAIL 은 근거 없어도 유지 · 근거 있는 PASS 는 PASS
_judge '{"text":"VERDICT: PASS"}'; _rc1=$?; _r1="$JUDGE_VERDICT"; _r1r="$JUDGE_REASON"
_judge '{"text":"VERDICT: PASS\n   \n"}'; _r2="$JUDGE_VERDICT"
_judge '{"text":"[VERDICT: PASS]"}'; _r3="$JUDGE_VERDICT"
_judge '{"text":"VERDICT: FAIL"}'; _rc4=$?; _r4="$JUDGE_VERDICT"
_judge '{"text":"VERDICT: PASS\n근거 있음"}'; _rc5=$?; _r5="$JUDGE_VERDICT"
[ "$_r1" = ERROR ] && [ "$_r1r" = "근거 줄 없는 PASS" ] && [ "$_rc1" = 3 ] && [ "$_r2" = ERROR ] && [ "$_r3" = ERROR ] && [ "$_r4" = FAIL ] && [ "$_rc4" = 0 ] && [ "$_r5" = PASS ] && [ "$_rc5" = 0 ] \
  && ok "T8.an 근거 줄 없는 PASS(1줄·공백 줄·대괄호) → ERROR+사유·rc 3 · FAIL 유지(rc 0) · 근거 있는 PASS 유지(rc 0)" || nope "T8.an" "$_r1|$_r1r|rc$_rc1|$_r2|$_r3|$_r4|rc$_rc4|$_r5|rc$_rc5"
# (Phase C) 근거 없는 PASS 는 보정 러너가 오통과로 세어야 하므로 신호(JUDGE_PASS_NOREASON)를 남긴다 — 제어문자만 있는 근거 줄도 근거 없음, FAIL·산문 ERROR·정상 PASS 는 0
_judge '{"text":"VERDICT: PASS\n\u0001\u0002"}'; _n1="$JUDGE_VERDICT|${JUDGE_PASS_NOREASON:-unset}"
_judge '{"text":"VERDICT: PASS"}'; _n2="${JUDGE_PASS_NOREASON:-unset}"
_judge '{"text":"VERDICT: FAIL"}'; _n3="${JUDGE_PASS_NOREASON:-unset}"
_judge '{"text":"기준을 만족하므로 통과로 봅니다."}'; _n4="$JUDGE_VERDICT|${JUDGE_PASS_NOREASON:-unset}"
_judge '{"text":"VERDICT: PASS\n근거 있음"}'; _n5="${JUDGE_PASS_NOREASON:-unset}"
[ "$_n1" = "ERROR|1" ] && [ "$_n2" = 1 ] && [ "$_n3" = 0 ] && [ "$_n4" = "ERROR|0" ] && [ "$_n5" = 0 ] \
  && ok "T8.an2 근거 없는 PASS 신호 JUDGE_PASS_NOREASON — 제어문자만 근거=1 · 1줄 PASS=1 · FAIL=0 · 산문 ERROR=0 · 정상 PASS=0" || nope "T8.an2" "$_n1|$_n2|$_n3|$_n4|$_n5"
_judge '{"text":"기준을 만족하므로 통과로 봅니다."}'
[ "$JUDGE_VERDICT" = ERROR ] && ok "T8.c VERDICT 줄 없는 산문 → ERROR (산문에서 PASS 를 추정하지 않음)" || nope "T8.c" "$JUDGE_VERDICT"
_judge '{"text":"VERDICT: PASS 그러나 FAIL 일 수도 있다"}'
[ "$JUDGE_VERDICT" = ERROR ] && ok "T8.d 모호한 첫 줄 → ERROR" || nope "T8.d" "$JUDGE_VERDICT"
_judge '{"text":"판정을 내립니다.\nVERDICT: PASS\n근거"}'
[ "$JUDGE_VERDICT" = ERROR ] && ok "T8.e 첫 줄이 아닌 곳의 VERDICT → ERROR" || nope "T8.e" "$JUDGE_VERDICT"
_judge '{}' "$TMP/dead-claude"
[ "$JUDGE_VERDICT" = ERROR ] && printf '%s' "$JUDGE_REASON" | grep -q '채점 호출 실패' && ok "T8.f result 없음 → ERROR · 사유" || nope "T8.f" "$JUDGE_VERDICT|$JUDGE_REASON"
printf '#!/usr/bin/env bash\nprintf "boom: rate limited\\nsecond\\n" >&2\nexit 1\n' > "$TMP/err-claude"; chmod +x "$TMP/err-claude"; _judge '{}' "$TMP/err-claude"
[ "$JUDGE_VERDICT" = ERROR ] && printf '%s' "$JUDGE_REASON" | grep -qF '채점 호출 실패(rc=' && printf '%s' "$JUDGE_REASON" | grep -qF ' — boom: rate limited' && ! printf '%s' "$JUDGE_REASON" | grep -qF second \
  && ok "T8.f2 호출 실패 사유에 claude stderr 첫 줄 부착" || nope "T8.f2" "$JUDGE_REASON"
_x=$(printf 'x%.0s' $(seq 1 100)); _judge '{"text":"VERDICT: FAIL\n\u001b[31m'"$_x"'"}'
[ "${#JUDGE_REASON}" -eq 80 ] && ! printf '%s' "$JUDGE_REASON" | grep -q "$(printf '\033')" && ok "T8.g 근거 80자 절단 · 제어문자 제거" || nope "T8.g" "len=${#JUDGE_REASON}"
# 호스트에 LLM_EVAL_JUDGE_MODEL 이 있어도 이 호출은 "기본은 --model 없음"을 검증한다(빈 값 = 미설정). T8.i 는 아래에서 명시 주입한다
LLM_EVAL_JUDGE_MODEL= _judge '{"text":"VERDICT: PASS\nok"}'
if grep -qF -- '--max-turns 1' "$TMP/args.log" && grep -qF -- '--strict-mcp-config' "$TMP/args.log" \
   && grep -qF -- '--disallowedTools Bash Read Glob Grep Agent Edit Write NotebookEdit WebFetch WebSearch ToolSearch Skill' "$TMP/args.log" \
   && ! grep -qF -- '--model' "$TMP/args.log"; then ok "T8.h 격리 인자 (max-turns 1 · strict-mcp · 도구+Skill 차단 · 기본은 --model 없음)"; else nope "T8.h" "$(head -c 300 "$TMP/args.log")"; fi
LLM_EVAL_JUDGE_MODEL=judge-m _judge '{"text":"VERDICT: PASS\nok"}'
grep -qF -- '--model judge-m' "$TMP/args.log" && ok "T8.i LLM_EVAL_JUDGE_MODEL → --model" || nope "T8.i" "$(head -c 300 "$TMP/args.log")"
cat > "$TMP/cwd-claude" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$(ls -A | wc -l | tr -d ' ')" >> "$TMP/cwd.log"
exec bash "$LE/stub-claude.sh" "\$@"
EOF
chmod +x "$TMP/cwd-claude"; rm -f "$TMP/cwd.log"; _judge '{"text":"VERDICT: PASS\nok"}' "$TMP/cwd-claude"
[ "$(cat "$TMP/cwd.log" 2>/dev/null)" = 0 ] && ok "T8.j 채점 호출 cwd 는 빈 디렉터리" || nope "T8.j" "cwd 파일 수 $(cat "$TMP/cwd.log" 2>/dev/null)"
mkdir -p "$TMP/data3/karpathy-ko"
jq -n '{skill:"karpathy-ko",cases:[{id:"e-1",prompt:"질문원문XYZ",asserts:[{type:"llm_rubric",value:"기준"}]}]}' > "$TMP/data3/karpathy-ko/evals.json"
_run '{"text":"응답","cost":0.2}\n{"text":"VERDICT: PASS\\n근거","cost":0.1}' SKILL_EVAL_DIR="$TMP/data3" -- --evals
if _line e-1 | grep -q 'PASS' && printf '%s' "$RUN_OUT" | grep -qE 'pass=1 fail=0 skip=0 cost=\$0\.30$'; then
  ok "T8.k 러너: 채점 PASS → 케이스 PASS · 비용 = 응답 + 채점"; else nope "T8.k" "$RUN_OUT"; fi
grep -qxF '[질문]' "$TMP/args.log" && ok "T8.w 러너가 케이스 prompt 를 채점자에게 전달" || nope "T8.w" "채점 호출에 [질문] 섹션 없음"
_run '{"text":"응답"}\n{"text":"VERDICT: FAIL\\n범위를 넘겼다"}' SKILL_EVAL_DIR="$TMP/data3" -- --evals
_line e-1 | grep -qF '첫 실패 llm_rubric:범위를 넘겼다' && printf '%s' "$RUN_OUT" | grep -q 'pass=0 fail=1 skip=0' \
  && ok "T8.l 러너: 채점 FAIL → 사유에 근거" || nope "T8.l" "$RUN_OUT"
_run '{"text":"응답"}\n{"text":"통과로 봅니다"}' SKILL_EVAL_DIR="$TMP/data3" -- --evals
_line e-1 | grep -qF 'SKIP(error: 채점 실패' && printf '%s' "$RUN_OUT" | grep -q 'pass=0 fail=0 skip=1' \
  && ok "T8.m 러너: 채점 ERROR → SKIP (PASS/FAIL 로 세지 않음)" || nope "T8.m" "$RUN_OUT"
# 응답 구분자는 호출마다 다른 nonce — 응답이 구분자를 위조해 채점 지시를 끼워 넣기 어렵게(완전 방어는 아님)
_p1=$(eval::judge_prompt "기준" "응답본문" N123); _p2=$(eval::judge_prompt "기준" "응답본문" N456)
if printf '%s\n' "$_p1" | grep -qxF '[응답-N123 시작]' && printf '%s\n' "$_p1" | grep -qxF '[응답-N123 끝]' && [ "$_p1" != "$_p2" ] \
   && printf '%s\n' "$_p1" | grep -qF -- '`VERDICT: PASS` 또는 `VERDICT: FAIL`'; then ok "T8.u 채점 프롬프트 — nonce 응답 구분자 · 출력 형식 지시"; else nope "T8.u" "$_p1"; fi
# 채점자는 원 질문을 본다 — 질문의 코드와 대조해야 자백 없는 변경을 잡는다
_q1=$(eval::judge_prompt "기준" "응답본문" N1 "질문원문XYZ"); _q0=$(eval::judge_prompt "기준" "응답본문" N1)
if printf '%s\n' "$_q1" | grep -qxF '[질문]' && printf '%s\n' "$_q1" | grep -qxF '질문원문XYZ' && ! printf '%s\n' "$_q0" | grep -qxF '[질문]'; then
  ok "T8.v 채점 프롬프트에 [질문] 섹션 (있을 때만)"; else nope "T8.v" "$_q1"; fi
CAL="$LE/judge-calibration/cases.jsonl"
if [ "$(jq -s 'length' "$CAL")" -eq 10 ] \
   && [ "$(jq -s '[.[]|select((.id|type=="string" and length>0) and (.prompt|type=="string" and length>0) and (.rubric|type=="string" and length>0) and (.response|type=="string" and length>0) and (.note|type=="string" and length>0) and (.expect=="PASS" or .expect=="FAIL"))]|length' "$CAL")" -eq 10 ] \
   && [ "$(jq -s '[.[].id]|unique|length' "$CAL")" -eq 10 ] \
   && [ "$(jq -s '[.[]|select(.expect=="PASS")]|length' "$CAL")" -ge 5 ] && [ "$(jq -s '[.[]|select(.expect=="FAIL")]|length' "$CAL")" -ge 5 ]; then
  ok "T8.n 보정 세트 계약 (10건 · prompt·rubric·response·note 필드 · id 유일 · PASS·FAIL 각 5건 이상)"; else nope "T8.n" "$CAL"; fi
jq -nc '{id:"a",rubric:"r",response:"x",expect:"PASS",note:"n"}' > "$TMP/cal4.jsonl"; jq -nc '{id:"b",rubric:"r",response:"x",expect:"FAIL",note:"n"}' >> "$TMP/cal4.jsonl"
jq -nc '{id:"c",rubric:"r",response:"x",expect:"PASS",note:"n"}' >> "$TMP/cal4.jsonl"; jq -nc '{id:"d",rubric:"r",response:"x",expect:"FAIL",note:"n"}' >> "$TMP/cal4.jsonl"
_cal() {  # <plan 행들(\n)> <claude bin> → 보정 러너 출력
  printf '%b\n' "$1" > "$TMP/cplan.jsonl"; rm -f "$TMP/cstate"
  env CLAUDE_BIN="$2" STUB_PLAN="$TMP/cplan.jsonl" STUB_STATE="$TMP/cstate" JUDGE_CAL_FILE="$TMP/cal4.jsonl" JUDGE_CAL_RUNS=1 bash "$LE/run-judge-calibration.sh" 2>&1
}
_o=$(_cal '{"text":"VERDICT: PASS\\nok"}\n{"text":"VERDICT: FAIL\\nno"}\n{"text":"VERDICT: PASS\\nok"}\n{"text":"VERDICT: FAIL\\nno"}' "$TMP/rec-claude")
printf '%s' "$_o" | grep -q '^CALIBRATION: agree=4/4 false_pass=0 error=0 ' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: ADOPT$' \
  && ok "T8.o 보정 러너: 기대와 모두 일치 → ADOPT" || nope "T8.o" "$_o"
_o=$(_cal '{"text":"VERDICT: PASS\\nok"}' "$TMP/rec-claude")
printf '%s' "$_o" | grep -q 'false_pass=2 ' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' \
  && ok "T8.p 보정 러너: 오답을 PASS 로 내는 채점기 → false_pass=2 · REJECT" || nope "T8.p" "$_o"
# 핵심 안전장치: 오답 오통과가 단 1건이면 일치율이 90%(경계)여도 REJECT — 일치율만 보면 관대한 채점기가 통과한다
: > "$TMP/cal10.jsonl"
for _i in 1 2 3 4 5; do jq -nc --arg id "p$_i" '{id:$id,rubric:"r",response:"x",expect:"PASS",note:"n"}' >> "$TMP/cal10.jsonl"; done
for _i in 1 2 3 4 5; do jq -nc --arg id "f$_i" '{id:$id,rubric:"r",response:"x",expect:"FAIL",note:"n"}' >> "$TMP/cal10.jsonl"; done
_pl=""; for _i in 1 2 3 4 5; do _pl="${_pl}"'{"text":"VERDICT: PASS\\nok"}\n'; done
for _i in 1 2 3 4; do _pl="${_pl}"'{"text":"VERDICT: FAIL\\nno"}\n'; done
_pl="${_pl}"'{"text":"VERDICT: PASS\\nleak"}'
printf '%b\n' "$_pl" > "$TMP/cplan10.jsonl"; rm -f "$TMP/cstate10"
_o=$(env CLAUDE_BIN="$TMP/rec-claude" STUB_PLAN="$TMP/cplan10.jsonl" STUB_STATE="$TMP/cstate10" JUDGE_CAL_FILE="$TMP/cal10.jsonl" JUDGE_CAL_RUNS=1 bash "$LE/run-judge-calibration.sh" 2>&1)
printf '%s' "$_o" | grep -q '^CALIBRATION: agree=9/10 false_pass=1 error=0 ' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' \
  && ok "T8.s 보정 러너: 일치 9/10 이어도 오답 오통과 1건이면 REJECT" || nope "T8.s" "$_o"
# 일치율 하한: 오답 오통과 0 이어도 일치가 90% 미만이면 REJECT (8/10), 정확히 90% 면 ADOPT (9/10 — -ge 경계)
_cal10() {  # <PASS 기대 5건 중 FAIL 로 답할 개수> → 오통과 없이 그만큼만 놓치는 채점기로 보정 러너 실행
  local _miss="$1" _i _pl=""
  for _i in 1 2 3 4 5; do
    if [ "$_i" -le $((5 - _miss)) ]; then _pl="${_pl}"'{"text":"VERDICT: PASS\\nok"}\n'; else _pl="${_pl}"'{"text":"VERDICT: FAIL\\nno"}\n'; fi
  done
  for _i in 1 2 3 4 5; do _pl="${_pl}"'{"text":"VERDICT: FAIL\\nno"}\n'; done
  printf '%b' "$_pl" > "$TMP/cplan10b.jsonl"; rm -f "$TMP/cstate10b"
  env CLAUDE_BIN="$TMP/rec-claude" STUB_PLAN="$TMP/cplan10b.jsonl" STUB_STATE="$TMP/cstate10b" JUDGE_CAL_FILE="$TMP/cal10.jsonl" JUDGE_CAL_RUNS=1 bash "$LE/run-judge-calibration.sh" 2>&1
}
_o=$(_cal10 2)
printf '%s' "$_o" | grep -q '^CALIBRATION: agree=8/10 false_pass=0 error=0 ' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' \
  && ok "T8.z1 보정 러너: 오통과 0 이어도 일치 8/10 (<90%) 이면 REJECT" || nope "T8.z1" "$_o"
_o=$(_cal10 1)
printf '%s' "$_o" | grep -q '^CALIBRATION: agree=9/10 false_pass=0 error=0 ' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: ADOPT$' \
  && ok "T8.z2 보정 러너: 오통과 0 · 일치 정확히 9/10 (=90%) 이면 ADOPT" || nope "T8.z2" "$_o"
_o=$(_cal '{"model":"claude-judge-x","text":"VERDICT: PASS\\nok"}\n{"model":"claude-judge-x","text":"VERDICT: FAIL\\nno"}\n{"model":"claude-judge-x","text":"VERDICT: PASS\\nok"}\n{"model":"claude-judge-x","text":"VERDICT: FAIL\\nno"}' "$TMP/rec-claude")
printf '%s' "$_o" | grep -q '^CALIBRATION-MODEL: claude-judge-x ' && ok "T8.x 보정 러너: 채점 모델 ID 기록 (모델 변경 시 재보정 안내)" || nope "T8.x" "$_o"
_o=$(_cal '{"text":"VERDICT: PASS\\nok"}\n{"text":"VERDICT: FAIL\\nno"}\n{"text":"VERDICT: PASS\\nok"}\n{"text":"VERDICT: FAIL\\nno"}' "$TMP/rec-claude")
printf '%s' "$_o" | grep -q '^CALIBRATION-MODEL: unknown ' && ok "T8.y 모델 ID 를 알 수 없으면 unknown" || nope "T8.y" "$_o"
_o=$(_cal '{}' "$TMP/dead-claude")
printf '%s' "$_o" | grep -q 'agree=0/4 false_pass=0 error=4 ' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' \
  && ok "T8.q 보정 러너: 채점 오류 → error 집계 · REJECT (일치로 세지 않음)" || nope "T8.q" "$_o"
# (Phase C) 증거 0·부분 증거로 ADOPT 금지 — 가드마다 고유 사유 문자열을 단언(가드가 겹쳐 REJECT 만 보면 변이가 안 잡힌다)
_calx() {  # <cases 파일> <JUDGE_CAL_RUNS> <plan 행들(\n)> → 보정 러너 출력 (호출 수는 $TMP/cstate — 부재면 0회)
  printf '%b\n' "$3" > "$TMP/cplanx.jsonl"; rm -f "$TMP/cstate"
  env CLAUDE_BIN="$TMP/rec-claude" STUB_PLAN="$TMP/cplanx.jsonl" STUB_STATE="$TMP/cstate" JUDGE_CAL_FILE="$1" JUDGE_CAL_RUNS="$2" bash "$LE/run-judge-calibration.sh" 2>&1
}
_ok4='{"text":"VERDICT: PASS\\nok"}\n{"text":"VERDICT: FAIL\\nno"}\n{"text":"VERDICT: PASS\\nok"}\n{"text":"VERDICT: FAIL\\nno"}'
_o=$(_calx "$TMP/cal4.jsonl" 0 "$_ok4")
printf '%s' "$_o" | grep -q '^ERROR: .*JUDGE_CAL_RUNS' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' && ! printf '%s' "$_o" | grep -q ADOPT && [ ! -e "$TMP/cstate" ] \
  && ok "T8.aa 보정 러너: JUDGE_CAL_RUNS=0 → 사유 ERROR · REJECT · 채점 호출 0회" || nope "T8.aa" "calls=$(cat "$TMP/cstate" 2>/dev/null) $_o"
_o=$(_calx "$TMP/cal4.jsonl" abc "$_ok4")
printf '%s' "$_o" | grep -q '^ERROR: .*JUDGE_CAL_RUNS' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' && ! printf '%s' "$_o" | grep -q ADOPT && [ ! -e "$TMP/cstate" ] \
  && ok "T8.ab 보정 러너: JUDGE_CAL_RUNS=abc (비정수) → 사유 ERROR · REJECT · 채점 호출 0회" || nope "T8.ab" "calls=$(cat "$TMP/cstate" 2>/dev/null) $_o"
_o=$(_calx "$TMP/cal4.jsonl" '' "$_ok4")
printf '%s' "$_o" | grep -q '^ERROR: .*JUDGE_CAL_RUNS' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' && [ ! -e "$TMP/cstate" ] \
  && ok "T8.ab2 보정 러너: JUDGE_CAL_RUNS= (명시적 빈값) → 기본값으로 삼키지 않고 ERROR · REJECT" || nope "T8.ab2" "calls=$(cat "$TMP/cstate" 2>/dev/null) $_o"
# 손상 세트: 10행 중 3행째가 깨진 JSON — 앞 2행만 채점해 부분 집합으로 ADOPT 하면 안 된다
{ sed -n '1,2p' "$TMP/cal10.jsonl"; printf '{"id":"broken",\n'; sed -n '4,10p' "$TMP/cal10.jsonl"; } > "$TMP/calbad.jsonl"
_o=$(_calx "$TMP/calbad.jsonl" 1 '{"text":"VERDICT: PASS\\nok"}')
printf '%s' "$_o" | grep -q '^ERROR: .*파싱 실패' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' && ! printf '%s' "$_o" | grep -q ADOPT && [ ! -e "$TMP/cstate" ] \
  && ok "T8.ac 보정 러너: 손상 행 세트 → 파싱 실패 ERROR · REJECT (부분 집합 ADOPT 아님) · 채점 호출 0회" || nope "T8.ac" "calls=$(cat "$TMP/cstate" 2>/dev/null) $_o"
printf '\n  \n' > "$TMP/calempty.jsonl"
_o=$(_calx "$TMP/calempty.jsonl" 1 '{"text":"VERDICT: PASS\\nok"}')
printf '%s' "$_o" | grep -q '^ERROR: .*비어' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' && [ ! -e "$TMP/cstate" ] \
  && ok "T8.ad 보정 러너: 빈 세트 → 사유 ERROR · REJECT" || nope "T8.ad" "$_o"
# JUDGE_CAL_FILE 스키마 — 한 행이라도 필드 누락·expect 값 이탈이면 돈 쓰기 전에 거절 ("null" 이 채점 프롬프트로 유료 전송되지 않게)
_schema_bad() {  # <3행째로 넣을 JSON> → 출력
  { sed -n '1,2p' "$TMP/cal4.jsonl"; printf '%s\n' "$1"; sed -n '4p' "$TMP/cal4.jsonl"; } > "$TMP/calschema.jsonl"
  _calx "$TMP/calschema.jsonl" 1 "$_ok4"
}
_SCHEMA_RE='^ERROR: .*스키마 위반'   # (20261003-eval-debt) 스키마 거절 사유 패턴 단일 정의 — T8.ae·af 가 쓰고 T8.al 이 정밀도를 잠근다
_sbad=""
for _row in '{"id":"c","rubric":"r","response":"x","note":"n"}' '{"id":"c","rubric":"r","expect":"PASS"}' '{"id":"c","response":"x","expect":"PASS"}' \
            '{"rubric":"r","response":"x","expect":"PASS"}' '{"id":"c","rubric":"r","response":"x","expect":"pass"}' '{"id":"c","rubric":"r","response":1,"expect":"PASS"}' '"문자열 행"'; do
  _o=$(_schema_bad "$_row")
  { printf '%s' "$_o" | grep -q "$_SCHEMA_RE" && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' && [ ! -e "$TMP/cstate" ]; } || _sbad="$_sbad [$_row → $(printf '%s' "$_o" | tr '\n' '|')]"
done
[ -z "$_sbad" ] && ok "T8.ae 보정 러너: 스키마 위반 행(id·rubric·response·expect 누락/타입·expect 값) → 스키마 ERROR · REJECT · 채점 호출 0회" || nope "T8.ae" "$_sbad"
# prompt 는 선택 — 없어도 스키마 통과 (T8.o 가 prompt 없는 cal4 로 ADOPT 를 잠근다) · 있는데 문자열이 아니면 위반
_o=$(_schema_bad '{"id":"c","rubric":"r","response":"x","expect":"PASS","prompt":3}')
printf '%s' "$_o" | grep -q "$_SCHEMA_RE" && [ ! -e "$TMP/cstate" ] && ok "T8.af 보정 러너: prompt 가 있으면 문자열이어야 함" || nope "T8.af" "$_o"
# (20261003-eval-debt AC-2) T8.ae/af 가 실제로 쓰는 패턴($_SCHEMA_RE)은 "스키마 위반" 사유만 매치하고 "스키마 검사 실행 실패" 사유는 매치하지 않는다 (음성 대조) —
# 실행 실패로 T8.ae/af 가 거짓 통과하지 않게. T8.ae/af 가 이 공유 패턴을 계속 쓰는지(느슨한 리터럴로 되돌리지 않았는지)도 함께 잠근다.
_re_uses=$(sed -n '/^_sbad=""$/,/ok "T8.af/p' "$LE/test-skill-evals.sh" | grep -c 'grep -q "\$_SCHEMA_RE"')
if grep -qF '스키마 검사 실행 실패' "$LE/run-judge-calibration.sh" && [ "$_re_uses" = 2 ] \
   && ! printf '%s\n' 'ERROR: 보정 세트 스키마 검사 실행 실패 (/x)' | grep -q "$_SCHEMA_RE" \
   && printf '%s\n' 'ERROR: 보정 세트 스키마 위반 — id·rubric·response(문자열)·expect(PASS|FAIL) 필수: c' | grep -q "$_SCHEMA_RE"; then
  ok "T8.al T8.ae/af 사유 패턴 정밀도 — 위반 사유만 매치 · 실행 실패 사유는 불매치 · ae/af 가 공유 패턴 사용(2곳)"; else nope "T8.al" "re_uses=$_re_uses RE=$_SCHEMA_RE"; fi
# (AC-1) 보정 세트 id 중복 — 채점(유료) 전에 거절. 중복 id 전부를 정렬·유일화해 한 줄에 나열
{ sed -n '1,2p' "$TMP/cal4.jsonl"; sed -n '1,2p' "$TMP/cal4.jsonl"; } > "$TMP/caldup2.jsonl"   # id a b a b
_o=$(_calx "$TMP/caldup2.jsonl" 1 "$_ok4")
printf '%s\n' "$_o" | grep -qxF 'ERROR: 보정 세트 id 중복 — a b' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' && ! printf '%s' "$_o" | grep -q ADOPT && [ ! -e "$TMP/cstate" ] \
  && ok "T8.ak 보정 러너: 중복 id 세트 → 'id 중복 — a b' ERROR · REJECT · 채점 호출 0회" || nope "T8.ak" "calls=$(cat "$TMP/cstate" 2>/dev/null) $_o"
{ sed -n '1,3p' "$TMP/cal4.jsonl"; sed -n '1p' "$TMP/cal4.jsonl"; } > "$TMP/caldup1.jsonl"   # id a b c a
_o=$(_calx "$TMP/caldup1.jsonl" 1 "$_ok4")
printf '%s\n' "$_o" | grep -qxF 'ERROR: 보정 세트 id 중복 — a' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' && [ ! -e "$TMP/cstate" ] \
  && ok "T8.ak2 보정 러너: 중복 id 한 쌍(a b c a) → 'id 중복 — a' 만 나열" || nope "T8.ak2" "calls=$(cat "$TMP/cstate" 2>/dev/null) $_o"
# 음성 대조 — id 가 유일한 세트(4행 · 기본 보정 세트 10행)는 중복 오류 없이 채점까지 간다
_o=$(_calx "$TMP/cal4.jsonl" 1 "$_ok4"); _c4=$(cat "$TMP/cstate" 2>/dev/null)
_o10=$(_calx "$CAL" 1 '{"text":"VERDICT: PASS\\nok"}')
! printf '%s' "$_o" | grep -q 'id 중복' && [ "$_c4" = 4 ] && ! printf '%s' "$_o10" | grep -q 'id 중복' && printf '%s' "$_o10" | grep -q '^CALIBRATION: agree=' \
  && ok "T8.ak3 id 유일 세트(4행·기본 10행)는 중복 오류 없이 채점 진행 (호출 4회)" || nope "T8.ak3" "c4=$_c4 $_o | $_o10"
# id 비교는 문자열 완전 일치 — 대소문자만 다른 id(a·A)는 중복이 아니다 (정규화하지 않는다)
{ sed -n '1,2p' "$TMP/cal4.jsonl"; jq -nc '{id:"A",rubric:"r",response:"x",expect:"PASS",note:"n"}'; } > "$TMP/calcase.jsonl"   # id a b A
_o=$(_calx "$TMP/calcase.jsonl" 1 "$_ok4"); _c3=$(cat "$TMP/cstate" 2>/dev/null)
! printf '%s' "$_o" | grep -q 'id 중복' && [ "$_c3" = 3 ] \
  && ok "T8.ak4 대소문자만 다른 id(a·A)는 중복이 아님 — 완전 일치 비교 (채점 3회)" || nope "T8.ak4" "c3=$_c3 $_o"
# (Phase C) id 비교는 바이트 단위 — 로케일 콜레이션으로 한글 NFC('가')·NFD(ᄀ+ᅡ) 가 거짓 중복이 되지 않는다 (UTF-8 로케일이 없는 환경에서는 C 로 폴백해 자명 통과)
{ sed -n '1,2p' "$TMP/cal4.jsonl"
  jq -nc --arg id "$(printf '\352\260\200')" '{id:$id,rubric:"r",response:"x",expect:"PASS",note:"n"}'
  jq -nc --arg id "$(printf '\341\204\200\341\205\241')" '{id:$id,rubric:"r",response:"x",expect:"FAIL",note:"n"}'; } > "$TMP/calnfc.jsonl"
_o=$(LC_ALL=en_US.UTF-8 _calx "$TMP/calnfc.jsonl" 1 "$_ok4"); _c4n=$(cat "$TMP/cstate" 2>/dev/null)
! printf '%s' "$_o" | grep -q 'id 중복' && [ "$_c4n" = 4 ] \
  && ok "T8.ak5 한글 NFC/NFD 로 다른 id 는 중복이 아님 — 바이트 비교 (채점 4회)" || nope "T8.ak5" "c4=$_c4n $_o"
# (Phase C) 중복 검사 파이프라인 자체가 실패하면(uniq rc≠0) 조용히 통과하지 않고 실행 실패 ERROR·REJECT·채점 0회 (pipefail + || reject)
mkdir -p "$TMP/fakebin"; printf '#!/bin/sh\nexit 1\n' > "$TMP/fakebin/uniq"; chmod +x "$TMP/fakebin/uniq"
_o=$(PATH="$TMP/fakebin:$PATH" _calx "$TMP/cal4.jsonl" 1 "$_ok4")
printf '%s' "$_o" | grep -q '^ERROR: 보정 세트 id 중복 검사 실행 실패' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' && [ ! -e "$TMP/cstate" ] \
  && ok "T8.ak6 중복 검사 파이프라인 실패(uniq rc 1) → 실행 실패 ERROR · REJECT · 채점 호출 0회" || nope "T8.ak6" "calls=$(cat "$TMP/cstate" 2>/dev/null) $_o"
# (Phase C) 오통과 0 불변식 — expect=FAIL 행에서 근거 없는 PASS(ERROR 로 강등)도 오통과로 센다: 일치 9/10 이어도 REJECT. 음성 대조: expect=PASS 행의 근거 없는 PASS 는 오통과가 아니다(ADOPT 가능)
_pl=""; for _i in 1 2 3 4 5; do _pl="${_pl}"'{"text":"VERDICT: PASS\\nok"}\n'; done
for _i in 1 2 3 4; do _pl="${_pl}"'{"text":"VERDICT: FAIL\\nno"}\n'; done
_pl="${_pl}"'{"text":"VERDICT: PASS"}'
printf '%b\n' "$_pl" > "$TMP/cplan10n.jsonl"; rm -f "$TMP/cstate10n"
_o=$(env CLAUDE_BIN="$TMP/rec-claude" STUB_PLAN="$TMP/cplan10n.jsonl" STUB_STATE="$TMP/cstate10n" JUDGE_CAL_FILE="$TMP/cal10.jsonl" JUDGE_CAL_RUNS=1 bash "$LE/run-judge-calibration.sh" 2>&1)
_pl='{"text":"VERDICT: PASS"}\n'; for _i in 1 2 3 4; do _pl="${_pl}"'{"text":"VERDICT: PASS\\nok"}\n'; done
for _i in 1 2 3 4 5; do _pl="${_pl}"'{"text":"VERDICT: FAIL\\nno"}\n'; done
printf '%b' "$_pl" > "$TMP/cplan10m.jsonl"; rm -f "$TMP/cstate10m"
_o2=$(env CLAUDE_BIN="$TMP/rec-claude" STUB_PLAN="$TMP/cplan10m.jsonl" STUB_STATE="$TMP/cstate10m" JUDGE_CAL_FILE="$TMP/cal10.jsonl" JUDGE_CAL_RUNS=1 bash "$LE/run-judge-calibration.sh" 2>&1)
printf '%s' "$_o" | grep -q '^CALIBRATION: agree=9/10 false_pass=1 error=1 ' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' \
  && printf '%s' "$_o2" | grep -q '^CALIBRATION: agree=9/10 false_pass=0 error=1 ' && printf '%s' "$_o2" | grep -q '^CALIBRATION-VERDICT: ADOPT$' \
  && ok "T8.ap 보정 러너: expect=FAIL 행의 근거 없는 PASS → false_pass 계상·REJECT (오통과 0 불변식) · expect=PASS 행의 것은 오통과 아님" || nope "T8.ap" "$_o | $_o2"
# (AC-5) 도달 불가 가드: 바로 윗줄 주석에 '방어 심층' 과 '도달 불가' 가 있고 가드 코드는 그대로 존속
_gok=1
for _pat in '[ -n "$got" ] || ok=0' '[ "$total" -eq "$rows" ] || echo "ERROR'; do
  _n=$(grep -nF -- "$_pat" "$LE/run-judge-calibration.sh" | sed -n 1p | cut -d: -f1)
  { [ -n "$_n" ] && [ "$_n" -gt 1 ] && sed -n "$((_n - 1))p" "$LE/run-judge-calibration.sh" | grep -q '^ *#.*방어 심층.*도달 불가'; } || _gok=0
done
[ "$_gok" = 1 ] && ok "T8.ao 보정 러너 got 빈값 가드·행 수 대조 — 윗줄에 '방어 심층 … 도달 불가' 주석 · 가드 코드 존속" || nope "T8.ao" "주석 부재 또는 가드 줄 소실"
# 채점 모델이 회차 간 바뀌면 보정이 어느 모델에도 묶이지 않는다 — mixed 로 드러내고 REJECT
_o=$(_calx "$TMP/cal4.jsonl" 1 '{"model":"m-a","text":"VERDICT: PASS\\nok"}\n{"model":"m-a","text":"VERDICT: FAIL\\nno"}\n{"model":"m-b","text":"VERDICT: PASS\\nok"}\n{"model":"m-a","text":"VERDICT: FAIL\\nno"}')
printf '%s' "$_o" | grep -q '^CALIBRATION-MODEL: mixed(m-a,m-b) ' && printf '%s' "$_o" | grep -q '^CALIBRATION: agree=4/4 false_pass=0 error=0 ' && printf '%s' "$_o" | grep -q '^CALIBRATION-VERDICT: REJECT$' \
  && ok "T8.ag 보정 러너: 회차 간 채점 모델 변동 → CALIBRATION-MODEL: mixed(...) · 일치 4/4 여도 REJECT" || nope "T8.ag" "$_o"
# 러너: 결정적 단언이 이미 FAIL 이면 채점 ERROR 가 그 확정 FAIL 을 SKIP 으로 덮지 않는다 · 결정적 통과 뒤 채점 ERROR 는 판정 불가 → SKIP
mkdir -p "$TMP/data4/karpathy-ko"
jq -n '{skill:"karpathy-ko",cases:[{id:"e-1",prompt:"p",asserts:[{type:"contains",value:"없는낱말QQ"},{type:"llm_rubric",value:"기준"}]}]}' > "$TMP/data4/karpathy-ko/evals.json"
_run '{"text":"응답"}\n{"text":"통과로 봅니다"}' SKILL_EVAL_DIR="$TMP/data4" -- --evals
_line e-1 | grep -qF 'FAIL  (첫 실패 contains:없는낱말QQ' && _line e-1 | grep -qF '채점 실패' && printf '%s' "$RUN_OUT" | grep -q 'pass=0 fail=1 skip=0' \
  && ok "T8.ah 러너: 결정적 FAIL + 채점 ERROR → FAIL 유지 (사유에 채점 실패 병기)" || nope "T8.ah" "$RUN_OUT"
jq -n '{skill:"karpathy-ko",cases:[{id:"e-1",prompt:"p",asserts:[{type:"contains",value:"응답"},{type:"llm_rubric",value:"기준"}]}]}' > "$TMP/data4/karpathy-ko/evals.json"
_run '{"text":"응답"}\n{"text":"통과로 봅니다"}' SKILL_EVAL_DIR="$TMP/data4" -- --evals
_line e-1 | grep -qF 'SKIP(error: 채점 실패' && printf '%s' "$RUN_OUT" | grep -q 'pass=0 fail=0 skip=1' \
  && ok "T8.ai 러너: 결정적 통과 + 채점 ERROR → SKIP 유지 (판정 불가)" || nope "T8.ai" "$RUN_OUT"
# 채점 ERROR 가 뒤 단언 평가를 끊지 않는다 — [llm_rubric(ERROR), contains(FAIL)] 순서여도 확정 FAIL 이 SKIP 으로 덮이지 않는다
jq -n '{skill:"karpathy-ko",cases:[{id:"e-1",prompt:"p",asserts:[{type:"llm_rubric",value:"기준"},{type:"contains",value:"없는낱말QQ"}]}]}' > "$TMP/data4/karpathy-ko/evals.json"
_run '{"text":"응답"}\n{"text":"통과로 봅니다"}' SKILL_EVAL_DIR="$TMP/data4" -- --evals
_line e-1 | grep -qF 'FAIL  (첫 실패 contains:없는낱말QQ' && _line e-1 | grep -qF '채점 실패' && printf '%s' "$RUN_OUT" | grep -q 'pass=0 fail=1 skip=0' \
  && ok "T8.aj 러너: 채점 ERROR 뒤의 결정적 FAIL 도 평가 — SKIP 으로 덮지 않음" || nope "T8.aj" "$RUN_OUT"
if grep -q 'run-judge-calibration.sh' "$PLUGIN/CLAUDE.md" && grep -q 'run-judge-calibration.sh' "$PLUGIN/scripts/README.md"; then
  ok "T8.r CLAUDE.md · scripts/README.md 에 보정 러너 등재"; else nope "T8.r" "run-judge-calibration.sh 미등재"; fi
# karpathy 행동 eval = 보정을 통과한 llm_rubric — 쓰는 문안이 보정 세트가 검증한 문안과 같아야 한다
_krub=$(jq -r '[.cases[].asserts[]|select(.type!="llm_rubric")]|length' "$LE/skills/karpathy-ko/evals.json")
# (프롬프트, 루브릭) 쌍으로 대조 — 루브릭만 보면 교차 매핑·미보정 프롬프트에 보정된 루브릭을 재사용해도 통과한다
_kmiss=$(jq -rn --slurpfile c "$LE/judge-calibration/cases.jsonl" --slurpfile e "$LE/skills/karpathy-ko/evals.json" '[$e[0].cases[] | {p:.prompt, v:(.asserts[].value)} | . as $k | select(([$c[] | select(.prompt==$k.p and .rubric==$k.v)]|length)==0)] | length')
[ "$_krub" = 0 ] && [ "$_kmiss" = 0 ] && ok "T8.t karpathy 행동 eval = llm_rubric 이며 (프롬프트, 문안) 쌍이 보정 세트가 검증한 쌍" || nope "T8.t" "비-rubric ${_krub} · 미검증 문안 ${_kmiss}"
# T7 (AC-6) 문서 등재 — 수동 러너는 CLAUDE.md 테스트 명령 + scripts/README.md llm-eval 절에 적는다
if grep -q 'run-skill-evals.sh' "$PLUGIN/CLAUDE.md" && grep -q 'run-skill-evals.sh' "$PLUGIN/scripts/README.md"; then
  ok "T7 CLAUDE.md · scripts/README.md 등재"; else nope "T7" "run-skill-evals.sh 미등재"; fi
# T9 `claude plugin eval` 스위트 구조 (20261007-doc-conformance) — 실행은 수동(토큰 비용)이고 여기서는 데이터 계약만 잠근다
#   공식 plugin-evals: 케이스 = prompt.md(+선택 case.yaml) + graders/*.md ≥1(type 필수). 케이스당 grader 가 없으면 로드 실패.
_ev_bad=""; _ev_n=0
for d in "$PLUGIN"/evals/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  [ "$n" = results ] && continue   # claude plugin eval 의 실행 결과 폴더(.gitignore) — 케이스가 아니다
  _ev_n=$((_ev_n+1))
  [ -f "$d/prompt.md" ] || _ev_bad="$_ev_bad $n(prompt.md 없음)"
  g=$(ls "$d"/graders/*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$g" -ge 1 ] || _ev_bad="$_ev_bad $n(grader 0)"
  for gf in "$d"/graders/*.md; do [ -f "$gf" ] && { sed -n '2,6p' "$gf" | grep -q '^type: ' || _ev_bad="$_ev_bad $n/$(basename "$gf")(type 없음)"; }; done
  if [ -f "$d/case.yaml" ]; then
    sc=$(sed -n 's/^  scaffold_script: *//p' "$d/case.yaml")
    { [ -n "$sc" ] && [ -x "$d/$sc" ]; } || _ev_bad="$_ev_bad $n(scaffold_script 없음·비실행)"
  fi
done
if [ "$_ev_n" -ge 4 ] && [ -z "$_ev_bad" ]; then ok "T9 evals/ 케이스 ${_ev_n}종 구조 계약(prompt·grader·scaffold)"; else nope "T9" "n=$_ev_n bad=$_ev_bad"; fi
# 라우팅 양성(lifecycle 진입)·음성(코딩 아님 → Skill 미호출) 케이스가 모두 있어야 회귀·재작성 비교가 성립한다
if [ -f "$PLUGIN/evals/route-feature-new/graders/lifecycle-entered.md" ] && grep -q 'max: 0' "$PLUGIN/evals/no-route-presentation/graders/no-lifecycle-skill.md" && grep -q 'max: 0' "$PLUGIN/evals/no-route-qa/graders/no-skill.md"; then ok "T9.b 라우팅 양성·음성 케이스 쌍"; else nope "T9.b" "양성/음성 라우팅 케이스 누락"; fi
# ── T10 (20261007-eval-agent-inject) agent 본문 주입 계약 — stub 전용, 토큰 0 ──
# 호출마다 인자를 NUL 구분 파일로 남기는 recorder — 채점 프롬프트는 개행·nonce 를 포함해 args.log 줄 판독이 안 된다
mkdir -p "$TMP/agents" "$TMP/data10/karpathy-ko" "$TMP/data10b/karpathy-ko" "$TMP/data10c/karpathy-ko"
cat > "$TMP/rec10" <<EOF
#!/usr/bin/env bash
n=\$(ls "$TMP/calls" 2>/dev/null | wc -l | tr -d ' '); n=\$((n+1))
printf '%s\0' "\$@" > "$TMP/calls/\$n.args"
exec bash "$LE/stub-claude.sh" "\$@"
EOF
chmod +x "$TMP/rec10"
_calls_reset() { rm -rf "$TMP/calls"; mkdir -p "$TMP/calls"; }
_arg_has() { tr '\0' '\n' < "$1" | grep -qxF -- "$2"; }      # 정확히 같은 인자가 있는가
_arg_has_part() { tr '\0' '\n' < "$1" | grep -qF -- "$2"; }  # 부분 문자열
_ncalls() { ls "$TMP/calls" 2>/dev/null | wc -l | tr -d ' '; }
printf -- '---\nname: fake-agent\nmodel: FMSENTINEL\n---\nBODYSENTINEL 본문\n' > "$TMP/agents/fake-agent.md"
jq -n '{skill:"karpathy-ko",cases:[
  {id:"a-1",agent:"fake-agent",prompt:"질문A",asserts:[{type:"llm_rubric",value:"기준"}]},
  {id:"b-1",prompt:"질문B",asserts:[{type:"contains",value:"응답"}]}]}' > "$TMP/data10/karpathy-ko/evals.json"
jq 'del(.cases[].agent)' "$TMP/data10/karpathy-ko/evals.json" > "$TMP/data10c/karpathy-ko/evals.json"
jq -n '{skill:"karpathy-ko",cases:[{id:"g-1",agent:"ghost-agent",prompt:"질문G",asserts:[{type:"contains",value:"응답"}]}]}' > "$TMP/data10b/karpathy-ko/evals.json"
PLAN10='{"text":"응답"}\n{"text":"VERDICT: PASS\\n근거"}\n{"text":"응답"}'
AG="SKILL_EVAL_AGENTS_DIR=$TMP/agents"

_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_INJECT=1 "$AG" -- --evals
ON_OUT="$RUN_OUT"
if _arg_has "$TMP/calls/1.args" '--append-system-prompt' && _arg_has "$TMP/calls/1.args" 'BODYSENTINEL 본문' \
   && ! _arg_has_part "$TMP/calls/1.args" 'FMSENTINEL' && ! _arg_has_part "$TMP/calls/1.args" 'name: fake-agent'; then
  ok "T10.a 주입 on — 본문만 --append-system-prompt 로 전달(frontmatter 제외)"; else nope "T10.a" "$(tr '\0' ' ' < "$TMP/calls/1.args" 2>/dev/null)"; fi
if [ "$(_ncalls)" -eq 3 ] && _arg_has "$TMP/calls/1.args" '--append-system-prompt' \
   && ! _arg_has_part "$TMP/calls/2.args" '--append-system-prompt' \
   && ! _arg_has_part "$TMP/calls/3.args" '--append-system-prompt' && ! _arg_has_part "$TMP/calls/3.args" 'BODYSENTINEL'; then
  ok "T10.b 누수 없음 — 채점기(2번)·후속 무agent 케이스(3번) 인자에 플래그 없음"; else nope "T10.b" "calls=$(_ncalls)"; fi
if printf '%s\n' "$ON_OUT" | grep -qE '^SKILL-EVAL: mode=routed\+inject evals pass=[0-9]+ fail=[0-9]+ skip=[0-9]+ cost=\$[0-9.]+$' \
   && printf '%s\n' "$ON_OUT" | grep -qxF 'INJECT: 1/1' && { RUN_OUT="$ON_OUT"; _line a-1 | grep -q 'PASS'; }; then
  ok "T10.e 표기 — mode=…+inject · INJECT: 1/1 · 케이스 줄 형식 불변"; else nope "T10.e" "$ON_OUT"; fi

_calls_reset
_run '{"text":"응답"}' CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10b" SKILL_EVAL_INJECT=1 "$AG" -- --evals
if [ "$(_ncalls)" -eq 0 ] && _line g-1 | grep -qF 'SKIP(agent 부재' && printf '%s\n' "$RUN_OUT" | grep -qxF 'INJECT: 0/1' \
   && printf '%s\n' "$RUN_OUT" | grep -q '^NOTE: SKILL_EVAL_INJECT=1 이지만 주입된 케이스 0건'; then
  ok "T10.c agent 파일 부재 → SKIP(무주입 실행 금지) + 0건 NOTE"; else nope "T10.c" "calls=$(_ncalls) $RUN_OUT"; fi

_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" "$AG" -- --evals
cp "$TMP/calls/1.args" "$TMP/off-agent-1.args"; cp "$TMP/calls/3.args" "$TMP/off-agent-3.args"; OFF_OUT="$RUN_OUT"
_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10c" "$AG" -- --evals
if cmp -s "$TMP/off-agent-1.args" "$TMP/calls/1.args" && cmp -s "$TMP/off-agent-3.args" "$TMP/calls/3.args" \
   && ! _arg_has_part "$TMP/off-agent-1.args" '--append-system-prompt' \
   && ! printf '%s\n' "$OFF_OUT" | grep -q 'inject' && ! printf '%s\n' "$OFF_OUT" | grep -q '^INJECT:'; then
  ok "T10.d 주입 off — agent 필드 유무와 무관하게 응답 호출 인자 바이트 동일 · 표기 없음(AC-R-1)"; else nope "T10.d" "$OFF_OUT"; fi

_run '{"text":"응답"}\n{"text":"응답"}' CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10c" SKILL_EVAL_INJECT=1 "$AG" -- --evals
if printf '%s\n' "$RUN_OUT" | grep -qxF 'INJECT: 0/0' && printf '%s\n' "$RUN_OUT" | grep -q '^NOTE: SKILL_EVAL_INJECT=1 이지만 주입된 케이스 0건'; then
  ok "T10.f 주입 on 인데 agent 필드 케이스 0 → INJECT: 0/0 + NOTE (with 로 오인 방지)"; else nope "T10.f" "$RUN_OUT"; fi

EJ="$LE/skills/implementing-ko/evals.json"
_ag_bad=$(jq -r '
  def want: if (.id|test("^e-(5|6|7|8|9)$")) then "implementer-ko" elif (.id|test("^e-(10|11|12)$")) then "code-reviewer-ko" else null end;
  .cases[] | select(want != null) | select(.agent != want) | .id' "$EJ" | tr '\n' ' ')
for a in implementer-ko code-reviewer-ko; do [ -f "$PLUGIN/agents/$a.md" ] || _ag_bad="$_ag_bad agents/$a.md"; done
for _f in "$LE"/skills/*/evals.json; do   # 전 skill 의 agent 값이 실존 파일을 가리키는가(off 실행에서는 러너가 못 잡는 오타 방지)
  for a in $(jq -r '.cases[].agent // empty' "$_f"); do [ -f "$PLUGIN/agents/$a.md" ] || _ag_bad="$_ag_bad $(basename "$(dirname "$_f")"):$a"; done
done
[ -z "$_ag_bad" ] && ok "T10.i implementing-ko e-5~e-12 agent 필드 정합 + 전 skill agent 값의 agent 파일 실존" || nope "T10.i" "불일치:$_ag_bad"
_ctx_bad=$(jq -r '.cases[] | select(.id|test("^e-(5|7|8|9)$")) | select(.prompt|contains("필수 컨텍스트 5개")|not) | .id' "$EJ" | tr '\n' ' ')
_ctx_bad="$_ctx_bad$(jq -r '.cases[] | select(.id|test("^e-(10|11|12)$")) | select(.prompt|contains("검토 컨텍스트 5종")|not) | .id' "$EJ" | tr '\n' ' ')"
[ -z "$_ctx_bad" ] && ok "T10.j e-5·e-7~e-12 prompt 에 컨텍스트 충족 문구(e-6 은 의도적 누락 시나리오)" || nope "T10.j" "문구 누락:$_ctx_bad"
[ "$(jq '[.cases[0:4][] | has("agent")] | any' "$EJ")" = false ] && ok "T10.k e-1~e-4 는 agent 필드 없음(불변)" || nope "T10.k" "e-1~e-4 에 agent 필드"
if grep -q 'SKILL_EVAL_INJECT' "$PLUGIN/scripts/README.md" && grep -q 'SKILL_EVAL_INJECT' "$PLUGIN/CLAUDE.md" \
   && grep -q 'N≥3' "$PLUGIN/scripts/README.md" && grep -q '별도 승인' "$PLUGIN/scripts/README.md"; then
  ok "T10.l 문서에 INJECT 사용법·측정 프로토콜(N≥3·비용 별도 승인)"; else nope "T10.l" "README/CLAUDE.md 에 SKILL_EVAL_INJECT·N≥3·별도 승인 누락"; fi

# ── T11 (20261007-eval-effort-knob) effort·model 노브 — stub 전용, 토큰 0 ──
_arg_pair() { tr '\0' '\n' < "$1" | grep -xF -A1 -- "$2" | grep -qxF -- "$3"; }   # <file> <flag> <value> — 플래그 바로 뒤 값
_arg_cnt() { tr '\0' '\n' < "$1" | grep -cxF -- "$2"; }                           # 같은 플래그 개수

_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_EFFORT=low "$AG" -- --evals
E_OUT="$RUN_OUT"
if [ "$(_ncalls)" -eq 3 ] && _arg_pair "$TMP/calls/1.args" --effort low && _arg_pair "$TMP/calls/3.args" --effort low \
   && [ "$(_arg_cnt "$TMP/calls/1.args" --effort)" = 1 ] && [ "$(_arg_cnt "$TMP/calls/2.args" --effort)" = 0 ] \
   && ! _arg_has_part "$TMP/calls/1.args" '--model' \
   && printf '%s\n' "$E_OUT" | grep -qE '^SKILL-EVAL: mode=routed\+effort=low evals pass=[0-9]+ fail=[0-9]+ skip=[0-9]+ cost=\$[0-9.]+$'; then
  ok "T11.a effort 노브 — candidate(1·3번)에만 --effort low 1회 · 채점기(2번) 없음 · 라벨 +effort=low (AC-1)"
else nope "T11.a" "calls=$(_ncalls) $E_OUT"; fi

_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_MODEL=sonnet "$AG" -- --evals
M_OUT="$RUN_OUT"
if [ "$(_ncalls)" -eq 3 ] && _arg_pair "$TMP/calls/1.args" --model sonnet && _arg_pair "$TMP/calls/3.args" --model sonnet \
   && [ "$(_arg_cnt "$TMP/calls/2.args" --model)" = 0 ] && ! _arg_has_part "$TMP/calls/1.args" '--effort' \
   && printf '%s\n' "$M_OUT" | grep -qE '^SKILL-EVAL: mode=routed\+model=sonnet evals '; then
  ok "T11.b model 노브 — candidate 에만 --model sonnet · 채점기 없음 · 라벨 +model=sonnet (AC-2)"
else nope "T11.b" "calls=$(_ncalls) $M_OUT"; fi

_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_INJECT=1 SKILL_EVAL_EFFORT=high SKILL_EVAL_MODEL=opus "$AG" -- --evals
B_OUT="$RUN_OUT"
if _arg_pair "$TMP/calls/1.args" --effort high && _arg_pair "$TMP/calls/1.args" --model opus && _arg_has "$TMP/calls/1.args" '--append-system-prompt' \
   && ! _arg_has_part "$TMP/calls/2.args" '--effort' && ! _arg_has_part "$TMP/calls/2.args" '--model' \
   && printf '%s\n' "$B_OUT" | grep -qE '^SKILL-EVAL: mode=routed\+inject\+effort=high\+model=opus evals '; then
  ok "T11.c 동시 사용 — inject·effort·model 공존 · 라벨 순서 +inject+effort+model · 채점기 무영향 (AC-2)"
else nope "T11.c" "$B_OUT"; fi

_bad_ok=1; _bad_why=""
for _kv in 'SKILL_EVAL_EFFORT=ultra' 'SKILL_EVAL_EFFORT=LOW' 'SKILL_EVAL_EFFORT=low ' 'SKILL_EVAL_MODEL=a b' 'SKILL_EVAL_MODEL=../x' 'SKILL_EVAL_MODEL=-x' $'SKILL_EVAL_MODEL=ok\n' 'SKILL_EVAL_MODEL=é' 'SKILL_EVAL_MODEL=ａb'; do
  _calls_reset   # LC_ALL=UTF-8 고정 — bash 3.2 대괄호 범위식은 로케일 정렬을 따라 비ASCII 를 통과시켰다(I-1)
  _run '{"text":"응답"}' CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10c" LC_ALL=en_US.UTF-8 "$_kv" "$AG" -- --evals
  if [ "$(_ncalls)" -ne 0 ] || [ "$RUN_RC" -ne 0 ] || ! printf '%s\n' "$RUN_OUT" | grep -qE '^ERROR: SKILL_EVAL_(EFFORT|MODEL) 형식 오류'; then
    _bad_ok=0; _bad_why="$_bad_why [$_kv calls=$(_ncalls) rc=$RUN_RC]"
  fi
done
[ "$_bad_ok" = 1 ] && ok "T11.d 형식 오류 9종 — claude 호출 0 · exit 0 · 사유 1줄 (AC-3)" || nope "T11.d" "$_bad_why"

_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" "$AG" -- --evals
OFFB_OUT="$RUN_OUT"; for _i in 1 2 3; do cp "$TMP/calls/$_i.args" "$TMP/offb-$_i.args"; done
_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_EFFORT= SKILL_EVAL_MODEL= "$AG" -- --evals
if [ "$(_ncalls)" -eq 3 ] && cmp -s "$TMP/offb-1.args" "$TMP/calls/1.args" \
   && cmp -s "$TMP/offb-3.args" "$TMP/calls/3.args" && ! _arg_has_part "$TMP/calls/2.args" '--effort' && ! _arg_has_part "$TMP/calls/2.args" '--model' && [ "$OFFB_OUT" = "$RUN_OUT" ] && ! printf '%s\n' "$RUN_OUT" | grep -qE 'effort|model='; then
  ok "T11.e 빈 값 = off — candidate 호출(1·3번) 인자·출력 바이트 동일 · 채점기(2번)는 nonce 로 비교 제외 · 표기 없음 (AC-R-1)"
else nope "T11.e" "$RUN_OUT"; fi

if grep -q 'SKILL_EVAL_EFFORT' "$PLUGIN/scripts/README.md" && grep -q 'SKILL_EVAL_MODEL' "$PLUGIN/scripts/README.md" \
   && grep -q 'SKILL_EVAL_EFFORT' "$PLUGIN/CLAUDE.md" && grep -q 'SKILL_EVAL_MODEL' "$PLUGIN/CLAUDE.md" \
   && grep -q '파일럿' "$PLUGIN/scripts/README.md" && grep -q '별도 승인' "$PLUGIN/scripts/README.md"; then
  ok "T11.f 문서에 노브·파일럿 프로토콜(별도 승인) 병기 (AC-4)"
else nope "T11.f" "README/CLAUDE.md 에 SKILL_EVAL_EFFORT·SKILL_EVAL_MODEL·파일럿·별도 승인 누락"; fi
# T11.g (AC-5) effort env + 노브 동시 설정 거절 · 노브 off/model 단독은 env 와 무관
_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_EFFORT=low CLAUDE_CODE_EFFORT_LEVEL=high "$AG" -- --evals
_g1_calls=$(_ncalls); _g1_rc=$RUN_RC; _g1_out="$RUN_OUT"
_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" CLAUDE_CODE_EFFORT_LEVEL=high "$AG" -- --evals
_g2_calls=$(_ncalls); _g2_out="$RUN_OUT"
_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_MODEL=sonnet CLAUDE_CODE_EFFORT_LEVEL=high "$AG" -- --evals
_g3_calls=$(_ncalls); _g3_out="$RUN_OUT"
if [ "$_g1_calls" -eq 0 ] && [ "$_g1_rc" -eq 0 ] && [ "$(printf '%s\n' "$_g1_out" | grep -cE '^ERROR: .*CLAUDE_CODE_EFFORT_LEVEL')" = 1 ] \
   && [ "$_g2_calls" -eq 3 ] && ! printf '%s\n' "$_g2_out" | grep -q '^ERROR:' \
   && [ "$_g3_calls" -eq 3 ] && ! printf '%s\n' "$_g3_out" | grep -q '^ERROR:'; then
  ok "T11.g effort env+노브 거절(호출 0·rc 0·사유 1줄) · 노브 off·model 단독은 env 무관 호출 3 (AC-5)"
else nope "T11.g" "g1 calls=$_g1_calls rc=$_g1_rc [$_g1_out] g2 calls=$_g2_calls g3 calls=$_g3_calls"; fi

# ── T12 (20261008-eval-case-filter) SKILL_EVAL_CASES 필터 — stub 전용, 토큰 0 ──
_calls_reset
_run '{"text":"응답"}' CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_CASES=b-1 "$AG" -- --evals
C1_OUT="$RUN_OUT"
if [ "$(_ncalls)" -eq 1 ] && printf '%s\n' "$C1_OUT" | grep -qF '  b-1  ' && ! printf '%s\n' "$C1_OUT" | grep -qF '  a-1  ' \
   && printf '%s\n' "$C1_OUT" | grep -qE '^SKILL-EVAL: mode=routed\+cases=1 evals pass=1 fail=0 skip=0 cost=\$[0-9.]+$'; then
  ok "T12.a 단일 id — b-1 만 질의(호출 1·채점기 없음)·a-1 줄/SKIP 집계 없음·라벨 +cases=1 (AC-1)"
else nope "T12.a" "calls=$(_ncalls) $C1_OUT"; fi

_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_CASES=a-1,b-1 "$AG" -- --evals
if [ "$(_ncalls)" -eq 3 ] && printf '%s\n' "$RUN_OUT" | grep -qE '^SKILL-EVAL: mode=routed\+cases=2 evals '; then
  ok "T12.b 두 id — 호출 3건(candidate 2 + 채점기 1)·라벨 +cases=2 (AC-1)"
else nope "T12.b" "calls=$(_ncalls) $RUN_OUT"; fi

_bad_ok=1; _bad_why=""
for _kv in 'SKILL_EVAL_CASES=a,' 'SKILL_EVAL_CASES=,a' 'SKILL_EVAL_CASES=a,,b' 'SKILL_EVAL_CASES=a b' 'SKILL_EVAL_CASES=é' 'SKILL_EVAL_CASES=ａb' 'SKILL_EVAL_CASES=-x' 'SKILL_EVAL_CASES=a,-x' 'SKILL_EVAL_CASES=a;b' $'SKILL_EVAL_CASES=a\n'; do
  _calls_reset
  _run '{"text":"응답"}' CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10c" LC_ALL=en_US.UTF-8 "$_kv" "$AG" -- --evals
  if [ "$(_ncalls)" -ne 0 ] || [ "$RUN_RC" -ne 0 ] || ! printf '%s\n' "$RUN_OUT" | grep -qE '^ERROR: SKILL_EVAL_CASES 형식 오류'; then
    _bad_ok=0; _bad_why="$_bad_why [$_kv calls=$(_ncalls) rc=$RUN_RC]"
  fi
done
[ "$_bad_ok" = 1 ] && ok "T12.c 형식 오류 10종(UTF-8 로케일) — claude 호출 0 · exit 0 · 사유 1줄 (AC-2)" || nope "T12.c" "$_bad_why"

_calls_reset
_run '{"text":"응답"}' CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_CASES=zz-9 "$AG" -- --evals
Z_OUT="$RUN_OUT"; Z_CALLS="$(_ncalls)"
_calls_reset
_run '{"text":"응답"}' CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_CASES=b-1,zz-9 "$AG" -- --evals
if [ "$(_ncalls)" -eq 1 ] && printf '%s\n' "$RUN_OUT" | grep -qE '^NOTE: SKILL_EVAL_CASES .*없음: zz-9$' \
   && [ "$Z_CALLS" = 0 ] && printf '%s\n' "$Z_OUT" | grep -qE '^NOTE: SKILL_EVAL_CASES .*매칭 0건' && printf '%s\n' "$Z_OUT" | grep -qE '^SKILL-EVAL: mode=routed\+cases=0 evals pass=0 fail=0 skip=0'; then
  ok "T12.d 오타 id NOTE(혼합: b-1 만 실행·zz-9 나열) · 매칭 0건 NOTE + 호출 0 (AC-3)"
else nope "T12.d" "calls=$(_ncalls) zcalls=$Z_CALLS mixed=[$RUN_OUT] zero=[$Z_OUT]"; fi

_calls_reset
_run '{"skills":["karpathy-ko"]}\n{"skills":["advisor-ko"]}' CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_CASES=e-1 -- --trigger
T_OUT="$RUN_OUT"; T_CALLS=$(_ncalls)
_calls_reset
_run '{"skills":["karpathy-ko"]}\n{"skills":["advisor-ko"]}' CLAUDE_BIN="$TMP/rec10" -- --trigger
if [ "$T_CALLS" = "$(_ncalls)" ] && printf '%s\n' "$T_OUT" | grep -qE '^NOTE: SKILL_EVAL_CASES .*--trigger' && ! printf '%s\n' "$T_OUT" | grep -q '+cases'; then
  ok "T12.e --trigger — 필터 무시(호출 수 off 와 동일)·NOTE·라벨 +cases 없음 (AC-4)"
else nope "T12.e" "$T_OUT"; fi

_calls_reset
_run '{"text":"응답"}' CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_INJECT=1 SKILL_EVAL_CASES=b-1 "$AG" -- --evals
O1="$RUN_OUT"
_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_INJECT=1 SKILL_EVAL_CASES=a-1 "$AG" -- --evals
if printf '%s\n' "$O1" | grep -qxF 'INJECT: 0/0' && printf '%s\n' "$RUN_OUT" | grep -qxF 'INJECT: 1/1' \
   && printf '%s\n' "$RUN_OUT" | grep -qE '^SKILL-EVAL: mode=routed\+inject\+cases=1 evals '; then
  ok "T12.f INJECT 집계 — 필터 통과 케이스만(b-1 필터 0/0 · a-1 필터 1/1)·라벨 +inject+cases=1 (AC-4)"
else nope "T12.f" "o1=[$O1] o2=[$RUN_OUT]"; fi

_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" "$AG" -- --evals
OFFC_OUT="$RUN_OUT"; for _i in 1 2 3; do cp "$TMP/calls/$_i.args" "$TMP/offc-$_i.args"; done
_calls_reset
_run "$PLAN10" CLAUDE_BIN="$TMP/rec10" SKILL_EVAL_DIR="$TMP/data10" SKILL_EVAL_CASES= "$AG" -- --evals
if [ "$(_ncalls)" -eq 3 ] && cmp -s "$TMP/offc-1.args" "$TMP/calls/1.args" && cmp -s "$TMP/offc-3.args" "$TMP/calls/3.args" \
   && ! _arg_has_part "$TMP/calls/2.args" 'cases' && [ "$OFFC_OUT" = "$RUN_OUT" ] && ! printf '%s\n' "$RUN_OUT" | grep -q 'cases'; then
  ok "T12.g 빈 값 = off — candidate 호출 인자·출력 바이트 동일·표기 없음 (AC-R-1)"
else nope "T12.g" "$RUN_OUT"; fi

if grep -q 'SKILL_EVAL_CASES' "$PLUGIN/scripts/README.md" && grep -q 'SKILL_EVAL_CASES' "$PLUGIN/CLAUDE.md" && grep -q '≈ \$16' "$PLUGIN/scripts/README.md"; then
  ok "T12.h 문서에 SKILL_EVAL_CASES 사용법·정정 비용(≈ \$16) 병기 (AC-5)"
else nope "T12.h" "README/CLAUDE.md 에 SKILL_EVAL_CASES 또는 ≈ \$16 누락"; fi
echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
