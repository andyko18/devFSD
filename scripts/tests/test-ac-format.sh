#!/usr/bin/env bash
# test-ac-format.sh — AC 필드 게이트 회귀 (20260807, OpenSpec 대비 갭분석 G1)
#
# 무엇을 잠그나: `emit-context.sh` 의 **must AC 역방향 커버리지** 검사는
#   `**우선순위**: must` 가 있는 AC 만 대상으로 삼는다(코드 주석: "우선순위 필드가
#   아예 없는 구식/픽스처 AC 문서는 자연히 대상 0건(하위호환 fail-open)").
#   → **필드를 안 쓰면 검사가 통째로 무음으로 꺼진다**. 그런데 그 필드의 존재를
#     강제하는 층이 0곳이었다(실측: 7개 AC 픽스처 중 6개가 우선순위 0건).
#   본 게이트가 그 스위치를 잠근다 — 게이트를 끄는 스위치의 무검증 노출 차단.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-ac-format.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# $1=FID  $2=AC 본문 → .specops/<FID>/acceptance-criteria.md 생성
_mkfid() {
  mkdir -p "$TMP/.specops/$1"
  cat > "$TMP/.specops/$1/acceptance-criteria.md"
}
# $1=FID → checker 실행 (stdout+stderr 합침), rc 를 _RC 에 저장
_run() {
  _OUT=$(cd "$TMP" && SPECOPS_ROOT=".specops" bash "$CHK" "$1" 2>&1); _RC=$?
}

_AC_OK='## 계약 항목

### AC-1: 로그인 성공

**Given** 등록된 사용자가 존재하고
**When** 올바른 비밀번호로 로그인하면
**Then** 세션 토큰이 발급된다

**검증 방법**: tests/test_auth.py::test_login
**관련 FR**: FR-1
**우선순위**: must
'

# ── T1: 정상 문서 → PASS ────────────────────────────────────────────────
_mkfid ok-fid <<< "$_AC_OK"
_run ok-fid
[ "$_RC" -eq 0 ] && ok "T1 전 필드 충족 → PASS" || nope "T1" "rc=$_RC out=$_OUT"

# ── T2: 우선순위 부재 → FAIL (핵심 — 스위치 잠금) ───────────────────────
_mkfid no-prio <<'EOF'
### AC-1: 로그인 성공

**Given** 등록된 사용자가 존재하고
**When** 올바른 비밀번호로 로그인하면
**Then** 세션 토큰이 발급된다

**검증 방법**: tests/test_auth.py::test_login
**관련 FR**: FR-1
EOF
_run no-prio
[ "$_RC" -eq 1 ] && printf '%s' "$_OUT" | grep -q '우선순위' \
  && ok "T2 우선순위 부재 → FAIL" || nope "T2" "rc=$_RC out=$_OUT"

# ── T3: 우선순위 값이 규약 밖 → FAIL ───────────────────────────────────
# 템플릿 §우선순위 규약 = must · should · nice-to-have. "높음" 같은 자유값은 must 판정에서
# 조용히 누락되므로(정규식 `must` 불일치) 값 검증까지 해야 스위치가 실제로 잠긴다.
_mkfid bad-prio <<'EOF'
### AC-1: 로그인 성공

**Given** 등록된 사용자가 존재하고
**When** 올바른 비밀번호로 로그인하면
**Then** 세션 토큰이 발급된다

**우선순위**: 높음
EOF
_run bad-prio
[ "$_RC" -eq 1 ] && printf '%s' "$_OUT" | grep -qE '우선순위.*(값|규약)' \
  && ok "T3 우선순위 값 규약 위반 → FAIL" || nope "T3" "rc=$_RC out=$_OUT"

# ── T4: Given/When/Then 누락 → FAIL (축 분리: When 만 제거) ─────────────
_mkfid no-when <<'EOF'
### AC-1: 로그인 성공

**Given** 등록된 사용자가 존재하고
**Then** 세션 토큰이 발급된다

**우선순위**: must
EOF
_run no-when
[ "$_RC" -eq 1 ] && printf '%s' "$_OUT" | grep -q 'When' \
  && ok "T4 When 누락 → FAIL" || nope "T4" "rc=$_RC out=$_OUT"

