#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
META="$PLUGIN/skills/using-specops-ko/SKILL.md"
# pending 절차는 메타 skill 밖 참조 파일로 옮겨졌다 (20260911-meta-skill-progressive-disclosure) —
#   SessionStart 인라인 예산(문자 10,000) 때문에 필요할 때만 읽힌다. 절차 키워드는 이 파일에서 잠근다.
FREEWORK="$PLUGIN/skills/using-specops-ko/freework-pending.md"

# T5.a 처리 규약 섹션 + 핵심 단계 키워드 존재
if grep -q '자유작업 pending 처리' "$FREEWORK" && \
   grep -q 'freelog.md' "$FREEWORK" && \
   grep -q 'gbrain-append' "$FREEWORK" && \
   grep -q '1줄 보고' "$FREEWORK" && \
   grep -q '재분류' "$FREEWORK"; then
  PASS=$((PASS+1)); echo "PASS T5.a 처리 규약 섹션"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.a"
fi
# T5.b 메타 skill 에는 절차 본문이 없고 참조 파일 포인터만 있다 (중복 = 예산 낭비 + 두 곳 drift)
#   ★ 앵커 고유성: 'using-specops-ko/freework-pending.md' 는 SKILL.md 포인터 행에만 있다 (grep -c = 1)
if ! grep -q 'freework-resolve-fid' "$META" && [ "$(grep -c 'using-specops-ko/freework-pending.md' "$META")" -eq 1 ]; then
  PASS=$((PASS+1)); echo "PASS T5.b 메타 skill 은 포인터만 (절차 본문 없음)"
else
  FAIL=$((FAIL+1)); echo "FAIL T5.b — 메타 skill 에 절차 본문 잔존 또는 포인터 부재"
fi
# T: freework.md 템플릿 5필드 존재 (AC-7)
TPL="$PLUGIN/templates/freework.md"
if [ -f "$TPL" ] && grep -q 'type' "$TPL" && grep -q 'files' "$TPL" \
   && grep -q 'prompt' "$TPL" && grep -q '요약' "$TPL" && grep -q 'ts' "$TPL"; then
  PASS=$((PASS+1)); echo "PASS freework.md 5필드"
else
  FAIL=$((FAIL+1)); echo "FAIL freework.md 템플릿"
fi
# T4: 분기 지시 키워드 존재 (AC-3,4,5,6,8,9,10,11,12)
if grep -q 'freework-resolve-fid' "$FREEWORK" && \
   grep -q 'freework.md' "$FREEWORK" && \
   grep -q 'ATTACH' "$FREEWORK" && \
   grep -q '\-\-fid' "$FREEWORK"; then
  PASS=$((PASS+1)); echo "PASS T4 분기 지시 키워드"
else
  FAIL=$((FAIL+1)); echo "FAIL T4 분기 지시 키워드"
fi
# ★★ 이 스위트의 교훈 (T6.a·T6.b·T6.c 가 순차로 같은 결함을 냈다 — 3회차) ★★
#   grep 앵커는 **검사 대상 행에만 존재하는 고유 문구**여야 한다.
#   파일 다른 곳에도 있으면 그 행을 통째로 지워도 PASS 한다 = tautology(거짓 안심)이며,
#   mutation(행 삭제 후 FAIL 확인) 없이는 절대 발견되지 않는다.
#   앵커 추가 시 반드시: grep -c '<앵커>' SKILL.md  → 결과가 정확히 1 인지 확인할 것.
#   (실례: 'PPT' 는 L34·L153 양쪽에 있어 count=2 → 앵커로 쓰면 안 된다. 'PPT·Excel' 은 count=1.)

# T6.a 배제 조건 본체 존재 (20260713-signal-coding-gate AC-1·AC-2)
#   블랙리스트 방식: "1% 라도 호출" 유지 + 좁은 배제 + "애매하면 호출"(안전측)
#   ★ 고유 문구 앵커 — '배제 조건'·'repo 밖' 은 적색 플래그 표(L151·L153)에도 있어
#     배제 조건 정의행을 삭제해도 PASS 하던 tautology 였다 (code-reviewer Phase C mutation 실측)
if grep -q '진입을 보류' "$META" && \
   grep -q 'PPT·Excel' "$META" && \
   grep -q '애매하면 호출' "$META"; then
  PASS=$((PASS+1)); echo "PASS T6.a 배제 조건 본체 (진입 보류 + repo 밖 산출물 예시 + 애매하면 호출)"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.a — 배제 조건 정의행(진입 보류/PPT·Excel) 또는 '애매하면 호출' 누락"
fi

# T6.e ★ 회귀 — repo 내 파일은 문서라도 **진입** 보장 (AC-7. false-negative 최대 위험)
#   README·CLAUDE.md 등 문서 편집을 배제로 오분류하면 코딩 작업을 통째로 놓친다.
#   ★ 고유 문구 앵커 — count=1 확인 완료
if grep -q 'README·CLAUDE.md' "$META"; then
  PASS=$((PASS+1)); echo "PASS T6.e repo 내 문서도 진입 (AC-7)"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.e — repo 내 파일(문서 포함) 진입 보장 행 부재 = 배제 과잉 위험"
fi

# T6.b 배제 시 고지 + /start 탈출구 (AC-3 — false-negative 안전망)
#   ★ 고유 문구로 앵커 — '/start'·'안내' 는 이미 SKILL.md 에 존재해 tautology 였다 (plan-reviewer I-1)
if grep -q 'lifecycle 을 진입하지 않았습니다' "$META" && grep -q '강제 진입' "$META"; then
  PASS=$((PASS+1)); echo "PASS T6.b 배제 고지 + /start 강제 진입 탈출구"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.b — 배제 고지 문구 또는 강제 진입 탈출구 부재"
fi

# T6.c 적색 플래그 대칭 — 과잉 발동도 적색 플래그 (AC-4)
#   ★ 고유 문구 단독 앵커 — '공회전' 은 배제 조건 블록에도 있어 행 삭제해도 PASS 하는 반쪽 tautology 였다 (code-reviewer I-2)
if grep -q '과잉 발동' "$META"; then
  PASS=$((PASS+1)); echo "PASS T6.c 적색 플래그 대칭 (과잉 발동)"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.c — 적색 플래그 반대 방향 행 부재"
fi

# T6.d ★ 회귀 — "1% 라도 호출" 정신 보존 (AC-2. 화이트리스트 전환 금지)
if grep -q '1% 가능성이라도' "$META"; then
  PASS=$((PASS+1)); echo "PASS T6.d 1% 정신 보존 (블랙리스트 유지)"
else
  FAIL=$((FAIL+1)); echo "FAIL T6.d — '1% 가능성이라도' 문구 소실 = 화이트리스트 전환 위험"
fi
# T7.a 민감 문자열 제외·마스킹 한계·redact_failed 설명 (AC-8 · AC-10)
if grep -q '민감' "$FREEWORK" && grep -q '완전 보장' "$FREEWORK" && grep -q 'redact_failed' "$FREEWORK" \
   && grep -q '완전 보장이 아니다' "$PLUGIN/scripts/_internal/redact.sh" 2>/dev/null; then
  PASS=$((PASS+1)); echo "PASS T7.a 민감 문자열 제외·한계·redact_failed 지침"
else
  FAIL=$((FAIL+1)); echo "FAIL T7.a 민감 문자열 제외·한계·redact_failed 지침"
fi
echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
