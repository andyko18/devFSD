#!/usr/bin/env bash
# code-reviewer-ko 증거·강등 규칙 정적 잠금 — fixture 전용(실제 .specops·~/.claude 를 읽지 않는다)
# 한계: 프롬프트 문구의 존재·위치·불변식만 잠근다. 모델이 그 규칙을 실제로 따르는지는 잠글 수 없다(수동 llm-eval 몫).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
AG="$PLUGIN/agents/code-reviewer-ko.md"
SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT

ck() { if [ "$2" = "$3" ]; then echo "PASS $1"; PASS=$((PASS+1)); else echo "FAIL $1 — exp '$3' got '$2'"; FAIL=$((FAIL+1)); fi; }
yn() { if printf '%s\n' "$1" | grep -qF -- "$2"; then printf y; else printf n; fi; }
# "## 이름" 으로 시작하는 절을 다음 "## " 직전까지 뽑는다
section() { awk -v h="$2" 'index($0, h) == 1 { on = 1; print; next } /^## / { on = 0 } on' "$1"; }
# 줄 번호(줄 머리가 일치하는 첫 줄 — 본문 속 언급은 세지 않는다. 없으면 0)
lineno() { local n; n=$(awk -v h="$2" 'index($0, h) == 1 { print NR; exit }' "$1"); echo "${n:-0}"; }

# 증거 규칙 절: 존재 · [검증 불가] · Minor 강등 · 메모리 안전 · 동시성 · 호환성 · 제거 금지 · diff 블록 → 8글자
rules_check() {
  local r; r=$(section "$1" '## 증거 규칙')
  printf '%s%s%s%s%s%s%s%s' "$([ -n "$r" ] && echo y || echo n)" "$(yn "$r" '[검증 불가]')" "$(yn "$r" 'Minor')" "$(yn "$r" '메모리 안전')" "$(yn "$r" '동시성')" "$(yn "$r" '호환성')" "$(yn "$r" '제거 금지')" "$(yn "$r" 'diff 블록')"
}
# 출력 포맷의 리스크 플랜 절: 존재 · (none) · high · medium · low · 검증 명령 → 6글자, 그리고 종합 판정보다 앞인지(y/n)
risk_check() {
  local r a b; r=$(section "$1" '## 리스크 플랜')
  a=$(lineno "$1" '## 리스크 플랜'); b=$(lineno "$1" '## 종합 판정')
  printf '%s%s%s%s%s%s%s' "$([ -n "$r" ] && echo y || echo n)" "$(yn "$r" '(none)')" "$(yn "$r" 'high')" "$(yn "$r" 'medium')" "$(yn "$r" 'low')" "$(yn "$r" '검증 명령')" "$([ "$a" -gt 0 ] && [ "$a" -lt "$b" ] && echo y || echo n)"
}
# 불변식: role · model · effort · tools(Write/Edit 없음) · SubagentStop 저장 계약 → 7글자
invariants_check() {
  local f="$1" fm tools sc
  fm=$(awk 'NR == 1 && $0 == "---" { on = 1; next } on && $0 == "---" { exit } on' "$f")
  tools=$(printf '%s\n' "$fm" | grep '^tools:')
  sc=$(section "$f" '## 최종 메시지 형식')
  printf '%s%s%s%s%s%s%s' "$(yn "$fm" 'role: evaluator')" "$(yn "$fm" 'model: opus')" "$(yn "$fm" 'effort: high')" "$([ "$tools" = 'tools: Read, Grep, Glob, Bash' ] && echo y || echo n)" "$(yn "$sc" '<<<REVIEW fid=')" "$(yn "$sc" 'phase=C')" "$(yn "$sc" '<<<END>>>')"
}

