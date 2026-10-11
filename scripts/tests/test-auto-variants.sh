#!/usr/bin/env bash
# /maintain-auto · /start-lite-auto · /maintain-lite-auto 계약 — 무인 표지·자동 통과·자동 승격·끝 보고 (20261008-auto-variants)
#   무인 변형은 진입 커맨드가 args 둘째 줄에 `<!-- auto: true -->` 를 붙이고, analyzing·specifying 이 그 줄을 보고
#   spec 에 `**§auto**: true` 를 적는 것으로 성립한다. 뒤 단계는 전부 그 라벨만 본다.
#   이 사슬의 한 곳이라도 빠지면 무인 커맨드가 대화형으로 돌거나(목표 실패), 사람 검토 없이 지나간 것이 끝 보고에서 빠진다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
cd "$PLUGIN" || exit 1

MA=commands/maintain-auto.md
SLA=commands/start-lite-auto.md
MLA=commands/maintain-lite-auto.md
AN=skills/analyzing-ko/SKILL.md
SP=skills/specifying-ko/SKILL.md
DE=skills/decomposing-ko/SKILL.md
PF=skills/performance-test-ko/SKILL.md

for f in "$MA" "$SLA" "$MLA" "$AN" "$SP" "$DE" "$PF"; do
  [ -f "$f" ] || { nope "T0 파일 존재" "부재: $f"; finish; }
done
ok "T0 명령·스킬 파일 존재"

has() { local f="$1" p; shift; for p in "$@"; do grep -qE -- "$p" "$f" || return 1; done; return 0; }
# pair <file> <entry> — 약속어 줄 바로 다음 줄이 무인 표지인가(순서가 계약이다: 첫 줄로 분기, 둘째 줄로 무인)
pair() { awk -v e="<!-- entry: $2 -->" '{sub(/^[[:space:]]+/,"")} $0==e{getline n; sub(/^[[:space:]]+/,"",n); if(n=="<!-- auto: true -->") f=1} END{exit f?0:1}' "$1"; }

# T1: 세 커맨드의 진입 표지 — 약속어 + 둘째 줄 무인 표지
pair "$MA" maintain && ok "T1a maintain-auto: entry: maintain + 둘째 줄 auto: true" || nope "T1a" "표지 쌍 없음"
pair "$SLA" lite && ok "T1b start-lite-auto: entry: lite + 둘째 줄 auto: true" || nope "T1b" "표지 쌍 없음"
pair "$MLA" maintain-lite && ok "T1c maintain-lite-auto: entry: maintain-lite + 둘째 줄 auto: true" || nope "T1c" "표지 쌍 없음"

# T2: 첫 호출 skill — 유지보수 계열은 analyzing, 신규는 specifying
has "$MA" '즉시 `specops-ko:analyzing-ko` 호출' && has "$MLA" '즉시 `specops-ko:analyzing-ko` 호출' \
  && has "$SLA" '즉시 `specops-ko:specifying-ko` 호출' \
  && ok "T2 첫 호출 skill (유지보수→analyzing · 신규→specifying)" || nope "T2" "첫 호출 skill 지시 부재"

# T3: frontmatter — 사용자 전용(모델이 스스로 부르지 못한다) + 대괄호 접두 description 따옴표
okf=1
for f in "$MA" "$SLA" "$MLA"; do
  has "$f" '^disable-model-invocation: true$' '^description: "\[.*무인\]' '^specops_version: [0-9]+\.[0-9]+\.[0-9]+$' || okf=0
done
[ "$okf" = 1 ] && ok "T3 사용자 전용(disable-model-invocation) + 무인 라벨 description" || nope "T3" "frontmatter 규약 위반"

# T4: 자연어 추론 금지 · 비가역 정지 유지 · 숨김 금지 — 세 커맨드 모두
okf=1
for f in "$MA" "$SLA" "$MLA"; do
  has "$f" '자연어로 무인 모드 추론 금지' '비가역 정지를 건너뜀' '자동 통과한 것을 숨김' 'security-review-ko Critical/High' || okf=0
done
[ "$okf" = 1 ] && ok "T4 자연어 추론 금지 · 비가역·보안 정지 유지 · 숨김 금지" || nope "T4" "안전 문구 부재"

# T5: 줄어드는 것은 사람의 확인뿐 — 회귀 AC·리뷰·verify 유지 문구
has "$MA" 'AC-R-1' 'Phase B/C' 'verify' && has "$MLA" 'AC-R-1' 'Phase B/C' 'analyzing 완전 skip' \
  && has "$SLA" 'Phase B/C' '화면·IF·Phase B/C·verify 생략' \
  && ok "T5 회귀 AC·리뷰·verify 유지" || nope "T5" "유지 불변식 문구 부재"

