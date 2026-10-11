#!/usr/bin/env bash
# specops-ko · rotate-evaluator-artifact + inject-evaluator-timestamp 검증
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
ROTATE="$PLUGIN/hooks/rotate-evaluator-artifact.sh"
INJECT="$PLUGIN/hooks/inject-evaluator-timestamp.sh"

source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

setup_file() {
  local f="$1"
  cat > "$f" <<'EOF'
# Clarifications

**status**: RESOLVED
**timestamp**: 2026-01-01T00:00:00Z

## Q1
내용
EOF
}

# ── rotate-evaluator-artifact.sh ──────────────────────────────────────

# T1.a: 스크립트 존재 + exec-bit
[ -x "$ROTATE" ] && ok "T1.a rotate 존재·exec-bit" || fail "T1.a rotate 존재·exec-bit"

# T1.b: 인자 없음 → exit 1 + usage 출력
T1_b_out=$(bash "$ROTATE" 2>&1)
T1_b_rc=$?
[ $T1_b_rc -eq 1 ] && echo "$T1_b_out" | grep -qi "사용법\|usage" \
  && ok "T1.b rotate 인자 없음 → exit 1" || fail "T1.b rotate 인자 없음 → exit 1"

# T1.c: 파일 미존재 → exit 0 (no-op)
tmp=$(mktemp -d)
bash "$ROTATE" "$tmp/nonexistent.md" >/dev/null 2>&1
[ $? -eq 0 ] && ok "T1.c rotate 파일 없음 → exit 0" || fail "T1.c rotate 파일 없음 → exit 0"

# T1.d: 기존 파일 → 아카이브 파일 생성 + 원본 사라짐
setup_file "$tmp/clarifications.md"
bash "$ROTATE" "$tmp/clarifications.md" >/dev/null 2>&1
archived=$(find "$tmp" -name "clarifications-*.md" 2>/dev/null | head -1)
[ ! -f "$tmp/clarifications.md" ] && [ -n "$archived" ] \
  && ok "T1.d rotate 아카이브 생성" || fail "T1.d rotate 아카이브 생성"

# T1.e: 아카이브 파일에 타임스탬프 포함 (YYYYMMDDTHHmmss 형식)
echo "$archived" | grep -qE 'clarifications-[0-9]{8}T[0-9]{6}\.md' \
  && ok "T1.e rotate 아카이브 파일명 타임스탬프 포맷" || fail "T1.e rotate 아카이브 파일명 타임스탬프 포맷"

# T1.f: 아카이브 내용 보존 (원본 내용 유지)
grep -q "RESOLVED" "$archived" 2>/dev/null \
  && ok "T1.f rotate 아카이브 내용 보존" || fail "T1.f rotate 아카이브 내용 보존"

rm -rf "$tmp"

# ── inject-evaluator-timestamp.sh ────────────────────────────────────

# T2.a: 스크립트 존재 + exec-bit
[ -x "$INJECT" ] && ok "T2.a inject 존재·exec-bit" || fail "T2.a inject 존재·exec-bit"

# T2.b: 인자 없음 → exit 1
bash "$INJECT" >/dev/null 2>&1
[ $? -eq 1 ] && ok "T2.b inject 인자 없음 → exit 1" || fail "T2.b inject 인자 없음 → exit 1"

# T2.c: 파일 없음 → exit 1
bash "$INJECT" "/nonexistent/path.md" >/dev/null 2>&1
[ $? -eq 1 ] && ok "T2.c inject 파일 없음 → exit 1" || fail "T2.c inject 파일 없음 → exit 1"

# T2.d: **timestamp**: 기존 줄 교체 (갱신)
tmp=$(mktemp -d)
setup_file "$tmp/clarifications.md"
bash "$INJECT" "$tmp/clarifications.md" >/dev/null 2>&1
ts_count=$(grep -c '^\*\*timestamp\*\*:' "$tmp/clarifications.md")
ts_line=$(grep '^\*\*timestamp\*\*:' "$tmp/clarifications.md")
[ "$ts_count" -eq 1 ] && echo "$ts_line" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T' \
  && ok "T2.d inject 기존 timestamp 교체 (1개, ISO-8601)" || fail "T2.d inject 기존 timestamp 교체"

# T2.e: **timestamp**: 없는 파일 → **status**: 뒤에 삽입
echo "**status**: RESOLVED" > "$tmp/no-ts.md"
bash "$INJECT" "$tmp/no-ts.md" >/dev/null 2>&1
grep -q '^\*\*timestamp\*\*:' "$tmp/no-ts.md" \
  && ok "T2.e inject timestamp 없는 파일 → 주입" || fail "T2.e inject timestamp 없는 파일 → 주입"

# T2.e2: status 뒤에 본문 줄이 있는 파일 — 삽입 텍스트 뒤 개행 보존 (BSD sed a\ 융합 회귀)
#   기존 T2.e 는 status 가 마지막 줄이라 "**timestamp**: ...Zbody" 융합을 못 잡았다 (dogfood 실측).
printf '**status**: RESOLVED\nbody-line\n' > "$tmp/mid-ts.md"
bash "$INJECT" "$tmp/mid-ts.md" >/dev/null 2>&1
grep -q '^\*\*timestamp\*\*: [0-9T:Z-]*$' "$tmp/mid-ts.md" && grep -qx 'body-line' "$tmp/mid-ts.md" \
  && ok "T2.e2 inject 중간 삽입 — 다음 줄 융합 없음" || fail "T2.e2 inject 중간 삽입 — 다음 줄 융합 없음"

# T2.f: 반복 호출 → timestamp 행 1개만 유지
bash "$INJECT" "$tmp/clarifications.md" >/dev/null 2>&1
bash "$INJECT" "$tmp/clarifications.md" >/dev/null 2>&1
ts_count_after=$(grep -c '^\*\*timestamp\*\*:' "$tmp/clarifications.md")
[ "$ts_count_after" -eq 1 ] \
  && ok "T2.f inject 반복 호출 → timestamp 1개 유지" || fail "T2.f inject 반복 호출 → timestamp 1개 유지"

rm -rf "$tmp"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
