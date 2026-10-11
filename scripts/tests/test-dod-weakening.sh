#!/usr/bin/env bash
# DoD 바닥선 + 기준 약화 탐지 정적 잠금 — fixture 전용(실제 .specops·~/.claude 를 읽지 않는다)
# 한계: 프롬프트·템플릿 문구의 존재·위치·불변식만 잠근다. 모델이 그 규칙을 실제로 따르는지는 잠글 수 없다(수동 llm-eval 몫).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
AG="$PLUGIN/agents/code-reviewer-ko.md"
TS="$PLUGIN/templates/test-strategy.md"
SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT

ck() { if [ "$2" = "$3" ]; then echo "PASS $1"; PASS=$((PASS+1)); else echo "FAIL $1 — exp '$3' got '$2'"; FAIL=$((FAIL+1)); fi; }
yn() { if printf '%s\n' "$1" | grep -qF -- "$2"; then printf y; else printf n; fi; }
# "## 이름" 으로 시작하는 절을 다음 "## " 직전까지 뽑는다
section() { awk -v h="$2" 'index($0, h) == 1 { on = 1; print; next } /^## / { on = 0 } on' "$1"; }
# 줄 머리가 일치하는 첫 줄 번호(본문 속 언급은 세지 않는다. 없으면 0)
lineno() { local n; n=$(awk -v h="$2" 'index($0, h) == 1 { print NR; exit }' "$1"); echo "${n:-0}"; }
# 줄 머리가 일치하는 줄의 개수
count() { awk -v h="$2" 'index($0, h) == 1 { n++ } END { print n + 0 }' "$1"; }
# a < b < c 이면 y (0 은 부재)
ordered() { if [ "$1" -gt 0 ] && [ "$1" -lt "$2" ] && [ "$2" -lt "$3" ]; then printf y; else printf n; fi; }

