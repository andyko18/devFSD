#!/usr/bin/env bash
# scripts/critic-ask.sh 검증 — CRITIC_BIN stub 주입 (토큰 0)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$PLUGIN/scripts/critic-ask.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT

printf '검토 지시문\n' > "$TD/prompt.md"
printf '플랜 본문 alpha\n' > "$TD/target.md"

# T1.a stub 성공 — 합성 프롬프트가 stub stdin 으로 전달 + CRITIC[custom]: 헤더 + 의견 출력 (AC-1)
cat > "$TD/stub.sh" <<'STUB'
#!/usr/bin/env bash
cat > "$STUB_IN"
echo "외부 의견: 위험 1건"
STUB
chmod +x "$TD/stub.sh"
export STUB_IN="$TD/received"
out=$(CRITIC_BIN="$TD/stub.sh" bash "$SCRIPT" "$TD/prompt.md" --files "$TD/target.md"); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^CRITIC\[custom\]:' && echo "$out" | grep -q '외부 의견: 위험 1건' \
   && grep -q '검토 지시문' "$STUB_IN" && grep -q -- '--- 파일: ' "$STUB_IN" && grep -q '플랜 본문 alpha' "$STUB_IN"; then
  PASS=$((PASS+1)); echo "PASS T1.a stub 위탁 + 합성 전달"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a (rc=$rc out=$out)"
fi
unset STUB_IN

