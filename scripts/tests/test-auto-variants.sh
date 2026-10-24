#!/usr/bin/env bash
# 단일 무인 변형 폐지 잠금 (20261024-remove-single-auto-variants)
#   /start-auto · /start-lite-auto · /maintain-auto · /maintain-lite-auto 는 기본 §일괄(승인 1회 뒤 PR 까지 무정지) 뒤로
#   더해 주는 것이 승인 1회 생략뿐이라 지웠다. 이 스위트는 지운 명령·전용 표지 해석이 되살아나지 않는지,
#   batch 무인(/start-all-auto)은 그대로인지 본다. 종전 무인 사슬 계약(20261008-auto-variants)을 대체한다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
cd "$PLUGIN" || exit 1

GONE="start-auto start-lite-auto maintain-auto maintain-lite-auto"
# 이름 경계 — /start-all-auto 는 다른 명령이라 걸리면 안 된다
NAME_RE='(^|[^a-z-])(start-auto|start-lite-auto|maintain-auto|maintain-lite-auto)([^a-z-]|$)'

# R0: 이름 정규식 자체 — 지운 이름은 잡고 start-all-auto 는 놓는다(공허한 grep 방지)
printf '%s\n' '/start-auto' 'commands/maintain-lite-auto.md' | grep -cE "$NAME_RE" | grep -qx 2 \
  && ! printf '%s\n' '/start-all-auto' | grep -qE "$NAME_RE" \
  && ok "R0 이름 정규식: 지운 이름 2/2 · start-all-auto 0" || nope "R0" "정규식 경계 오류"

# R1: 명령 파일 부재
miss=""; for c in $GONE; do [ -e "commands/$c.md" ] && miss="$miss $c"; done
[ -z "$miss" ] && ok "R1 단일 무인 명령 4종 파일 부재" || nope "R1" "되살아남:$miss"

# R2: 런타임·안내 문서에 이름 0건 (hooks·docs·CHANGELOG 의 과거 서술은 범위 밖)
#   대상 목록이 읽히지 않으면 0건과 구별되지 않으므로, 같은 대상에서 start-all-auto 가 보이는지 먼저 본다(양성 대조)
R2_T="skills commands agents templates README.md CLAUDE.md CONTRIBUTING.md scripts/_internal/propagation-matrix.jsonl"
# shellcheck disable=SC2086
_pos=$(grep -rlF 'start-all-auto' $R2_T 2>/dev/null | grep -c .)
# shellcheck disable=SC2086
hits=$(grep -rnE "$NAME_RE" $R2_T 2>/dev/null | head -3)
[ "$_pos" -ge 3 ] && [ -z "$hits" ] && ok "R2 지운 명령 이름 잔존 0 (대상 양성 대조 start-all-auto ${_pos}파일)" || nope "R2" "pos=$_pos hits=$hits"
# R2b: 약어로 남은 안내(`-lite-auto` — 전체 이름이 아니라 NAME_RE 가 못 잡는다)
# shellcheck disable=SC2086
hits=$(grep -rnF -- '-lite-auto' $R2_T 2>/dev/null | head -3)
[ -z "$hits" ] && ok "R2b 약어 -lite-auto 안내 0" || nope "R2b" "$hits"