# ── 템플릿: DoD 절 → 존재 1회 · 위치(§6 뒤 §7 앞) · 바닥선 6항 · 예외 절차 4어 → 12글자
tpl_check() {
  local f="$1" r
  r=$(section "$f" '## 6.5. 완료 정의(DoD)')
  printf '%s%s' "$([ "$(count "$f" '## 6.5. 완료 정의(DoD)')" = 1 ] && echo y || echo n)" "$(ordered "$(lineno "$f" '## 6. 결정 기록')" "$(lineno "$f" '## 6.5. 완료 정의(DoD)')" "$(lineno "$f" '## 7. 참조')")"
  printf '%s%s%s%s%s%s' "$(yn "$r" '테스트가 통과한다')" "$(yn "$r" 'assertion')" "$(yn "$r" '억제')" "$(yn "$r" '삭제')" "$(yn "$r" '임계')" "$(yn "$r" '무력화')"
  printf '%s%s%s%s' "$(yn "$r" '예외 절차')" "$(yn "$r" 'Suggestion')" "$(yn "$r" 'Important')" "$(yn "$r" 'Critical')"
}
# ── 리뷰어: 기준 약화 탐지 절 → 존재 1회 · 위치(빈 출력 규칙 뒤 5원칙 앞) · 5클래스 · 기준점 · 증거 · 등급 3 · AC · 지우지 않는다 → 13글자
rev_check() {
  local f="$1" r
  r=$(section "$f" '## 기준 약화 탐지')
  printf '%s%s' "$([ "$(count "$f" '## 기준 약화 탐지')" = 1 ] && echo y || echo n)" "$(ordered "$(lineno "$f" '## 빈 출력 규칙')" "$(lineno "$f" '## 기준 약화 탐지')" "$(lineno "$f" '## 5원칙 자동 탐지 룰')")"
  printf '%s%s%s%s%s' "$(yn "$r" '억제 주석 신규')" "$(yn "$r" '테스트 삭제·skip')" "$(yn "$r" 'assertion 순감소')" "$(yn "$r" '임계값 하향')" "$(yn "$r" '검증 무력화')"
  printf '%s%s%s%s%s%s' "$(yn "$r" '6.5. 완료 정의(DoD)')" "$(yn "$r" 'diff 줄')" "$(yn "$r" 'Important')" "$(yn "$r" 'Critical')" "$(yn "$r" 'Suggestion')" "$(yn "$r" '지우지 않는다')"
}
# 줄 전체가 h 와 같은 첫 줄 번호 · 그 줄부터 다음 "## " 직전까지(정확 일치 — "## 기준 약화" 가 "## 기준 약화 탐지" 를 삼키지 않는다)
# BSD awk 는 `==` 를 로케일 정렬로 비교해 한글 줄이 서로 같다고 나온다 — 정확 일치는 LC_ALL=C(바이트 비교)로 한다
lineq() { local n; n=$(LC_ALL=C awk -v h="$2" '$0 == h { print NR; exit }' "$1"); echo "${n:-0}"; }
secq() { LC_ALL=C awk -v h="$2" '$0 == h { on = 1; print; next } /^## / { on = 0 } on' "$1"; }
# ── 등급 정책 문구 7종(사유 없음 Important · AC 소멸 Critical · 판정 연결 · 반-자기발급 단서 · 보고 위치 · 강등 금지 영역 · (none) 재확인) → 7글자
grade_check() {
  local r; r=$(section "$1" '## 기준 약화 탐지')
  printf '%s%s%s%s%s%s%s' "$(yn "$r" '사유가 없으면 **Important**')" "$(yn "$r" '비면 **Critical**')" "$(yn "$r" 'Critical 1건 이상이면 `NEEDS_FIX`')" "$(yn "$r" '작성자의 한 줄 해명')" "$(yn "$r" '`## 🔴 Critical`·`## 🟡 Important` 절에도')" "$(yn "$r" '강등 금지 영역')" "$(yn "$r" 'git diff --stat')"
}
# ── 프로세스·출력 포맷 연결 → 프로세스 항목 · 출력 섹션 위치(테스트 커버리지 뒤 리스크 플랜 앞) · (none) → 3글자
wire_check() {
  local f="$1"
  printf '%s%s%s' "$(yn "$(section "$f" '## 프로세스')" '기준 약화')" "$(ordered "$(lineq "$f" '## 테스트 커버리지')" "$(lineq "$f" '## 기준 약화')" "$(lineq "$f" '## 리스크 플랜')")" "$(yn "$(secq "$f" '## 기준 약화')" '(none)')"
}
# ── 기존 불변식: role · tools(Write/Edit 없음) · 저장 계약 3 · A4 증거 규칙·빈 출력 규칙·5원칙 룰 절 각 1회 → 8글자
inv_check() {
  local f="$1" fm tools sc
  fm=$(LC_ALL=C awk 'NR == 1 && $0 == "---" { on = 1; next } on && $0 == "---" { exit } on' "$f")
  tools=$(printf '%s\n' "$fm" | grep '^tools:')
  sc=$(section "$f" '## 최종 메시지 형식')
  printf '%s%s%s%s%s' "$(yn "$fm" 'role: evaluator')" "$([ "$tools" = 'tools: Read, Grep, Glob, Bash' ] && echo y || echo n)" "$(yn "$sc" '<<<REVIEW fid=')" "$(yn "$sc" 'phase=C')" "$(yn "$sc" '<<<END>>>')"
  printf '%s%s%s' "$([ "$(count "$f" '## 증거 규칙')" = 1 ] && echo y || echo n)" "$([ "$(count "$f" '## 빈 출력 규칙')" = 1 ] && echo y || echo n)" "$([ "$(count "$f" '## 5원칙 자동 탐지 룰')" = 1 ] && echo y || echo n)"
}
# ── 교차 정합: 템플릿 바닥선의 6 신호어(억제·삭제·skip·assertion·임계·무력화)가 템플릿과 리뷰어 절 양쪽에 있다 → 6글자
cross_check() {
  local t r k; t=$(section "$1" '## 6.5. 완료 정의(DoD)'); r=$(section "$2" '## 기준 약화 탐지')
  for k in 억제 삭제 skip assertion 임계 무력화; do
    if printf '%s\n' "$t" | grep -qF -- "$k" && printf '%s\n' "$r" | grep -qF -- "$k"; then printf y; else printf n; fi
  done
}