# T1.b provider 전부 부재 → SKIP + exit 0 (AC-2 — PATH 축소 격리, clarify Q5)
out=$(env -i PATH="/usr/bin:/bin" HOME="$HOME" bash "$SCRIPT" "$TD/prompt.md" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^CRITIC: SKIP (외부 CLI 부재)'; then
  PASS=$((PASS+1)); echo "PASS T1.b 부재 SKIP + exit 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b (rc=$rc out=$out)"
fi

# T1.h stale shim — claude 가 PATH 에 존재하나 실행 불가(rc=127) → FAIL(provider rc=127) 아닌 SKIP
#   (dogfood 20260717 test2: command -v 통과 후 실행 127 → 외부 critic 실효 0 이 FAIL 로 위장됨.
#    preflight(_usable --version)가 부재로 강등해 cascade/SKIP 으로 정직하게 강등돼야 한다)
mkdir -p "$TD/shim"
printf '#!/usr/bin/env bash\nexit 127\n' > "$TD/shim/claude"; chmod +x "$TD/shim/claude"
out=$(env -i PATH="$TD/shim:/usr/bin:/bin" HOME="$HOME" bash "$SCRIPT" "$TD/prompt.md" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^CRITIC: SKIP (외부 CLI 부재)' && ! echo "$out" | grep -q 'rc=127'; then
  PASS=$((PASS+1)); echo "PASS T1.h stale shim → SKIP 강등 (FAIL rc=127 위장 차단)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.h (rc=$rc out=$out)"
fi

# T1.i cascade — 깨진 claude shim + 정상 codex → 다음 provider 로 넘어가 실효 유지
printf '#!/usr/bin/env bash\n[ "$1" = "--version" ] 2>/dev/null && { echo 0.1; exit 0; }\ncase "$*" in *--help*) echo "      --sandbox <SANDBOX_MODE>"; exit 0 ;; esac\ncat >/dev/null\necho "코덱스 의견"\n' > "$TD/shim/codex"
chmod +x "$TD/shim/codex"
out=$(env -i PATH="$TD/shim:/usr/bin:/bin" HOME="$HOME" bash "$SCRIPT" "$TD/prompt.md" 2>/dev/null); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^CRITIC\[codex\]:' && echo "$out" | grep -q '코덱스 의견'; then
  PASS=$((PASS+1)); echo "PASS T1.i 깨진 shim → codex cascade"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.i (rc=$rc out=$out)"
fi
rm -rf "$TD/shim"

# T1.c timeout → CRITIC: FAIL + exit 0 (AC-3 — advisory 비차단)
cat > "$TD/hang.sh" <<'HANG'
#!/usr/bin/env bash
echo "hang stderr" >&2
exec sleep 30
HANG
chmod +x "$TD/hang.sh"
out=$(CRITIC_TIMEOUT=1 CRITIC_BIN="$TD/hang.sh" bash "$SCRIPT" "$TD/prompt.md" 2>/dev/null); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^CRITIC: FAIL (timeout'; then
  PASS=$((PASS+1)); echo "PASS T1.c timeout FAIL + exit 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.c (rc=$rc out=$out)"
fi

# T1.d 200KB 절단 — 고지 + stub 수신 ≤ 한도+여유 (AC-4)
awk 'BEGIN{for(i=0;i<30000;i++) print "padding line padding line"}' > "$TD/big.md"
cat > "$TD/size-stub.sh" <<'SZ'
#!/usr/bin/env bash
wc -c | tr -d " " > "$SZ_OUT"
echo "ok"
SZ
chmod +x "$TD/size-stub.sh"
export SZ_OUT="$TD/size"
err=$(CRITIC_BIN="$TD/size-stub.sh" bash "$SCRIPT" "$TD/prompt.md" --files "$TD/big.md" 2>&1 >/dev/null); rc=$?
got=$(cat "$SZ_OUT" 2>/dev/null || echo 0)
if [ $rc -eq 0 ] && echo "$err" | grep -q '절단' && [ "$got" -le 205000 ]; then
  PASS=$((PASS+1)); echo "PASS T1.d 절단 + 고지 (수신 ${got}B)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.d (rc=$rc got=$got err=$err)"
fi
unset SZ_OUT

# T1.e prompt-file 부재 → exit 1 (사용 오류)
err=$(bash "$SCRIPT" "$TD/nope.md" 2>&1 >/dev/null); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'ERROR'; then
  PASS=$((PASS+1)); echo "PASS T1.e prompt 부재 exit 1"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.e (rc=$rc err=$err)"
fi

# T1.g provider 즉시 실패 (exit 1) → CRITIC: FAIL (provider rc=1) + exit 0 (AC-3 — advisory 비차단)
cat > "$TD/fail-stub.sh" <<'FS'
#!/usr/bin/env bash
echo "boom" >&2
exit 1
FS
chmod +x "$TD/fail-stub.sh"
out=$(CRITIC_BIN="$TD/fail-stub.sh" bash "$SCRIPT" "$TD/prompt.md" 2>/dev/null); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^CRITIC: FAIL (provider rc=1)'; then
  PASS=$((PASS+1)); echo "PASS T1.g provider 실패 FAIL + exit 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.g (rc=$rc out=$out)"
fi

# T1.f 템플릿 2종 존재 + respond-in-Korean 지시 (AC-8)
if [ -f "$PLUGIN/templates/critic-prompt-plan.md" ] && [ -f "$PLUGIN/templates/critic-prompt-diff.md" ] \
   && grep -qi 'respond in korean' "$PLUGIN/templates/critic-prompt-plan.md" \
   && grep -qi 'respond in korean' "$PLUGIN/templates/critic-prompt-diff.md"; then
  PASS=$((PASS+1)); echo "PASS T1.f 템플릿 2종"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.f 템플릿 누락"
fi

# ── T2 skill 연결 (AC-5·6·7) ──

# T2.a planning-ko — critic 병행 단계 (PASS 직후·§8 기록·advisory) (AC-5)
PL="$PLUGIN/skills/planning-ko/SKILL.md"
if grep -q 'critic-ask.sh' "$PL" && grep -q 'critic-prompt-plan.md' "$PL" \
   && awk '/### 외부 critic 병행/,/^## /' "$PL" | grep -q '판정 권한 없음'; then
  PASS=$((PASS+1)); echo "PASS T2.a planning-ko 연결"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.a"
fi

# T2.b requesting-code-review-ko — diff 의견 병행 (저장 경로·경로만 전달·advisory) (AC-6)
RQ="$PLUGIN/skills/requesting-code-review-ko/SKILL.md"
if grep -q 'critic-ask.sh' "$RQ" && grep -q 'critic-prompt-diff.md' "$RQ" \
   && grep -q 'reviews/external-critic.md' "$RQ" \
   && awk '/### 외부 모델 의견 병행/,/^## /' "$RQ" | grep -q '판정 권한 없음'; then
  PASS=$((PASS+1)); echo "PASS T2.b requesting-code-review-ko 연결"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.b"
fi

# T2.c advisor-ko — 외부 위탁 경로 문서화 (세션 미접근 한계 포함) (AC-7)
AD="$PLUGIN/skills/advisor-ko/SKILL.md"
if grep -q 'critic-ask.sh' "$AD" && grep -q 'conversation' "$AD" \
   && grep -qE '(advisor disabled|disabled 환경)' "$AD"; then
  PASS=$((PASS+1)); echo "PASS T2.c advisor-ko 문서화"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.c"
fi

# ── T3 문서 등재 (AC-9) ──
if grep -q 'critic-ask.sh' "$PLUGIN/scripts/README.md"; then
  PASS=$((PASS+1)); echo "PASS T3.a scripts/README 등재"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.a"
fi

# ── T-ollama provider 정적 검증 (AC-5) ──

# T-ollama provider 로직 정적 검증 (실 위탁은 verify smoke — 토큰0)
SRC_FILE="$SCRIPT"   # critic-ask.sh 경로
if grep -q 'provider="ollama"' "$SRC_FILE" && grep -q 'api/generate' "$SRC_FILE" && grep -q 'CRITIC_MODEL' "$SRC_FILE"; then
  PASS=$((PASS+1)); echo "PASS T-ollama provider 로직(감지+API+CRITIC_MODEL) 존재"
else
  FAIL=$((FAIL+1)); echo "FAIL T-ollama provider 로직 누락"
fi

# T-ollama-2 CRITIC_BIN 최우선 보존 — ollama 설치돼도 CRITIC_BIN 우선 (디스패치 우선순위)
cat > "$TD/stub2.sh" <<'STUB2'
#!/usr/bin/env bash
cat >/dev/null; echo "stub-custom-opinion"
STUB2
chmod +x "$TD/stub2.sh"
out=$(CRITIC_BIN="$TD/stub2.sh" bash "$SCRIPT" "$TD/prompt.md"); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q "CRITIC\[custom\]"; then
  PASS=$((PASS+1)); echo "PASS T-ollama-2 CRITIC_BIN 최우선(ollama 무관)"
else
  FAIL=$((FAIL+1)); echo "FAIL T-ollama-2 (rc=$rc out=$out)"
fi

# ── T-claude provider 정적 검증 (advisor 백엔드 최우선 — opus 우선·sonnet fallback) ──

# T-claude provider 로직 존재 (감지 + --model/--fallback-model + CRITIC_CLAUDE_MODEL override)
if grep -q 'provider="claude"' "$SRC_FILE" \
   && grep -q -- '--fallback-model' "$SRC_FILE" \
   && grep -q 'CRITIC_CLAUDE_MODEL' "$SRC_FILE"; then
  PASS=$((PASS+1)); echo "PASS T-claude provider 로직(감지+fallback-model+CRITIC_CLAUDE_MODEL) 존재"
else
  FAIL=$((FAIL+1)); echo "FAIL T-claude provider 로직 누락"
fi

# T-claude-2 감지 우선순위: CRITIC_BIN > claude (custom override 가 claude 설치보다 우선)
out=$(CRITIC_BIN="$TD/stub2.sh" bash "$SCRIPT" "$TD/prompt.md"); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q "CRITIC\[custom\]"; then
  PASS=$((PASS+1)); echo "PASS T-claude-2 CRITIC_BIN 이 claude 보다 우선"
else
  FAIL=$((FAIL+1)); echo "FAIL T-claude-2 (rc=$rc out=$out)"
fi

# T-claude-3 기본 모델 = opus, fallback = sonnet (요구 계약)
if grep -q 'CRITIC_CLAUDE_MODEL:-opus' "$SRC_FILE" && grep -q 'CRITIC_CLAUDE_FALLBACK:-sonnet' "$SRC_FILE"; then
  PASS=$((PASS+1)); echo "PASS T-claude-3 기본 opus·fallback sonnet"
else
  FAIL=$((FAIL+1)); echo "FAIL T-claude-3 기본 모델 계약 누락"
fi

# ══ T4 (20261002-critic-readonly-flags): provider argv 읽기 전용 · fail closed — argv 기록 stub(실제 CLI·네트워크 미사용) ══
t4() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 — exp '$3' got '$2'"; fi; }
# mkprov DIR NAME HELP — --version·--help 에 응답하고, 그 밖 호출은 인자를 [인자] 줄로 기록하고 stdin 을 받아 의견을 낸다
mkprov() {
  mkdir -p "$1"
  cat > "$1/$2" <<STUB
#!/usr/bin/env bash
case "\$1" in --version) echo 1.0; exit 0 ;; esac
case "\$*" in *--help*) printf '%s\n' "$3"; exit 0 ;; esac
for a in "\$@"; do printf '[%s]\n' "\$a"; done > "$1/argv.$2"
cat > "$1/stdin.$2"
echo "$2 의견"
STUB
  chmod +x "$1/$2"
}
argv() { tr '\n' ',' < "$1"; }
runc() { env -i PATH="$1:/usr/bin:/bin" HOME="$HOME" bash "$SCRIPT" "$TD/prompt.md" --files "$TD/target.md" 2>&1; }
mkprov "$TD/p-claude" claude '  --tools <tools...>  Specify the list of available tools   --strict-mcp-config  Only use MCP servers from --mcp-config'
out=$(runc "$TD/p-claude")
t4 "T4.a claude 는 -p --tools \"\"(빈 인자 보존) --strict-mcp-config(전역 MCP 도구 차단) --model --fallback-model 로 호출되고 합성 프롬프트가 stdin 으로 간다" "$(printf '%s' "$out" | grep -c '^CRITIC\[claude\]:')|$(argv "$TD/p-claude/argv.claude")|$(grep -c '검토 지시문' "$TD/p-claude/stdin.claude")" "1|[-p],[--tools],[],[--strict-mcp-config],[--model],[opus],[--fallback-model],[sonnet],|1"
mkprov "$TD/p-codex" codex '      --sandbox <SANDBOX_MODE>  [possible values: read-only, workspace-write, danger-full-access]'
out=$(runc "$TD/p-codex")
t4 "T4.b codex 는 exec --sandbox read-only --ephemeral - 로 호출된다" "$(printf '%s' "$out" | grep -c '^CRITIC\[codex\]:')|$(argv "$TD/p-codex/argv.codex")" "1|[exec],[--sandbox],[read-only],[--ephemeral],[-],"
mkprov "$TD/p-gemini" gemini 'usage'
out=$(runc "$TD/p-gemini")
t4 "T4.c gemini 는 실측하지 못해 종전 그대로(-p -) — 추측 플래그를 넣지 않는다" "$(printf '%s' "$out" | grep -c '^CRITIC\[gemini\]:')|$(argv "$TD/p-gemini/argv.gemini")" "1|[-p],[-],"
mkprov "$TD/p-weak" claude 'usage: claude [options]'
mkprov "$TD/p-weak" codex '      --sandbox <SANDBOX_MODE>'
out=$(runc "$TD/p-weak")
t4 "T4.d fail closed: --tools 를 모르는 claude 는 플래그 없이 호출되지 않고 제외된다(stderr 사유 1줄) — 다음 후보 codex 로 cascade" "$(printf '%s' "$out" | grep -c '^CRITIC\[codex\]:')|$(printf '%s' "$out" | grep -c 'claude 가 읽기 전용 플래그를 지원하지 않음')|$([ -e "$TD/p-weak/argv.claude" ] && echo called || echo never)" "1|1|never"
mkprov "$TD/p-nomcp" claude '  --tools <tools...>  Specify the list of available tools'
out=$(runc "$TD/p-nomcp"); rc=$?
t4 "T4.g fail closed: --strict-mcp-config 를 모르는 claude(--tools 만 있음)는 전역 MCP 도구가 열린 채 호출되지 않고 제외된다" "$rc|$(printf '%s' "$out" | grep -c '^CRITIC: SKIP (외부 CLI 부재)')|$([ -e "$TD/p-nomcp/argv.claude" ] && echo called || echo never)" "0|1|never"
mkprov "$TD/p-weak2" codex 'usage: codex exec [OPTIONS]'
out=$(runc "$TD/p-weak2"); rc=$?
t4 "T4.e fail closed: --sandbox 를 모르는 codex 단독이면 SKIP + exit 0 이고 호출 기록이 없다" "$rc|$(printf '%s' "$out" | grep -c '^CRITIC: SKIP (외부 CLI 부재)')|$([ -e "$TD/p-weak2/argv.codex" ] && echo called || echo never)" "0|1|never"
rd=$(awk '/^## critic-ask.sh/ { on = 1; next } /^## / { on = 0 } on' "$PLUGIN/scripts/README.md")
kw() { if printf '%s\n' "$rd" | grep -qF -- "$1"; then printf y; else printf n; fi; }
t4 "T4.f 주석·README 에 실측 사실(버전)과 gemini 미실측 한계가 있고 '실측 미확인' 문구는 없다" "$(grep -c '실측 미확인' "$SCRIPT")|$(grep -c '2.1.287' "$SCRIPT")|$(grep -c '0.153.2' "$SCRIPT")|$(grep -c 'gemini 는 미설치라 실측하지 못했다' "$SCRIPT")|$(kw '--tools')$(kw 'read-only')$(kw 'fail closed')$(kw 'gemini')" "0|1|1|1|yyyy"

# T9 하류 저장소(cwd 에 templates/ 없음)에서 플러그인 프롬프트를 상대 경로로 불러도 찾는다
#   문서가 `critic-ask.sh templates/critic-prompt-plan.md` 로 적어 두어, 하류에서는 "prompt-file 부재"·rc=1 로 끝났다.
TD9=$(mktemp -d); printf '플랜\n' > "$TD9/plan.md"
cat > "$TD9/stub.sh" <<'STUB'
#!/usr/bin/env bash
cat > /dev/null
echo "의견 없음"
STUB
chmod +x "$TD9/stub.sh"
out=$(cd "$TD9" && CRITIC_BIN="$TD9/stub.sh" bash "$SCRIPT" templates/critic-prompt-plan.md --files plan.md 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '^CRITIC\[custom\]:' && ! echo "$out" | grep -q 'prompt-file 부재'; then
  PASS=$((PASS+1)); echo "PASS T9.a 하류 cwd + 플러그인 상대 경로 프롬프트 → 플러그인 루트에서 찾음"
else
  FAIL=$((FAIL+1)); echo "FAIL T9.a (rc=$rc out=$out)"
fi
# T9.b 어디에도 없는 프롬프트는 종전대로 rc=1 (사용 오류)
out=$(cd "$TD9" && CRITIC_BIN="$TD9/stub.sh" bash "$SCRIPT" templates/no-such-prompt.md 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q 'prompt-file 부재'; then
  PASS=$((PASS+1)); echo "PASS T9.b 없는 프롬프트 → rc=1 유지"
else
  FAIL=$((FAIL+1)); echo "FAIL T9.b (rc=$rc out=$out)"
fi
# T9.c cwd 에 같은 상대 경로의 파일이 있으면 그것이 우선이다 (사용자가 준 파일을 플러그인 것으로 바꿔치지 않는다)
mkdir -p "$TD9/templates"; printf 'LOCAL-PROMPT-MARK\n' > "$TD9/templates/critic-prompt-plan.md"
cat > "$TD9/stub2.sh" <<'STUB'
#!/usr/bin/env bash
cat
STUB
chmod +x "$TD9/stub2.sh"
out=$(cd "$TD9" && CRITIC_BIN="$TD9/stub2.sh" bash "$SCRIPT" templates/critic-prompt-plan.md 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q 'LOCAL-PROMPT-MARK'; then
  PASS=$((PASS+1)); echo "PASS T9.c cwd 의 파일이 우선"
else
  FAIL=$((FAIL+1)); echo "FAIL T9.c (rc=$rc out=$(echo "$out" | head -3))"
fi
# T9.d 폴백은 플러그인이 싣고 온 프롬프트 이름(templates/critic-prompt-*.md)에만 — 플러그인 루트의 다른 파일을 조용히 집지 않는다
TD9b=$(mktemp -d)
out=$(cd "$TD9b" && CRITIC_BIN="$TD9/stub2.sh" bash "$SCRIPT" README.md 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q 'prompt-file 부재'; then
  PASS=$((PASS+1)); echo "PASS T9.d 플러그인 루트의 다른 파일(README.md)은 폴백 대상 아님 → rc=1"
else
  FAIL=$((FAIL+1)); echo "FAIL T9.d (rc=$rc out=$(echo "$out" | head -2))"
fi
# T9.e 상위 경로(..)가 든 이름은 폴백하지 않는다
out=$(cd "$TD9b" && CRITIC_BIN="$TD9/stub2.sh" bash "$SCRIPT" 'templates/critic-prompt-../../README.md' 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q 'prompt-file 부재'; then
  PASS=$((PASS+1)); echo "PASS T9.e .. 가 든 이름은 폴백 없음 → rc=1"
else
  FAIL=$((FAIL+1)); echo "FAIL T9.e (rc=$rc out=$(echo "$out" | head -2))"
fi
# T9.f 폴백이 일어나면 무엇을 집었는지 알린다 (외부로 나가는 입력이다)
out=$(cd "$TD9b" && CRITIC_BIN="$TD9/stub.sh" bash "$SCRIPT" templates/critic-prompt-plan.md 2>&1 >/dev/null); rc=$?
if echo "$out" | grep -q 'CRITIC: prompt-file 을 플러그인에서 찾음: .*/templates/critic-prompt-plan.md'; then
  PASS=$((PASS+1)); echo "PASS T9.f 폴백 사실을 stderr 로 알림"
else
  FAIL=$((FAIL+1)); echo "FAIL T9.f (out=$out)"
fi
rm -rf "$TD9" "$TD9b"

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
