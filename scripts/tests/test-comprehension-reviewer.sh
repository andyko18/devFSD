#!/usr/bin/env bash
# test-comprehension-reviewer.sh — 이해 검사 리뷰어(comprehension-reviewer-ko) 구조 잠금 (EGM 차용 1/5 · 토큰 0)
#   AC-1 에이전트 정의(evaluator 규약) · AC-2 본문 행동 계약 · README 개수·모델 표
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 실저장소를 건드리지 않는다
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || exit 1
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
cd "$PLUGIN" || exit 1

A=agents/comprehension-reviewer-ko.md
# has <file> <regex...> — 모든 패턴이 파일에 존재하면 0
has() { local f="$1"; shift; local p; for p in "$@"; do grep -qE -- "$p" "$f" 2>/dev/null || return 1; done; return 0; }

# ══ AC-1: 에이전트 정의와 evaluator 규약 ══
if [ -f "$A" ]; then ok "A1.a 에이전트 파일 존재"; else nope "A1.a" "$A 부재"; fi
FM=$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f {print}' "$A" 2>/dev/null)
printf '%s\n' "$FM" | grep -qx 'name: comprehension-reviewer-ko' && ok "A1.b name" || nope "A1.b" "name 줄 불일치"
printf '%s\n' "$FM" | grep -qx 'role: evaluator' && ok "A1.c role: evaluator" || nope "A1.c" "role: evaluator 없음"
[ "$(printf '%s\n' "$FM" | grep '^tools:')" = "tools: Read" ] && ok "A1.d tools 는 Read 하나뿐" || nope "A1.d" "tools 줄이 'tools: Read' 가 아님"
printf '%s\n' "$FM" | grep -qE '^model: (sonnet|opus)$' && printf '%s\n' "$FM" | grep -qE '^effort: (low|medium|high|xhigh|max)$' \
  && ! printf '%s\n' "$FM" | grep -qiE 'fable|claude-' && ok "A1.e 모델 별칭·effort (fable·전체 모델 ID 없음)" || nope "A1.e" "model/effort 규약 위반"
printf '%s\n' "$FM" | grep -qxF 'reference_upstream: google/elephant-goldfish-model@67353fc4 agents/comprehension.md' \
  && ok "A1.f 출처 표기(reference_upstream)" || nope "A1.f" "reference_upstream 불일치"

# ══ AC-2: 본문 행동 계약 ══
has "$A" '^### 이 문서가 제안하는 것' '^### 문서가 말하는 기존 시스템 동작' '^### 지적' \
  && ok "A2.a 출력 형식 — 재진술 2절 + 지적 절" || nope "A2.a" "출력 형식 절 누락"
l1=$(grep -n '^### 이 문서가 제안하는 것' "$A" | head -1 | cut -d: -f1); l3=$(grep -n '^### 지적' "$A" | head -1 | cut -d: -f1)
[ -n "$l1" ] && [ -n "$l3" ] && [ "$l1" -lt "$l3" ] && ok "A2.b 재진술이 지적보다 먼저" || nope "A2.b" "재진술/지적 순서 ($l1/$l3)"
has "$A" '경로 3개만' 'spec\.md' 'acceptance-criteria\.md' 'plan\.md' '그 밖의 파일은 열지 않는다' \
  && ok "A2.c 입력은 문서 3종 경로만 · 그 밖 파일 열람 금지" || nope "A2.c" "입력 한정 문구 누락"
has "$A" '\[이해 불가\]' '\[오독 위험\]' && ok "A2.d 지적 유형 2종" || nope "A2.d" "[이해 불가]/[오독 위험] 누락"
has "$A" 'Minor' 'Critical·Important 를 쓰지 않는다' && ok "A2.e 심각도 Minor 만" || nope "A2.e" "Minor 전용 문구 누락"
has "$A" '^COMPREHENSION-RESULT: DONE \(지적 N\)' && ! grep -qE '^COMPREHENSION-RESULT: (PASS|FAIL)' "$A" \
  && ok "A2.f 결과 줄 DONE (PASS/FAIL 표기 없음)" || nope "A2.f" "결과 줄 형식"
has "$A" '일반 공학 용어는 지적하지 않는다' && ok "A2.g 프로젝트 고유 용어만 지적" || nope "A2.g" "일반 공학 용어 제외 문구 누락"
o2=$(grep -n '^2\. \*\*재진술을 먼저 쓴다' "$A" | head -1 | cut -d: -f1); o3=$(grep -n '^3\. 문서를 부분' "$A" | head -1 | cut -d: -f1)
[ -n "$o2" ] && [ -n "$o3" ] && [ "$o2" -lt "$o3" ] && has "$A" '각 2~5문장' && ok "A2.h 작업 순서 — 재진술(2)이 부분별 지적(3)보다 먼저 · 각 2~5문장" || nope "A2.h" "작업 순서 문구 (2=$o2 3=$o3)"
has "$A" '코드·`\.specops/memory/\*`·`intent\.md`·다른 FID·README 포함' && ok "A2.i 열지 않을 파일 예시(코드·memory·intent·다른 FID·README)" || nope "A2.i" "금지 예시 문구 누락"

# ══ README 개수·모델 표 (AC-6 일부) ══
grep -qE 'agents/ .*← 16건' README.md && grep -qE '^│ +design-reviewer · comprehension-reviewer' README.md && ok "R.a README agents 16건 + 이름(다음 줄 이어짐)" || nope "R.a" "README agents 줄"
grep -qE '^\| comprehension-reviewer-ko .*\| sonnet · high \|' README.md && ok "R.b README 모델 표 행(sonnet · high)" || nope "R.b" "README 모델 표 행 없음"

