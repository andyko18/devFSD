#!/usr/bin/env bash
# test-plan-predispatch.sh — plan-reviewer 사전검사 회귀
#   FID 20260809-predispatch-fail-check
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
CHK="$PLUGIN/scripts/_internal/check-plan-predispatch.sh"
FX="$PLUGIN/scripts/tests/fixtures/predispatch"
PASS=0; FAIL=0
ok()   { echo "PASS $1"; PASS=$((PASS+1)); }
nope() { echo "FAIL $1 — $2"; FAIL=$((FAIL+1)); }
finish() { echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ] || exit 1; exit 0; }

# P0 가드 — 픽스처가 git 에 추적(또는 stage)되는가.
#   untracked 는 ls-files 에 안 잡힌다 — 생성 후 git add 하지 않으면 아래가 전부 공허해진다.
_t=$(cd "$PLUGIN" && git ls-files scripts/tests/fixtures/predispatch/ | wc -l | tr -d ' ')
[ "$_t" -ge 9 ] && ok "P0 픽스처 git 추적 ${_t}건" \
  || { nope "P0" "픽스처 미추적(${_t}건) — 다른 clone 에서 공허 통과"; finish; }

_run() { bash "$CHK" --plan "$FX/$1" 2>&1; }

# P1 — dangling-lock 양성 (AC-1)
#   ★ 토큰 자체를 어서션에 쓰지 않는다 — 그러면 **이 테스트 파일**이 그 토큰을 담게 되고,
#     검사기의 repo 탐색이 그것을 매치해 dangling 이 영원히 통과한다(구현 중 실증).
#     rc + 규칙명만 본다. 어느 토큰인지는 P2·P3 음성 대조가 보장한다.
o=$(_run 01-dangling-lock.md); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$o" | grep -q 'dangling-lock' \
  && ok "P1 dangling-lock 검출 (AC-1)" || nope "P1" "rc=$rc out=[$o]"

# P2 — 그 plan 이 만드는 문자열은 통과 (AC-2 음성)
o=$(_run 02-lock-in-impl.md); rc=$?
#   ★ OK 를 명시 확인한다 — rc=0 만 보면 픽스처 경로 오타·소실 시 `PREDISPATCH: SKIP`(rc=0)
#     을 PASS 로 읽어 공허 통과한다(Phase C 프로브 I-3 실증).
[ "$rc" -eq 0 ] && printf '%s' "$o" | grep -q 'PREDISPATCH: OK' \
  && ok "P2 구현부에 있는 신규 문자열 미보고 (AC-2)" || nope "P2" "rc=$rc out=[$o]"

# P3 — 정규식 메타문자 건너뛰기 (AC-3 음성)
o=$(_run 03-regex-meta.md); rc=$?
#   ★ OK 를 명시 확인한다 — rc=0 만 보면 픽스처 경로 오타·소실 시 `PREDISPATCH: SKIP`(rc=0)
#     을 PASS 로 읽어 공허 통과한다(Phase C 프로브 I-3 실증).
[ "$rc" -eq 0 ] && printf '%s' "$o" | grep -q 'PREDISPATCH: OK' \
  && ok "P3 메타문자 인용 판정 제외 (AC-3)" || nope "P3" "rc=$rc out=[$o]"

# P4 — propagation 스키마 위반 검출 (AC-4 양성)
o=$(_run 04-prop-bad.md); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$o" | grep -q 'propagation-schema' \
  && ok "P4 propagation 스키마 위반 검출 (AC-4)" || nope "P4" "rc=$rc out=[$o]"

# P5 — 정상 레코드 미보고 (AC-4 음성)
o=$(_run 05-prop-good.md); rc=$?
#   ★ OK 를 명시 확인한다 — rc=0 만 보면 픽스처 경로 오타·소실 시 `PREDISPATCH: SKIP`(rc=0)
#     을 PASS 로 읽어 공허 통과한다(Phase C 프로브 I-3 실증).
[ "$rc" -eq 0 ] && printf '%s' "$o" | grep -q 'PREDISPATCH: OK' \
  && ok "P5 정상 propagation 레코드 미보고 (AC-4)" || nope "P5" "rc=$rc out=[$o]"

# P6 — red-evidence 양성 (AC-5)
o=$(_run 06-red-missing.md); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$o" | grep -q 'red-evidence' \
  && ok "P6 RED 미실측 검출 (AC-5)" || nope "P6" "rc=$rc out=[$o]"

