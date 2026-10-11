#!/usr/bin/env bash
# command description 라벨 규약 검증 (FID 20260904-design-cmd-scope-desc)
#   ① 대괄호 접두를 쓰는 description 은 frontmatter 파싱 실패를 막기 위해 따옴표 필수
#   ② /maintain 은 형제 8건과 동일하게 모드 라벨 접두를 갖는다
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

# CDL-1: /maintain description 이 모드 라벨 접두를 갖는다 (spec AC-5)
grep -m1 '^description:' "$PLUGIN/commands/maintain.md" | grep -q '\[유지보수·대화형\]' \
  && ok "CDL-1[spec AC-5] /maintain 모드 라벨 접두" || nope "CDL-1[spec AC-5]" "접두 없음 — maintain-lite 와 비대칭"

# CDL-2: 대괄호 접두 description 은 전부 따옴표로 감싼다
#   따옴표가 없으면 YAML 이 `[` 를 flow-sequence 시작으로 읽고 뒤따르는 스칼라에서
#   **ParserError** 를 낸다 — frontmatter 전체가 파싱 실패해 커맨드가 로드되지 않는다
#   (실측: pyyaml 로 `description: [lifecycle 밖] 화면 …` → ParserError. "배열로 파싱"이
#   아니다 — Phase C 리뷰어 정정).
#   콜론 뒤 공백은 1개로 한정하지 않는다 — `description:  [`(2칸)도 같은 실패를 낸다.
_bad=""
for _f in "$PLUGIN"/commands/*.md; do
  _d=$(grep -m1 '^description:' "$_f" 2>/dev/null | sed 's/^description:[[:space:]]*//') || continue
  case "$_d" in
    '['*) _bad="${_bad}${_bad:+ }$(basename "$_f")" ;;
  esac
done
[ -z "$_bad" ] && ok "CDL-2 대괄호 접두 description 따옴표 규약" || nope "CDL-2" "따옴표 없는 대괄호 접두: $_bad"

finish