# ══ AC-3·AC-5: planning-ko 합류·제외·기록·반영 규칙 ══
P=skills/planning-ko/SKILL.md
has "$P" '^### 이해 검사 \(comprehension-reviewer' && ok "P.a planning-ko 에 이해 검사 절" || nope "P.a" "절 제목 없음"
has "$P" 'devfsd:comprehension-reviewer-ko' '순차 추가 금지' '한 메시지의 `Agent` 호출 2개\*\*\(아래 「이해 검사」를 더하면 3개\)' \
  && ok "P.b 같은 메시지 합류(순차 추가 금지) · 1회차 동시 dispatch 문구 연동" || nope "P.b" "합류 문구 누락"
has "$P" '`§batch`\(plan-reviewer DEFER\)·`§lite`·`§유형: trivial`·promote\(`promote-fid`\)·foundation 은 부르지 않고 기록 행도 남기지 않는다' '2회차에는 부르지 않는다' \
  && ok "P.c 제외 조건 5종 · 2회차 미호출" || nope "P.c" "제외·2회차 문구 누락"
has "$P" '`PLAN-REVIEW-RESULT`·cap 계산·외부 critic 입력에 넣지 않는다' && ok "P.d 판정 불변(PLAN-REVIEW-RESULT·cap·critic)" || nope "P.d" "판정 불변 문구 누락"
has "$P" '\| comprehension \| comprehension-reviewer-ko \| 반영 \| experts/comprehension\.md' '\| comprehension \| comprehension-reviewer-ko \| 산출 없음 \|' \
  && ! grep -qE '\| comprehension \| comprehension-reviewer-ko \| (DONE|IMPL) ' "$P" \
  && ok "P.e 기록 행 형식(결과 칸 DONE·IMPL 금지)" || nope "P.e" "기록 행 형식"
has "$P" '"작성자는 안다"·"맥락상 명확하다" 는 기각 사유가 될 수 없다' '이월\(spec·AC 는 읽기 전용' '1회차 동시 dispatch」 3번 규칙대로 plan-reviewer 2회차를 부른다' \
  && ok "P.f 반영 규칙(기각 사유 금지 · 이월 · 2회차)" || nope "P.f" "반영 규칙 문구 누락"
has "$P" '모델 불가·산출 없음.*sonnet 을 쓸 수 없으면 같은 에이전트를 가용 모델 override 로 다시 dispatch 한다\(부모가 대신 검토하지 않는다\)' \
  && ok "P.g 모델 불가 — 같은 에이전트 override 재dispatch(부모 대행 금지)" || nope "P.g" "모델 불가 문구 누락"
has "$P" '1회차에는 위 「이해 검사」 의 에이전트를 같은 메시지에 더한다 — 테스트 전문가 패스 발동 여부와 무관' \
  && ok "P.h 비-batch plan-reviewer dispatch 절에도 합류 문구(테스트 전문가 미발동 경로)" || nope "P.h" "비-batch dispatch 절 연결 문구 누락"
has "$P" '비고 칸에도 `COMPREHENSION-RESULT` 줄을 옮겨 적지 않는다' \
  && ok "P.i 상세 칸에 결과 줄 금지(reconcile-check 가 dispatch-log 전체의 DONE 을 구현 증거로 읽는다)" || nope "P.i" "상세 칸 금지 문구 누락"

# ══ AC-4: plan-reviewer 와의 결합 금지 ══
[ -s agents/plan-reviewer-ko.md ] && ! grep -qiE 'comprehension|이해 검사|재진술' agents/plan-reviewer-ko.md && ok "D.a plan-reviewer-ko 본문은 이해 검사를 모른다(결합 없음 · 파일 부재 시 FAIL)" || nope "D.a" "plan-reviewer-ko 부재 또는 이해 검사·재진술 언급"

# ══ AC-7: 평가 케이스 데이터(실행 제외) ══
EV=scripts/tests/llm-eval/skills/specifying-ko/evals.json
CMP='[.cases[] | select(.agent=="comprehension-reviewer-ko")]'
[ "$(jq "$CMP | length" "$EV")" = 4 ] && ok "E.a comprehension-reviewer-ko 평가 케이스 4건" || nope "E.a" "케이스 수 $(jq "$CMP | length" "$EV")"
[ "$(jq "$CMP | map(select(.asserts[0].value | test(\"^결함\\\\(유형: .+ · 위치: \"))) | length" "$EV")" = 3 ] \
  && ok "E.b 결함 3종 — 유형·위치 기록" || nope "E.b" "결함 케이스(유형·위치) 수"
[ "$(jq "$CMP | map(select(.asserts[0].value | startswith(\"대조군\"))) | length" "$EV")" = 1 ] \
  && ok "E.c 정상 대조군 1종" || nope "E.c" "대조군 수"
e_t=0; for t in '맥락 의존 지시어' '부분 간 단절' '기존 동작 서술 모순'; do jq -e "$CMP | any(.asserts[0].value | contains(\"유형: $t\"))" "$EV" >/dev/null && e_t=$((e_t+1)); done
[ "$e_t" = 3 ] && ok "E.d 결함 유형 3종이 서로 다르다" || nope "E.d" "유형 $e_t/3"


finish
