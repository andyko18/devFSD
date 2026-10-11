#!/usr/bin/env bash
# specops-ko · validate-context.sh 검증
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "$0")/../../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCRIPT="$PLUGIN/scripts/dag/validate-context.sh"


# ── fixture helpers ─────────────────────────────────────────────────────

# 5개 섹션 모두 유효한 완전한 context
make_valid_context() {
  local f="$1"
  cat > "$f" <<'EOF'
# Dispatch Context: task-1 (FID 20260101-test)

## 1. 담당 AC

- AC-1: Given X / When Y / Then Z

## 2. 관련 spec.md 섹션

- `.specops/20260101-test/spec.md` §2 포함 (line 10-30)
- `.specops/20260101-test/acceptance-criteria.md` AC-1

## 3. 테스트 명령

```bash
bash scripts/tests/test-feature.sh
```

기대 출력: `PASS=1 FAIL=0`

## 4. 수정 허용 파일 (whitelist)

- `scripts/feature.sh`
- `scripts/tests/test-feature.sh`

## 5. 작업 디렉터리

- `.worktrees/20260101-test-task-1/`
EOF
}

# ── T1: 기본 동작 ──────────────────────────────────────────────────────

# T1.a: 스크립트 존재
[ -f "$SCRIPT" ] && ok "T1.a script 존재" || fail "T1.a script 존재"

# T1.b: exec-bit
[ -x "$SCRIPT" ] && ok "T1.b exec-bit" || fail "T1.b exec-bit"

# T1.c: 인자 없음 → exit 2
bash "$SCRIPT" >/dev/null 2>&1
[ $? -eq 2 ] && ok "T1.c 인자 없음 → exit 2" || fail "T1.c 인자 없음 → exit 2"

# T1.d: 파일 미존재 → exit 2
bash "$SCRIPT" "/nonexistent/path.md" >/dev/null 2>&1
[ $? -eq 2 ] && ok "T1.d 파일 없음 → exit 2" || fail "T1.d 파일 없음 → exit 2"

# T1.e: 유효한 context → exit 0
tmp=$(mktemp)
make_valid_context "$tmp"
bash "$SCRIPT" "$tmp" >/dev/null 2>&1
[ $? -eq 0 ] && ok "T1.e 유효 context → exit 0" || fail "T1.e 유효 context → exit 0"
rm -f "$tmp"

# ── T2: 섹션별 누락 → exit 1 ──────────────────────────────────────────

# T2.a: §1 담당 AC 누락 → exit 1
T2_a() {
  local f
  f=$(mktemp)
  make_valid_context "$f"
  # AC-N 줄 제거
  sed -i.bak '/^- AC-/d' "$f"
  rm -f "${f}.bak"
  bash "$SCRIPT" "$f" >/dev/null 2>&1
  local rc=$?
  rm -f "$f"
  [ $rc -eq 1 ]
}
T2_a && ok "T2.a §1 AC 누락 → exit 1" || fail "T2.a §1 AC 누락 → exit 1"

# T2.b: §2 spec.md 경로 누락 → exit 1
T2_b() {
  local f
  f=$(mktemp)
  make_valid_context "$f"
  sed -i.bak '/\.specops\//d' "$f"
  rm -f "${f}.bak"
  bash "$SCRIPT" "$f" >/dev/null 2>&1
  local rc=$?
  rm -f "$f"
  [ $rc -eq 1 ]
}
T2_b && ok "T2.b §2 spec 경로 누락 → exit 1" || fail "T2.b §2 spec 경로 누락 → exit 1"

# T2.c: §3 테스트 명령 누락 (fenced block 없음) → exit 1
T2_c() {
  local f
  f=$(mktemp)
  cat > "$f" <<'EOF'
# Dispatch Context: task-1

## 1. 담당 AC

- AC-1: Given X / When Y / Then Z

## 2. 관련 spec.md 섹션

- `.specops/20260101-test/spec.md` §2 (line 10-30)

## 3. 테스트 명령

테스트 명령 미기재.

## 4. 수정 허용 파일 (whitelist)

- `scripts/feature.sh`

## 5. 작업 디렉터리

- `.worktrees/20260101-test-task-1/`
EOF
  bash "$SCRIPT" "$f" >/dev/null 2>&1
  local rc=$?
  rm -f "$f"
  [ $rc -eq 1 ]
}
T2_c && ok "T2.c §3 테스트 명령 없음 → exit 1" || fail "T2.c §3 테스트 명령 없음 → exit 1"

# T2.d: §4 whitelist 비어있음 (placeholder만) → exit 1
T2_d() {
  local f
  f=$(mktemp)
  make_valid_context "$f"
  sed -i.bak '/^- `scripts\//d' "$f"
  rm -f "${f}.bak"
  bash "$SCRIPT" "$f" >/dev/null 2>&1
  local rc=$?
  rm -f "$f"
  [ $rc -eq 1 ]
}
T2_d && ok "T2.d §4 whitelist 비어있음 → exit 1" || fail "T2.d §4 whitelist 비어있음 → exit 1"