# T6: 경량 무인의 자동 승격 — 멈추지 않고 풀 경로로, override 로 가드를 끄지 않는다
okf=1
for f in "$SLA" "$MLA"; do
  has "$f" '^## 고위험이면 자동 승격' 'LITE-STRICT-GUARD' '멈추지 않고 풀 무인 경로로 승격' 'SPECOPS_LITE_STRICT_OVERRIDE. 로 가드를 끄지 않는다' || okf=0
done
[ "$okf" = 1 ] && ok "T6 경량 무인: strict → 풀 무인 경로 자동 승격(가드 override 금지)" || nope "T6" "자동 승격 절 부재"

# ── 절 단위 단언 ──────────────────────────────────────────────────────────────
#   파일 전체 grep 은 같은 낱말이 다른 절에 있으면 대상 문장을 지워도 통과한다(독립 리뷰가 변이 16건 중 11건 생존을 확인).
#   아래는 무인 규칙이 적힌 **그 절의 본문만** 떼어 그 안에서 찾는다.
sec_h2() { awk -v h="$2" 'index($0, h)==1 {on=1; print; next} on && /^## / {exit} on' "$1"; }          # `## 제목` ~ 다음 `## `
sec_between() { awk -v a="$2" -v b="$3" 'index($0, a) {on=1} on && index($0, b) {exit} on' "$1"; }      # 시작 표지 줄 ~ 끝 표지 줄 앞
tin() { local t="$1" p; shift; for p in "$@"; do printf '%s\n' "$t" | grep -qE -- "$p" || { MISS="$p"; return 1; }; done; return 0; }

# T7: analyzing-ko `## 무인 표지` 절 — 검토만 건너뛴다 · 산출물은 그대로 · strict 는 승격 · 승격 사실을 넘긴다
A_SEC=$(sec_h2 "$AN" '## 무인 표지')
tin "$A_SEC" '분석은 \*\*그대로 하고 사람의 검토만 건너뛴다' '묻지 않고 통과' '분석 검토 자동 통과\(무인\)' \
  && ok "T7a analyzing 무인 절: 검토 자동 통과 + 통과 사실 1줄 출력" || nope "T7a" "절에 없음: $MISS"
tin "$A_SEC" '분석 산출물은 줄이지 않는다' 'check-maintain-baseline\.sh' '없으면 구현 dispatch 가 열리지 않는다' \
  && ok "T7b analyzing 무인 절: 산출물 기계 판정은 그대로" || nope "T7b" "절에 없음: $MISS"
tin "$A_SEC" '중단하지 않고 승격' '풀 체크리스트' '첫 줄을 `<!-- entry: maintain -->` 로 바꾸고' '<!-- promoted: lite -->' 'Advisor 협의 기록. 아래에도 승격 1줄' \
  && ok "T7c analyzing 무인 절: strict → 풀 분석 승격 + 승격 표지(promoted)·기록" || nope "T7c" "절에 없음: $MISS"
tin "$A_SEC" '주석 줄\(약속어·무인 표지\)을 \*\*모두\*\* 뺀 나머지' '무인 표지 줄을 지우지 않는다' \
  && ok "T7d analyzing 무인 절: 슬러그는 주석 줄 제외 · 표지는 specifying 으로 전달" || nope "T7d" "절에 없음: $MISS"
has "$AN" '^- \*\*무인 표지\*\* — args \*\*둘째 줄\*\*이 `<!-- auto: true -->` 면' '무인 표지 진입은 검토만 자동 통과한다' '무인 표지가 있으면 중단 대신 승격한다' \
  && ok "T7e analyzing 개요·HARD-GATE·lite-mini 가드가 무인 절을 가리킨다" || nope "T7e" "포인터 부재"

# T8: specifying-ko `[무인 표지 (둘째 줄)]` 절
S_SEC=$(sec_between "$SP" '**[무인 표지 (둘째 줄)]**' '1.5. **Intent 캡처')
tin "$S_SEC" '둘째 줄이 `<!-- auto: true -->`' '자연어로 추론하지 않는다' 'spec\.md 가 아직 없어도' \
  && ok "T8a specifying 무인 절: 판정(둘째 줄) · 자연어 추론 금지 · spec 이전에도 무인" || nope "T8a" "절에 없음: $MISS"
tin "$S_SEC" 'Step 3~4 의 명확화 질문' '사용자 응답 없이 지난다' '\(ASSUMED\)' '여기서 적지 않으면 어디에도 남지 않는다' \
  && ok "T8b specifying 무인 절: Step 3~4·승인 게이트 무질문 + ASSUMED 기록(lite 는 뒤에 clarify 가 없다)" || nope "T8b" "절에 없음: $MISS"
