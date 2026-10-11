#!/usr/bin/env bash
# test-screen-verify-backstop.sh — verify 껍데기 backstop 검증
# AC-5(경고 기록 + 비차단 + 신설 아님) · AC-6(차단 승급 조건 명시)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)

PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
VERIFY="$PLUGIN/skills/verifying-evidence-ko/SKILL.md"
PASS=0; FAIL=0

# T1: 경고 섹션 기록 지시 (AC-5 ①)
[ "$(grep -cF '## 화면 껍데기 경고' "$VERIFY")" -eq 1 ] \
  && ok  "T1.a evidence.md '## 화면 껍데기 경고' 기록 지시 정확히 1회" \
  || nope "T1.a 경고 섹션 지시" "count=$(grep -cF '## 화면 껍데기 경고' "$VERIFY")"

# T1.b: 기존 헬퍼 재사용 — 새 스크립트 신설 아님 (AC-5 ③)
[ "$(grep -cF 'design-screen.sh --check' "$VERIFY")" -eq 1 ] \
  && ok  "T1.b 기존 헬퍼(--check) 재사용 — 신규 스캐너 0" \
  || nope "T1.b 헬퍼 재사용" "count=$(grep -cF 'design-screen.sh --check' "$VERIFY")"

# T2: 비차단 명시 (AC-5 ②)
grep -qF '비차단' "$VERIFY" \
  && ok  "T2.a 비차단 명시" \
  || nope "T2.a 비차단" "'비차단' 앵커 없음"

# T2.b: VERIFY: FAIL 로 승급하지 않음이 명문화
grep -qF 'VERIFY: FAIL` 로 승급하지 않는다' "$VERIFY" \
  && ok  "T2.b 이번 버전 미승급 명문화" \
  || nope "T2.b 미승급 명문화" "앵커 없음"

# T3: 차단 승급 조건 (AC-6)
grep -qF '상류 교정 실패의 증거이므로 차단으로 승급' "$VERIFY" \
  && ok  "T3.a 차단 승급 조건 명문화" \
  || nope "T3.a 승급 조건" "'상류 교정 실패의 증거이므로 차단으로 승급' 앵커 없음"

finish