# ── T5: 불릿 전용 AC 문서 → PASS + WARN (하드 아님) ────────────────────
# emit-context 의 must 판정은 `^#{2,3} AC-N` 헤더만 본다. 불릿 전용 문서는
# 요약 추출(#209 · 20260716 dogfood 완화)은 통과하지만 **must 커버리지는 영구히 0건**이다.
# 그 완화 계약을 여기서 일방적으로 깨지 않는다 — 침묵만 걷어낸다.
# 완전 봉합은 "불릿 형식 지원 폐기" 결정이 선행돼야 한다(별도 판단).
_mkfid bullet-only <<'EOF'
- **AC-1**: 로그인 성공
- **AC-2**: 로그아웃 성공
EOF
_run bullet-only
[ "$_RC" -eq 0 ] && printf '%s' "$_OUT" | grep -q 'WARN.*헤더형' \
  && ok "T5 불릿 전용 → PASS + WARN (must 커버리지 무력 고지)" || nope "T5" "rc=$_RC out=$_OUT"

# ── T6: AC 0건 → FAIL ──────────────────────────────────────────────────
_mkfid empty-ac <<'EOF'
# 수락 기준

## 계약 항목

(아직 작성 안 함)
EOF
_run empty-ac
[ "$_RC" -eq 1 ] && ok "T6 AC 0건 → FAIL" || nope "T6" "rc=$_RC out=$_OUT"

# ── T7: 검증 방법·관련 FR 부재 → PASS + WARN (hard 아님) ────────────────
# 검증 방법은 tasks.md `test_command` 가 이미 hard 로 잡고, 관련 FR 은 대조 SoT
# (spec §4 vs memory/requirements.md)가 미결이라 warn-first. 전환점은 헤더에 기록.
_mkfid warn-only <<'EOF'
### AC-1: 로그인 성공

**Given** 등록된 사용자가 존재하고
**When** 올바른 비밀번호로 로그인하면
**Then** 세션 토큰이 발급된다

**우선순위**: should
EOF
_run warn-only
# ⚠️ 'WARN' 단순 매칭 금지 — PASS 요약줄이 "WARN N건" 을 포함해 변이가 통과했다(20260807 실측).
#    WARN **행 자체**를 항목별로 확인한다.
if [ "$_RC" -eq 0 ] \
   && printf '%s' "$_OUT" | grep -q '^AC-FORMAT: WARN — AC-1: \*\*검증 방법\*\* 부재' \
   && printf '%s' "$_OUT" | grep -q '^AC-FORMAT: WARN — AC-1: \*\*관련 FR\*\* 부재'; then
  ok "T7 검증방법·관련FR 부재 → PASS + WARN 각 1행"
else
  nope "T7" "rc=$_RC out=$_OUT"
fi

# ── T8: 템플릿 placeholder 잔존 → FAIL ─────────────────────────────────
_mkfid placeholder <<'EOF'
### AC-1: <기능 이름>

**Given** <전제 조건·초기 상태>
**When** <사용자/시스템 동작>
**Then** <관찰 가능한 결과>

**검증 방법**: <수동 재현 단계 또는 자동 테스트 경로>
**관련 FR**: FR-1
**우선순위**: must
EOF
_run placeholder
[ "$_RC" -eq 1 ] && printf '%s' "$_OUT" | grep -qi 'placeholder\|미채움' \
  && ok "T8 placeholder 잔존 → FAIL" || nope "T8" "rc=$_RC out=$_OUT"

# ── T8b: 템플릿 2번째 AC 의 `...` 골격 잔존 → FAIL ─────────────────────
# templates/acceptance-criteria.md 의 AC-2/AC-3 은 `**Given** ...` 형태로 배포된다.
# AC-1 만 채우고 나머지를 두면 껍데기 AC 가 계약에 남는다.
_mkfid dots <<'EOF'
### AC-1: 로그인 성공

**Given** 등록된 사용자가 존재하고
**When** 올바른 비밀번호로 로그인하면
**Then** 세션 토큰이 발급된다

**검증 방법**: tests/test_auth.py::test_login
**관련 FR**: FR-1
**우선순위**: must

### AC-2: <기능 이름>

**Given** ...

**When** ...

**Then** ...

**검증 방법**: ...
**관련 FR**: FR-2
**우선순위**: must
EOF
_run dots
[ "$_RC" -eq 1 ] && ok 'T8b 골격 점(...) 잔존 → FAIL' || nope "T8b" "rc=$_RC out=$_OUT"