# ══ AC-1: 템플릿 DoD 절 ══
ck "T1.a test-strategy.md 에 DoD 절이 1회 · §6 뒤 §7 앞 · 바닥선 6항(테스트 통과·assertion·억제·삭제·임계·무력화) · 예외 절차(Suggestion·Important·Critical)" "$(tpl_check "$TS")" "yyyyyyyyyyyy"
ck "T1.b 기존 절 번호 불변: §1~§7 제목이 그대로 있고 6.5 가 재번호를 일으키지 않는다" "$(for h in '## 1. 테스트 피라미드 정책' '## 2. 테스트 도구' '## 3. 커버리지 목표' '## 4. 회귀 테스트 정책' '## 4.5. 마이그레이션 테스트 정책' '## 5. CI 통합' '## 6. 결정 기록' '## 7. 참조'; do count "$TS" "$h"; done | tr -d '\n')" "11111111"
awk 'index($0, "## 6.5. 완료 정의(DoD)") == 1 { skip = 1; next } /^## / { skip = 0 } !skip' "$TS" > "$SB/ts-nosec.md"
grep -vF '임계' "$TS" > "$SB/ts-noroof.md"
awk 'index($0, "## 6.5. 완료 정의(DoD)") == 1 { on = 1 } on && /^## 7\./ { on = 0 } { if (on) held = held $0 "\n"; else print } END { printf "%s", held }' "$TS" > "$SB/ts-moved.md"
sed 's/예외 절차/예외/' "$TS" > "$SB/ts-noexc.md"
ck "T1.c 음성 대조: 절을 지운 사본 · 임계 줄을 지운 사본 · 절을 맨 끝으로 옮긴 사본 · 예외 절차 어휘를 바꾼 사본은 걸린다(검사가 헛돌지 않는다)" "$(tpl_check "$SB/ts-nosec.md")|$(tpl_check "$SB/ts-noroof.md")|$(tpl_check "$SB/ts-moved.md")|$(tpl_check "$SB/ts-noexc.md")" "nnnnnnnnnnnn|yyyyyynyyyyy|ynyyyyyyyyyy|yyyyyyyynyyy"

# ══ AC-2: 리뷰어 기준 약화 탐지 절 ══
ck "T2.a code-reviewer-ko 에 기준 약화 탐지 절이 1회 · 빈 출력 규칙 뒤 5원칙 룰 앞 · 5클래스 · 프로젝트 DoD 기준점 · diff 줄 증거 · Important·Critical·Suggestion · 지우지 않는다" "$(rev_check "$AG")" "yyyyyyyyyyyyy"
awk 'index($0, "## 기준 약화 탐지") == 1 { skip = 1; next } /^## / { skip = 0 } !skip' "$AG" > "$SB/ag-nosec.md"
awk 'index($0, "## 기준 약화 탐지") == 1 { on = 1 } /^## / && index($0, "## 기준 약화 탐지") != 1 { on = 0 } on && /검증 무력화/ { next } { print }' "$AG" > "$SB/ag-noclass.md"
awk 'index($0, "## 기준 약화 탐지") == 1 { on = 1; print; next } /^## / { on = 0 } on { gsub(/Critical/, "Minor") } { print }' "$AG" > "$SB/ag-nocrit.md"
awk 'index($0, "## 기준 약화 탐지") == 1 { on = 1; print; next } /^## / { on = 0 } on { gsub(/지우지 않는다/, "정리한다") } { print }' "$AG" > "$SB/ag-erase.md"
ck "T2.b 음성 대조: 절을 지운 사본 · 클래스 줄을 지운 사본 · Critical 등급을 바꾼 사본 · 지우지 않는다를 뒤집은 사본은 걸린다" "$(rev_check "$SB/ag-nosec.md")|$(rev_check "$SB/ag-noclass.md")|$(rev_check "$SB/ag-nocrit.md")|$(rev_check "$SB/ag-erase.md")" "nnnnnnnnnnnnn|yyyyyynyyyyyy|yyyyyyyyyynyy|yyyyyyyyyyyyn"
ck "T2.c 교차 정합: 템플릿 바닥선의 신호어 6종(억제·삭제·skip·assertion·임계·무력화)이 템플릿과 리뷰어 절 양쪽에 있다" "$(cross_check "$TS" "$AG")" "yyyyyy"
ck "T2.d 교차 음성 대조: 템플릿에서 임계 줄을 지운 사본 · 리뷰어에서 클래스 줄을 지운 사본은 걸린다" "$(cross_check "$SB/ts-noroof.md" "$AG")|$(cross_check "$TS" "$SB/ag-noclass.md")" "yyyyny|yyyyyn"

