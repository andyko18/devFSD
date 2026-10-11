#!/usr/bin/env bash
# deprecated alias 제거 검증 (FID 20260620-remove-deprecated-alias)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
P=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$P/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

# AC-1: alias 2파일 부재
[ ! -f "$P/commands/start-project.md" ] && [ ! -f "$P/commands/start-batch.md" ] \
  && ok "AC-1 alias 2건 삭제" || nope "AC-1" "alias 파일 잔존"
# AC-2: baseline commands count 가 실제 commands/*.md 수와 정합 (하드코딩 14 → 동적 — 새 command 추가에 brittle하지 않게)
bc=$(grep -o '"glob":"commands/\*\.md","count":[0-9]*' "$P/scripts/_internal/.structure-baseline" | grep -o '[0-9]*$')
ac=$(ls "$P"/commands/*.md 2>/dev/null | wc -l | tr -d ' ')
[ -n "$bc" ] && [ "$bc" = "$ac" ] && ok "AC-2 baseline commands 정합 ($bc=$ac)" || nope "AC-2" "baseline($bc)≠실제($ac)"
# AC-3: stale 문구 정리 — "deprecated alias 보존"·"(구 /start-batch)" 부재
! grep -q 'deprecated alias 보존' "$P/commands/init-project.md" && ! grep -q '(구 /start-batch)' "$P/commands/start-all.md" \
  && ok "AC-3 stale 문구 정리" || nope "AC-3" "stale 문구 잔존"
# AC-R-3: 오케스트레이터·런타임 치환 토큰 정합 (placeholder 짝 일치 → _replace_token 동작 보존)
#   — 구 가드는 api-spec.md 의 `/start-project` 문자열 존재만 확인했으나 init-project rename 으로 `/init-project` 로 전환.
#     회귀 정신(런타임 치환이 깨지지 않는가)은 "두 파일의 placeholder 토큰이 동일"로 직접 검증.
TOK='<`/init-project` 입력값>'   # api-spec.md placeholder (escape 없음)
[ -f "$P/scripts/_internal/init-project.sh" ] \
  && grep -qF "$TOK" "$P/templates/api-spec.md" \
  && cat "$P"/scripts/_internal/init-project.sh "$P"/scripts/_internal/init-project/*.sh 2>/dev/null | grep -q '_replace_token.*init-project.*입력값' \
  && ok "AC-R-3 런타임 치환 토큰 정합" || nope "AC-R-3" "placeholder 짝 불일치"

echo "── test-remove-alias: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
