#!/usr/bin/env bash
# test-init-project-enrich.sh — /init-project Phase 11 LLM 보강 패스 계약 스캔
# FID: 20260709-init-project-llm-enrich · AC-1~AC-6 + FR-8
# 계약: 지시문 "존재" 검증 (품질은 e2e V21 placeholder 스캔 + 수동 리뷰 담당)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
CMD="$PLUGIN/commands/init-project.md"
BM_SKILL="$PLUGIN/skills/brainstorming-ko/SKILL.md"
BM_CMD="$PLUGIN/commands/brainstorming.md"
E2E_SKILL="$PLUGIN/skills/e2e-test-ko/SKILL.md"
PROCESS_TPL="$PLUGIN/templates/process-design.md"
SPEC_SKILL="$PLUGIN/skills/specifying-ko/SKILL.md"
PASS=0; FAIL=0
t() { # $1=id $2=desc $3=ERE pattern $4=file
  if grep -qE "$3" "$4"; then
    printf 'PASS %-6s %s\n' "$1" "$2"; PASS=$((PASS+1))
  else
    printf 'FAIL %-6s %s\n' "$1" "$2"; FAIL=$((FAIL+1))
  fi
}
# AC-1 Phase 11 정의
t T1.a "Phase 11 섹션 존재"        'Phase 11'                                        "$CMD"
t T1.b "깊게 제품 requirements"    'requirements\.md.*M1|깊게.*(requirements)'         "$CMD"
t T1.c "깊게 아키텍처 api/data"    'api-spec\.md.*data-model|깊게.*(api-spec)'         "$CMD"
t T1.d "얕게 운영 skip"            '얕게/스킵|constitution\.md.*test-strategy'         "$CMD"
t T1.e "단일 커밋"                  '부트스트랩\+enrich|단일 커밋'                       "$CMD"
# AC-2 PRD 초안 합성
t T2.a "PRD 6필드 초안 합성"        '6필드 초안'                                       "$CMD"
t T2.b "근거문서 부재 fallback"     '(메모 부재|다 부재).*(수동|현행)'                 "$CMD"   # 개수 비의존 — 경로가 늘 때마다 깨지지 않게(2→3: 20260716 · 3→4: 20260820 plan 0-b2)
# AC-1·AC-2 프로세스 설계 템플릿 (프로세스 단위 — 화면별 아님)
# 20260917 개명: templates/intent.md → templates/process-design.md
# (기능 단위 intent 템플릿과 이름이 겹쳐 분리 — 신 intent.md 는 별도 계약)
t T13.a "process-design 7요소 골격" '트리거·행위자·화면·API·테이블·결과·예외'          "$PROCESS_TPL"
t T13.b "process-design 예시 격리"  'specops:example:start|예시 없음'                  "$PROCESS_TPL"
# AC-4·5·9·10·11 Phase 11 화면·프로세스 보강 계약
# T13.e 는 헤더가 아니라 **계약 본문**을 잡는다 — 초안 `…(생성하지 않는|제외)` 는 같은 줄 헤더
# `**셸 3종 제외**:` 만으로 매칭돼 본문을 지워도 PASS 했다(plan-reviewer 2회차 실측: 거짓 격추).
t T13.e "allowlist 3종 미생성"      '(app-shell|셸 3종).*생성하지 않는'                "$CMD"
t T13.f "화면 .html 동시+마커삭제"  '`screens/<name>\.html` 을 \*\*함께\*\* 생성'      "$CMD"
t T13.g "overview 상태 셀 갱신"     'init 보강 \(미확정'                               "$CMD"
# T13.h — 대안 `KIND 무관 항상 산출` 은 개명 전 `:78` 에도 매치해 판별력이 0 이라 제거했다
# (T13.e·T13.l 이 겪은 "공허 매칭" 과 같은 병 — tasks.md Task 1 Step 2 주석).
t T13.h "process-design KIND 무관"  'process-design\.md.*KIND 무관'                    "$CMD"
# T13.l — process-design 골격의 출처·대상 경로 (T13.f 의 화면판과 대칭).
# `process-design.md` 는 bash 비생성분이라 이 산문이 유일한 생성 경로다 — 빠지면 LLM 이 7요소
# 골격 없이 자유 작성하거나 skip 한다. 리터럴 `templates/process-design.md` 는 `:78` 불릿에만 둔다
# (헤더에도 두면 불릿을 지워도 통과하는 공허 매칭이 된다 — T13.e 가 겪은 거짓 격추).
t T13.l "골격 출처·대상 경로"        'templates/process-design\.md` 기반으로 `\.specops/memory/process-design\.md'  "$CMD"
# T13.n — 하류 이관은 **제안만** (AC-2). 자동 개명·덮어쓰기는 사용자 주권 침해다.
t T13.n "구 intent.md 이관 제안·자동변경 금지" '구 .*intent\.md.*process-design.*제안|덮어쓰지 않' "$CMD"
# T13.m — 미확정 마커 수 **상한 없음** (사용자 결정 Q3 · AC-11 마지막 문장).
# T13.g 는 `init 보강 (미확정` 만 보므로 "최대 3개" 가 삽입돼도 통과한다 — 같은 줄이라
# 변이 실증 시 상한 문구만 지워야 T13.m 단독 격추가 확인된다.
t T13.m "마커 수 상한 없음"          '마커 수 상한.*두지 않는'                          "$CMD"
# AC-6 소비측 배선 — 생성측(Phase 11)만 강화하고 읽는 쪽을 빼먹는 패턴 차단
t T13.i "specifying 이 소비"          '\| `process-design\.md` \|'                       "$SPEC_SKILL"
t T13.j "화면 보강 DESIGN.md 준수"  'DESIGN\.md.*(§6\.1|화면 원형)'                    "$CMD"
# AC-3 사실성·상세성 계약 (Karpathy)
t T3.a "근거 N원 (3→4 진화 수용)"  '근거 [34]원'                                     "$CMD"
t T3.b "boilerplate 금지"          '(일반론|boilerplate).*금지'                        "$CMD"
t T3.c "미확정 마커"                '미확정 — 근거 필요'                               "$CMD"
t T3.d "가정: 접두"                '`가정:` 접두'                                     "$CMD"
t T3.e "개발 기준 문서 용도"        '개발 기준 문서'                                    "$CMD"
t T3.f "문서별 최소 채움/깊이 기준" '최소 (채움|깊이) 기준'                            "$CMD"
# AC-4 --enrich
t T4.a "--enrich 분기"             '\-\-enrich'                                      "$CMD"
t T4.b "멱등 — 잔존 문서만"         '잔존 문서만'                                      "$CMD"
# AC-5 무인 자동수락
t T5.a "무인 자동수락"              '자동수락'                                         "$CMD"
t T5.b "e2e·auto 명시"             '(e2e|§auto).*자동수락|자동수락.*(e2e|§auto)'       "$CMD"
# AC-6 brainstorming 안내 동기
t T9.a "brainstorming skill 동기"   'Phase 11'                                        "$BM_SKILL"
t T9.b "brainstorming command 동기" 'Phase 11'                                        "$BM_CMD"
# FR-8 e2e V21 배선 (nice-to-have)
t T9.c "e2e V21 placeholder 스캔"   'V21'                                             "$E2E_SKILL"