# T2.e: §5 작업 디렉터리 누락 → exit 1
T2_e() {
  local f
  f=$(mktemp)
  make_valid_context "$f"
  sed -i.bak '/^- `\.worktrees\//d' "$f"
  rm -f "${f}.bak"
  bash "$SCRIPT" "$f" >/dev/null 2>&1
  local rc=$?
  rm -f "$f"
  [ $rc -eq 1 ]
}
T2_e && ok "T2.e §5 작업 디렉터리 없음 → exit 1" || fail "T2.e §5 작업 디렉터리 없음 → exit 1"

# ── T3: 오류 메시지 ────────────────────────────────────────────────────

# T3.a: 누락 시 stderr에 항목 출력
T3_a() {
  local f err
  f=$(mktemp)
  make_valid_context "$f"
  sed -i.bak '/^- AC-/d' "$f"
  rm -f "${f}.bak"
  err=$(bash "$SCRIPT" "$f" 2>&1 >/dev/null)
  rm -f "$f"
  echo "$err" | grep -q "담당 AC\|누락"
}
T3_a && ok "T3.a 누락 항목 stderr 출력" || fail "T3.a 누락 항목 stderr 출력"

# T3.b: 절대 경로도 §5로 허용 (/ 시작)
T3_b() {
  local f
  f=$(mktemp)
  cat > "$f" <<'EOF'
# Dispatch Context: task-1

## 1. 담당 AC

- AC-1: Given X / When Y / Then Z

## 2. 관련 spec.md 섹션

- `.specops/20260101-test/spec.md` §2 (line 10-30)

## 3. 테스트 명령

```bash
bash scripts/tests/test-feature.sh
```

## 4. 수정 허용 파일 (whitelist)

- `scripts/feature.sh`

## 5. 작업 디렉터리

- `/Users/dev/project/.worktrees/20260101-test-task-1/`
EOF
  bash "$SCRIPT" "$f" >/dev/null 2>&1
  local rc=$?
  rm -f "$f"
  [ $rc -eq 0 ]
}
T3_b && ok "T3.b §5 절대 경로 허용" || fail "T3.b §5 절대 경로 허용"

# ── T4: AC-R 단독 인식 ────────────────────────────────────────────────────

# T4.a: AC-R 단독 §1 통과 (AC-R-N 인식)
T4_a() {
  local tmp f
  tmp=$(mktemp -d)
  f="$tmp/ctx.md"
  cat > "$f" <<'CTX'
# Dispatch Context: T

## 1. 담당 AC

- AC-R-2: 회귀 무손상

## 2. 관련 spec.md 섹션

- .specops/x/spec.md

## 3. 테스트 명령

```bash
bash scripts/tests/run-all.sh
```

## 4. 수정 허용 파일 (whitelist)

- `foo.sh`

## 5. 작업 디렉터리

- `/tmp/x`
CTX
  local ret=0
  bash "$SCRIPT" "$f" >/dev/null 2>&1 || ret=1
  rm -rf "$tmp"
  return $ret
}
T4_a && ok "T4.a AC-R 단독 §1 통과 (AC-R-N 인식)" || fail "T4.a AC-R 단독 §1 통과 (AC-R-N 인식)"

# ── T5: §3 fence 상태 추적 ────────────────────────────────────────────────

# T5.a: 코드블록에 명령 없고 닫는 fence 뒤 산문만 → exit 1 (fence 누출 거짓 PASS 회귀)
T5_a() {
  local f
  f=$(mktemp)
  cat > "$f" <<'EOF'
# Dispatch Context: task-1

## 1. 담당 AC

- AC-1: Given X / When Y / Then Z

## 2. 관련 spec.md 섹션

- `.specops/20260101-test/spec.md` §2 (line 10-30)

## 3. 테스트 명령

```bash
# TODO
```

명령은 추후 기재 예정.

## 4. 수정 허용 파일 (whitelist)

- `scripts/feature.sh`

## 5. 작업 디렉터리

- `.worktrees/20260101-test-task-1/`
EOF
  bash "$SCRIPT" "$f" >/dev/null 2>&1
  local rc=$?
  rm -f "$f"
  [ $rc -eq 1 ]
}
T5_a && ok "T5.a §3 fence 뒤 산문 누출 차단 → exit 1" || fail "T5.a §3 fence 뒤 산문 누출 차단 → exit 1"

# T5.b: bash 아닌 fence(```text) 내용은 테스트 명령으로 미인식 → exit 1
T5_b() {
  local f
  f=$(mktemp)
  cat > "$f" <<'EOF'
# Dispatch Context: task-1

## 1. 담당 AC

- AC-1: Given X / When Y / Then Z

## 2. 관련 spec.md 섹션

- `.specops/20260101-test/spec.md` §2 (line 10-30)

## 3. 테스트 명령

```text
이것은 명령이 아님
```

## 4. 수정 허용 파일 (whitelist)

- `scripts/feature.sh`

## 5. 작업 디렉터리

- `.worktrees/20260101-test-task-1/`
EOF
  bash "$SCRIPT" "$f" >/dev/null 2>&1
  local rc=$?
  rm -f "$f"
  [ $rc -eq 1 ]
}
T5_b && ok "T5.b §3 비-bash fence 미인식 → exit 1" || fail "T5.b §3 비-bash fence 미인식 → exit 1"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