# ── T8c: placeholder 를 **언급하는** 정당한 문장은 골격이 아니다 (오탐 차단) ──
# 실사용 검증 1호 결함(20260807): FID 20260807-specops-doctor 의 AC-3 본문
#   "…api-spec.md 에 `<placeholder>` 가 남아 있을 때" 가 골격으로 오판돼 dispatch 가 막혔다.
#   원인: skeleton() 이 `<...>` 를 **부분 매칭**했다. 템플릿 골격은 값 **전체**가
#   placeholder 인 형태(`**Given** <전제 조건·초기 상태>`)이므로 앵커드 매칭이 맞다.
#   클래스 B 교훈과 같다 — 과탐지는 정상 문서를 막아 게이트 신뢰를 깎는다.
_mkfid mentions-ph <<'EOF'
### AC-1: placeholder 검출

**Given** `.specops/memory/api-spec.md` 에 `<placeholder>` 가 남아 있을 때
**When** 스캐너를 실행하면
**Then** 미채움으로 판정된다

**검증 방법**: tests/test_scan.py
**관련 FR**: FR-2
**우선순위**: must
EOF
_run mentions-ph
[ "$_RC" -eq 0 ] && ok "T8c placeholder 언급 문장은 골격 아님 (오탐 차단)" \
  || nope "T8c" "정상 문서 오탐 — rc=$_RC out=$_OUT"

# ── T8d: 백틱으로 감싼 골격도 검출 (백틱 제거 로직이 살아 있는가) ────────
# T8c 의 앵커드 매칭만으로는 `` `<전제 조건>` `` 형태가 통과한다 — 백틱 제거가 그걸 잡는다.
# 이 축이 없으면 백틱 제거 줄이 무검증 코드가 된다(변이 생존 실측).
_mkfid backtick-ph <<'EOF'
### AC-1: 무언가

**Given** `<전제 조건·초기 상태>`
**When** 실행하면
**Then** 결과가 나온다

**우선순위**: must
EOF
_run backtick-ph
[ "$_RC" -eq 1 ] && ok "T8d 백틱 감싼 골격도 검출" || nope "T8d" "rc=$_RC out=$_OUT"

# ── T9: h2 헤더(## AC-1)도 인정 ────────────────────────────────────────
# emit-context 가 h2 drift 를 구제하므로(20260722 실측) 본 게이트도 같은 폭이어야 한다.
# 좁으면 h2 문서가 "헤더 0건" 으로 오판된다.
_mkfid h2 <<'EOF'
## AC-1: 로그인 성공

**Given** 등록된 사용자가 존재하고
**When** 올바른 비밀번호로 로그인하면
**Then** 세션 토큰이 발급된다

**검증 방법**: tests/test_auth.py::test_login
**관련 FR**: FR-1
**우선순위**: must
EOF
_run h2
[ "$_RC" -eq 0 ] && ok "T9 h2 헤더 인정" || nope "T9" "rc=$_RC out=$_OUT"

# ── T10: AC-R-* 는 본 게이트 대상 밖 (SoT = check-regression-ac) ────────
# 템플릿이 AC-R-1/R-2 를 대괄호 placeholder 로 배포하므로, 신규 FID 가 그대로
# 두는 것이 정상이다(check-regression-ac 가 §유형=유지보수 일 때만 요구).
# 여기서 함께 FAIL 내면 모든 신규 FID 가 막힌다.
_mkfid with-acr <<'EOF'
### AC-1: 로그인 성공

**Given** 등록된 사용자가 존재하고
**When** 올바른 비밀번호로 로그인하면
**Then** 세션 토큰이 발급된다

**검증 방법**: tests/test_auth.py::test_login
**관련 FR**: FR-1
**우선순위**: must

### AC-R-1: <기존 동작 보존>

**Given** <구체적 입력 또는 기존 호출 패턴>
**Then** 기존 출력과 동일하게 동작한다
EOF
_run with-acr
# ⚠️ AC-R 블록을 **본 게이트 기준으로는 명백히 위반**(각괄호 골격 · When 부재 · 우선순위 부재)
#    으로 만들어 skip 이 load-bearing 이 되게 한다. 채워진 AC-R 을 쓰면 skip 을 제거해도
#    테스트가 통과해 변이를 못 잡는다(20260807 실측 — M4 생존).
[ "$_RC" -eq 0 ] && ok "T10 AC-R-* 는 대상 밖 (신규 FID 무손상)" || nope "T10" "rc=$_RC out=$_OUT"