# T11 — Phase 11 v2 품질 계약 (FID 20260710-init-p11-quality · AC-1~AC-7)
# AC-1 인터뷰 스텝
t T11.a "Phase 11.5 인터뷰 스텝"     'Phase 11\.5'                                    "$CMD"
t T11.b "인터뷰 상한 (총≤5)"         '총 최대 5문항|최대 5문항'                         "$CMD"
t T11.c "모름/나중에 선택지 의무"    '모름/나중에'                                     "$CMD"
t T11.d "근거 4원 — 인터뷰 응답 편입" '④.*인터뷰 응답|인터뷰 응답.*④'                  "$CMD"
# AC-7 질문 선정 우선순위
t T11.e "결정급 우선 선정"           '결정급.*우선'                                    "$CMD"
# AC-2 가정 다이제스트 게이트
t T11.f "가정 전건 번호 목록"        '가정.*전건.*번호 목록|번호 목록.*가정'            "$CMD"
t T11.g "결정급 ★ 표시"             '결정급.*★'                                      "$CMD"
t T11.h "y/번호 수정 응답 규약"      '\[y/번호 수정\]'                                 "$CMD"
# AC-3 다이제스트 기록 (대화형·무인 공통, PRD 단일 출처)
t T11.i "§보강 가정 다이제스트 섹션" '§보강 가정 다이제스트'                            "$CMD"
t T11.j "무인에서도 다이제스트 기록" '무인에서도.*다이제스트|다이제스트.*무인에서도 수행' "$CMD"
# AC-4 깊이 기준 v2
t T11.k "must 빈 셀 금지"           '빈 셀 금지'                                      "$CMD"
t T11.l  "should NFR 정량화"          'NFR 정량화'                                     "$CMD"
t T11.l2 "should M2/M3 사전 분해"     'M2/M3 사전 분해'                                "$CMD"
# AC-5 무인 degrade — 양쪽 파일 동기 (전파 누락 차단)
t T11.m "무인 degrade (command)"    '인터뷰.*건별 승인.*생략|건별 승인을 생략'          "$CMD"
t T11.n "무인 degrade (e2e 동기)"   'Phase 11\.5.*생략|인터뷰.*생략'                   "$E2E_SKILL"
# AC-6 질문 스킵 주권
t T11.o "질문 스킵 주권"            '질문 스킵'                                       "$CMD"
# AC-4 must ① — M1 FR 분해 (plan-reviewer Minor 반영: 무경보 탈락 방지)
t T11.p "M1 FR 분해 필수"           '첫 마일스톤.*FR 분해|M1.*FR 분해|M1 시드를 세부 FR' "$CMD"
# AC (리뷰 fix 1) — 다이제스트 재실행 멱등 규칙
t T11.q "다이제스트 재실행 갱신 규칙"  '기존 섹션.*전건 갱신|중복 섹션 append 금지' "$CMD"
# AC (리뷰 fix 2) — V21 판정에 다이제스트 존재 assertion 배선 (bash 블록 grep 명령만 매칭)
t T11.r "V21 다이제스트 존재 검증 배선" 'grep.*§보강 가정 다이제스트' "$E2E_SKILL"
t T11.s "결정 원장 기록"            'decisions\.md|project-context\.md'               "$CMD"
t T11.t "단일 승인 게이트"          '단일 승인 게이트|1회.*요약 제시'                   "$CMD"

