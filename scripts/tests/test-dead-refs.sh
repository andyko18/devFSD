#!/usr/bin/env bash
# 죽은 지시·낡은 안내 잠금 (20261114 소스 검토)
#   모델이 읽고 따르는 본문(명령·skill·에이전트·템플릿)과 사용자 문서에 없는 명령·파일·skill 을 가리키는 문장이 남으면,
#   모델은 그것을 찾느라 시간을 쓰고 사용자는 없는 명령을 안내받는다(템플릿의 `/tasks <FID>` 는 산출 문서 끝에 그대로 찍혔다).
#   frontmatter(reference_upstream 등 상류 출처 기록)와 CHANGELOG·감사 기록 같은 이력 문서는 보지 않는다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

cd "$PLUGIN" || exit 1
FILES=$(ls commands/*.md skills/*/*.md agents/*.md templates/*.md README.md CONTRIBUTING.md \
  docs/harness-principles.md docs/adoption-notes.md docs/governance-history.md 2>/dev/null)
# 본문만 — 맨 앞 frontmatter(--- … ---)는 건너뛴다
body_hits() {  # $1 = 고정 문자열 → "파일:줄" 목록
  local f
  for f in $FILES; do
    awk -v pat="$1" -v f="$f" 'NR==1&&$0=="---"{fm=1;next} fm&&$0=="---"{fm=0;next} fm{next} index($0,pat){print f":"NR}' "$f"
  done
}
chk() {  # $1 = id  $2 = 설명  $3… = 금지 문자열
  local id=$1 desc=$2; shift 2
  local p hits=""
  for p in "$@"; do h=$(body_hits "$p"); [ -z "$h" ] || hits="$hits [$p] $(printf '%s' "$h" | tr '\n' ' ')"; done
  [ -z "$hits" ] && ok "$id $desc" || nope "$id $desc" "$hits"
}

chk D1 "사용자에게 보이는 오타(분析) 없음" '분析'
chk D2 "없는 명령 파일(commands/clarify.md·commands/tasks.md)을 선례로 가리키지 않는다" '선례: `commands/clarify.md`' '선례: `commands/tasks.md`'
chk D3 "★ 템플릿·본문이 없는 슬래시 명령(/tasks·/clarify·/specify)을 안내하지 않는다 — 산출 문서에 그대로 찍힌다" \
  '`/tasks <FID>`' '`/tasks`에서' '`/clarify`에서' '`/clarify` 단계' '`/clarify`가' '`/specify`가 생성' '`/specify` 시점' '`/specify` 이후'
chk D4 "없는 skill·템플릿(writing-plans-ko·templates/analysis.md)을 가리키지 않는다" 'writing-plans-ko' 'templates/analysis.md'
chk D5 "★ '/start 는 무조건 직행' — 지금은 갈래 판정을 먼저 한다(모든 세션에 주입되는 문장)" '무조건 직행'
chk D6 "v5.0.0 에서 지운 skill 이름을 지시처럼 쓰지 않는다" 'context-resets 스킬' '(file-based-communication)' 'file-based-communication 참조' 'sprint-contracts schema' 'sprint-contracts 상 spec'
chk D7 "v5.0.0 에서 지운 lite 명령·분기를 안내하지 않는다" '/maintain-lite' '/start-lite' 'lite 는 plan 검토가 없어'
chk D8 "낡은 수·줄 번호 참조(3개 에이전트 · L170)가 없다" '3개 에이전트가 `agents/`' 'L170 비차단'
chk D9 "v5.1.0 뒤 사라진 'PR 질문' 을 사용자 문서가 안내하지 않는다" 'PR 질문에서 함께 보여 준다' 'PR 질문 직전'

# 대조: 고친 문구가 남아 있다(지우기만 하고 대신 쓰지 않은 경우를 막는다)
[ "$(grep -cF '분석 결과 검토. 진행? [y/n]' skills/analyzing-ko/SKILL.md)" = 2 ] \
  && ok "C1 analyzing 검토 게이트 문구 2곳(오타 고친 형태) 보존" || nope "C1" "$(grep -cF '분석 결과 검토. 진행? [y/n]' skills/analyzing-ko/SKILL.md)곳"
grep -qF '갈래는 스크립트가 고른다' skills/using-specops-ko/SKILL.md \
  && ok "C2 메타 skill 이 /start 가 갈래 판정을 거친다고 적는다" || nope "C2" "대체 문구 없음"

finish