# ── T10b: AC-R 만 있는 유지보수 문서 → 차단 금지 ───────────────────────
# 도달 경로: T8/T8b 가 미채운 AC-1..3 골격을 hard 로 막으므로, 유지보수 FID 에서
#   템플릿 골격을 **지우는 것이 정상 대응**이다. 그러면 AC-R 만 남는다.
#   이때 "AC 0건 — 계약이 비어 있다" 로 막으면 AC-R-1 이 눈앞에 있는데 오진이다.
_mkfid acr-only <<'EOF'
### AC-R-1: 기존 동작 보존

**Given** 기존 호출 패턴
**When** 동일 트리거
**Then** 동일 출력

**검증 방법**: tests/test_regression.py
**관련 FR**: 회귀 방지
**우선순위**: must
EOF
_run acr-only
[ "$_RC" -ne 1 ] && ok "T10b AC-R 전용 유지보수 문서 → 차단 안 함 (rc=$_RC)" \
  || nope "T10b" "AC-R-1 이 있는데 '계약 비어있음' 오진 — out=$_OUT"

# ── T11: AC 파일 부재 → rc=2 (호출자 판단) ─────────────────────────────
mkdir -p "$TMP/.specops/no-file"
_run no-file
[ "$_RC" -eq 2 ] && ok "T11 AC 파일 부재 → rc=2" || nope "T11" "rc=$_RC out=$_OUT"

# ── T12: emit-context 배선 — 실패 시 dispatch 파일 0 (원자성) ──────────
EMIT="$PLUGIN/scripts/dag/emit-context.sh"
W="$TMP/wire"; mkdir -p "$W/.specops/wire-fid"
cat > "$W/.specops/wire-fid/spec.md" <<'EOF'
# spec
**§유형**: 신규
EOF
cat > "$W/.specops/wire-fid/acceptance-criteria.md" <<'EOF'
### AC-1: 로그인 성공

**Given** 등록된 사용자가 존재하고
**When** 올바른 비밀번호로 로그인하면
**Then** 세션 토큰이 발급된다
EOF
cat > "$W/.specops/wire-fid/tasks.md" <<'EOF'
# tasks

## 의존 그래프

```yaml
tasks:
  - id: T1
    ac: [AC-1]
    test_command: "pytest tests/test_auth.py"
    inputs: []
    outputs: []
```
EOF
out=$(cd "$W" && bash "$EMIT" wire-fid 2>&1); rc=$?
n=$(find "$W/.specops/wire-fid/dispatch" -name '*-context.md' 2>/dev/null | grep -c . || true)
if [ "$rc" -ne 0 ] && [ "${n:-0}" -eq 0 ] && printf '%s' "$out" | grep -q '우선순위'; then
  ok "T12 emit-context 배선 — 우선순위 부재 시 dispatch 0"
else
  nope "T12" "rc=$rc files=${n:-0} out=$out"
fi

# ── T13: 배선 정상 경로 — 우선순위 채우면 emit 성공 ────────────────────
cat > "$W/.specops/wire-fid/acceptance-criteria.md" <<'EOF'
### AC-1: 로그인 성공

**Given** 등록된 사용자가 존재하고
**When** 올바른 비밀번호로 로그인하면
**Then** 세션 토큰이 발급된다

**검증 방법**: tests/test_auth.py::test_login
**관련 FR**: FR-1
**우선순위**: must
EOF
out=$(cd "$W" && bash "$EMIT" wire-fid 2>&1); rc=$?
n=$(find "$W/.specops/wire-fid/dispatch" -name '*-context.md' 2>/dev/null | grep -c . || true)
[ "$rc" -eq 0 ] && [ "${n:-0}" -eq 1 ] \
  && ok "T13 배선 정상 경로 통과" || nope "T13" "rc=$rc files=${n:-0} out=$out"

# ── T14~T17: verify 관문 배선 (FID 20260828-ac-absence-detect) ──
#   결함: check-ac-format 은 emit-context.sh:87 에서만 불린다 — 즉 **decompose 단계 전용**이다.
#   clarify·plan·decompose 를 건너뛰면(§lite·수기 진행) emit-context 가 돌 기회 자체가 없어
#   **AC 파일 부재가 아무 데서도 안 걸린다**. specifying-ko:19 는 "emit-context 가
#   acceptance-criteria.md 실재를 요구한다" 를 우회 차단 근거로 선언하는데, 그 전제가 깨진다.
#   실측(argus batch-20260729): AC 파일이 아예 없는 FID 3건이 verify·리뷰를 통과했다.
RV="$PLUGIN/scripts/_internal/run-verification.sh"