# T10 — V21 스캔 규약 표기 allowlist (scan-enrich-placeholders.sh 가 SoT)
# 배경: V21 원 regex 가 `.specops/<FID>` 류 규약 표기를 검출 → 정직 보강 + 정직 스캔 = 항상 FAIL.
SCAN="$PLUGIN/scripts/_internal/scan-enrich-placeholders.sh"

# T10.a 실 부트스트랩 산출물: 규약 표기 미검출 + 실 placeholder 검출 유지 (스캔 무력화 방지)
T10DIR=$(mktemp -d) || exit 1
(
  cd "$T10DIR" && git init -q \
    && git config user.email t@t && git config user.name t
  printf '3\nskip\n1. CLI fixture\n2. dev\n3. a, b, c\n4. m1\n5. m2\n6. m3\n\nN\n' \
    | RESUME_MODE=0 bash "$PLUGIN/scripts/_internal/init-project.sh" t10 >/dev/null 2>&1
)
scan_out=$(bash "$SCAN" "$T10DIR/PRD.md" "$T10DIR"/.specops/memory/*.md 2>/dev/null)
if [ -n "$scan_out" ] && ! printf '%s' "$scan_out" | grep -q '<FID>'; then
  printf 'PASS %-6s %s\n' "T10.a" "부트스트랩 산출물: 실 placeholder 검출 + <FID> 규약 제외"; PASS=$((PASS+1))
else
  printf 'FAIL %-6s %s\n' "T10.a" "부트스트랩 산출물: 실 placeholder 검출 + <FID> 규약 제외"; FAIL=$((FAIL+1))
fi
rm -rf "$T10DIR"

# T10.b 미확정 마커 줄 + 규약 표기만 → clean (exit 0)
T10F=$(mktemp) || exit 1
printf '항목: <미확정 — 근거 필요>\n참조: `.specops/<FID>/spec.md`\n상세: `screens/<name>.md`\n' > "$T10F"
if bash "$SCAN" "$T10F" >/dev/null 2>&1; then
  printf 'PASS %-6s %s\n' "T10.b" "마커 줄 + 규약 표기만 → clean exit 0"; PASS=$((PASS+1))
else
  printf 'FAIL %-6s %s\n' "T10.b" "마커 줄 + 규약 표기만 → clean exit 0"; FAIL=$((FAIL+1))
fi
rm -f "$T10F"

# T10.c 혼재 줄 (규약 표기 + 실 placeholder 동일 줄) → token-level 로 검출 유지
T10F=$(mktemp) || exit 1
printf -- '- 종속 .specops/<FID> 디렉토리: <목록>\n' > "$T10F"
if ! bash "$SCAN" "$T10F" >/dev/null 2>&1; then
  printf 'PASS %-6s %s\n' "T10.c" "혼재 줄 token-level 검출 (<목록> 잔존 적발)"; PASS=$((PASS+1))
else
  printf 'FAIL %-6s %s\n' "T10.c" "혼재 줄 token-level 검출 (<목록> 잔존 적발)"; FAIL=$((FAIL+1))
fi
rm -f "$T10F"

# T10.d e2e V21 블록이 스캔 스크립트 호출 (인라인 regex 이원화 방지)
t T10.d "e2e V21 스캔 스크립트 배선"  'scan-enrich-placeholders\.sh'                    "$E2E_SKILL"
# T10.e Phase 11 계약에 규약 표기 잔존 허용 명시
t T10.e "규약 표기 잔존 허용 계약"    '규약 표기'                                        "$CMD"

# ── T10.f HTML 주석 마커 오검출 (20260806 실측) ──────────────────────────────
# 모든 specops 템플릿은 `<!-- OWNER_COMMAND: ... -->` · `<!-- layer: ... -->` 헤더를 갖는다.
# 이건 구조 계약이라 **지울 수 없는데** 스캐너가 placeholder 로 센다 → V21(검출 0)이
# 구조적으로 달성 불가. 실측: 부트스트랩 산출물 163건 중 26건이 HTML 주석.
T10F=$(mktemp) || exit 1
printf '<!-- OWNER_COMMAND: /init-project -->\n<!-- layer: Project-Document -->\n\n# 문서\n' > "$T10F"
if bash "$SCAN" "$T10F" >/dev/null 2>&1; then
  printf 'PASS %-6s %s\n' "T10.f" "HTML 주석 마커만 → clean exit 0 (지울 수 없는 구조 계약)"; PASS=$((PASS+1))
else
  printf 'FAIL %-6s %s\n' "T10.f" "HTML 주석 마커만 → clean exit 0 (지울 수 없는 구조 계약)"; FAIL=$((FAIL+1))
fi
rm -f "$T10F"

# T10.g 주석 안에 진짜 placeholder 가 있어도 주석은 주석 — 단, 주석 **밖** 실 placeholder 는 검출 유지
T10F=$(mktemp) || exit 1
printf '<!-- layer: Project-Memory -->\n- 항목: <미기재>\n' > "$T10F"
if ! bash "$SCAN" "$T10F" >/dev/null 2>&1 \
   && bash "$SCAN" "$T10F" 2>/dev/null | grep -q '<미기재>' \
   && ! bash "$SCAN" "$T10F" 2>/dev/null | grep -q 'layer:'; then
  printf 'PASS %-6s %s\n' "T10.g" "주석 제외 후에도 실 placeholder 검출 유지"; PASS=$((PASS+1))
else
  printf 'FAIL %-6s %s\n' "T10.g" "주석 제외 후에도 실 placeholder 검출 유지"; FAIL=$((FAIL+1))
fi
rm -f "$T10F"

# ── T12: PRD.md 가 Phase 11 보강 깊이 목록에 배정돼 있는가 (담당 공백) ───────
# e2e V21 은 PRD.md 를 **스캔 대상으로 지정**하는데, Phase 11 의 깊게/얕게 목록
# 어디에도 PRD.md 가 없었다 — 게이트는 검사하는데 담당이 없는 상태.
# 실측: 부트스트랩 직후 PRD.md 에 원시 <TODO> 10곳(NFR·리스크·기술스택) 잔존.
# 느슨한 grep 은 인접 줄의 다른 PRD.md 언급(가정 다이제스트 등)에 걸려 공허하게 통과한다.
# `깊게` 블록의 **불릿 항목**으로 존재하는지만 본다 (블록 = `**깊게**` ~ 다음 빈 줄).
_deep_block=$(awk '/^\*\*깊게\*\*/{f=1;next} f&&/^$/{exit} f' "$CMD")
if printf '%s\n' "$_deep_block" | grep -qE '^- `PRD\.md`'; then
  printf 'PASS %-6s %s\n' "T12.b" "PRD.md 가 '깊게' 불릿 항목으로 명시"; PASS=$((PASS+1))
else
  printf 'FAIL %-6s %s\n' "T12.b" "PRD.md 가 '깊게' 불릿 항목으로 명시"; FAIL=$((FAIL+1))
fi
# 얕게/스킵 목록과 중복 배정되면 모순 — 한쪽에만 있어야 한다
_shallow_block=$(awk '/^\*\*얕게\/스킵\*\*/{f=1;next} f&&/^$/{exit} f' "$CMD")
if ! printf '%s\n' "_$_shallow_block" | grep -q 'PRD\.md'; then
  printf 'PASS %-6s %s\n' "T12.b2" "PRD.md 가 얕게/스킵에 중복 배정 안 됨"; PASS=$((PASS+1))
else
  printf 'FAIL %-6s %s\n' "T12.b2" "PRD.md 가 얕게/스킵에 중복 배정 안 됨"; FAIL=$((FAIL+1))
fi
# screens-overview.md 는 얕게 쪽에만 — 깊게로 승격되면 Phase 7 bash 소유권(표 본문)과 충돌한다.
# T12.b2 는 `PRD\.md` 만 보므로 이 배치를 감시하지 못한다(plan §7-4 의 서술은 실측과 달랐다).
# 블록을 재계산한다 — 위 지역 변수 재사용보다 스코프 독립이 안전하다.
_shallow2=$(awk '/^\*\*얕게\/스킵\*\*/{f=1;next} f&&/^$/{exit} f' "$CMD")
if printf '%s\n' "$_shallow2" | grep -q 'screens-overview\.md'; then
  printf 'PASS %-6s %s\n' "T13.k" "screens-overview.md 가 얕게/스킵에 유지"; PASS=$((PASS+1))
else
  printf 'FAIL %-6s %s\n' "T13.k" "screens-overview.md 가 얕게/스킵에 유지"; FAIL=$((FAIL+1))
fi
# Phase 4 확정분(§1~2)은 보강이 덮지 않는다는 경계 명시
t T12.c "Phase 4 확정분 보존 경계"    'Phase 4 확정|§1.*보존|사용자 응답.*덮어쓰기 금지' "$CMD"

# ── T13.c/T13.d: 화면·process-design 이 '깊게' 불릿 항목인지 (블록 추출) ──────
# 줄 grep 은 인접 언급(Phase 7 의 screens 서술 등)에 공허 통과한다 — T12.b 와 동일 이유.
_deep2=$(awk '/^\*\*깊게\*\*/{f=1;next} f&&/^$/{exit} f' "$CMD")
for _pair in 'T13.c|screens/<name>\.md|화면이' 'T13.d|process-design\.md|프로세스가'; do
  _id=${_pair%%|*}; _rest=${_pair#*|}; _pat=${_rest%%|*}; _what=${_rest#*|}
  if printf '%s\n' "$_deep2" | grep -qE "^- \`$_pat\`"; then
    printf 'PASS %-6s %s\n' "$_id" "$_what '깊게' 불릿 항목으로 명시"; PASS=$((PASS+1))
  else
    printf 'FAIL %-6s %s\n' "$_id" "$_what '깊게' 불릿 항목으로 명시"; FAIL=$((FAIL+1))
  fi
done
echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
