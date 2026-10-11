#!/usr/bin/env bash
# scope-explain.sh — 면제 조회 CLI 스위트 (20260910-commit-scope-prelude AC-5)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SE="$PLUGIN/scripts/_internal/scope-explain.sh"
_G=$(printf 'g%sit' ''); _C=$(printf 'c%sommit' '')

_se_case() {  # $1 label  $2 기대 grep 패턴  $3 명령
  local out; out=$(bash "$SE" "$3" 2>&1); local rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qE "$2"; then
    PASS=$((PASS+1)); echo "PASS $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL $1 (rc=$rc out=$out)"
  fi
}

_se_case "T-se.a 축소 형태 SCOPE=staged"  '^SCOPE=staged '        "$_G $_C -m 'docs: x'"
_se_case "T-se.b 보수 형태 SCOPE=conservative" '^SCOPE=conservative ' "$_G $_C -am 'x'"
_se_case "T-se.c 출력 3필드 고정"          'SCOPE=.* EXEMPT=(yes|no) REASON=' "$_G $_C -m x"

# T-se.d stdin 경로 — 인자 없이 파이프
out=$(printf '%s' "$_G $_C -m 'docs: x'" | bash "$SE" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^SCOPE=staged '; then
  PASS=$((PASS+1)); echo "PASS T-se.d stdin 경로"
else
  FAIL=$((FAIL+1)); echo "FAIL T-se.d (rc=$rc out=$out)"
fi

# T-se.e 판정 사본 금지 — 스크립트가 governance-lib 를 source 하고 자체 정규식을 두지 않는다
if grep -q 'governance-lib.sh' "$SE" && ! grep -qE "git[[:space:]]+commit'?\)" "$SE"; then
  PASS=$((PASS+1)); echo "PASS T-se.e 판정 사본 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T-se.e 판정 로직 사본 의심"
fi

# ── 판정 불가를 판정으로 위장하지 않는다 (부모 판단 2026-09-10) ──────────────
# T-se.k 라이브러리 부재 → rc≠0 + stderr 사유. 사본을 lib 없는 트리에 두어 재현한다.
_tmp=$(mktemp -d); mkdir -p "$_tmp/scripts/_internal"
cp "$SE" "$_tmp/scripts/_internal/scope-explain.sh"
out=$(bash "$_tmp/scripts/_internal/scope-explain.sh" "$_G $_C -m x" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'governance-lib.sh' && ! printf '%s' "$out" | grep -q '^SCOPE='; then
  PASS=$((PASS+1)); echo "PASS T-se.k 라이브러리 부재 → 판정 거부"
else
  FAIL=$((FAIL+1)); echo "FAIL T-se.k (rc=$rc out=$out)"
fi

# T-se.l 라이브러리는 있으나 판정 함수 미정의 → rc≠0 + 함수명 사유
mkdir -p "$_tmp/hooks"; : > "$_tmp/hooks/governance-lib.sh"
out=$(bash "$_tmp/scripts/_internal/scope-explain.sh" "$_G $_C -m x" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '_commit_scope_is_staged' && ! printf '%s' "$out" | grep -q '^SCOPE='; then
  PASS=$((PASS+1)); echo "PASS T-se.l 판정 함수 미정의 → 판정 거부"
else
  FAIL=$((FAIL+1)); echo "FAIL T-se.l (rc=$rc out=$out)"
fi
rm -rf "$_tmp"

# T-se.m 양성 대조군 — 같은 입력이 정상 트리(lib 존재)에서는 rc=0 + 1줄
out=$(bash "$SE" "$_G $_C -m x" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^SCOPE='; then
  PASS=$((PASS+1)); echo "PASS T-se.m 양성 대조군 정상 rc=0"
else
  FAIL=$((FAIL+1)); echo "FAIL T-se.m (rc=$rc out=$out)"
fi

# T-se.n 빈 stdin → usage + rc=2 (빈 명령을 conservative 로 답하지 않는다)
out=$(bash "$SE" </dev/null 2>&1); rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'usage:' && ! printf '%s' "$out" | grep -q '^SCOPE='; then
  PASS=$((PASS+1)); echo "PASS T-se.n 빈 stdin → rc=2"
else
  FAIL=$((FAIL+1)); echo "FAIL T-se.n (rc=$rc out=$out)"
fi

# T-se.o 읽히지 않는 stdin(쓰는 쪽이 열린 채 데이터 없음) → 행(hang) 금지, rc=2
#   fifo 로 재현한다. mkfifo 없으면 어서션을 넣지 않는다(불안정 어서션 금지 — 카운트 미반영 SKIP).
if command -v mkfifo >/dev/null 2>&1; then
  _fifo=$(mktemp -u)
  if mkfifo "$_fifo" 2>/dev/null; then
    exec 9<>"$_fifo"                      # 쓰는 쪽을 열어 두어 EOF 가 오지 않게 한다
    out=$(SPECOPS_SCOPE_STDIN_TIMEOUT=1 bash "$SE" <"$_fifo" 2>&1); rc=$?
    exec 9>&-; rm -f "$_fifo"
    if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '안에 읽지 못했다' && ! printf '%s' "$out" | grep -q '^SCOPE='; then
      PASS=$((PASS+1)); echo "PASS T-se.o 블로킹 stdin → 행 없이 rc=2"
    else
      FAIL=$((FAIL+1)); echo "FAIL T-se.o (rc=$rc out=$out)"
    fi
  else
    echo "SKIP T-se.o (mkfifo 실패)"
  fi
else
  echo "SKIP T-se.o (mkfifo 부재)"
fi

# ── 소비측 문서 잠금 (T5) ─────────────────────────────────────────────────
# T-se.f doc-lock: CLAUDE.md 가 조회 경로를 안내한다 (생성측만 강화하고 소비측을 빼먹는 패턴 방지)
if grep -q 'scope-explain.sh' "$PLUGIN/CLAUDE.md"; then
  PASS=$((PASS+1)); echo "PASS T-se.f CLAUDE.md 조회 경로 안내"
else
  FAIL=$((FAIL+1)); echo "FAIL T-se.f CLAUDE.md 안내 부재"
fi

echo "==== test-scope-explain: PASS=$PASS FAIL=$FAIL ===="
[ "$FAIL" -eq 0 ]
