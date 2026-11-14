#!/usr/bin/env bash
# 에이전트 계약 정합 (20261114 소스 검토) — 부르는 쪽과 받는 쪽, 템플릿과 평가자가 같은 말을 하는지 잠근다.
#   · 스펙 리뷰어는 must 수용 기준만으로 PASS 를 정한다(templates/acceptance-criteria.md §우선순위 규약과 같은 기준).
#   · 종합 판정은 기계가 읽을 수 있는 고정 한 줄(`판정: PASS|NEEDS_FIX`)이다 — 낱말은 훅이 저장하는 verdict 어휘와 같다.
#   · 기본 경로(commands/basic.md)는 dispatch 컨텍스트 파일 없이 리뷰어를 부른다 — 두 리뷰어가 그 입력을 안다.
#   · 구현자는 whitelist 밖 파일(tasks.md·진행 기록)을 쓰지 않는다 — 부모(record-task-done.sh)가 남긴다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

SR="$PLUGIN/agents/spec-reviewer-ko.md"
CR="$PLUGIN/agents/code-reviewer-ko.md"
IM="$PLUGIN/agents/implementer-ko.md"
BA="$PLUGIN/commands/basic.md"
AC="$PLUGIN/templates/acceptance-criteria.md"
SS="$PLUGIN/commands/security-scan.md"
IMP="$PLUGIN/skills/implementing-ko/SKILL.md"
has() { local f=$1; shift; local p; for p in "$@"; do grep -qF -- "$p" "$f" || return 1; done; }
# 섹션 본문: 제목 줄부터 다음 같은 깊이 제목 직전까지
sect() { awk -v h="$2" 'index($0,h)==1 { f=1; next } f && /^## / { exit } f { print }' "$1"; }

# ── 스펙 리뷰어 ──
has "$SR" '**우선순위**' 'must' 'should' 'nice-to-have' \
  && ok "A1 스펙 리뷰어가 수용 기준 우선순위(must·should·nice-to-have)를 읽는다" || nope "A1" "정의에 우선순위 낱말 없음"
sect "$SR" '## 종합 판정' | grep -qE '^판정: PASS$' && sect "$SR" '## 종합 판정' | grep -qE '^판정: NEEDS_FIX$' \
  && ok "A2 ★ 종합 판정이 고정 한 줄 형식(판정: PASS · 판정: NEEDS_FIX)이다" || nope "A2" "종합 판정 절에 고정 판정 줄이 없다"
! sect "$SR" '## 종합 판정' | grep -qE '⚠️|❌|\*\*PARTIAL\*\*|\*\*FAIL\*\*' \
  && ok "A3 ★ 종합 판정에 옛 3벌 낱말(⚠️ PARTIAL · ❌ FAIL)이 없다 — 훅 verdict 어휘(PASS|NEEDS_FIX)와 하나" || nope "A3" "종합 판정에 옛 낱말 잔존"
sect "$SR" '## 종합 판정' | grep -qE 'must' && sect "$SR" '## 종합 판정' | grep -qE 'should.*PASS|PASS.*should' \
  && ok "A4 ★ PASS 는 must 만 센다 — should·nice-to-have 미충족은 PASS(표에 남긴다)" || nope "A4" "종합 판정 절에 must 기준·should 예외 없음"
has "$SR" 'verdict=<PASS|NEEDS_FIX>' \
  && ok "A5 대조: 훅이 읽는 verdict 어휘(PASS|NEEDS_FIX)는 그대로" || nope "A5" "verdict 어휘 소실"
has "$SR" '기본 경로: yes' '우선순위대로 판정' 'NEEDS_CONTEXT 를 반환하지 않는다' \
  && ok "A6 ★ 기본 경로 입력 규약 — dispatch 컨텍스트 파일 없이 AC 전체로 평가한다(NEEDS_CONTEXT 로 끝나지 않는다)" || nope "A6" "기본 경로 예외 없음"

# ── 코드 리뷰어 ──
has "$CR" '기본 경로: yes' \
  && ok "B1 코드 리뷰어도 '기본 경로: yes' 를 안다(quick 경로와 같게 SKIP 하지 않는다)" || nope "B1" "기본 경로 표시 없음"

# ── 기본 경로 호출 쪽 ──
n=$(grep -cF '기본 경로: yes' "$BA")
[ "$n" -ge 2 ] && ok "C1 basic.md 가 두 리뷰어 프롬프트에 '기본 경로: yes' 를 적는다($n곳)" || nope "C1" "basic.md 의 '기본 경로: yes' $n곳 (2곳 필요)"
grep -qF 'BASE:' "$BA" && ! grep -qF '`git diff <base>...HEAD`' "$BA" \
  && ok "C2 ★ basic.md 의 diff 기준이 정의 없는 <base> 가 아니라 스크립트가 내는 BASE: 줄이다" || nope "C2" "<base> 잔존 또는 BASE: 언급 없음"
grep -qE 'should.*nice-to-have.*backlog|backlog.*should.*nice-to-have' "$BA" \
  && ok "C3 basic.md 가 B 의 should·nice-to-have 미충족을 backlog 로 남기게 한다(PR 본문 '넘긴 것')" || nope "C3" "backlog 연결 없음"
grep -qE 'should.*nice-to-have.*backlog|backlog.*should.*nice-to-have' "$IMP" \
  && ok "C4 implementing-ko 도 같은 처리(풀 경로)" || nope "C4" "implementing-ko 에 backlog 연결 없음"

