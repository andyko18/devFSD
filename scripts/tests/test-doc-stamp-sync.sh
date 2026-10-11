#!/usr/bin/env bash
# 문서 stale·형식 정리 검증 (FID 20260619-doc-stamp-sync)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
RM="$PLUGIN/README.md"; CL="$PLUGIN/CLAUDE.md"

# AC-1: test suite number hardcoding removed
! grep -qE '[0-9]+ suites' "$RM" && ! grep -qE '[0-9]+ suites' "$CL" \
  && ok "AC-1 suite count hardcoding removed" || nope "AC-1" "[0-9]+ suites remains"
# AC-2: README governance with PreToolUse
awk '/^## 거버넌스 엔진/,/^## [^거]/' "$RM" | grep -q 'PreToolUse' \
  && ok "AC-2 README PreToolUse explicit" || nope "AC-2" "PreToolUse missing"
# AC-3: reference_upstream 단일라인 (frontmatter 영역 `^  - ` 0)
for f in skills/requesting-code-review-ko/SKILL.md commands/start.md commands/maintain.md; do
  # reference_upstream: 의 continuation `  - ` 만 카운트. 다른 YAML 키(triggers 등) 만나면
  # 즉시 f=0 으로 종료 — reference_upstream 위치(마지막 키 여부) 무관하게 키 경계로 격리.
  n=$(awk 'NR>1 && /^---$/{exit}
           /^reference_upstream:/{f=1;next}
           /^[a-z_]+:/{f=0}
           f && /^  - /{c++;next}
           END{print c+0}' "$PLUGIN/$f")
  [ "$n" = "0" ] || nope "AC-3 $f" "reference_upstream hyphen dash $n lines remain"
done
[ "$FAIL" -eq 0 ] && ok "AC-3 reference_upstream single-line(3files)" || true
# AC-R-3: reference_upstream first line primary reference preserved
grep -q '^reference_upstream: obra/superpowers@v5.0.7 skills/requesting-code-review' "$PLUGIN/skills/requesting-code-review-ko/SKILL.md" \
  && ok "AC-R-3 primary reference preserved" || nope "AC-R-3" "first line lost"

echo "test-doc-stamp-sync: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
