#!/usr/bin/env bash
# U3 (wobbly §U3) — extract-test-commands.sh + run-verification.sh 검증
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
EXTRACT="$PLUGIN/scripts/_internal/extract-test-commands.sh"
RUN="$PLUGIN/scripts/_internal/run-verification.sh"


# ── T1.a extract: bash scripts/ 패턴 추출 ─────
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/tasks.md" <<'EOF'
# tasks
- [ ] **스텝 4**: 실행: `bash scripts/tests/test-foo.sh`
- [ ] **스텝 4**: 실행: `bash scripts/_internal/validate-structure.sh`
EOF
out=$(bash "$EXTRACT" "$TMPDIR/tasks.md")
if echo "$out" | grep -q "test-foo.sh" && echo "$out" | grep -q "validate-structure.sh"; then
  ok "T1.a extract → bash scripts/ 패턴 2건 추출"
else
  nope "T1.a" "out='$out'"
fi
rm -rf "$TMPDIR"

# ── T1.b extract: placeholder (<...>) 제외 ─────
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/tasks.md" <<'EOF'
- [ ] **스텝 3**: 실행: `bash scripts/_internal/init-project.sh "<프로젝트명>"`
- [ ] **스텝 4**: 실행: `bash scripts/tests/test-real.sh`
EOF
out=$(bash "$EXTRACT" "$TMPDIR/tasks.md")
if echo "$out" | grep -q "test-real.sh" && ! echo "$out" | grep -q '<'; then
  ok "T1.b extract → placeholder <...> 명령 제외"
else
  nope "T1.b" "out='$out'"
fi
rm -rf "$TMPDIR"

# ── T1.c extract: 빈 tasks.md → exit 1 (Wave 2 U2 — AC-4 "둘 다 부재") ──
TMPDIR=$(mktemp -d)
echo "" > "$TMPDIR/tasks.md"
out=$(bash "$EXTRACT" "$TMPDIR/tasks.md" 2>/dev/null)
ec=$?
if [ -z "$out" ] && [ "$ec" -eq 1 ]; then
  ok "T1.c extract → 빈 tasks.md exit 1 (Wave 2 U2 — 명령 0건)"
else
  nope "T1.c" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T1.d extract: tasks.md 부재 → exit 1 + stderr ──
out=$(bash "$EXTRACT" /tmp/nonexistent-$$.md 2>&1)
ec=$?
if [ "$ec" -eq 1 ] && echo "$out" | grep -q "not found"; then
  ok "T1.d extract → tasks.md 부재 exit 1 + stderr 'not found'"
else
  nope "T1.d" "ec=$ec out='$out'"
fi

# ── T2.a run: 모든 명령 PASS → exit 0 + 'VERIFY: PASS' ──
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.specops/fid-test"
cat > "$TMPDIR/.specops/fid-test/tasks.md" <<'EOF'
- [ ] **스텝 4**: 실행: `bash scripts/tests/dummy-pass.sh`
EOF
mkdir -p "$TMPDIR/scripts/tests"
echo '#!/usr/bin/env bash
exit 0' > "$TMPDIR/scripts/tests/dummy-pass.sh"
chmod +x "$TMPDIR/scripts/tests/dummy-pass.sh"
(cd "$TMPDIR" && out=$(bash "$RUN" fid-test 2>&1); ec=$?
 if [ "$ec" -eq 0 ] && echo "$out" | grep -q "VERIFY: PASS"; then
   echo "OK"
 else
   echo "FAIL ec=$ec out='$out'"
 fi) > "$TMPDIR/result"
if grep -q "^OK$" "$TMPDIR/result"; then
  ok "T2.a run → 모든 PASS exit 0 + 'VERIFY: PASS'"
else
  nope "T2.a" "$(cat "$TMPDIR/result")"
fi
rm -rf "$TMPDIR"

# ── T2.b run: 1건 FAIL → exit 1 + 'VERIFY: FAIL' stderr ──
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.specops/fid-test" "$TMPDIR/scripts/tests"
cat > "$TMPDIR/.specops/fid-test/tasks.md" <<'EOF'
- [ ] **스텝 4**: 실행: `bash scripts/tests/dummy-fail.sh`
EOF
echo '#!/usr/bin/env bash
exit 1' > "$TMPDIR/scripts/tests/dummy-fail.sh"
chmod +x "$TMPDIR/scripts/tests/dummy-fail.sh"
(cd "$TMPDIR" && bash "$RUN" fid-test >/tmp/run-stdout-$$ 2>/tmp/run-stderr-$$; ec=$?
 if [ "$ec" -eq 1 ] && grep -q "VERIFY: FAIL" /tmp/run-stderr-$$; then
   echo "OK"
 else
   echo "FAIL ec=$ec stderr='$(cat /tmp/run-stderr-$$)'"
 fi) > "$TMPDIR/result"
rm -f /tmp/run-stdout-$$ /tmp/run-stderr-$$
if grep -q "^OK$" "$TMPDIR/result"; then
  ok "T2.b run → 1건 FAIL exit 1 + 'VERIFY: FAIL' stderr"
else
  nope "T2.b" "$(cat "$TMPDIR/result")"
fi
rm -rf "$TMPDIR"

