#!/usr/bin/env bash
# 인터페이스 설계 경로 분업 문서 검증 (FID 20260710-design-interface-slash)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
DI="$PLUGIN/commands/design-interface.md"
DIS="$PLUGIN/commands/design-interfaces.md"
SP="$PLUGIN/skills/specifying-ko/SKILL.md"

# AC-1: 단수 무스크립트 + 마스터 append
grep -q '^## 인터페이스 설계 경로 분업' "$DI" && grep -q 'api-spec.md' "$DI" && grep -q 'data-model.md' "$DI" \
  && ! grep -q 'design-interface.sh' "$DI" \
  && ok "AC-1 단수 무스크립트+마스터 append" || nope "AC-1" "무스크립트/마스터 계약 누락"
# AC-2: 복수 오케스트레이터
grep -q '목록 자동 판단' "$DIS" && grep -q '순차' "$DIS" \
  && ok "AC-2 복수 오케스트레이터" || nope "AC-2" "목록/순차 누락"
# AC-3: 화면→API 도출
grep -qiE 'screens/.*Interactions|Interactions.*스캔' "$DI" \
  && ok "AC-3 화면→API 도출" || nope "AC-3" "화면 도출 없음"
# AC-4: 채택 섹션 + 부재 가드
DTBL=$(awk '/^### Step 3/,/^## 안티패턴/' "$DI")
printf '%s' "$DTBL" | grep -q '채택' && printf '%s' "$DTBL" | grep -q '부재' \
  && ok "AC-4 채택섹션+부재가드" || nope "AC-4" "채택/부재 누락"
# AC-5: cross-ref 단일출처(단수) + Step5.6 동기(양쪽)
grep -q '^## 인터페이스 설계 경로 분업' "$DI" \
  && awk '/^5\.6\./,/^6\. /' "$SP" | grep -qE '/design-interface' \
  && ok "AC-5 cross-ref 단일출처+Step5.6 동기" || nope "AC-5" "한쪽 누락"
# AC-6: false-pass 방지 — 분업표 블록 내부 한정 (+ Phase 2.5-B batch 경로)
TBL=$(awk '/^## 인터페이스 설계 경로 분업/,/^## Process/' "$DI")
printf '%s' "$TBL" | grep -qiE 'lifecycle 자동' && printf '%s' "$TBL" | grep -qiE '독립' \
  && printf '%s' "$TBL" | grep -q 'Phase 2.5-B' \
  && ok "AC-6 표내부 한정(false-pass 방지)" || nope "AC-6" "표 내부 기준 없음"
# AC-8: 소비 API 대상
grep -q 'api-spec-consumer' "$DI" && ok "AC-8 소비 API 대상" || nope "AC-8" "consumer 누락"
# AC-9: 복수 이중 근거
grep -qiE 'Interactions' "$DIS" && grep -qiE 'requirements.md FR|FR 표' "$DIS" \
  && ok "AC-9 복수 이중근거" || nope "AC-9" "이중근거 누락"
# AC-9b: 복수→단수 고유 cross-ref (대칭 원본 AC-3 회귀 안전망 — plan-reviewer Minor)
grep -q '§인터페이스 설계 경로 분업' "$DIS" \
  && ok "AC-9b 복수 고유 cross-ref" || nope "AC-9b" "고유 cross-ref 없음"

# AC-10: Step 5.6 클라이언트 스토리지 축 (localStorage-only 앱 skip 방지) — Step5.6 블록 한정(AC-R-1 선례)
awk '/^5\.6\./,/^6\. /' "$SP" | grep -qE '클라이언트 영속 데이터|localStorage·IndexedDB' \
  && ok "AC-10 Step5.6 클라이언트 스토리지 축" || nope "AC-10" "클라이언트 스토리지 축 없음"
# AC-11: design-interface Step3 클라이언트 스토리지 전용 data-model 분기 (plan-reviewer Minor: teeth 강화)
grep -q '클라이언트 스토리지' "$DI" && grep -qE '클라이언트 스토리지.*data-model|저장 키.*append|objectStore·keyPath' "$DI" \
  && ok "AC-11 design-interface Step3 클라이언트 스토리지 data-model" || nope "AC-11" "클라이언트 스토리지 분기 없음"
# AC-11b: design-interface Step2 저장방식 3택 한 줄 (teeth 강화 — Phase C Important)
grep -qE '제공 API.*외부 소비 API.*클라이언트 스토리지' "$DI" \
  && ok "AC-11b Step2 저장방식 3택" || nope "AC-11b" "3택 한 줄 없음"
# AC-12: 순수 UI·CLI skip 보존 (과확대 방지 — AC-R-2) — Step5.6 블록 한정(AC-R-1 선례)
awk '/^5\.6\./,/^6\. /' "$SP" | grep -qE '순수 UI·CLI 로직만이면.*skip|순수 UI·CLI.*skip' \
  && ok "AC-12 순수 UI·CLI skip 보존" || nope "AC-12" "skip 문구 소실"
# AC-13: templates data-model 유형 확장
grep -qE 'localStorage / IndexedDB|localStorage·IndexedDB' "$PLUGIN/templates/data-model.md" \
  && ok "AC-13 data-model 유형 확장" || nope "AC-13" "localStorage 유형 없음"

# AC-R-1: Step5.6 기존 로직 보존
awk '/^5\.6\./,/^6\. /' "$SP" | grep -q '채택된 정의방식' && ok "AC-R-1 Step5.6 로직 보존" || nope "AC-R-1" "기존 로직 소실"

# AC-14: verify 역방향 안전망 클라이언트 스토리지 커버 (P1-4 audit 20260710)
grep -qE 'localStorage|objectStore' "$PLUGIN/skills/verifying-evidence-ko/SKILL.md" \
  && ok "AC-14 verify net 클라이언트 스토리지" || nope "AC-14" "verify 추출 대상에 localStorage/objectStore 없음"