# ══ AC-1: 증거 규칙 절 ══
ck "T1.a code-reviewer-ko 에 증거 규칙 절이 있고 [검증 불가]·Minor 강등·강등 금지 3영역(메모리 안전·동시성·호환성)·제거 금지·diff 블록이 모두 적혀 있다" "$(rules_check "$AG")" "yyyyyyyy"
ck "T1.b 증거 규칙 절은 프로세스 뒤·5원칙 자동 탐지 룰 앞에 정확히 한 번 있다" "$(grep -c '^## 증거 규칙' "$AG")|$([ "$(lineno "$AG" '## 프로세스')" -lt "$(lineno "$AG" '## 증거 규칙')" ] && [ "$(lineno "$AG" '## 증거 규칙')" -lt "$(lineno "$AG" '## 5원칙 자동 탐지 룰')" ] && echo ordered)" "1|ordered"
awk 'index($0, "## 증거 규칙") == 1 { skip = 1; next } /^## / { skip = 0 } !skip' "$AG" > "$SB/no-section.md"
grep -vF '메모리 안전' "$AG" > "$SB/no-areas.md"
sed 's/\[검증 불가\]/[미확인]/g' "$AG" > "$SB/no-label.md"
ck "T1.c 음성 대조: 절을 지운 사본 · 강등 금지 줄을 지운 사본 · 라벨을 바꾼 사본은 검사에서 걸린다(검사가 헛돌지 않는다)" "$(rules_check "$SB/no-section.md")|$(rules_check "$SB/no-areas.md")|$(rules_check "$SB/no-label.md")" "nnnnnnnn|yyynnnyy|ynyyyyyy"
sed 's/ — \*\*증거 인용 필수\*\*(아래 「증거 규칙」)//' "$AG" > "$SB/no-mark.md"
mark_check() { printf '%s%s' "$(grep -F '🔴 **Critical**' "$1" | head -1 | grep -qF '증거 인용 필수' && echo y || echo n)" "$(grep -F '🟡 **Important**' "$1" | head -1 | grep -qF '증거 인용 필수' && echo y || echo n)"; }
ck "T1.d 이슈 분류의 Critical·Important 줄에 증거 인용 필수 표시가 있고(음성 대조: 표시를 지운 사본은 걸린다)" "$(mark_check "$AG")|$(mark_check "$SB/no-mark.md")" "yy|nn"

# ══ AC-2: 출력 포맷·절대 금지 ══
ck "T2.a 출력 포맷에 리스크 플랜 절(high·medium·low + 검증 명령, (none) 허용)이 종합 판정 앞에 있다" "$(risk_check "$AG")" "yyyyyyy"
awk 'index($0, "## 리스크 플랜") == 1 { skip = 1; next } /^## / { skip = 0 } !skip' "$AG" > "$SB/no-risk.md"
sed 's/(none)/(비어 있음)/' "$AG" > "$SB/no-none.md"
ck "T2.b 음성 대조: 리스크 플랜 절을 지운 사본 · (none) 을 바꾼 사본은 걸린다" "$(risk_check "$SB/no-risk.md")|$(risk_check "$SB/no-none.md")" "nnnnnnn|ynyyyyy"
ck "T2.c 절대 금지 목록에 증거 없는 Critical/Important 금지가 있다" "$(yn "$(section "$AG" '## 절대 금지')" '증거 없는')" "y"

# ══ AC-3: 불변식(평가자 계약·저장 계약) ══
ck "T3.a role: evaluator · model: opus · effort: high · tools 는 Read, Grep, Glob, Bash 만(Write·Edit 없음) · SubagentStop 저장 계약 블록(<<<REVIEW fid= · phase=C · <<<END>>>)이 그대로" "$(invariants_check "$AG")" "yyyyyyy"
sed 's/^tools: Read, Grep, Glob, Bash$/tools: Read, Write, Grep, Glob, Bash/' "$AG" > "$SB/write-tool.md"
sed 's/<<<END>>>/<<<FIN>>>/' "$AG" > "$SB/no-end.md"
ck "T3.b 음성 대조: Write 도구를 준 사본 · 저장 계약 종료 마커를 바꾼 사본은 걸린다" "$(invariants_check "$SB/write-tool.md")|$(invariants_check "$SB/no-end.md")" "yyynyyy|yyyyyyn"
ck "T3.c 같은 규칙의 선례가 plan-reviewer-ko·design-reviewer-ko 에 그대로 남아 있다(참조 대상 불변)" "$(yn "$(cat "$PLUGIN/agents/plan-reviewer-ko.md")" '[검증 불가]')$(yn "$(cat "$PLUGIN/agents/design-reviewer-ko.md")" '[검증 불가]')" "yy"