# ── T2.c run: 명령 추출 0건 → NOT_RUN + non-zero (PASS 금지) ──
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.specops/20260803-no-commands"
echo "no commands here" > "$TMPDIR/.specops/20260803-no-commands/tasks.md"
(cd "$TMPDIR" && out=$(bash "$RUN" 20260803-no-commands 2>&1); ec=$?
 state=$(bash "$PLUGIN/scripts/_internal/verification-state.sh" current 20260803-no-commands)
 if [ "$ec" -ne 0 ] && echo "$out" | grep -q "VERIFY: NOT_RUN" && [ "$state" = "NOT_RUN" ]; then
   echo "OK"
 else
   echo "FAIL ec=$ec state=$state out='$out'"
 fi) > "$TMPDIR/result"
if grep -q "^OK$" "$TMPDIR/result"; then
  ok "T2.c run → 명령 0건 NOT_RUN + non-zero"
else
  nope "T2.c" "$(cat "$TMPDIR/result")"
fi
rm -rf "$TMPDIR"

# ── T2.c2 PASS 실행은 상태 SoT와 verify 계측을 함께 남긴다 ──
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.specops/20260803-instrumented" "$TMPDIR/scripts/tests"
cat > "$TMPDIR/.specops/20260803-instrumented/tasks.md" <<'EOF'
- [ ] **스텝 4**: 실행: `bash scripts/tests/dummy-pass.sh`
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMPDIR/scripts/tests/dummy-pass.sh"
chmod +x "$TMPDIR/scripts/tests/dummy-pass.sh"
(cd "$TMPDIR" && bash "$RUN" 20260803-instrumented >/dev/null 2>&1)
state=$(cd "$TMPDIR" && bash "$PLUGIN/scripts/_internal/verification-state.sh" current 20260803-instrumented)
if [ "$state" = "PASS" ] \
   && jq -e 'select(.phase=="verify" and .verdict=="PASS" and .wall_ms >= 0)' \
      "$TMPDIR/.specops/20260803-instrumented/metrics.jsonl" >/dev/null 2>&1; then
  ok "T2.c2 PASS 상태·verify 계측 동시 기록"
else
  nope "T2.c2" "state=$state metric=$(cat "$TMPDIR/.specops/20260803-instrumented/metrics.jsonl" 2>/dev/null)"
fi
rm -rf "$TMPDIR"

# --- T5: 혼합 SSOT (Wave 2 U2 — FID 20260514) ---
FIXT="$PLUGIN/scripts/tests/extract-test-commands/fixtures"

# T5.a: YAML test_command 우선 — yaml-primary.md (test_command 기재)
out=$(bash "$PLUGIN/scripts/_internal/extract-test-commands.sh" "$FIXT/yaml-primary.md" 2>/dev/null)
if [[ "$out" == *"test-fromyaml.sh"* && "$out" != *"test-fromstep4.sh"* ]]; then
  PASS=$((PASS+1)); echo "PASS T5.a YAML test_command 우선"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.a (out='$out')"
fi

# T5.b: 구 FID fallback — fallback-step4.md (test_command 미기재, Step 4 라인 보유) → fallback + stderr WARN
err=$(mktemp)
out=$(bash "$PLUGIN/scripts/_internal/extract-test-commands.sh" "$FIXT/fallback-step4.md" 2>"$err")
if [[ "$out" == *"test-fromstep4.sh"* ]] && grep -q "WARN" "$err" && grep -q "falling back" "$err"; then
  PASS=$((PASS+1)); echo "PASS T5.b fallback + stderr WARN"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.b (out='$out' err=$(cat "$err"))"
fi
rm -f "$err"

# T5.c: 둘 다 부재 — empty.md → exit 1
out=$(bash "$PLUGIN/scripts/_internal/extract-test-commands.sh" "$FIXT/empty.md" 2>/dev/null; echo "exit=$?")
if echo "$out" | grep -q "exit=1"; then
  PASS=$((PASS+1)); echo "PASS T5.c 둘 다 부재 → exit 1"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.c"
fi

# ── T2.g run: downstream 표준 배치 bash tests/*.sh → 실행 + VERIFY: PASS ──
#   (20260716 trivial dogfood 발견 #3: whitelist 가 scripts/ 접두 하드코딩 — 플러그인 자기 repo
#    레이아웃 편향. 외부 프로젝트 표준 tests/·test/ 가 PARTIAL 로 떨어져 실행-근거 게이트 불인정
#    → 정직한 외부 완주가 커밋 deny → BYPASS 강요. 완주율 문(도달 14%)을 게이트가 직접 막던 결함)
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.specops/fid-test" "$TMPDIR/tests"
cat > "$TMPDIR/.specops/fid-test/tasks.md" <<'EOF'
- [ ] **스텝 4**: 실행: `bash tests/test-downstream.sh`
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMPDIR/tests/test-downstream.sh"
chmod +x "$TMPDIR/tests/test-downstream.sh"
(cd "$TMPDIR" && out=$(bash "$RUN" fid-test 2>&1); ec=$?
 if [ "$ec" -eq 0 ] && echo "$out" | grep -q "VERIFY: PASS"; then echo "OK"; else echo "FAIL ec=$ec out='$out'"; fi) > "$TMPDIR/result"
if grep -q "^OK$" "$TMPDIR/result"; then
  ok "T2.g run → downstream bash tests/*.sh 인정 (VERIFY: PASS)"
