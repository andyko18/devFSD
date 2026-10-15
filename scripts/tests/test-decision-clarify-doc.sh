#!/usr/bin/env bash
# 명확화 추천 먼저·범주표 + 원장 이유·대안 기록 지시 — 문구 잠금 (20261015-design-quality-stage1)
#
# 지침 문서의 계약이라 실행 검사 대신 핵심 문구를 잠근다. 문구가 빠지면 모델이 그 규칙을 받지 못한다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CL="$PLUGIN/skills/clarifying-ko/SKILL.md"
IP="$PLUGIN/commands/init-project.md"

# 추천 먼저 규칙 — 파일 인자로 받아 변이 검사에 재사용한다
_recommend_ok() {
  grep -qF '추천 선택지와 근거 한 줄을 맨 앞에' "$1" && grep -qF '"추천대로"' "$1"
}

# C1: 대화 규칙 — 추천 먼저 · "추천대로" 수락
_recommend_ok "$CL" && ok "C1 추천 먼저·추천대로 규칙" || nope "C1" "clarifying-ko 대화 규칙 미갱신"

# C2: 5원칙 4행 — 옵션만 제시가 아니라 추천 먼저·선택은 사용자
row=$(grep -E '^\| 4 \*\*주권 존중\*\*' "$CL")
printf '%s' "$row" | grep -qF '추천은 근거와 함께 먼저 제시하되 선택은 사용자' \
  && ! printf '%s' "$row" | grep -qF '옵션만 제시' \
  && ok "C2 5원칙 4행 갱신" || nope "C2" "row=$row"

# C3: 범주표 8범주 — 절 안에 표 행으로 모두
blk=$(awk '/^### 범주표 \(빈 곳 훑기\)/{f=1;next} f&&/^\*\*BLOCKING\*\*/{exit} f' "$CL")
miss=""
for c in '기능 범위' '데이터' '화면 흐름' '비기능' '외부 연동' '예외·경계' '용어' '완료 신호'; do
  printf '%s\n' "$blk" | grep -qF "| $c |" || miss="$miss $c"
done
[ -n "$blk" ] && [ -z "$miss" ] && ok "C3 범주표 8범주" || nope "C3" "절 부재 또는 누락:$miss"

# C4: 범주표가 확인됨·부분·빠짐으로 보고 BLOCKING/DESIRABLE 기준은 그대로
printf '%s' "$blk" | grep -qF '확인됨 · 부분 · 빠짐' \
  && ok "C4 범주 판정 3단" || nope "C4" "확인됨·부분·빠짐 문구 부재"

# C5: 경량 모드의 DESIRABLE 발굴이 범주표를 쓴다
grep -qF '범주표로 훑어' "$CL" && ok "C5 경량 모드 범주표 사용" || nope "C5" "경량 모드 미갱신"

# C6: clarifications.md 형식 — 범주 점검 줄 · 추천 줄
grep -qF '**범주 점검**: 빠짐 N · 부분 M' "$CL" && grep -qF '**추천**: <선택지 — 근거 한 줄>' "$CL" \
  && ok "C6 clarifications 형식(범주 점검·추천)" || nope "C6" "형식 블록 미갱신"

# C7: 원장 기록 지시 — 이유·검토한 대안 · 5칸 확장법 · 판정기 지목 유지
grep -qF '이유 한 줄과 검토한 대안' "$CL" && grep -qF '머리·구분선 끝에' "$CL" \
  && grep -qF 'check-decisions-ledger.sh' "$CL" \
  && ok "C7 clarifying 원장 기록 지시" || nope "C7" "원장 upsert 지시 미갱신"

# C8: init 의 원장 upsert 지시 두 곳(디자인 방향 · Phase 0/11.5) 각각 이유·검토한 대안
l89=$(grep -E '^- `DESIGN\.md` — \*\*UI KIND일 때만\*\*' "$IP")
l140=$(grep -E '^- \*\*동시\*\*: .*decisions\.md' "$IP")
printf '%s' "$l89" | grep -qF '이유·검토한 대안' && printf '%s' "$l140" | grep -qF '이유·검토한 대안' \
  && ok "C8 init 원장 기록 지시 2곳" || nope "C8" "디자인 방향 줄 또는 동시 줄 미갱신"

# C9: §auto 블록 핵심 문장 보존 (무인 동작 불변)
grep -qF 'best-guess 자동 응답' "$CL" && grep -qF '`status: ASSUMED` 기재' "$CL" \
  && ok "C9 §auto 블록 보존" || nope "C9" "§auto 문장 변경됨"

# C11: 예시 질문이 추천 줄로 시작한다 (AC-3 예시)
grep -qF '추천: (1) 파일 캐시' "$CL" && grep -qF '사용자: "추천대로"' "$CL" \
  && ok "C11 예시 추천 형식" || nope "C11" "예시 미갱신"

# C10 (변이): 추천 규칙 줄을 지운 사본에서 C1 판정이 실패해야 한다 — 잠금이 살아 있음
TMP=$(mktemp)
grep -vF '추천 선택지와 근거 한 줄을 맨 앞에' "$CL" > "$TMP"
_recommend_ok "$TMP" && nope "C10 변이" "규칙을 지워도 통과 — 잠금 무효" || ok "C10 변이 적발"
rm -f "$TMP"

finish
