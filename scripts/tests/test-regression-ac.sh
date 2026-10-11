#!/usr/bin/env bash
# 회귀 AC(AC-R-1/AC-R-2) 게이트 기계화 — 20260806 /maintain 정밀분석
#
# 결함: "/maintain 의 존재 이유" 인 회귀 안전망이 전부 산문이었다.
#   - specifying-ko:133·205 "유지보수 → AC-R-1 강제(스키마면 AC-R-2)"
#   - 템플릿: "sprint-contracts evaluator 가 회귀 AC 누락 시 verdict=BLOCK"
#   그런데 verify·emit-context·release-ready 어디에도 검사 스크립트가 0곳 —
#   모델이 빠뜨리면 회귀 AC 없이 구현이 진행된다(멀쩡하던 것이 깨지는 클래스).
# 추가: 템플릿이 AC-R-1/AC-R-2 섹션을 **기본 포함**하므로 "헤더 존재" 만 보면
#   템플릿 복사만으로 뚫린다 — Given/When/Then 의 템플릿 문구 잔존을 미채움으로 판정.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-regression-ac.sh"

_mk() {  # $1=dir $2=fid $3=§유형 [$4=override(y)]
  # 마커는 analyzing 계약과 정합하게 생성 — override 는 라인수 무관 강제 비trivial 이고,
  # trivial 라벨이면 마커도 trivial 이어야 한다 (불일치 조합은 T13 라벨 검사 전용 픽스처).
  mkdir -p "$1/.specops/$2"
  printf '**§유형**: %s\n' "$3" > "$1/.specops/$2/spec.md"
  if [ "${4:-n}" = "y" ]; then
    printf '# 현행\n**라인 범위 합산: 2줄 → 유지보수(스키마 override)**\n' \
      > "$1/.specops/$2/current-state.md"
  elif [ "$3" = "trivial" ]; then
    printf '# 현행\n**라인 범위 합산: 3줄 → trivial**\n' \
      > "$1/.specops/$2/current-state.md"
  else
    printf '# 현행\n**라인 범위 합산: 12줄 → 유지보수**\n' \
      > "$1/.specops/$2/current-state.md"
  fi
}
_ac_r1_filled() { cat <<'EOF'
# AC

### AC-1: 기본
**Given** 입력 x
**When** 실행
**Then** 출력 y
**우선순위**: must

### AC-R-1: 기존 동작 보존
**Given** 기존 사용자가 `login.sh alice` 를 실행하던 패턴
**When** 변경 후 동일 명령 실행
**Then** 기존 출력 `welcome alice` 와 동일하게 동작한다 — 변경되지 않음
**검증 방법**: bash scripts/tests/test-login-regression.sh
**우선순위**: must
EOF
}
_ac_r1_template() { cat <<'EOF'
# AC

### AC-R-1: 기존 동작 보존
**Given** [구체적 입력 또는 기존 호출 패턴]
**When** [현재와 동일한 트리거]
**Then** 기존 출력 [구체적 결과] 와 동일하게 동작한다 — 변경되지 않음
**검증 방법**: [기존 회귀 테스트 경로 또는 신규 회귀 테스트 추가]
**우선순위**: must
EOF
}
_ac_r2_filled() { cat <<'EOF'

### AC-R-2: 데이터 보존·역가역성
**Given** users 테이블에 기존 행 100건, email 컬럼 채워짐
**When** 마이그레이션 forward(up) 적용 후 reverse(down) 적용
**Then** up→down→up 멱등 + 기존 100건 데이터 손실 0 + NOT NULL 위반 0
**검증 방법**: bash scripts/tests/test-migration-roundtrip.sh
**우선순위**: must
EOF
}