else
  nope "T2.g" "$(cat "$TMPDIR/result")"
fi
rm -rf "$TMPDIR"

# ── T2.h run: 앵커 잠금 — 절대경로·비테스트 디렉토리 bash 는 여전히 SKIP(PARTIAL) ──
#   YAML test_command 로 주입 — Step 4 fallback 은 extract 층에서 걸러져 whitelist 층이 안 돌므로
#   (T2.g 는 extract 층, 본 케이스는 whitelist 층을 각각 잠근다)
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.specops/fid-test" "$TMPDIR/lib"
cat > "$TMPDIR/.specops/fid-test/tasks.md" <<'EOF'
## 의존 그래프

```yaml
tasks:
  - id: T1
    depends_on: []
    inputs: []
    outputs: []
    ac: [AC-1]
    test_command: bash /tmp/evil.sh
  - id: T2
    depends_on: [T1]
    inputs: []
    outputs: []
    ac: [AC-1]
    test_command: bash lib/helper.sh
```
EOF
(cd "$TMPDIR" && out=$(bash "$RUN" fid-test 2>&1); ec=$?
 if [ "$ec" -eq 1 ] && echo "$out" | grep -q "VERIFY: PARTIAL" && ! echo "$out" | grep -q "VERIFY: PASS"; then echo "OK"; else echo "FAIL ec=$ec out='$out'"; fi) > "$TMPDIR/result"
if grep -q "^OK$" "$TMPDIR/result"; then
  ok "T2.h run → 절대경로·lib/ bash 여전히 SKIP (앵커 잠금)"
else
  nope "T2.h" "$(cat "$TMPDIR/result")"
fi
rm -rf "$TMPDIR"

# ── T2.d run: whitelist 거부 명령 → WARN stderr + skip + VERIFY:PARTIAL exit 1 ──
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.specops/fid-test"
printf '%s\n' \
  '## 의존 그래프' \
  '' \
  '```yaml' \
  'tasks:' \
  '  - id: T1' \
  '    test_command: "rm -rf /"' \
  '    depends_on: []' \
  '    inputs: []' \
  '    outputs: []' \
  '    ac: [AC-1]' \
  '```' \
  > "$TMPDIR/.specops/fid-test/tasks.md"
(cd "$TMPDIR" && bash "$RUN" fid-test >/tmp/t2d-out-$$ 2>/tmp/t2d-err-$$; ec=$?
 if [ "$ec" -eq 1 ] && grep -q "WARN: SKIP" /tmp/t2d-err-$$ && grep -q "VERIFY: PARTIAL" /tmp/t2d-out-$$; then
   echo "OK"
 else
   echo "FAIL ec=$ec err='$(cat /tmp/t2d-err-$$)' out='$(cat /tmp/t2d-out-$$)'"
 fi) > "$TMPDIR/result"
rm -f /tmp/t2d-out-$$ /tmp/t2d-err-$$
if grep -q "^OK$" "$TMPDIR/result"; then
  ok "T2.d run → whitelist 거부 명령 WARN + VERIFY:PARTIAL exit 1"
else
  nope "T2.d" "$(cat "$TMPDIR/result")"
fi
rm -rf "$TMPDIR"

# ── T2.e run: .. path traversal 차단 → WARN stderr + VERIFY:PARTIAL exit 1 ──
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.specops/fid-test"
printf '%s\n' \
  '## 의존 그래프' \
  '' \
  '```yaml' \
  'tasks:' \
  '  - id: T1' \
  '    test_command: "bash scripts/../../etc/passwd.sh"' \
  '    depends_on: []' \
  '    inputs: []' \
  '    outputs: []' \
  '    ac: [AC-1]' \
  '```' \
  > "$TMPDIR/.specops/fid-test/tasks.md"
(cd "$TMPDIR" && bash "$RUN" fid-test >/tmp/t2e-out-$$ 2>/tmp/t2e-err-$$; ec=$?
 if [ "$ec" -eq 1 ] && grep -q "WARN: SKIP" /tmp/t2e-err-$$ && grep -q "VERIFY: PARTIAL" /tmp/t2e-out-$$; then
   echo "OK"
 else
   echo "FAIL ec=$ec err='$(cat /tmp/t2e-err-$$)' out='$(cat /tmp/t2e-out-$$)'"
 fi) > "$TMPDIR/result"
rm -f /tmp/t2e-out-$$ /tmp/t2e-err-$$
if grep -q "^OK$" "$TMPDIR/result"; then
  ok "T2.e run → path traversal WARN + VERIFY:PARTIAL exit 1"
else
  nope "T2.e" "$(cat "$TMPDIR/result")"
fi
rm -rf "$TMPDIR"

