#!/usr/bin/env bash
# scripts/_internal/init-project/lib.sh · _replace_token 단위 테스트
# 토큰(LHS) BRE 메타문자 escape — `.` 가 any-char 로 오매치되지 않아야 함
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=/dev/null
. "$PLUGIN/scripts/_internal/init-project/lib.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# T1.a 기본 치환 — <PROJECT_NAME> (현행 호출자 계약 회귀)
f="$TMP/a.md"
printf '# <PROJECT_NAME> 문서\n<PROJECT_NAME> 반복\n' > "$f"
_replace_token "$f" "<PROJECT_NAME>" "my-app"
if grep -q "my-app 문서" "$f" && ! grep -q "<PROJECT_NAME>" "$f"; then
  PASS=$((PASS+1)); echo "PASS T1.a 기본 치환"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a ($(cat "$f"))"
fi

# T1.b value 메타문자(| & \) escape 보존 (기존 동작 회귀)
f="$TMP/b.md"
printf '<PROJECT_NAME>\n' > "$f"
_replace_token "$f" "<PROJECT_NAME>" 'a|b&c\d'
if [ "$(cat "$f")" = 'a|b&c\d' ]; then
  PASS=$((PASS+1)); echo "PASS T1.b value escape"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b ($(cat "$f"))"
fi

# T2.a 토큰 내 `.` 가 any-char 오매치 금지 — <A.B> 치환 시 <AXB> 는 보존
f="$TMP/c.md"
printf '<A.B>\n<AXB>\n' > "$f"
_replace_token "$f" "<A.B>" "hit"
if grep -qx "hit" "$f" && grep -qx "<AXB>" "$f"; then
  PASS=$((PASS+1)); echo "PASS T2.a 토큰 . 리터럴 매칭"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.a ($(tr '\n' ' ' < "$f"))"
fi

# T2.b 토큰 내 `*` `[` `]` — BRE 메타문자 리터럴 취급
f="$TMP/d.md"
printf '<X*[1]>\nplain\n' > "$f"
_replace_token "$f" "<X*[1]>" "ok"
if grep -qx "ok" "$f" && grep -qx "plain" "$f"; then
  PASS=$((PASS+1)); echo "PASS T2.b 토큰 *[] 리터럴 매칭"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.b ($(tr '\n' ' ' < "$f"))"
fi

# T2.c 토큰 내 `|` — sed 구분자 충돌 시 표현식 미파손
f="$TMP/e.md"
printf '<A|B>\n' > "$f"
if _replace_token "$f" "<A|B>" "piped" 2>/dev/null && grep -qx "piped" "$f"; then
  PASS=$((PASS+1)); echo "PASS T2.c 토큰 | 구분자 안전"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.c ($(cat "$f" 2>/dev/null))"
fi

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
