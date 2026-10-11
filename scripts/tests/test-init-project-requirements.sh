#!/usr/bin/env bash
# init-project Phase 8a FR 표 자동 합성 (FID 20260619-start-project-fr-synth)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCRIPT="$PLUGIN/scripts/_internal/init-project.sh"

# _parse_numbered 가 'N. label: text' 의 colon 뒤만 추출 → 입력 colon 필수.
# 정상: 1/2/3 + M 3개 = 6 필드 ≥4 → fallback 미발동.
run_with_prd() {
  local m1="$1" m2="$2" m3="$3"
  printf '3\nskip\n1. 한 줄 설명: 한줄\n2. 페르소나: 페르소나\n3. 가치제안: v1, v2, v3\n4. M1: %s\n5. M2: %s\n6. M3: %s\n\nn\nn\n' \
    "$m1" "$m2" "$m3" | bash "$SCRIPT" testproj >/dev/null 2>&1 || true
}

# T1.a — AC-1/2/5/3/4: M 입력 시 치환
T=$(mktemp -d); cd "$T"; git init -q; git config user.email t@t; git config user.name t
run_with_prd "로그인 기능" "검색 기능" "알림 기능"
REQ=".specops/memory/requirements.md"
grep -q '^### M1 — 로그인 기능' "$REQ" && ok "T1.a AC-1 마일스톤 이름 치환" || nope "T1.a AC-1" "M1 이름 미치환"
grep -qE '^\| FR-1 \| 로그인 기능 \| M1 \| must \|' "$REQ" && ok "T1.b AC-2 FR-1 시드" || nope "T1.b AC-2" "FR-1 미시드"
grep -qE '^\| FR-1 \|.*\| \(TBD\) \|$' "$REQ" && ok "T1.c AC-5 관련spec (TBD)" || nope "T1.c AC-5" "관련spec 미치환"
grep -qiE '시드|분해' "$REQ" && ok "T1.d AC-3 안내 주석" || nope "T1.d AC-3" "안내 주석 없음"
grep -qE '^\| FR-[0-9]+ \|' "$REQ" && ok "T1.e AC-4 batch 정규식 호환" || nope "T1.e AC-4" "FR 정규식 불일치"
cd /tmp; rm -rf "$T"

# T1.f — AC-R-1: M=<TODO> 시 가드로 placeholder 보존 (fallback 회피 위해 <TODO>)
T=$(mktemp -d); cd "$T"; git init -q; git config user.email t@t; git config user.name t
run_with_prd "<TODO>" "<TODO>" "<TODO>"
REQ=".specops/memory/requirements.md"
grep -q '<마일스톤 1 이름>' "$REQ" && ok "T1.f AC-R-1 <TODO> placeholder 보존" || nope "T1.f AC-R-1" "<TODO>인데 치환됨"
grep -qE '^\| FR-1 \| <한 줄> \|' "$REQ" && ok "T1.g AC-R-1b FR placeholder 보존" || nope "T1.g AC-R-1b" "FR <TODO> 치환됨"
cd /tmp; rm -rf "$T"

echo "── test-init-project-requirements: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