# ── T2.f run: 혼합(bash PASS + make skip) → VERIFY:PARTIAL exit 1 (P0 거짓양성 방지) ──
#   20260713-verify-exec-gate: npm 이 화이트리스트에 편입되어 더 이상 skip 되지 않음 → skip 러너를 make 로 교체.
#   (make/gradle/mvn 은 의도적 미포함 — clarify D-1 YAGNI)
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.specops/fid-test" "$TMPDIR/scripts/tests"
echo '#!/usr/bin/env bash
exit 0' > "$TMPDIR/scripts/tests/dummy-pass.sh"
chmod +x "$TMPDIR/scripts/tests/dummy-pass.sh"
printf '%s\n' \
  '## 의존 그래프' \
  '' \
  '```yaml' \
  'tasks:' \
  '  - id: T1' \
  '    test_command: "bash scripts/tests/dummy-pass.sh"' \
  '    depends_on: []' \
  '    inputs: []' \
  '    outputs: []' \
  '    ac: [AC-1]' \
  '  - id: T2' \
  '    test_command: "make test"' \
  '    depends_on: []' \
  '    inputs: []' \
  '    outputs: []' \
  '    ac: [AC-2]' \
  '```' \
  > "$TMPDIR/.specops/fid-test/tasks.md"
(cd "$TMPDIR" && bash "$RUN" fid-test >/tmp/t2f-out-$$ 2>/tmp/t2f-err-$$; ec=$?
 if [ "$ec" -eq 1 ] && grep -q "VERIFY: PARTIAL" /tmp/t2f-out-$$ && grep -q "WARN: SKIP" /tmp/t2f-err-$$; then
   echo "OK"
 else
   echo "FAIL ec=$ec out='$(cat /tmp/t2f-out-$$)' err='$(cat /tmp/t2f-err-$$)'"
 fi) > "$TMPDIR/result"
rm -f /tmp/t2f-out-$$ /tmp/t2f-err-$$
if grep -q "^OK$" "$TMPDIR/result"; then
  ok "T2.f run → 혼합(bash PASS+make skip) VERIFY:PARTIAL exit 1 (P0 거짓양성 방지)"
else
  nope "T2.f" "$(cat "$TMPDIR/result")"
fi
rm -rf "$TMPDIR"

# ── T-multi: 다언어 러너 화이트리스트 (20260713-verify-exec-gate AC-1·AC-2·AC-3) ──
# 가짜 러너를 PATH 선점으로 주입 — 실제 pytest/npm 없이 exit 0 재현
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.specops/fid-multi" "$TMPDIR/bin"
printf '#!/bin/sh\necho "3 passed"\nexit 0\n' > "$TMPDIR/bin/pytest"
printf '#!/bin/sh\necho "ok"\nexit 0\n' > "$TMPDIR/bin/npm"
chmod +x "$TMPDIR/bin/pytest" "$TMPDIR/bin/npm"

# T-multi.a: pytest 실행 → VERIFY: PASS (AC-1·AC-3)
printf '%s\n' \
  '## 의존 그래프' \
  '' \
  '```yaml' \
  'tasks:' \
  '  - id: T1' \
  '    test_command: "pytest tests/"' \
  '```' \
  > "$TMPDIR/.specops/fid-multi/tasks.md"
out=$(cd "$TMPDIR" && PATH="$TMPDIR/bin:$PATH" bash "$RUN" fid-multi 2>&1)
if printf '%s' "$out" | grep -q 'VERIFY: PASS'; then
  ok "T-multi.a pytest 러너 실행 → VERIFY: PASS"
else
  nope "T-multi.a" "expected 'VERIFY: PASS', got: $out"
fi

# T-multi.b: npm test 실행 → VERIFY: PASS (AC-1 — 실행부 일반화가 bash 외 러너에도 동작하는지)
rm -f "$TMPDIR/.specops/fid-multi/evidence.md"
printf '%s\n' \
  '## 의존 그래프' '' '```yaml' 'tasks:' '  - id: T1' \
  '    test_command: "npm test"' '```' \
  > "$TMPDIR/.specops/fid-multi/tasks.md"
out=$(cd "$TMPDIR" && PATH="$TMPDIR/bin:$PATH" bash "$RUN" fid-multi 2>&1)
if printf '%s' "$out" | grep -q 'VERIFY: PASS'; then
  ok "T-multi.b npm test 실행 → VERIFY: PASS"
else
  nope "T-multi.b" "expected 'VERIFY: PASS', got: $out"
fi

# T-multi.c: 앵커 검증 — echo 위장 SKIP (AC-2)
rm -f "$TMPDIR/.specops/fid-multi/evidence.md"
printf '%s\n' \
  '## 의존 그래프' '' '```yaml' 'tasks:' '  - id: T1' \
  '    test_command: "echo pytest fake"' '```' \
  > "$TMPDIR/.specops/fid-multi/tasks.md"
out=$(cd "$TMPDIR" && PATH="$TMPDIR/bin:$PATH" bash "$RUN" fid-multi 2>&1)
if printf '%s' "$out" | grep -q 'PARTIAL'; then
  ok "T-multi.c echo 위장 → SKIP(PARTIAL)"
else
  nope "T-multi.c" "expected PARTIAL, got: $out"
fi

# T-multi.d: 앵커 검증 — 체이닝 위장 SKIP (AC-2)
rm -f "$TMPDIR/.specops/fid-multi/evidence.md"
printf '%s\n' \
  '## 의존 그래프' '' '```yaml' 'tasks:' '  - id: T1' \
  '    test_command: "pytest; rm -rf /tmp/x"' '```' \
  > "$TMPDIR/.specops/fid-multi/tasks.md"
out=$(cd "$TMPDIR" && PATH="$TMPDIR/bin:$PATH" bash "$RUN" fid-multi 2>&1)
if printf '%s' "$out" | grep -q 'PARTIAL'; then
  ok "T-multi.d 체이닝 위장 → SKIP(PARTIAL)"