# P7 — 명시 유보는 통과 (AC-5 음성). 정직한 유보를 막으면 안 된다.
o=$(_run 07-red-deferred.md); rc=$?
#   ★ OK 를 명시 확인한다 — rc=0 만 보면 픽스처 경로 오타·소실 시 `PREDISPATCH: SKIP`(rc=0)
#     을 PASS 로 읽어 공허 통과한다(Phase C 프로브 I-3 실증).
[ "$rc" -eq 0 ] && printf '%s' "$o" | grep -q 'PREDISPATCH: OK' \
  && ok "P7 명시 유보 통과 (AC-5)" || nope "P7" "rc=$rc out=[$o]"

# P8 — plan.md 부재는 SKIP + rc=0 (AC-6). §lite·trivial 은 plan 이 없다 — chain 차단 금지.
o=$(bash "$CHK" --plan "$FX/does-not-exist.md" 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$o" | grep -q 'PREDISPATCH: SKIP' \
  && ok "P8 plan 부재 SKIP rc=0 (AC-6)" || nope "P8" "rc=$rc out=[$o]"

# P9 — read-only (AC-6): 실행 전후 워킹트리 델타 0
if command -v md5 >/dev/null 2>&1; then _H=md5; else _H=md5sum; fi
_b=$(cd "$PLUGIN" && git status --porcelain | sort | $_H)
for f in "$FX"/*.md; do bash "$CHK" --plan "$f" >/dev/null 2>&1; done
_a=$(cd "$PLUGIN" && git status --porcelain | sort | $_H)
[ "$_b" = "$_a" ] && ok "P9 read-only (AC-6)" || nope "P9" "파일 변경 발생"

# P10 — 실 코퍼스 회귀: 기존 plan.md 전체에서 **오탐 0** (NFR-3 핵심)
#   ★ 오탐 억제의 본체다. 합성 픽스처는 작성자가 상상한 입력만 담는다.
#   0건이면 graceful skip — .specops/* 는 gitignore 라 clone 에 따라 없을 수 있다.
_fp=0; _scan=0; _bad=""
for p in "$PLUGIN"/.specops/*/plan.md; do
  [ -f "$p" ] || continue
  _scan=$((_scan+1))
  bash "$CHK" --plan "$p" >/dev/null 2>&1 || { _fp=$((_fp+1)); _bad="$_bad $(basename "$(dirname "$p")")"; }
done
if [ "$_scan" -eq 0 ]; then ok "P10 실 코퍼스 스캔 SKIP (plan.md 0건)"
elif [ "$_fp" -eq 0 ]; then ok "P10 실 코퍼스 오탐 0 (스캔 ${_scan}건)"
else nope "P10" "실 코퍼스 오탐 ${_fp}/${_scan}건 —$_bad"; fi

# P11 — 배선 (AC-7)
grep -q 'check-plan-predispatch.sh' "$PLUGIN/skills/planning-ko/SKILL.md" \
  && ok "P11 planning-ko 배선 (AC-7)" || nope "P11" "planning-ko 에 호출 부재"

# P12 — 리뷰어 입력 계약 (AC-7)
grep -q 'NEEDS_CONTEXT' "$PLUGIN/skills/implementing-ko/SKILL.md" \
  && grep -q '받는 컨텍스트' "$PLUGIN/skills/implementing-ko/SKILL.md" \
  && ok "P12 리뷰어 입력 계약 명시 (AC-7)" || nope "P12" "입력 계약 문구 부재"

# P13 — 생성과 어서션이 **같은 줄**이어도 오탐하지 않는다 (Phase C I-1)
#   줄을 통째로 지우는 필터는 구현 증거까지 지워 dangling 오탐을 낸다.
o=$(_run 08-oneline-create-assert.md); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$o" | grep -q 'PREDISPATCH: OK' \
  && ok "P13 한 줄 생성+어서션 오탐 없음 (NFR-3)" || nope "P13" "rc=$rc out=[$o]"

# P14 — "Step 25" 는 Step 2 가 아니다 (Phase C I-2, 숫자 경계)
o=$(_run 09-step2x-boundary.md); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$o" | grep -q 'PREDISPATCH: OK' \
  && ok "P14 Step 2X 접두 오매치 없음 (NFR-3)" || nope "P14" "rc=$rc out=[$o]"

finish
