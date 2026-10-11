#!/usr/bin/env bash
# lint error 게이트 (shellcheck -S error) — CI(.github/workflows/test.yml shellcheck job)와 동일 명령의 로컬 parity
# CI 만 돌던 -S error 게이트가 로컬 run-all green 후 push 에서 최초 발각되던 비대칭 해소
# 도구(shellcheck) 미설치 환경은 graceful SKIP (CI 가 최종 게이트)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "PASS T1.a skipped — shellcheck 미설치 (CI shellcheck job 이 최종 게이트)"
  echo "---"; echo "PASS=1 FAIL=0"
  exit 0
fi

# T1.a CI parity: hooks/ + scripts/ 전체 *.sh 에 error 급 0건
# 병렬 실행(-n 40 -P 4): 319개를 한 프로세스로 직렬 검사하면 단독 86s — run-all 최대 병렬(부하) 에서 300s 상한을 넘겨
#   TIMEOUT 이 났다(20261007). 같은 파일 집합을 40개씩 4병렬로 나눠 11s. -S error 는 파일 간 source 추적(-x)을 쓰지 않아
#   분할해도 판정이 같고, xargs 는 어느 묶음이든 비0 이면 123 을 돌려줘 아래 rc 판정이 그대로 유효하다.
out=$(cd "$PLUGIN" && find hooks scripts -name '*.sh' -print0 | xargs -0 -n 40 -P 4 shellcheck -S error 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T1.a shellcheck -S error 0건 (CI parity)"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a shellcheck error 검출:"; printf '%s\n' "$out" | head -20
fi

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
