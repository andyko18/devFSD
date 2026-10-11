#!/usr/bin/env bash
set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/screens/login.html"
PASS=0; FAIL=0

check() {
  local label="$1" pattern="$2"
  if grep -qF "$pattern" "$FILE"; then
    echo "PASS: $label"; PASS=$((PASS+1))
  else
    echo "FAIL: $label"; FAIL=$((FAIL+1))
  fi
}

check "AC-1 이메일 input(type=email)" 'type="email"'
check "AC-1 비밀번호 input(type=password)" 'type="password"'
check "AC-1 label[for=email]" 'for="email"'
check "AC-1 label[for=password]" 'for="password"'
check "AC-2/AC-3 error-msg 요소" 'error-msg'
check "AC-2/AC-3 error-input 클래스" 'error-input'
check "AC-2 btn.disabled 처리" 'btn.disabled'
check "AC-2 로그인 중 텍스트" '로그인 중'
check "AC-4 viewport meta" 'width=device-width'
check "AC-5 비밀번호 토글 버튼" 'toggle-password'
check "AC-5 토글 aria-label" 'aria-label="비밀번호 표시/숨김"'

echo ""
echo "결과: PASS=${PASS}, FAIL=${FAIL}"
# grep checks assert presence only — dynamic behavior (AC-2/AC-3/AC-5) requires manual browser verification
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