# T1: 유지보수 + acceptance-criteria.md 부재 → FAIL
TD=$(mktemp -d); _mk "$TD" 20260806-m 유지보수
(cd "$TD" && bash "$CHK" 20260806-m >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T1 유지보수 + AC 파일 부재 → FAIL" || nope "T1" "rc=$rc"
rm -rf "$TD"

# T2: 유지보수 + AC-R-1 채움 → PASS
TD=$(mktemp -d); _mk "$TD" 20260806-m 유지보수
_ac_r1_filled > "$TD/.specops/20260806-m/acceptance-criteria.md"
(cd "$TD" && bash "$CHK" 20260806-m >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T2 AC-R-1 채움 → PASS" || nope "T2" "rc=$rc"
rm -rf "$TD"

# T3: ★ 템플릿 그대로(placeholder 잔존) → FAIL — 헤더만으론 안 뚫린다
TD=$(mktemp -d); _mk "$TD" 20260806-m 유지보수
_ac_r1_template > "$TD/.specops/20260806-m/acceptance-criteria.md"
(cd "$TD" && bash "$CHK" 20260806-m >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T3 템플릿 placeholder 잔존 → FAIL" || nope "T3" "rc=$rc"
rm -rf "$TD"

# T4: AC-R-1 헤더 자체가 없음 → FAIL
TD=$(mktemp -d); _mk "$TD" 20260806-m 유지보수
printf '# AC\n### AC-1: 기본\n**Given** x\n**When** y\n**Then** z\n' \
  > "$TD/.specops/20260806-m/acceptance-criteria.md"
(cd "$TD" && bash "$CHK" 20260806-m >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T4 AC-R-1 부재 → FAIL" || nope "T4" "rc=$rc"
rm -rf "$TD"

# T5: §유형=신규 → skip (AC-R 면제 계약)
TD=$(mktemp -d); _mk "$TD" 20260806-m 신규
printf '# AC\n' > "$TD/.specops/20260806-m/acceptance-criteria.md"
(cd "$TD" && bash "$CHK" 20260806-m >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T5 신규 → skip" || nope "T5" "rc=$rc"
rm -rf "$TD"

# T6: §유형=trivial → skip
TD=$(mktemp -d); _mk "$TD" 20260806-m trivial
printf '# AC\n' > "$TD/.specops/20260806-m/acceptance-criteria.md"
(cd "$TD" && bash "$CHK" 20260806-m >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T6 trivial → skip" || nope "T6" "rc=$rc"
rm -rf "$TD"

# T7: ★ 스키마 override 마커 + AC-R-2 부재 → FAIL (AC-R-1 채움이어도)
TD=$(mktemp -d); _mk "$TD" 20260806-m 유지보수 y
_ac_r1_filled > "$TD/.specops/20260806-m/acceptance-criteria.md"
out=$(cd "$TD" && bash "$CHK" 20260806-m 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'AC-R-2' \
  && ok "T7 스키마 override + AC-R-2 부재 → FAIL" || nope "T7" "rc=$rc out=$out"
rm -rf "$TD"

# T8: 스키마 override + AC-R-1·AC-R-2 채움 → PASS
TD=$(mktemp -d); _mk "$TD" 20260806-m 유지보수 y
{ _ac_r1_filled; _ac_r2_filled; } > "$TD/.specops/20260806-m/acceptance-criteria.md"
(cd "$TD" && bash "$CHK" 20260806-m >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T8 override + 둘 다 채움 → PASS" || nope "T8" "rc=$rc"
rm -rf "$TD"

# T9: ★ trivial 라벨 + 스키마 override → 차단 (라벨 불일치 우선 — analyzing 계약상
#     override 는 라인수 무관 강제 비trivial 이므로 이 조합 자체가 다운그레이드다.
#     정정 후 spec=유지보수 가 되면 AC-R-2 요구는 T7 이 잠근다 — 데이터 안전 우회 경로 없음)
TD=$(mktemp -d); _mk "$TD" 20260806-m trivial y
printf '# AC\n### AC-1: 기본\n**Given** x\n**When** y\n**Then** z\n' \
  > "$TD/.specops/20260806-m/acceptance-criteria.md"
out=$(cd "$TD" && bash "$CHK" 20260806-m 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qE '라벨|AC-R-2' \
  && ok "T9 trivial + override → 차단(라벨 불일치)" || nope "T9" "rc=$rc out=$out"
rm -rf "$TD"

# T10: spec.md 부재 → fail-open
TD=$(mktemp -d); mkdir -p "$TD/.specops/20260806-m"
(cd "$TD" && bash "$CHK" 20260806-m >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T10 spec 부재 → fail-open" || nope "T10" "rc=$rc"
rm -rf "$TD"

# T11: emit-context 배선 (구현 직전 — foundation 게이트와 동일 지점)
grep -q 'check-regression-ac.sh' "$PLUGIN/scripts/dag/emit-context.sh" \
  && ok "T11 emit-context 배선" || nope "T11" "미배선 — 산문 잔존"

# T12: 템플릿이 판정 SoT 를 지목 (구 문구는 evaluator BLOCK 주장뿐 — 구현 없었음)
grep -q 'check-regression-ac.sh' "$PLUGIN/templates/acceptance-criteria.md" \
  && ok "T12 템플릿 SoT 지목" || nope "T12" "템플릿 미갱신"

# ── 라벨 정합 (20260806 후속) — analyzing 마커 ↔ spec §유형 다운그레이드 차단 ──
# analyzing 이 합산 >5 로 `→ 유지보수` 마커를 썼는데 spec 이 trivial 로 라벨되면
# AC-R-1 면제가 근거 없이 열린다. 두 산출물 다 파일이라 정합은 기계 검사 가능.
# T13: 마커 유지보수 + spec trivial → FAIL (라벨 다운그레이드)
TD=$(mktemp -d); _mk "$TD" 20260806-m trivial
printf '# 현행\n**라인 범위 합산: 12줄 → 유지보수**\n' > "$TD/.specops/20260806-m/current-state.md"
printf '# AC\n' > "$TD/.specops/20260806-m/acceptance-criteria.md"
out=$(cd "$TD" && bash "$CHK" 20260806-m 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '라벨' \
  && ok "T13 마커 유지보수 + spec trivial → FAIL(라벨 불일치)" || nope "T13" "rc=$rc out=$out"
rm -rf "$TD"

# T14: 마커 trivial + spec trivial → 정합 skip (정당한 trivial)
TD=$(mktemp -d); _mk "$TD" 20260806-m trivial
printf '# 현행\n**라인 범위 합산: 3줄 → trivial**\n' > "$TD/.specops/20260806-m/current-state.md"
printf '# AC\n' > "$TD/.specops/20260806-m/acceptance-criteria.md"
(cd "$TD" && bash "$CHK" 20260806-m >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T14 마커·spec 둘 다 trivial → skip" || nope "T14" "rc=$rc"
rm -rf "$TD"

# T15: 마커 trivial + spec 유지보수(상향) → 허용 — 더 엄격한 쪽은 정당
TD=$(mktemp -d); _mk "$TD" 20260806-m 유지보수
printf '# 현행\n**라인 범위 합산: 3줄 → trivial**\n' > "$TD/.specops/20260806-m/current-state.md"
_ac_r1_filled > "$TD/.specops/20260806-m/acceptance-criteria.md"
(cd "$TD" && bash "$CHK" 20260806-m >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T15 상향(spec 유지보수) → 허용" || nope "T15" "rc=$rc"
rm -rf "$TD"

# ── T-neg: "스키마 override: 미발동" 부정문을 긍정으로 오독하지 않는다 ──────
# 20260807 실사용 검증(FID 20260807-doctor-ci-check) 실측 결함:
#   판정이 `grep -q '스키마 override'` 라 **문자열 존재만** 봤다. analyzing-ko 가
#   "스키마 override: 미발동 — …" 이라고 **부정문으로 근거를 남기면** 그것마저
#   양성으로 읽혀 AC-R-2(데이터 보존)를 근거 없이 요구했다.
#   analyzing-ko:122 가 규정한 **양성 마커**는 합산 줄의 `→ 유지보수(스키마 override)` 다.
#   1호(AC 골격 오탐)·2호와 같은 클래스 — "언급" vs "해당".
_neg=$(mktemp -d); mkdir -p "$_neg/.specops/20260101-neg"
cat > "$_neg/.specops/20260101-neg/spec.md" <<'EOF'
# spec
**§유형**: 유지보수
EOF
cat > "$_neg/.specops/20260101-neg/current-state.md" <<'EOF'
# 현재 상태
**라인 범위 합산: 90줄 → 유지보수**

**스키마 override**: 미발동 — CLI 스크립트로 마이그레이션·ALTER/DROP 변경 없음.
EOF
cat > "$_neg/.specops/20260101-neg/acceptance-criteria.md" <<'EOF'
### AC-R-1: 기존 동작 보존

**Given** 기존 호출 패턴
**When** 동일 트리거
**Then** 동일 출력

**우선순위**: must
EOF
_o=$(cd "$_neg" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/check-regression-ac.sh" 20260101-neg 2>&1); _r=$?
if [ "$_r" -eq 0 ]; then
  ok "T-neg 부정문(미발동)은 AC-R-2 를 요구하지 않는다"
else
  nope "T-neg" "부정 언급을 양성으로 오독 — rc=$_r out=$_o"
fi

# ── T-pos: 양성 마커(합산 줄의 `→ 유지보수(스키마 override)`)는 여전히 AC-R-2 요구 ──
# 축 분리 — T-neg 수정이 판정을 통째로 죽이면 안 된다.
cat > "$_neg/.specops/20260101-neg/current-state.md" <<'EOF'
# 현재 상태
**라인 범위 합산: 3줄 → 유지보수(스키마 override)**
EOF
_o=$(cd "$_neg" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/check-regression-ac.sh" 20260101-neg 2>&1); _r=$?
if [ "$_r" -eq 1 ] && printf '%s' "$_o" | grep -q 'AC-R-2'; then
  ok "T-pos 양성 마커는 AC-R-2 요구 (판정 유지)"
else
  nope "T-pos" "양성 마커를 놓침 — rc=$_r out=$_o"
fi
rm -rf "$_neg"

finish