else
  nope "T-multi.d" "expected PARTIAL, got: $out"
fi

# ── T-multi.e: 실패하는 non-bash 러너 → VERIFY: FAIL (else 분기 실패 경로 고정) ──
#   왜 필요한가: T-multi.a/b 는 else 분기(비-bash 러너)의 성공 경로만 고정한다.
#   run-verification.sh 의 `ec=$?` 가 실행 분기 밖 한 줄이라, 분기 안에 명령이 하나만 끼어들어도
#   그 status(0)를 캡처해 **실패한 러너가 VERIFY: PASS 로 샌다** (plan I-4 — 출하 직전까지 간 실증 함정).
#   후속 거버넌스 게이트가 'VERIFY: PASS' 문자열을 앵커하므로, 무증상 false green 은 실패 테스트를 통과로 연다.
#   → stdout·exit code·evidence 3중 단언으로 고정한다 (하나만 보면 회귀를 놓친다).
rm -f "$TMPDIR/.specops/fid-multi/evidence.md"
printf '#!/bin/sh\necho "1 failed"\nexit 1\n' > "$TMPDIR/bin/pytest"   # a/b 완료 후이므로 덮어써도 안전
chmod +x "$TMPDIR/bin/pytest"
printf '%s\n' \
  '## 의존 그래프' '' '```yaml' 'tasks:' '  - id: T1' \
  '    test_command: "pytest tests/"' '```' \
  > "$TMPDIR/.specops/fid-multi/tasks.md"
out=$(cd "$TMPDIR" && PATH="$TMPDIR/bin:$PATH" bash "$RUN" fid-multi 2>&1); ec=$?
if [ "$ec" -eq 1 ] \
   && printf '%s' "$out" | grep -q 'VERIFY: FAIL' \
   && grep -q 'RUN-VERIFICATION-RESULT: FAIL' "$TMPDIR/.specops/fid-multi/evidence.md" 2>/dev/null; then
  ok "T-multi.e 실패 러너(pytest exit 1) → VERIFY: FAIL + exit 1 + evidence FAIL"
else
  nope "T-multi.e" "expected exit 1 + 'VERIFY: FAIL' + evidence 'RUN-VERIFICATION-RESULT: FAIL'; got ec=$ec out: $out"
fi

# ── T-multi.f: 러너 미설치(exit 127) → VERIFY: FAIL (exit code 원문 전달) ──
#   한계 고백: 실제 미설치 대신 exit 127 을 내는 가짜 cargo 로 결정론적 재현.
#   (PATH 에서 실 러너만 골라 지울 수 없고, PATH 를 비우면 스크립트가 쓰는 기본 유틸까지 사라져 환경 의존이 된다.
#    bash 의 command-not-found 도 동일하게 ec=127 을 내므로 run-verification.sh 관점에서 두 경로는 같다.)
rm -f "$TMPDIR/.specops/fid-multi/evidence.md"
printf '#!/bin/sh\necho "cargo: command not found" >&2\nexit 127\n' > "$TMPDIR/bin/cargo"
chmod +x "$TMPDIR/bin/cargo"
printf '%s\n' \
  '## 의존 그래프' '' '```yaml' 'tasks:' '  - id: T1' \
  '    test_command: "cargo test"' '```' \
  > "$TMPDIR/.specops/fid-multi/tasks.md"
out=$(cd "$TMPDIR" && PATH="$TMPDIR/bin:$PATH" bash "$RUN" fid-multi 2>&1); ec=$?
if [ "$ec" -eq 1 ] \
   && printf '%s' "$out" | grep -q 'VERIFY: FAIL cargo test (exit=127)' \
   && grep -q 'RUN-VERIFICATION-RESULT: FAIL' "$TMPDIR/.specops/fid-multi/evidence.md" 2>/dev/null; then
  ok "T-multi.f 러너 미설치(exit 127) → VERIFY: FAIL (exit=127 원문)"
else
  nope "T-multi.f" "expected exit 1 + 'VERIFY: FAIL cargo test (exit=127)' + evidence FAIL; got ec=$ec out: $out"
fi
rm -rf "$TMPDIR"

