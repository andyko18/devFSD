#!/usr/bin/env bash
# init-project rename 검증 (FID 20260619-rename-init-project)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
P=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$P/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

# AC-1: init-project.md 존재 + name + trigger + 오케스트레이터 호출
IP="$P/commands/init-project.md"
[ -f "$IP" ] && grep -q '^name: init-project' "$IP" && grep -q '"/init-project"' "$IP" && grep -q 'init-project.sh' "$IP" \
  && ok "AC-1 init-project.md 신설" || nope "AC-1" "init-project.md 결함"
# AC-2: start-project alias 제거됨 (deprecated stub → 부재)
[ ! -f "$P/commands/start-project.md" ] && ok "AC-2 start-project alias 제거" || nope "AC-2" "alias 잔존"
# AC-3: 메타skill /init-project 안내
grep -q '/init-project' "$P/skills/using-specops-ko/SKILL.md" \
  && ok "AC-3 메타skill /init-project" || nope "AC-3" "메타skill 미갱신"
# AC-4: chain 안내 파일에 /init-project 등장 + 사용자노출 /start-project 잔존 0
#   (deprecated stub·테스트·CHANGELOG·init-project.sh 참조 제외)
miss=""
for f in skills/specifying-ko/SKILL.md skills/e2e-test-ko/SKILL.md commands/start-all.md commands/start-foundation.md; do
  grep -q '/init-project' "$P/$f" || miss="$miss $f(no-init)"
  # start-project.{sh,md} 경로 마스킹 후 /start-project(슬래시) 잔존 검사 (줄단위 false-neg 회피)
  # sed -E 필수 — BSD sed(macOS)는 BRE `\|` 교대 미지원(no-op→false-positive). plan-reviewer 2회차.
  sed -E 's#start-project\.(sh|md)#XMASKX#g' "$P/$f" | grep -q '/start-project' && miss="$miss $f(stale-start)"
done
[ -z "$miss" ] && ok "AC-4 chain 안내 갱신" || nope "AC-4" "$miss"
# AC-5: templates footer + README 갱신 (대표 샘플)
grep -q '/init-project' "$P/templates/PRD.md" && grep -q '/init-project' "$P/README.md" \
  && ok "AC-5 templates/README 갱신" || nope "AC-5" "footer/README 미갱신"
# AC-R-1: 오케스트레이터 실행 진입 보존 (파일 rename·escape fix 후에도 main 진입 유지)
#   — 구 "git diff 무변경" 가드는 start-project.sh→init-project.sh rename + awk escape fix 로 폐기.
#     회귀 정신(오케스트레이터를 깨먹지 마라)은 "파일 존재 + main 진입부 보존"으로 전환.
OS="$P/scripts/_internal/init-project.sh"
[ -f "$OS" ] && grep -q 'main "\$@"' "$OS" \
  && ok "AC-R-1 오케스트레이터 main 진입 보존" || nope "AC-R-1" "오케스트레이터 진입부 결함"

echo "── test-rename-init-project: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
