#!/usr/bin/env bash
# README §2 진입로 결정 트리 검증 (FID 20260619-entry-decision-tree)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
R="$PLUGIN/README.md"
# 진입로 절만 뽑는다 — README 전체에 grep 하면 다른 절(산출물 트리·Lifecycle)의 같은 낱말로 통과한다.
#   AC-3·5·6a 는 진입로 절의 그 문장을 지워도 초록이었다(20261009 변이 실험).
SEC=$(mktemp) || exit 1
trap 'rm -f "$SEC"' EXIT
awk '/^## 진입로/{f=1; next} f && /^## /{exit} f' "$R" > "$SEC"
[ -s "$SEC" ] && ok "AC-0 진입로 절 존재" || nope "AC-0" "## 진입로 절을 찾지 못함"

# AC-1: /start-auto 등장
grep -q '/start-auto' "$R" && ok "AC-1 start-auto 등장" || nope "AC-1" "start-auto 누락"
# AC-2: 10종 모두 등장 (lite·maintain-lite·start-all-auto 포함)
miss=""
for s in '/start ' '/start-lite' '/start-auto' '/start-foundation' '/start-all' '/start-all-auto' '/init-project' '/maintain' '/maintain-lite' '/brainstorming'; do
  grep -q -- "$s" "$R" || miss="$miss $s"
done
[ -z "$miss" ] && ok "AC-2 10종 진입로 등장" || nope "AC-2" "누락:$miss"
# AC-2b: 무인 변형 3종 (20261008-auto-variants) — 진입로 표와 결정 트리 양쪽
miss=""
for s in '/maintain-auto' '/start-lite-auto' '/maintain-lite-auto'; do
  [ "$(grep -c -- "$s" "$SEC")" -ge 2 ] || miss="$miss $s"
done
[ -z "$miss" ] && ok "AC-2b 무인 변형 3종 — 표·결정 트리" || nope "AC-2b" "누락(2곳 미만):$miss"
# AC-3: start↔maintain 판단 기준 (신규/기존 키워드)
grep -q '기존 코드를 고치나' "$SEC" && grep -q '새 산출물' "$SEC" && ok "AC-3 판단 기준" || nope "AC-3" "결정 트리의 신규/기존 판단 기준 없음"
# AC-4: project→foundation→batch 순서 표현 (한 줄 요약 라인 매칭 — grep 줄단위)
grep -qE '/init-project →.*/start-foundation →.*/start-all' "$SEC" && ok "AC-4 선택 순서" || nope "AC-4" "순서 흐름 없음"
# AC-5: start vs start-auto 차이 (게이트/자동통과)
grep -q '가역 게이트 자동 통과' "$SEC" && ok "AC-5 게이트 차이" || nope "AC-5" "게이트 차이 없음"
# AC-6: foundation/batch 주의 항목 (진입로 절 안)
grep -q 'foundation-manifest' "$SEC" && ok "AC-6a foundation-manifest" || nope "AC-6a" "foundation-manifest 누락"
grep -qE 'check-foundation-merged|머지 후' "$SEC" && ok "AC-6b merged 게이트" || nope "AC-6b" "merged/머지 후 누락"
grep -q 'foundation-baseline' "$SEC" && ok "AC-6c IF baseline" || nope "AC-6c" "foundation-baseline 누락"
grep -q 'foundation-shell' "$SEC" && ok "AC-6d shell baseline" || nope "AC-6d" "foundation-shell 누락"
grep -q 'init-batch-queue' "$SEC" && ok "AC-6e queue 기계화" || nope "AC-6e" "init-batch-queue 누락"
grep -qF '[공통]' "$SEC" && ok "AC-6f 공통 FR SKIP" || nope "AC-6f" "[공통] 누락"
# AC-R-1: 기존 자동체인 설명 보존
grep -qE 'spec → clarify → plan' "$R" && ok "AC-R-1 자동체인 설명 보존" || nope "AC-R-1" "자동체인 설명 소실"
grep -q 'using-specops-ko' "$R" && ok "AC-R-1b 라우팅 설명 보존" || nope "AC-R-1b" "라우팅 설명 소실"

echo "── test-readme-entry-tree: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
