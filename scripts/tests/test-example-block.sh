#!/usr/bin/env bash
# 템플릿 예시 블록 잔존 검출 — 20260806 design 계열 정밀분석 3라운드
#
# 결함: `api-spec.md`·`data-model.md` 템플릿이 e-commerce **예시 표**(users/orders/products,
#   `/v1/users/:id` 등)를 **경고 한 줄 없이** 담고 배포된다. 그리고 이 예시는
#   placeholder(`<...>`)가 아니라 **완성된 실값처럼 보이므로** 유일한 기계 검사인
#   scan-enrich-placeholders.sh 가 **구조적으로 못 본다**(실측: 검출 0).
#
# 왜 심각한가: 이 두 문서는 구현의 **설계 계약**이다.
#   - `/design-interface` Step 3 는 **append** 경로라 예시가 남는다(design-screen 과 동종).
#   - `design-reviewer-ko`(Phase 2.5-D)가 Interactions↔api-spec 정합을 보고,
#     `verifying-evidence-ko` memory 동기화 점검이 엔드포인트·스키마를 역방향 대조한다.
#   → 전자상거래가 아닌 프로젝트에 `users/orders/products` 유령 스키마가 계약으로 남는다.
#
# 해법: 예시를 `<!-- specops:example:start -->`…`:end -->` 로 감싸 **기계 검출 가능**하게 하고,
#   placeholder SoT 스캐너가 잔존 시 미채움으로 판정한다(기존 배선 재사용 — e2e V21 은
#   이미 `.specops/memory/*.md` 를 이 스캐너로 검사한다).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCAN="$PLUGIN/scripts/_internal/scan-enrich-placeholders.sh"

# T1: 예시 블록 잔존 → 스캐너가 미채움으로 검출
TF=$(mktemp)
cat > "$TF" <<'EOF'
# 테이블 설계서

## §3. 핵심 엔티티 표

<!-- specops:example:start -->
| 테이블 | 역할 |
|---|---|
| `users` | 사용자 계정 |
<!-- specops:example:end -->
EOF
out=$(bash "$SCAN" "$TF" 2>/dev/null); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'example' \
  && ok "T1 예시 블록 잔존 → 검출(미채움)" || nope "T1" "rc=$rc out=$out"
rm -f "$TF"

# T2: 예시 블록 제거(실제 내용으로 교체) → clean
TF=$(mktemp)
cat > "$TF" <<'EOF'
# 테이블 설계서

## §3. 핵심 엔티티 표

| 테이블 | 역할 |
|---|---|
| `sessions` | 세션 저장 |
EOF
bash "$SCAN" "$TF" >/dev/null 2>&1 \
  && ok "T2 예시 블록 제거 → clean" || nope "T2" "여전히 검출"
rm -f "$TF"

# T3: 블록 밖 실 placeholder 는 계속 검출 (기존 동작 무손상)
TF=$(mktemp)
printf '%s\n' '- **버전**: <버전>' > "$TF"
! bash "$SCAN" "$TF" >/dev/null 2>&1 \
  && ok "T3 기존 placeholder 검출 무손상" || nope "T3" "회귀"
rm -f "$TF"

# T4: api-spec·data-model 템플릿의 예시 표가 마커로 감싸였는가
for t in api-spec data-model; do
  f="$PLUGIN/templates/$t.md"
  if grep -q 'specops:example:start' "$f" && grep -q 'specops:example:end' "$f"; then
    ok "T4.$t 예시 블록 마커 존재"
  else
    nope "T4.$t" "마커 부재 — 스캐너 사각지대 잔존"
  fi
done

# T5: 마커 안에 실제 예시 표가 들어 있는가 (마커만 달고 표는 밖에 두는 위장 방지)
for t in api-spec data-model; do
  f="$PLUGIN/templates/$t.md"
  n=$(awk '/specops:example:start/{f=1;next} /specops:example:end/{f=0} f&&/^\|/' "$f" | grep -c . || true)
  [ "${n:-0}" -ge 2 ] \
    && ok "T5.$t 마커 내부에 예시 표 행 ${n}건" \
    || nope "T5.$t" "마커 내부 표 행 ${n}건 — 위장 마커"
done

# T6: 템플릿에 삭제 지침 명시 (모델이 지워야 할 것임을 안다)
for t in api-spec data-model; do
  grep -qE '예시.*삭제|삭제.*예시' "$PLUGIN/templates/$t.md" \
    && ok "T6.$t 예시 삭제 지침" || nope "T6.$t" "지침 부재"
done

# ── T7: 골격 예시 소비처 계약 (클래스 B 재발 방지, 20260806) ──────────────────
# 20260806 감사에서 "골격 예시가 실데이터로 읽힘" 결함 4건:
#   decisions.md(면제 개방) · screens-overview(유령 화면) ·
#   api-spec/data-model(유령 스키마 = 설계 계약) · requirements FR(placeholder 로 batch 진입)
#
# 정적 메타 규칙은 **만들지 않았다** — 실측 결과 placeholder 형식이 4가지
#   (`<...>` · `{{...}}` · `#______` · `(예시)`)라 "실값 행" 휴리스틱이 오탐 4건을 냈고
#   (DESIGN.md 색상·SKILL.md·dispatch-context 5원칙표·decisions 예시행 — 전부 정상),
#   진짜 성질은 "기계가 프로젝트 데이터로 읽는가" 라는 **의미론**이라 정적 판별이 안 된다.
# 대신 **소비처마다 제외 규칙을 둔다**(클래스 A 를 관문에서 잡은 것과 같은 원리).
#   본 테스트는 그 제외 규칙들이 **조용히 사라지지 않도록** 한곳에서 잠근다 —
#   새 소비처가 생기면 여기 행을 추가하는 것이 규약이다.
_consumer_guard() {  # $1=스크립트 $2=제외패턴 $3=라벨
  if grep -q "$2" "$PLUGIN/$1" 2>/dev/null; then
    ok "T7 소비처 예시-제외 유지: $3"
  else
    nope "T7 $3" "$1 에서 제외 규칙($2) 소실 — 골격 예시가 실데이터로 읽힌다"
  fi
}
_consumer_guard scripts/_internal/check-decisions-ledger.sh '(예시)'        'decisions 원장'
_consumer_guard scripts/_internal/check-fr-table.sh          'TBD'          'requirements FR 표'
_consumer_guard scripts/_internal/scan-enrich-placeholders.sh 'specops:example' 'api-spec·data-model 블록'

# T7.d: screens-overview 골격 fence 는 비어 있어야 한다 (append 경로 유령 화면 차단)
_tplrows=$(awk '/screens-table:start/{f=1;next} /screens-table:end/{f=0} f&&/^\|/' \
  "$PLUGIN/templates/screens-overview.md" | grep -c . || true)
[ "${_tplrows:-0}" -eq 0 ] \
  && ok "T7 소비처 예시-제외 유지: screens-overview 빈 fence" \
  || nope "T7 screens-overview" "fence 에 ${_tplrows}행 — 유령 화면 배포"


finish
