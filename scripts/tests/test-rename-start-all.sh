#!/usr/bin/env bash
# start-all rename 검증 (FID 20260619-rename-start-all)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
P=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$P/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

# AC-1: start-all.md 신설 + name + trigger + 3-Phase 오케스트레이터
SA="$P/commands/start-all.md"
[ -f "$SA" ] && grep -q '^name: start-all' "$SA" && grep -q '"/start-all"' "$SA" && grep -q 'Phase 1' "$SA" \
  && ok "AC-1 start-all.md 신설" || nope "AC-1" "start-all.md 결함"
# AC-2: start-batch alias 제거됨
[ ! -f "$P/commands/start-batch.md" ] && ok "AC-2 start-batch alias 제거" || nope "AC-2" "alias 잔존"
# AC-3: 사용자 슬래시 갱신 — /init-project 류 마스킹 후 /start-batch(슬래시) 잔존 0
#   (.md 파일명·§batch·batch-id·BATCH- 신호어 제외)
miss=""
for f in README.md skills/specifying-ko/SKILL.md skills/integration-test-ko/SKILL.md skills/performance-test-ko/SKILL.md skills/receiving-code-review-ko/SKILL.md skills/decomposing-ko/SKILL.md; do
  grep -q '/start-all' "$P/$f" || miss="$miss $f(no-all)"
  # start-batch.md(파일명) 마스킹 후 /start-batch(슬래시) 잔존 검사
  sed -E 's#start-batch\.md#XMASKX#g' "$P/$f" | grep -q '/start-batch' && miss="$miss $f(stale-batch)"
done
[ -z "$miss" ] && ok "AC-3 슬래시 갱신" || nope "AC-3" "$miss"
# AC-R-1: §batch 신호어 보존 (소비처 grep 건수 — 분기 라벨 무변경)
for sig in '\*\*§batch\*\*' 'BATCH-PHASE1-DONE' 'batch-id'; do
  c=$(grep -rl "$sig" "$P/skills" 2>/dev/null | wc -l | tr -d ' ')
  [ "$c" -gt 0 ] || nope "AC-R-1 $sig" "신호어 소실"
done
[ "$FAIL" -eq 0 ] && ok "AC-R-1 §batch 신호어 보존" || true

echo "── test-rename-start-all: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
