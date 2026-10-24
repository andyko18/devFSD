#!/usr/bin/env bash
# 화면 설계 경로 분업 문서 검증 (FID 20260619-screen-routing-doc)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
DS="$PLUGIN/commands/design-screen.md"
DSS="$PLUGIN/commands/design-screens.md"
SP="$PLUGIN/skills/specifying-ko/SKILL.md"

# AC-1: design-screen.md 에 분업표 + batch Phase 2.5-A
grep -q '^## 화면 설계 경로 분업' "$DS" && grep -q 'Step 5.5' "$DS" && grep -q '/design-screens' "$DS" \
  && grep -q 'Phase 2.5-A' "$DS" \
  && ok "AC-1 분업표+Phase 2.5-A" || nope "AC-1" "분업표 헤더/경로 누락"
# AC-2: "언제 쓰나" 기준 — 분업표 블록 *내부*에서만 검사
TBL=$(awk '/^## 화면 설계 경로 분업/,/^## Process/' "$DS")
printf '%s' "$TBL" | grep -qiE 'lifecycle 자동' && printf '%s' "$TBL" | grep -qiE '독립' \
  && ok "AC-2 언제쓰나 기준(표 내부)" || nope "AC-2" "표 내부 기준 없음"
# AC-3: design-screens.md 고유 cross-ref
grep -q '§화면 설계 경로 분업' "$DSS" && ok "AC-3 design-screens cross-ref(고유)" || nope "AC-3" "고유 cross-ref 없음"
# AC-4: specifying Step5.5 cross-ref
awk '/^5\.5\./,/^6\. /' "$SP" | grep -qE '/design-screen' && ok "AC-4 Step5.5 cross-ref" || nope "AC-4" "cross-ref 없음"

# AC-R-1: Step5.5 기존 로직 보존
awk '/^5\.5\./,/^6\. /' "$SP" | grep -q 'ui-ux-pro-max' && nope "AC-R-1" "외부 디자인 플러그인 호출 잔존" \
  || { awk '/^5\.5\./,/^6\. /' "$SP" | grep -q 'DESIGN.md' && ok "AC-R-1 Step5.5 DESIGN.md 단일 출처" || nope "AC-R-1" "DESIGN.md 지시 소실"; }
! awk '/^5\.5\./,/^6\. /' "$SP" | grep -q '§auto' && ok "AC-R-1b Step 5.5~6 에 도달 불가 §auto 문단 없음 (20261024)" || nope "AC-R-1b" "5.5~6 구간에 §auto 잔존"
# AC-R-2: design-screen Process 보존
grep -q '^## Process' "$DS" && grep -q 'design-screen.sh' "$DS" && ok "AC-R-2 Process 보존" || nope "AC-R-2" "Process 소실"

# AC-5: description 2건이 관할(lifecycle 밖) + lifecycle 안 담당자를 밝힌다
_d_ds=$(grep -m1 '^description:' "$DS"); _d_dss=$(grep -m1 '^description:' "$DSS")
printf '%s' "$_d_ds"  | grep -q 'lifecycle 밖' \
  && printf '%s' "$_d_ds"  | grep -q 'Step 5.5' && printf '%s' "$_d_ds"  | grep -q 'Phase 2.5-A' \
  && printf '%s' "$_d_dss" | grep -q 'lifecycle 밖' \
  && printf '%s' "$_d_dss" | grep -q 'Step 5.5' && printf '%s' "$_d_dss" | grep -q 'Phase 2.5-A' \
  && [ "$(grep -c '^description:' "$DS")" = 1 ] && [ "$(grep -c '^description:' "$DSS")" = 1 ] \
  && ok "AC-5[spec AC-1·2·4] 화면 description 관할+담당+1행" || nope "AC-5[spec AC-1·2·4]" "범위 한정 누락 또는 description 다중 행"

# AC-6: 복수 파일 **본문**(frontmatter 제외)에도 분업이 있다
#   ★ frontmatter 를 잘라내는 이유: 안 자르면 description 만 고쳐도 통과해,
#     이 FID 가 발견한 "복수 본문 공백"을 다시 놓친다.
#   ★ 세 토큰을 **같은 한 줄**에서 요구한다 — 파일 전역 grep 이면 `design-screen.md`
#     conjunct 가 tautology 다(본문에 이미 존재).
#   ★★ 앵커는 `^> **분업**:` 로 **고정**한다 — 느슨한 `grep -m1 '분업'` 은 본문의
#     기존 cross-ref 줄을 잡을 수 있어 판정 대상이 조용히 바뀐다(IF 경로에서 실측).
_body_dss=$(awk 'BEGIN{c=0} /^---$/{c++; next} c>=2' "$DSS")
_l_dss=$(printf '%s' "$_body_dss" | grep -m1 '^> \*\*분업\*\*:')
printf '%s' "$_l_dss" | grep -q 'Step 5.5' \
  && printf '%s' "$_l_dss" | grep -q 'Phase 2.5-A' \
  && printf '%s' "$_l_dss" | grep -q 'design-screen.md' \
  && ok "AC-6[spec AC-3] design-screens 본문 분업(frontmatter 제외)" || nope "AC-6[spec AC-3]" "본문 분업 누락"

echo "── test-screen-routing-doc: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