# ══ AC-1: 에이전트 모델·effort 프로파일 (별칭만 · fable·전체 모델 ID 금지) ══
# $2=model $3=effort → model 일치 · effort 일치 · fable/전체 ID 부재 → 3글자
profile_check() {
  local fm; fm=$(awk 'NR == 1 && $0 == "---" { on = 1; next } on && $0 == "---" { exit } on' "$1")
  printf '%s%s%s' "$(printf '%s\n' "$fm" | grep -qx "model: $2" && echo y || echo n)" "$(printf '%s\n' "$fm" | grep -qx "effort: $3" && echo y || echo n)" "$(printf '%s\n' "$fm" | grep -qE 'fable|claude-' && echo n || echo y)"
}
ck "T4.a spec-reviewer-ko 는 sonnet·high, code-reviewer-ko 는 opus·high 이고 fable·전체 모델 ID 가 없다" "$(profile_check "$PLUGIN/agents/spec-reviewer-ko.md" sonnet high)|$(profile_check "$AG" opus high)" "yyy|yyy"
sed 's/^model: opus$/model: fable/' "$AG" > "$SB/model-fable.md"
sed 's/^effort: high$/effort: max/' "$AG" > "$SB/effort-max.md"
ck "T4.b 음성 대조: model 을 fable 로 바꾼 사본 · effort 를 바꾼 사본은 걸린다" "$(profile_check "$SB/model-fable.md" opus high)|$(profile_check "$SB/effort-max.md" opus high)" "nyn|yny"
ck "T4.c plan-reviewer-ko 는 opus·high, design-reviewer-ko 는 sonnet·high 이고 fable·전체 모델 ID 가 없다" "$(profile_check "$PLUGIN/agents/plan-reviewer-ko.md" opus high)|$(profile_check "$PLUGIN/agents/design-reviewer-ko.md" sonnet high)" "yyy|yyy"

# ══ 20261007-fable-tips: 인용 규율 · 정답 예시 · 문체 ══
_ev=$(section "$AG" '## 증거 규칙')
ck "T9.a code-reviewer 증거 규칙에 인용 규율(원문=따옴표·코드블록 / 해석=요약:)이 있다" "$(yn "$_ev" '인용 규율')$(yn "$_ev" '따옴표 또는 코드블록')$(yn "$_ev" '`요약:`')" "yyy"
ck "T9.b 정답 형태 예시 1건(요청·증거·요약·왜 올바른가)이 증거 규칙 절 안에 있다" "$(yn "$_ev" '### 정답 형태 예시')$(yn "$_ev" '증거: `printf')$(yn "$_ev" '왜 올바른가')" "yyy"
ck "T9.c code-reviewer 증거 규칙에 비유·수사 금지 문체 규칙이 있다" "$(yn "$_ev" '비유·수사 없이')" "y"
_st=""
for a in spec plan design; do f="$PLUGIN/agents/$a-reviewer-ko.md"; _st="$_st$(yn "$(section "$f" '## 보고 문체')" '원문과 요약을 구분한다')$(yn "$(section "$f" '## 보고 문체')" '비유·수사 없이')"; done
ck "T9.d spec·plan·design 리뷰어에 ## 보고 문체 절(원문/요약 구분·비유 금지)이 있다" "$_st" "yyyyyy"

# ══ 20261007-doc-conformance: 필수 지적 한정 (공식 best-practices — 적대적 리뷰어 과잉 지적 경고) ══
_ev2=$(section "$AG" '## 증거 규칙')
ck "T9.e code-reviewer: 필수(Critical·Important) 지적은 정확성·명시 요구 영향 갭으로 한정, 나머지는 Suggestion" "$(yn "$_ev2" '필수 지적은 정확성·명시 요구에 영향을 주는 갭만')$(yn "$_ev2" '취향·스타일·과잉 설계 지적은 Suggestion')" "yy"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