tin "$S_SEC" '`\*\*§auto\*\*: true` 를 \*\*함께\*\* 적고' '\*\*자동 결정 분석\*\*: current-state\.md' \
  && ok "T8c specifying 무인 절: §auto 동시 기재 + 자동 결정 분석" || nope "T8c" "절에 없음: $MISS"
#   ★ 승격 라벨 — trivial 로 남기면 단축 경로가 clarify·plan 을 다시 건너뛰고 §lite 가 없어 가드도 안 걸린다(리뷰 I1)
tin "$S_SEC" '`§lite` 를 적지 않고 `§유형` 은 `신규`\(`/start-lite-auto`\) 또는 `유지보수`\(`/maintain-lite-auto`\)' '`trivial` 로 적으면' \
             '\*\*자동 승격\*\*: lite → 풀 경로' '다음 skill 은 정상 경로\(`clarifying-ko`\)' \
  && ok "T8d ★ specifying 무인 절: 승격 시 §lite 미기재 · §유형=신규/유지보수 · clarifying 으로" || nope "T8d" "절에 없음: $MISS"
tin "$S_SEC" '<!-- promoted: lite -->' '승격이 PR 게이트 다이제스트에서 빠진다' \
  && ok "T8e specifying 무인 절: analyzing 의 승격 표지 → spec 의 자동 승격 줄" || nope "T8e" "절에 없음: $MISS"
has "$SP" 'auto \(무인 표지 포함\)' '§lite. 는 .## 다음 skill. 의 §lite 단축 경로로 decomposing-ko' \
          '무인 표지가 있으면 중단 대신 승격한다 — 아래' '무인 표지가 있으면 중단 대신 승격 — 아래' \
  && ok "T8f specifying: intent 표·검토 게이트·lite 가드 2곳이 무인 절과 맞물린다" || nope "T8f" "연결 문구 부재"

# T9: decomposing-ko — 무인이면 가드·규모 초과에서 묻지 않고 승격, 승격을 기록, 분석은 제자리 보강
D_GUARD=$(grep -E 'LITE-STRICT-GUARD. \(HARD GATE' "$DE")
tin "$D_GUARD" '`§auto`\(`/start-lite-auto`·`/maintain-lite-auto`\)면 묻지 않고 이 승격을 수행한다' '\*\*자동 승격\*\*: lite → 풀 경로 \(<신호>\)' \
               'Step 1~6\) 기준으로 \*\*이 자리에서\*\* 보강' '`analyzing-ko` 를 다시 호출하지 않는다' '무인에서 override env 로 가드를 끄지 않는다' \
  && ok "T9a decomposing 가드 줄: 무인 승격 · 승격 기록 · 분석 제자리 보강 · override 금지" || nope "T9a" "가드 줄에 없음: $MISS"
D_SIZE=$(grep -E '^> \*\*오판 안전망\*\*' "$DE")
tin "$D_SIZE" '`§auto` 면 묻지 않고 정상 경로로 올린다' '\*\*자동 승격\*\*: lite → 풀 경로 \(규모 초과\)' '유지보수면 분석을 먼저 보강' \
  && ok "T9b decomposing 규모 초과 줄: 무인 승격 + 같은 기록·보강" || nope "T9b" "규모 초과 줄에 없음: $MISS"

# T10: 끝 보고 — 자동 통과한 분석·자동 승격이 PR 게이트 다이제스트에 실린다
has "$PF" '자동 결정 intent\|자동 결정 분석\|자동 승격' '^### 자동 통과한 분석 · 자동 승격' \
  && ok "T10 performance-test-ko: 다이제스트 수집 grep + 제시 절에 자동 통과한 분석·자동 승격" || nope "T10" "다이제스트 절 부재"

# T10b: 커맨드 문서가 그 사슬을 그대로 말한다(진입 문서만 읽고도 경로가 같아야 한다)
has "$MA" '`\*\*§auto\*\*: true` 와 `\*\*자동 결정 분석\*\*` 1줄을 적는다' '자동 통과한 분석\*\* 절을 먼저 읽는다' \
  && has "$SLA" '`§유형: 신규` 로 적어 `/start-auto` 와 같은 경로' '큰 변경에 사용' '사람의 검토가 가장 적은 경로' \
  && has "$MLA" '<!-- promoted: lite -->' '분석을 풀 체크리스트 기준으로 보강한 뒤 clarify → plan' '사람의 검토가 가장 적은 경로' \
  && ok "T10b 커맨드 3종: spec 라벨·승격 라벨·승격 표지·규모 경고" || nope "T10b" "커맨드 문서의 사슬 문구 부재"