# ── T-subdir: cd <subdir> && <runner> whitelist + exec (false-block 9호) ──
# 헬퍼: 임시 FID tasks.md(YAML test_command) 구성 → run-verification 실행 → evidence 검사
_mk_fid() {  # $1=test_command  → echo FIDDIR
  local d; d=$(mktemp -d)
  mkdir -p "$d/.specops/FID"
  # `## 의존 그래프` 헤더 + 행두 ```yaml 펜스 필수 — dag::extract_yaml 전제(리뷰 R2 Critical 대응).
  #   헤더 없으면 extract_yaml 빈출력 → Step4 grep fallback → 명령 0건 → VERIFY: NO COMMANDS(whitelist 미도달).
  cat > "$d/.specops/FID/tasks.md" <<YAML
## 의존 그래프

\`\`\`yaml
tasks:
  - id: T1
    test_command: "$1"
\`\`\`
YAML
  echo "$d"
}
# subdir 러너 픽스처(인용부 없음): $D/sub/tests/x.sh 에 exit 코드 스크립트 생성
_mk_subrunner() {  # $1=FIDDIR $2=exitcode
  mkdir -p "$1/sub/tests"; printf 'exit %s\n' "$2" > "$1/sub/tests/x.sh"
}

# T-subdir.a: cd sub && bash tests/x.sh (exit 0) → 실행 + PASS (AC-1, AC-2 정상경로)
D=$(_mk_fid 'cd sub && bash tests/x.sh'); _mk_subrunner "$D" 0
out=$(cd "$D" && bash "$RUN" FID 2>&1); ec=$?
if echo "$out" | grep -q "VERIFY: PASS" && ! echo "$out" | grep -q "SKIP 'cd sub"; then
  ok "T-subdir.a cd sub && bash 러너 → 실행·PASS"
else nope "T-subdir.a" "ec=$ec out='$out'"; fi
rm -rf "$D"

# T-subdir.b: cd sub && bash tests/x.sh (exit 1) → 실행 + FAIL 정직포착 (AC-2 실패경로)
D=$(_mk_fid 'cd sub && bash tests/x.sh'); _mk_subrunner "$D" 1
out=$(cd "$D" && bash "$RUN" FID 2>&1); ec=$?
if echo "$out" | grep -q "VERIFY: FAIL" && [ "$ec" -ne 0 ]; then
  ok "T-subdir.b cd sub && 실패러너 → FAIL 정직포착"
else nope "T-subdir.b" "ec=$ec out='$out'"; fi
rm -rf "$D"

# T-subdir.c: npx/exec 러너형 매칭 (AC-3) — 실제 스크립트의 단일라인 패턴 추출해 대조
#   Step3 이 _WHITELIST_PAT 를 단일라인 단일따옴표로 유지하므로 sed 추출이 유효(리뷰 Critical#3 대응)
source_pat() { grep -m1 "^_WHITELIST_PAT=" "$RUN" | sed -E "s/^_WHITELIST_PAT='(.*)'\$/\1/"; }
PAT=$(source_pat)
pass_c=1
# FIX-B(#5): npx/exec 인자에 @ 허용 — bin 은 @scope/pkg 허용하면서 인자 --config=@scope/x 는
#   SKIP 되던 비대칭 해소. "cd sub && npx vitest --config=@scope/x" 가 매칭돼야 함.
for c in "cd apps/web && npx vitest run" "pnpm exec jest" "yarn exec mocha" "npx jest --ci" "cd sub && npx vitest --config=@scope/x"; do
  [[ "$c" =~ $PAT ]] && [[ "$c" != *..* ]] || { pass_c=0; echo "  miss: $c"; }
done
[ "$pass_c" = 1 ] && ok "T-subdir.c npx/exec 러너형 5종 매칭(인자 @ 포함)" || nope "T-subdir.c" "PAT 매칭 실패"

# T-subdir.d: 차단 유지 (AC-4) — 트래버설·절대경로·임의체인·비러너·bare
#   FIX-A(#3+#4): npx/exec bin 토큰 선두 char 를 [A-Za-z0-9_@] 로 제한 →
#     선두 '/'(절대경로 npx /abs/path)·선두 '-'(옵션주입 npx --yes pkg) 차단.
pass_d=1
for c in "cd ../evil && npx vitest" "cd /abs && npx vitest" "foo && bar" "cd sub && rm -rf x" "pnpm vitest" \
         "npx /abs/path" "cd sub && npx /etc/x" "npx --yes pkg" "pnpm exec -c foo"; do
  if [[ "$c" =~ $PAT ]] && [[ "$c" != *..* ]]; then pass_d=0; echo "  leak: $c"; fi
done
[ "$pass_d" = 1 ] && ok "T-subdir.d 트래버설/절대/임의체인/비러너/bare/npx선두char 차단" || nope "T-subdir.d" "차단 누출"

# T-subdir.e: 기존 통과형 무손상 (AC-R-1)
pass_e=1
for c in "pnpm test" "bash scripts/tests/run-all.sh" "pytest tests/foo.py" "go test ./pkg"; do
  [[ "$c" =~ $PAT ]] && [[ "$c" != *..* ]] || { pass_e=0; echo "  regress: $c"; }
done
[ "$pass_e" = 1 ] && ok "T-subdir.e 기존 통과형 무손상" || nope "T-subdir.e" "회귀"

# T-subdir.f: run-verification 루프 내 cwd 비오염 (AC-2 ③) — FIX-C(#2) 재작성.
#   구버전은 부모 셸 pwd 를 검사했으나 `bash "$RUN"` 은 자식 프로세스라 부모 pwd 는 어떤 구현이든
#   불변 → 공허(vacuous). 실제 위험은 run-verification **자신의 while 루프 내** cwd 오염이다:
#   한 명령의 `cd sub` 가 서브셸로 격리되지 않으면 후속 명령의 cwd 를 오염시킨다.
#   → 2-command tasks.md 로 검증: T1(`cd sub`)이 먼저 실행(pollute 후보), T2 는 pwd 를 파일에 기록.
#   ★ T2 를 `bash tests/probe.sh` 로 못 쓰는 이유: extract 의 `sort -u`(extract-test-commands.sh:31)가
#     'bash…' < 'cd…' 로 정렬 → probe 가 cd 보다 **먼저** 실행되어 다시 공허해진다. 그래서 T2 를
#     'cd' 뒤로 정렬되는 `pytest`(선두 'p')로 두고, PATH 주입 가짜 pytest 가 cwd 와 무관히 실행되며
#     자신의 pwd 를 기록하게 한다 — 오염 시 pwd 가 $D/sub 로 바뀌어 포착된다.
D=$(mktemp -d); mkdir -p "$D/.specops/FID" "$D/sub/tests" "$D/bin"
cat > "$D/.specops/FID/tasks.md" <<YAML
## 의존 그래프

\`\`\`yaml
tasks:
  - id: T1
    test_command: "cd sub && bash tests/x.sh"
  - id: T2
    test_command: "pytest"
\`\`\`
YAML
printf 'exit 0\n' > "$D/sub/tests/x.sh"
# 가짜 pytest: 실행 위치(pwd)를 파일로 남긴다 — run-verification 루프의 실제 cwd 를 드러냄.
printf '#!/bin/sh\npwd > "%s/probe-out"\nexit 0\n' "$D" > "$D/bin/pytest"
chmod +x "$D/bin/pytest"
expected=$(cd "$D" && pwd)   # pwd 시맨틱 정규화(macOS 심링크 대비) — run-verification 도 동일 경로에서 시작
(cd "$D" && PATH="$D/bin:$PATH" bash "$RUN" FID >/dev/null 2>&1)
probe=$(cat "$D/probe-out" 2>/dev/null)
if [ -n "$probe" ] && [ "$probe" = "$expected" ]; then
  ok "T-subdir.f run-verification 루프 내 cwd 비오염 (서브셸 exec — 후속 명령 pwd 보존)"
else
  nope "T-subdir.f" "probe='$probe' expected='$expected' (cwd 오염 의심)"
fi
rm -rf "$D"

# ── T-subdir.g: cd 실패(부재 subdir) 진단이 evidence 출력블록에 캡처됨 (Imp1 — L12 투명성) ──
#   버그: `2>&1` 가 러너에만 결속되면 `cd` 실패 시 진단이 스크립트 stderr 로 유출 → evidence 출력블록이
#   빈 채 exit 만 기록(투명성 위반). 그룹 `{ cd && runner; } 2>&1` 로 감싸야 cd 진단까지 캡처된다.
#   ★ evidence 파일에 단언(테스트 out 아님) — out 은 러너 stderr 를 folding 하므로 버그에도 통과(vacuous).
#     FIX-D(#6): 앵커를 로케일 불변 'cd:'(셸 빌트인명) 단독으로. 'No such file' 은 LANG 에 따라
#     번역돼(예: ko_KR '그런 파일이나 디렉터리가 없습니다') non-C 로케일에서 헛디딜 수 있다.
#     한계 고백: 'cd:' 는 셸 진단 접두라 로케일 불변이나, 셸 구현이 이 접두를 바꾸면 재검토 필요.
D=$(_mk_fid 'cd nosuchdir && bash tests/x.sh')   # nosuchdir 미생성 → cd 실패
out=$(cd "$D" && bash "$RUN" FID 2>&1); ec=$?
ev="$D/.specops/FID/evidence.md"
if grep -q "cd:" "$ev" 2>/dev/null; then
  ok "T-subdir.g cd 실패 진단 evidence 캡처 (Imp1 투명성)"
else nope "T-subdir.g" "ec=$ec evidence='$(cat "$ev" 2>/dev/null)'"; fi
rm -rf "$D"

# ── T-subdir.h: SKIP 힌트가 새 지원형 광고 (Imp2 — 힌트 불신→BYPASS 도피 차단) ──
#   비동작 문자열 계약. 힌트가 npx·pnpm|yarn exec·cd subdir 접두·bare 미지원 안내를 담는지 grep 단언.
hint=$(grep -m1 "WARN: SKIP '\$cmd'" "$RUN")
pass_h=1
for token in "npx" "exec" "cd " "bare"; do
  echo "$hint" | grep -q "$token" || { pass_h=0; echo "  hint 누락: $token"; }
done
[ "$pass_h" = 1 ] && ok "T-subdir.h SKIP 힌트 새 지원형 광고 (Imp2)" || nope "T-subdir.h" "hint='$hint'"

# ── T-wl: whitelist 접두·플래그 확장 (FID 20260903-runner-whitelist-prefix) ──
#   정규식은 **파일에서 읽는다** — 테스트가 자기 사본을 들면 그게 4번째 드리프트 지점이 된다.
_wl_pat=$(grep -oE "\^\(cd\[\[:blank:\]\]\+.*\)\\\$" "$PLUGIN/scripts/_internal/run-verification.sh" | head -1)
_wl_chk() {  # <cmd> <기대 PASS|BLOCK> <id>
  local c="$1" want="$2" id="$3" got
  if [[ "$c" =~ $_wl_pat ]] && [[ "$c" != *..* ]]; then got=PASS; else got=BLOCK; fi
  if [ "$got" = "$want" ]; then
    PASS=$((PASS+1)); echo "PASS $id ($want) $c"
  else
    FAIL=$((FAIL+1)); echo "FAIL $id 기대 $want 실제 $got — $c"
  fi
}
# AC-1 관측 3계열
_wl_chk 'pnpm --dir frontend test chart-wiring'                  PASS  T-wl.a
_wl_chk 'pnpm --filter @ssl-portal/web test'                     PASS  T-wl.b
_wl_chk 'poetry run pytest tests/unit/test_scheduler.py -q'      PASS  T-wl.c
# AC-2 미관측 3형태
_wl_chk 'uv run pytest tests/unit -q'                            PASS  T-wl.d
_wl_chk 'npm run test:unit'                                      PASS  T-wl.e
_wl_chk 'yarn workspace web test'                                PASS  T-wl.f
# AC-3 우회 차단
_wl_chk 'pnpm --dir ../evil test'                                BLOCK T-wl.g
_wl_chk 'pnpm --dir /etc test'                                   BLOCK T-wl.h
_wl_chk 'pnpm --filter -rf test'                                 BLOCK T-wl.i
# AC-3 보강 — -w 는 매니저별 의미 충돌로 의도적 제외 (plan-review I-2)
_wl_chk 'pnpm -w test'                                           BLOCK T-wl.j
# AC-R-1 baseline 6형태 불변
_wl_chk 'bash scripts/tests/run-all.sh'                          PASS  T-wl.k
_wl_chk 'pytest tests/unit -q'                                   PASS  T-wl.l
_wl_chk 'npm test'                                               PASS  T-wl.m
_wl_chk 'npm run test'                                           PASS  T-wl.n
_wl_chk 'cd apps/web && npx vitest run'                          PASS  T-wl.o
_wl_chk 'pnpm exec vitest run'                                   PASS  T-wl.p
# 음성 회귀
_wl_chk 'echo pytest'                                            BLOCK T-wl.q
_wl_chk 'rm -rf /'                                               BLOCK T-wl.r
_wl_chk 'pnpm vitest'                                            BLOCK T-wl.s

# ── T2.h2 run: 비테스트 디렉토리(lib/) bash 는 **그것만으로** SKIP(PARTIAL) ──
#   T2.h 는 절대경로 명령과 한 픽스처라, 절대경로가 이미 PARTIAL 을 만들어 lib/ 를 허용해도 통과했다(변이 실측 20261009).
#   lib/helper.sh 는 실재하고 exit 0 이다 — whitelist 가 막지 않으면 실행돼 PASS 가 된다.
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.specops/fid-test" "$TMPDIR/lib"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMPDIR/lib/helper.sh"
cat > "$TMPDIR/.specops/fid-test/tasks.md" <<'EOF'
## 의존 그래프

```yaml
tasks:
  - id: T1
    depends_on: []
    inputs: []
    outputs: []
    ac: [AC-1]
    test_command: bash lib/helper.sh
```
EOF
(cd "$TMPDIR" && out=$(bash "$RUN" fid-test 2>&1); ec=$?
 if [ "$ec" -eq 1 ] && echo "$out" | grep -qE "VERIFY: (PARTIAL|NOT_RUN)" && ! echo "$out" | grep -q "VERIFY: PASS"; then echo "OK"; else echo "FAIL ec=$ec out='$out'"; fi) > "$TMPDIR/result"
if grep -q "^OK$" "$TMPDIR/result"; then
  ok "T2.h2 run → lib/ bash 단독도 SKIP (PASS 아님)"
else
  nope "T2.h2" "$(cat "$TMPDIR/result")"
fi
rm -rf "$TMPDIR"

# ── T2.i run: 실패한 명령 수가 판정 기록에 남는다 (verification-state.json 의 failed) ──
#   실패 집계를 0 으로 고정해도 어떤 테스트도 실패하지 않았다(변이 실측 20261009) — FAIL 판정 자체는 다른 변수가 만든다.
TMPDIR=$(mktemp -d); _FIDF=20261009-failcount
mkdir -p "$TMPDIR/.specops/$_FIDF" "$TMPDIR/tests"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMPDIR/tests/a.sh"; printf '#!/usr/bin/env bash\nexit 3\n' > "$TMPDIR/tests/b.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMPDIR/tests/c.sh"
cat > "$TMPDIR/.specops/$_FIDF/tasks.md" <<'EOF'
## 의존 그래프

```yaml
tasks:
  - id: T1
    depends_on: []
    inputs: []
    outputs: []
    ac: [AC-1]
    test_command: bash tests/a.sh
  - id: T2
    depends_on: []
    inputs: []
    outputs: []
    ac: [AC-1]
    test_command: bash tests/b.sh
  - id: T3
    depends_on: []
    inputs: []
    outputs: []
    ac: [AC-1]
    test_command: bash tests/c.sh
```
EOF
(cd "$TMPDIR" && git init -q && bash "$RUN" "$_FIDF" >/dev/null 2>&1)
_st="$TMPDIR/.specops/$_FIDF/verification-state.json"
if [ -f "$_st" ] && [ "$(jq -r '.verdict' "$_st")" = "FAIL" ] && [ "$(jq -r '.failed' "$_st")" = "2" ] && [ "$(jq -r '.executed' "$_st")" = "3" ]; then
  ok "T2.i run → 3건 실행·2건 실패가 판정 기록에 남는다"
else
  nope "T2.i" "state=$(cat "$_st" 2>/dev/null | tr -d '\n' | cut -c1-200)"
fi
rm -rf "$TMPDIR"

echo ""
echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