# R3: 명령 개수 — 실제 ↔ 구조 기준선 ↔ README 진입로 수 ↔ docs/architecture.md 표
_ac=$(ls commands/*.md 2>/dev/null | grep -c .)
_bl=$(jq -rs 'map(select(.category=="commands")) | .[0].count' scripts/_internal/.structure-baseline 2>/dev/null)
_rd=$(grep -oE '슬래시 진입로 [0-9]+건' README.md | head -1 | grep -oE '[0-9]+')
_ar=$(grep -E '^\| 슬래시 커맨드 \| [0-9]+건' docs/architecture.md | head -1 | grep -oE '[0-9]+')
[ -n "$_bl" ] && [ "$_ac" = "$_bl" ] && [ "$_ac" = "$_rd" ] && [ "$_ac" = "$_ar" ] \
  && ok "R3 commands 실제 $_ac = baseline $_bl = README $_rd = architecture $_ar" || nope "R3" "actual=$_ac baseline=$_bl readme=$_rd architecture=$_ar"

# R4: skill 의 단일 무인 전용 분기 0건 — 지운 명령만 쓰던 표지 해석
#   파일이 없으면 grep rc 2 가 "없음"으로 읽히므로 존재를 먼저 본다
SK4="skills/specifying-ko/SKILL.md skills/analyzing-ko/SKILL.md skills/decomposing-ko/SKILL.md skills/performance-test-ko/SKILL.md"
r4=""
for f in $SK4; do [ -s "$f" ] || r4="$r4 [부재:$f]"; done
for p in 'entry: auto' '[무인 표지 (둘째 줄)]' '## 무인 표지' 'promoted: lite' '자동 결정 분석' '자동 승격' '위 `§auto` 와 같은 승격 절차'; do
  # shellcheck disable=SC2086
  grep -qF -- "$p" $SK4 && r4="$r4 [$p]"
done
[ -z "$r4" ] && ok "R4 skill 4종에 단일 무인 전용 분기 0건" || nope "R4" "잔존:$r4"
# R4b: 둘째 줄 무인 표지 해석 0 — analyzing 은 무인 표지를 읽지 않고, specifying 의 `auto: true` 는 batch 셋째 줄 문장뿐
BATCH_AUTO='셋째 줄이 `<!-- auto: true -->` 이면 spec.md §1에 `**§auto**: true` 도 동시 기재'
! grep -qF '<!-- auto: true -->' skills/analyzing-ko/SKILL.md \
  && [ "$(grep -F '<!-- auto: true -->' skills/specifying-ko/SKILL.md | grep -vcF "$BATCH_AUTO")" = 0 ] \
  && ok "R4b 무인 표지는 batch 셋째 줄 문장만" || nope "R4b" "batch 셋째 줄 밖의 auto: true 해석 잔존"
# R4c: entry: auto 약속어가 안내 문서·명령·skill 어디에도 없다 (지운 명령 이름이 없는 잔재 — CLAUDE.md 약속어 절 등)
r4c=$(grep -rnF 'entry: auto' skills commands CLAUDE.md README.md CONTRIBUTING.md 2>/dev/null | head -3)
[ -z "$r4c" ] && ok "R4c entry: auto 약속어 잔존 0" || nope "R4c" "$r4c"
# R4d: decomposing 의 §일괄 승격 문장이 지운 §auto 문장을 가리키지 않고 스스로 절차를 말한다
grep -qF '> **`§일괄`** 도 묻지 않고 정상 경로(clarify → plan)에 올리고(유지보수면' skills/decomposing-ko/SKILL.md \
  && ok "R4d decomposing §일괄 승격 문장 자족" || nope "R4d" "§일괄 승격 문장이 바뀌지 않음"

# R5: batch 무인 보존 — /start-all-auto 진입 표지 · specifying batch 의 §auto 기재 · PR 다이제스트의 수집 grep·절 제목
PF=skills/performance-test-ko/SKILL.md
grep -qxF '   <!-- entry: batch -->' commands/start-all-auto.md && grep -qxF '   <!-- auto: true -->' commands/start-all-auto.md \
  && grep -qF "$BATCH_AUTO" skills/specifying-ko/SKILL.md \
  && grep -qxF 'grep -E "자동 결정 화면|자동 결정 인터페이스|자동 결정 intent" .specops/<FID>/spec.md' "$PF" \
  && grep -qxF '### 자동 결정 intent (Step 1.5)' "$PF" && grep -qxF '### 자동 생성된 화면 (Step 5.5)' "$PF" \
  && grep -qxF '### 자동 결정된 인터페이스 (Step 5.6)' "$PF" \
  && grep -qxF '<spec.md "자동 결정 인터페이스" 목록 — 엔드포인트/테이블. 없으면 "(없음)">' "$PF" \
  && ok "R5 batch 무인 경로 보존(진입 표지·§auto 기재·다이제스트 수집·절 3개)" || nope "R5" "batch 무인 표지·기재·다이제스트 중 소실"

finish