# AC-15: verify 역방향 안전망 소비 IF 축 (C2 20260716 — 소비 IF 만 정방향뿐인 반쪽 안전망 복원)
#   추출 대상(외부 API 소비 호출)과 대조 대상(api-spec-consumer.md) 둘 다 있어야 한다.
n=$(grep -c 'api-spec-consumer' "$PLUGIN/skills/verifying-evidence-ko/SKILL.md")
[ "$n" -ge 2 ] && grep -q '외부 API 소비 호출' "$PLUGIN/skills/verifying-evidence-ko/SKILL.md" \
  && ok "AC-15 verify net 소비 IF 축 (consumer ${n}곳 + 추출 대상)" || nope "AC-15" "consumer=$n (기대 ≥2) 또는 추출 대상 없음"

# AC-16: implementing §설계 계약 + emit-context §6 에 consumer 대칭 (C2)
grep -q 'api-spec-consumer' "$PLUGIN/skills/implementing-ko/SKILL.md" \
  && grep -q 'api-spec-consumer' "$PLUGIN/scripts/dag/emit-context.sh" \
  && ok "AC-16 소비 IF 계약 대칭 (implementing + emit-context)" || nope "AC-16" "consumer 계약 미대칭"

# ── DB lifecycle gap3/5/6 배선 (20260716 — #152 잔여 종결) ──
# AC-17 (gap3): test-strategy 마이그레이션 테스트 정책 + tdd-ko DDL TDD 힌트
grep -q '4.5. 마이그레이션 테스트 정책' "$PLUGIN/templates/test-strategy.md" \
  && grep -q 'up → down → up' "$PLUGIN/templates/test-strategy.md" \
  && grep -q '마이그레이션(DDL)도 TDD' "$PLUGIN/skills/tdd-ko/SKILL.md" \
  && ok "AC-17 gap3 마이그레이션 테스트 정책 (test-strategy §4.5 + tdd-ko)" || nope "AC-17" "gap3 배선 누락"
# AC-18 (gap5): verify 스키마 추출 heuristic 도구별 명세 + ERD 수기 한계 고백
grep -q '스키마 추출 heuristic' "$PLUGIN/skills/verifying-evidence-ko/SKILL.md" \
  && grep -q 'alembic/versions' "$PLUGIN/skills/verifying-evidence-ko/SKILL.md" \
  && grep -q '§3 엔티티 표' "$PLUGIN/skills/verifying-evidence-ko/SKILL.md" \
  && ok "AC-18 gap5 verify 스키마 추출 명세 (+ERD 한계)" || nope "AC-18" "gap5 배선 누락"
# AC-19 (gap6): data-model 비-PG 주의 노트 (MySQL/SQLite/MongoDB 치환 + document 모델)
grep -q '비-PostgreSQL 주의' "$PLUGIN/templates/data-model.md" \
  && grep -q 'FTS5' "$PLUGIN/templates/data-model.md" \
  && grep -q 'jsonSchema' "$PLUGIN/templates/data-model.md" \
  && ok "AC-19 gap6 data-model 비-PG 조건부화" || nope "AC-19" "gap6 배선 누락"

# ── description 관할 한정 (FID 20260904-design-cmd-scope-desc) ──
# AC-20: description 2건이 관할(lifecycle 밖) + lifecycle 안 담당자를 밝힌다
_d_di=$(grep -m1 '^description:' "$DI"); _d_dis=$(grep -m1 '^description:' "$DIS")
printf '%s' "$_d_di"  | grep -q 'lifecycle 밖' \
  && printf '%s' "$_d_di"  | grep -q 'Step 5.6' && printf '%s' "$_d_di"  | grep -q 'Phase 2.5-B' \
  && printf '%s' "$_d_dis" | grep -q 'lifecycle 밖' \
  && printf '%s' "$_d_dis" | grep -q 'Step 5.6' && printf '%s' "$_d_dis" | grep -q 'Phase 2.5-B' \
  && [ "$(grep -c '^description:' "$DI")" = 1 ] && [ "$(grep -c '^description:' "$DIS")" = 1 ] \
  && ok "AC-20[spec AC-1·2·4] IF description 관할+담당+1행" || nope "AC-20[spec AC-1·2·4]" "범위 한정 누락 또는 description 다중 행"

# AC-21: 복수 파일 **본문**(frontmatter 제외)에도 분업이 있다
#   ★ frontmatter 를 잘라내는 이유: 안 자르면 description 만 고쳐도 통과해,
#     이 FID 가 발견한 "복수 본문 공백"을 다시 놓친다.
#   ★ 앵커는 `^> **분업**:` 로 **고정**한다 — 느슨한 `grep -m1 '분업'` 은 본문 기존
#     "분업 기준은 …" 줄을 잡고, 거기엔 Step 5.6·Phase 2.5-B 가 없어 항상 FAIL 한다.
_body_dis=$(awk 'BEGIN{c=0} /^---$/{c++; next} c>=2' "$DIS")
_l_dis=$(printf '%s' "$_body_dis" | grep -m1 '^> \*\*분업\*\*:')
printf '%s' "$_l_dis" | grep -q 'Step 5.6' \
  && printf '%s' "$_l_dis" | grep -q 'Phase 2.5-B' \
  && printf '%s' "$_l_dis" | grep -q 'design-interface.md' \
  && ok "AC-21[spec AC-3] design-interfaces 본문 분업(frontmatter 제외)" || nope "AC-21[spec AC-3]" "본문 분업 누락"

echo "── test-interface-routing-doc: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