ck "T2.e 등급 정책 문구 7종이 모두 있다(사유 없음 Important · AC 소멸 Critical · Critical 1건 이상 NEEDS_FIX · 한 줄 해명 단서 · 🔴·🟡 절 보고 · 강등 금지 영역 · git diff --stat 재확인)" "$(grade_check "$AG")" "yyyyyyy"
sed 's/사유가 없으면 \*\*Important\*\*/사유가 없으면 **Critical**/' "$AG" > "$SB/ag-swap.md"
sed 's/Critical 1건 이상이면 `NEEDS_FIX`/Critical 1건 이상이면 `READY_TO_MERGE`/' "$AG" > "$SB/ag-verdict.md"
sed 's/작성자의 한 줄 해명/작성자 해명/' "$AG" > "$SB/ag-selfgrant.md"
sed 's/`## 🔴 Critical`·`## 🟡 Important` 절에도/표에만/' "$AG" > "$SB/ag-where.md"
ck "T2.f 음성 대조: 등급을 맞바꾼 사본 · 판정 연결을 뒤집은 사본 · 한 줄 해명 단서를 지운 사본 · 보고 위치를 지운 사본은 각자 해당 위치에서 걸린다(침묵 통과 없음)" "$(grade_check "$SB/ag-swap.md")|$(grade_check "$SB/ag-verdict.md")|$(grade_check "$SB/ag-selfgrant.md")|$(grade_check "$SB/ag-where.md")" "nyyyyyy|yynyyyy|yyynyyy|yyyynyy"

# ══ AC-3: 프로세스·출력 포맷 연결 · 기존 불변식 ══
ck "T3.a 프로세스에 기준 약화 평가 항목 · 출력 포맷 기준 약화 섹션이 테스트 커버리지 뒤 리스크 플랜 앞 · (none) 허용" "$(wire_check "$AG")" "yyy"
LC_ALL=C awk '$0 == "## 기준 약화" { skip = 1; next } /^## / { skip = 0 } !skip' "$AG" > "$SB/ag-nowire.md"
LC_ALL=C awk '$0 == "## 기준 약화" { on = 1 } on && /^## 리스크 플랜/ { on = 0 } { if (on) held = held $0 "\n"; else print } /^## 종합 판정/ { printf "%s", held; held = "" } END { printf "%s", held }' "$AG" > "$SB/ag-wiremoved.md"
ck "T3.b 음성 대조: 출력 섹션을 지운 사본 · 리스크 플랜 뒤로 옮긴 사본은 걸린다" "$(wire_check "$SB/ag-nowire.md")|$(wire_check "$SB/ag-wiremoved.md")" "ynn|yny"
ck "T3.c 기존 불변식 보존: role evaluator · tools(Read, Grep, Glob, Bash) · 저장 계약(<<<REVIEW fid= · phase=C · <<<END>>>) · 증거 규칙·빈 출력 규칙·5원칙 룰 절 각 1회" "$(inv_check "$AG")" "yyyyyyyy"
sed 's/^tools: Read, Grep, Glob, Bash$/tools: Read, Write, Grep, Glob, Bash/' "$AG" > "$SB/ag-write.md"
sed 's/<<<END>>>/<<<FIN>>>/' "$AG" > "$SB/ag-noend.md"
awk 'index($0, "## 증거 규칙") == 1 { skip = 1; next } /^## / { skip = 0 } !skip' "$AG" > "$SB/ag-noevid.md"
ck "T3.d 음성 대조: Write 를 준 사본 · 저장 계약 종료 마커를 바꾼 사본 · A4 증거 규칙 절을 지운 사본은 걸린다" "$(inv_check "$SB/ag-write.md")|$(inv_check "$SB/ag-noend.md")|$(inv_check "$SB/ag-noevid.md")" "ynyyyyyy|yyyynyyy|yyyyynyy"

# 출력 헤딩 `## 기준 약화` 는 정확히 1회(중복되면 위치 검사가 첫 줄만 본다)
cntq() { LC_ALL=C awk -v h="$2" '$0 == h { n++ } END { print n + 0 }' "$1"; }
LC_ALL=C awk '{ print } $0 == "## 기준 약화" { print }' "$AG" > "$SB/ag-dupout.md"
ck "T3.e 출력 헤딩 ## 기준 약화 는 정확히 1회 · 헤딩을 중복한 사본은 걸린다" "$(cntq "$AG" '## 기준 약화')|$(cntq "$SB/ag-dupout.md" '## 기준 약화')" "1|2"

# ══ 한계 고지 ══
ck "T4.a 이 스위트의 머리에 한계(문구의 존재·위치만 잠그고 모델 준수는 수동 llm-eval 몫)가 적혀 있다" "$(head -4 "${BASH_SOURCE[0]}" | grep -c -e '모델이 그 규칙을 실제로 따르는지' -e '수동 llm-eval')" "1"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