# T11: 뒤 단계는 spec 의 라벨만 본다 — 경량 라벨과 겹쳐도 §auto 면 리프 계약은 auto 다.
#      그리고 무인이어도 유지보수 관문(analyzing 산출물 · 회귀 AC)은 그대로 닫혀 있다 — 무인은 사람의 확인만 줄인다.
EMIT=scripts/dag/emit-context.sh; FIX=scripts/tests/dag/fixtures/emit-context/ok-fid
_emit_case() {  # $1=라벨(여러 줄) $2=baseline(yes|no) → stdout "<rc> <모드>" · 출력은 $EMIT_OUT
  local tmp d; tmp=$(mktemp -d); d="$tmp/.specops/20260902-mode"; mkdir -p "$d"; cp "$PLUGIN/$FIX"/*.md "$d/"
  grep -vE '^\*\*§(유형|lite|auto)\*\*:' "$d/spec.md" > "$tmp/s"; mv "$tmp/s" "$d/spec.md"
  printf '\n%s\n' "$1" >> "$d/spec.md"
  if [ "$2" = yes ]; then
    printf '# 현재 상태\n\n## 1. 변경 대상\n- src/a.sh:1-3 (3줄)\n\n## 4. 관찰 동작\n- 줄 수를 센다\n' > "$d/current-state.md"
    printf '# 영향 분석\n\n## 3. 회귀 영향\n- 호출자 없음\n\n## 4. Advisor 협의 기록\n해당 없음 — 불확실 지점 없음\n' > "$d/impact-analysis.md"
  fi
  EMIT_OUT=$( (cd "$tmp" && bash "$PLUGIN/$EMIT" 20260902-mode 2>&1) ); local rc=$?
  printf '%s %s\n' "$rc" "$(sed -n 's/^- 모드: \([a-z]*\).*/\1/p' "$d/dispatch/T1-context.md" 2>/dev/null | head -1)"
  rm -rf "$tmp"
}
if [ -d "$FIX" ]; then
  _T11=$(mktemp)
  _emit_case $'**§유형**: trivial\n**§lite**: true\n**§auto**: true' no > "$_T11"; r=$(cat "$_T11")
  [ "$r" = "0 auto" ] && ok "T11a 경량 라벨 + §auto → dispatch 실행 모드 auto" || nope "T11a" "r=$r out=$(printf '%s' "$EMIT_OUT" | tail -2 | tr '\n' ' ')"
  _emit_case $'**§유형**: 유지보수\n**§lite**: true\n**§auto**: true' no > "$_T11"; r=$(cat "$_T11")
  [ "${r%% *}" != 0 ] && printf '%s' "$EMIT_OUT" | grep -q 'baseline 부재' \
    && ok "T11b 무인 유지보수도 analyzing 산출물 없이는 dispatch 가 열리지 않는다" || nope "T11b" "r=$r out=$(printf '%s' "$EMIT_OUT" | tail -2 | tr '\n' ' ')"
  _emit_case $'**§유형**: 유지보수\n**§auto**: true' yes > "$_T11"; r=$(cat "$_T11")
  [ "${r%% *}" != 0 ] && printf '%s' "$EMIT_OUT" | grep -q '회귀 AC' \
    && ok "T11c 무인 유지보수도 회귀 AC(AC-R) 없이는 dispatch 가 열리지 않는다" || nope "T11c" "r=$r out=$(printf '%s' "$EMIT_OUT" | tail -2 | tr '\n' ' ')"
  rm -f "$_T11"
else
  nope "T11" "픽스처 부재: $FIX"
fi

# T12: 진입 문서 — README 진입로 표·결정 트리, CLAUDE.md 약속어 절
has README.md '/maintain-auto' '/start-lite-auto' '/maintain-lite-auto' && has CLAUDE.md '<!-- auto: true -->' '/maintain-auto' \
  && ok "T12 README 진입로 · CLAUDE.md 약속어 절에 무인 변형" || nope "T12" "진입 문서 누락"

# T13: 구조 기준선의 커맨드 수 ↔ 실제
_bl=$(jq -rs 'map(select(.category=="commands")) | .[0].count' scripts/_internal/.structure-baseline 2>/dev/null)
_ac=$(ls commands/*.md 2>/dev/null | grep -c .)
[ -n "$_bl" ] && [ "$_bl" = "$_ac" ] && ok "T13 baseline commands=$_bl ↔ 실제 $_ac" || nope "T13" "baseline=$_bl actual=$_ac — --update-baseline 필요"

finish