# ── 구현자 ──
! grep -qF '`- [ ]` → `- [x]`' "$IM" && ! grep -qE '^10\. \*\*session-progress append\*\*' "$IM" \
  && ok "D1 ★ 구현자가 tasks.md 체크·진행 기록을 쓰라는 지시가 없다(whitelist 밖 — 부모가 남긴다)" || nope "D1" "옛 마킹·append 지시 잔존"
has "$IM" 'record-task-done.sh' \
  && ok "D2 대신 부모가 record-task-done.sh 로 남긴다고 적는다" || nope "D2" "부모 기록 안내 없음"
sed -n '3p' "$IM" | grep -qF 'session-progress·dispatch-log를 갱신' \
  && nope "D3 frontmatter description" "아직 진행 기록을 갱신한다고 적는다" || ok "D3 frontmatter description 이 진행 기록 갱신을 말하지 않는다"
has "$IM" '변이' 'git diff' 'whitelist' \
  && ok "D4 ★ 기존 동작만 고정하는 태스크는 변이로 RED 를 대신한다 — whitelist 안에서만 · git diff 로 원복 확인" || nope "D4" "변이 RED 대체 규칙 없음"
grep -qF '체크박스로 다음 태스크 식별' "$IM" \
  && nope "D5 컨텍스트 확인" "체크박스로 태스크를 고른다는 옛 문장 잔존" || ok "D5 태스크 선택을 체크박스에 의존하지 않는다"

# ── 감사 3종 · 템플릿 ──
n=$(grep -cE 'model: "sonnet"' "$SS")
[ "$n" -ge 3 ] && ok "E1 /security-scan --self-config 가 red·blue·auditor 호출에 model: \"sonnet\" 을 적는다($n곳)" || nope "E1" "model: \"sonnet\" $n곳 (3곳 필요)"
grep -qF 'verdict = BLOCK' "$AC" && nope "F1 AC 템플릿" "어느 에이전트도 내지 않는 verdict = BLOCK 잔존" || ok "F1 AC 템플릿에 없는 판정 낱말(verdict = BLOCK)이 없다"
has "$AC" 'check-regression-ac.sh' \
  && ok "F2 회귀 AC 누락은 실제로 막는 스크립트(check-regression-ac.sh)로 안내한다" || nope "F2" "스크립트 안내 없음"
grep -qF '`verify.md`에 사유 기록' "$AC" && nope "F3 should 규약" "없는 verify.md 를 안내" || ok "F3 should 미충족 기록이 없는 파일(verify.md)을 가리키지 않는다"

# ── 기본 경로 BASE: 줄 (행동) ──
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
R="$SB/r"; mkdir -p "$R" && ( cd "$R" && git init -q -b main . && git -c user.name=t -c user.email=t@e.com -c commit.gpgsign=false commit -q --allow-empty -m init && mkdir -p .specops )
FID=20261114-base-line
( cd "$R" && bash "$PLUGIN/scripts/basic-path.sh" start "$FID" "목록 화면 안내 문구를 고친다" >/dev/null 2>&1 )
if [ -f "$R/.specops/$FID/spec.md" ]; then
  python3 - "$R/.specops/$FID/spec.md" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
s=re.sub(r'\{\{[^}]*\}\}','내용',s)
if '### AC-1' not in s:
    s=re.sub(r'(^## .*수용 기준.*$)', r'\1\n\n### AC-1: 안내 문구\n\n- **Given** 목록이 비어 있다\n- **When** 화면을 연다\n- **Then** 안내 문구가 보인다\n- **우선순위**: must\n', s, count=1, flags=re.M)
open(p,'w',encoding='utf-8').write(s)
PY
  ( cd "$R" && bash "$PLUGIN/scripts/basic-path.sh" approve "$FID" >/dev/null 2>&1 )
  main_sha=$(cd "$R" && git rev-parse HEAD)
  ( cd "$R" && git switch -q -c work && echo x > a.txt && git add a.txt && git -c user.name=t -c user.email=t@e.com -c commit.gpgsign=false commit -q -m work )
  out=$(cd "$R" && bash "$PLUGIN/scripts/basic-path.sh" review "$FID" 2>&1); rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qx "BASE: $main_sha" \
    && ok "G1 ★ review 가 BASE: <기본 브랜치와의 merge-base> 를 낸다(작업 브랜치에서도 main 의 커밋)" || nope "G1" "rc=$rc out=$out"
  ( cd "$R" && git switch -q main )
  out=$(cd "$R" && bash "$PLUGIN/scripts/basic-path.sh" review "$FID" 2>&1)
  printf '%s\n' "$out" | grep -qx "BASE: $main_sha" \
    && ok "G2 기본 브랜치 위에서도 BASE: 는 HEAD(커밋 안 한 변경만 보이는 기준)" || nope "G2" "out=$out"
  R2="$SB/r2"; mkdir -p "$R2" && ( cd "$R2" && git init -q -b trunk . && git -c user.name=t -c user.email=t@e.com -c commit.gpgsign=false commit -q --allow-empty -m init && mkdir -p .specops && cp -R "$R/.specops/$FID" .specops/ && cp "$R/.specops/session-progress.md" .specops/ )
  out=$(cd "$R2" && bash "$PLUGIN/scripts/basic-path.sh" review "$FID" 2>&1); rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qE '^BASE: none' \
    && ok "G3 기본 브랜치(main·master·origin/HEAD)를 못 찾으면 BASE: none 으로 알린다(리뷰를 막지 않는다)" || nope "G3" "rc=$rc out=$out"
else
  nope "G1~G3" "픽스처: basic-path.sh start 가 spec 을 만들지 못했다"
fi

finish