# T14 run-verification 배선 — 검사기만 있고 부르는 곳이 decompose 뿐이면 그대로다
grep -q 'check-ac-format.sh' "$RV" \
  && ok "T14 run-verification 배선 (decompose 밖에서도 AC 부재를 본다)" \
  || nope "T14 미배선" "verify 관문이 AC 부재를 보지 못한다"

# T15 rc 를 판정에 반영 — 부르기만 하고 무시하면 관측도 차단도 아니다
grep -qE 'acfmt_ec|AC-FORMAT: MISSING|VERIFY: FAIL ac-format' "$RV" \
  && ok "T15 rc 반영" || nope "T15" "rc 무시 — 호출만 하고 판정에 안 쓴다"

# T16 lifecycle FID(spec.md 존재) + AC 부재 → 차단
#   AC 는 스프린트 계약이다. 없으면 Phase B 가 대조할 기준이 없다.
TD=$(mktemp -d)
mkdir -p "$TD/.specops/20260101-noac"
printf '# spec\n\n**§유형**: 신규\n**§lite**: false\n' > "$TD/.specops/20260101-noac/spec.md"
out=$(cd "$TD" && SPECOPS_ROOT="$TD/.specops" bash "$PLUGIN/scripts/_internal/check-ac-format.sh" 20260101-noac 2>&1); rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'MISSING'; then
  ok "T16 lifecycle FID + AC 부재 → exit 2 MISSING"
else
  nope "T16 AC 부재 미검출" "rc=$rc out=$out"
fi

# T17 freework mini-FID(spec.md 부재) → 차단하지 않는다
#   templates/freework.md 가 "spec.md 없는 경량 트랙" 이라고 직접 선언한다.
#   여기서 FAIL 내면 정당한 자유작업 경로가 통째로 막힌다.
rm -rf "$TD/.specops/20260101-mini"; mkdir -p "$TD/.specops/20260101-mini"
printf '# freework.md — 20260101-mini\n\n- **type**: fix\n' > "$TD/.specops/20260101-mini/freework.md"
grep -qE 'freework|spec\.md.*부재|mini-FID' "$RV" \
  && ok "T17 freework mini-FID 면제 배선" \
  || nope "T17 mini-FID 면제 부재" "spec.md 없는 경량 트랙이 차단될 수 있다"
rm -rf "$TD"

# ── T18~T19: 배선을 **실행으로** 검증한다 ──
#   T14·T15 는 grep 이라 배선 존재만 본다. 실제로 `FID_DIR: unbound variable` 로 터지는
#   버그를 grep 이 통과시켰다(구현 중 실측). 스크립트를 돌려서 확인한다.
TD2=$(mktemp -d)

# T18 lifecycle FID(spec.md 존재) + AC 부재 → VERIFY: FAIL ac-format
mkdir -p "$TD2/.specops/20260101-noac"
printf '# spec\n\n**§유형**: 신규\n' > "$TD2/.specops/20260101-noac/spec.md"
printf '# tasks\n' > "$TD2/.specops/20260101-noac/tasks.md"
out=$(cd "$TD2" && bash "$RV" 20260101-noac 2>&1); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'VERIFY: FAIL ac-format' \
   && ! printf '%s' "$out" | grep -q 'unbound variable'; then
  ok "T18 실행 검증 — AC 부재 차단 (unbound 없음)"
else
  nope "T18 실행 실패" "rc=$rc out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)"
fi

# T19 freework mini-FID(spec.md 부재) → ac-format 이 발화하지 않는다
#    정당한 경량 트랙을 막으면 이 수정이 새 결함이 된다.
mkdir -p "$TD2/.specops/20260101-mini"
printf '# freework.md — 20260101-mini\n' > "$TD2/.specops/20260101-mini/freework.md"
printf '# tasks\n' > "$TD2/.specops/20260101-mini/tasks.md"
out=$(cd "$TD2" && bash "$RV" 20260101-mini 2>&1); rc=$?
if ! printf '%s' "$out" | grep -q 'ac-format'; then
  ok "T19 freework mini-FID 면제 실행 검증"
else
  nope "T19 경량 트랙 오차단" "out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)"
fi
rm -rf "$TD2"

finish
