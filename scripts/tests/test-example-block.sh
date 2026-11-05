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

# ── T-tok: 백틱으로 감싼 닫힌 규약 토큰은 빈칸이 아니다 (20261105-detector-false-positives AC-1) ──
# 기대값은 손으로 쓴 리터럴이다. 스캐너 출력은 sed 를 거친 뒤의 줄이므로 "출력에 토큰 글자가 남았나"로 제거 여부를 본다.
_tok_scan() {  # $1=파일 내용 → _rc, _out (매번 새 임시 파일; 파일이 실제로 읽혔는지는 양성 대조가 보증)
  local _f; _f=$(mktemp)
  printf '%s\n' "$1" > "$_f"
  _out=$(bash "$SCAN" "$_f" 2>/dev/null); _rc=$?
  rm -f "$_f"
}
# a: 닫힌 토큰 4개만 → clean
_tok_scan '참조: `<FID>` · `<fid>` · `<name>` · `<task-id>` 를 쓴다'
[ "$_rc" -eq 0 ] && [ -z "$_out" ] && ok "T-tok.a 백틱 규약 토큰만 → clean" || nope "T-tok.a" "rc=$_rc out=$_out"
# a2: 양성 대조 — 같은 토큰 줄 + 진짜 빈칸 줄. 파일이 읽히고 있으며(스캐너는 없는 파일에도 rc 0 이다), 토큰 줄만 빠지고 빈칸 줄은 남는다
_tok_scan '참조: `<FID>` · `<fid>` · `<name>` · `<task-id>` 를 쓴다
- **버전**: <버전>'
[ "$_rc" -eq 1 ] && printf '%s' "$_out" | grep -qF '<버전>' && ! printf '%s' "$_out" | grep -qF '<FID>' \
  && ok "T-tok.a2 토큰 줄은 빠지고 같은 파일의 진짜 빈칸은 검출(양성 대조)" || nope "T-tok.a2" "rc=$_rc out=$_out"
# b: 백틱 밖 꺾쇠 FID(템플릿 제목 꼴) → 검출, 그 줄이 출력에 있다
_tok_scan '# 현재 시스템 분석 — <FID>'
[ "$_rc" -eq 1 ] && printf '%s' "$_out" | grep -qF '— <FID>' \
  && ok "T-tok.b 백틱 밖 <FID> → 검출" || nope "T-tok.b" "rc=$_rc out=$_out"
# b2: 같은 줄에 백틱 토큰과 백틱 밖 토큰 → 밖의 것 때문에 검출
_tok_scan '- `<FID>` 와 <FID>'
[ "$_rc" -eq 1 ] && ok "T-tok.b2 한 줄 백틱 토큰 + 백틱 밖 토큰 → 검출" || nope "T-tok.b2" "rc=$_rc out=$_out"
# c: 백틱 안이어도 목록 밖(경로 자리) → 검출, 토큰 글자가 출력에 남는다
_tok_scan '- 파일: `<path/to/file.ts>`'
[ "$_rc" -eq 1 ] && printf '%s' "$_out" | grep -qF '<path/to/file.ts>' \
  && ok "T-tok.c 백틱 안 목록 밖 → 검출" || nope "T-tok.c" "rc=$_rc out=$_out"
# d: 한 줄에 둘 다 → 목록 밖(심볼) 때문에 검출, FID 는 빠지고 심볼은 남는다
_tok_scan '- `<FID>` 의 `<symbol>`'
[ "$_rc" -eq 1 ] && printf '%s' "$_out" | grep -qF '<symbol>' && ! printf '%s' "$_out" | grep -qF '<FID>' \
  && ok "T-tok.d 한 줄 목록 + 목록 밖 → 목록 밖만 검출" || nope "T-tok.d" "rc=$_rc out=$_out"
# f: 목록은 닫힌 집합·대소문자 구분 — 철자만 다른 것은 빈칸이다 (대소문자 무시 변이 차단)
for _t in '`<Fid>`' '`<NAME>`' '`<Task-ID>`' '`<task_id>`'; do
  _tok_scan "- 표기 $_t"
  [ "$_rc" -eq 1 ] && ok "T-tok.f 목록 밖 철자 $_t → 검출" || nope "T-tok.f $_t" "rc=$_rc out=$_out"
done
# g: 닫는/여는 백틱 한쪽이 없으면 '감싼' 것이 아니다
for _t in '`<FID>' '<FID>`'; do
  _tok_scan "- 표기 $_t"
  [ "$_rc" -eq 1 ] && ok "T-tok.g 한쪽 백틱만 $_t → 검출" || nope "T-tok.g $_t" "rc=$_rc out=$_out"
done
# e: 실제 템플릿 5종 원본 — 미채움 원본이 계속 검출된다.
#   rc 1 만으로는 부족하다(5종 모두 백틱 밖 빈칸이 많아 제외 로직이 망가져도 rc 1). 그래서 템플릿에서
#   "백틱으로 감싼 꺾쇠 한 덩어리"를 grep 으로 뽑아(구현과 별개의 출처) 그 글자가 출력에 그대로 남는지 본다.
_etok_n=0
for _t in current-state impact-analysis intent spec requirements; do
  _tf="$PLUGIN/templates/$_t.md"
  [ -s "$_tf" ] || { nope "T-tok.e $_t" "템플릿 부재/빈 파일"; continue; }
  _out=$(bash "$SCAN" "$_tf" 2>/dev/null); _rc=$?
  [ "$_rc" -eq 1 ] && ok "T-tok.e $_t 원본 → 검출(rc 1)" || nope "T-tok.e $_t" "rc=$_rc"
  while IFS= read -r _tk; do
    [ -n "$_tk" ] || continue
    _etok_n=$((_etok_n+1))
    printf '%s' "$_out" | grep -qF -- "$_tk" && ok "T-tok.e $_t 백틱 빈칸 $_tk 검출 유지" || nope "T-tok.e $_t" "백틱 빈칸 $_tk 가 검출에서 사라짐"
  done <<EOF
$(grep -oE '`<[^`>]+>`' "$_tf" | tr -d '`')
EOF
done
[ "$_etok_n" -ge 4 ] && ok "T-tok.e 백틱 빈칸 대상 ${_etok_n}개 (current-state 4개 이상 — 공허 방지)" || nope "T-tok.e 대상 수" "${_etok_n}개 — 템플릿에서 뽑지 못했다"


finish
