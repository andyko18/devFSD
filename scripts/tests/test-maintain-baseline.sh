#!/usr/bin/env bash
# 유지보수 baseline 산출물 게이트 — 20260806 구현 정합성 개선
#
# 결함(클래스 A — 선언은 HARD, 구현은 0곳): `analyzing-ko` 의 HARD-GATE 는
#   "두 산출물(current-state.md + impact-analysis.md) 사용자 검토 통과 전 specifying 호출 금지"
#   인데, **산출물 존재 자체를 검사하는 층이 0곳**이었다. 실측: 유지보수 FID 가
#   analyzing 산출물 0개로 emit-context 를 통과해 구현까지 간다.
#
# 왜 심각한가 — 2차 피해가 데이터 안전이다:
#   `check-regression-ac` 의 **스키마 override 판정이 current-state.md 를 읽는다**.
#   파일이 없으면 need_r2=0 이 되어 **파괴적 스키마 변경에도 AC-R-2(데이터 보존)가
#   요구되지 않는다** — 안전망이 조용히 꺼진다.
#   또 AC-R-1("기존 동작 보존")은 baseline 없이는 근거가 없다 — 무엇을 보존하는지 모른다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-maintain-baseline.sh"

_fid() {  # $1=dir $2=fid $3=§유형
  mkdir -p "$1/.specops/$2"
  printf '**§유형**: %s\n' "$3" > "$1/.specops/$2/spec.md"
  printf '# tasks\n' > "$1/.specops/$2/tasks.md"
}
_baseline() {  # $1=dir $2=fid — analyzing 산출물 2종
  printf '# 현행\n**라인 범위 합산: 12줄 → 유지보수**\n' > "$1/.specops/$2/current-state.md"
  printf '# 영향\n## 1. 외부 영향\n실제 내용\n' > "$1/.specops/$2/impact-analysis.md"
}

# T1: ★ 유지보수 + 산출물 0개 → FAIL
TD=$(mktemp -d); _fid "$TD" 20260806-m 유지보수
out=$(cd "$TD" && bash "$CHK" 20260806-m 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'current-state' \
  && ok "T1 유지보수 + baseline 0개 → FAIL" || nope "T1" "rc=$rc out=$out"
rm -rf "$TD"

# T2: 둘 다 있으면 PASS
TD=$(mktemp -d); _fid "$TD" 20260806-m 유지보수; _baseline "$TD" 20260806-m
(cd "$TD" && bash "$CHK" 20260806-m >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T2 baseline 2종 존재 → PASS" || nope "T2" "rc=$rc"
rm -rf "$TD"

# T3: 하나만 있어도 FAIL (impact 누락)
TD=$(mktemp -d); _fid "$TD" 20260806-m 유지보수
printf '# 현행\n**라인 범위 합산: 12줄 → 유지보수**\n' > "$TD/.specops/20260806-m/current-state.md"
out=$(cd "$TD" && bash "$CHK" 20260806-m 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'impact-analysis' \
  && ok "T3 impact-analysis 누락 → FAIL" || nope "T3" "rc=$rc out=$out"
rm -rf "$TD"

# T4: ★ 껍데기 baseline(템플릿 placeholder 잔존) → FAIL (파일만 만들고 안 채운 통과 차단)
TD=$(mktemp -d); _fid "$TD" 20260806-m 유지보수
printf '# 현행\n<변경 대상 파일>\n' > "$TD/.specops/20260806-m/current-state.md"
printf '# 영향\n<외부 영향 내용>\n' > "$TD/.specops/20260806-m/impact-analysis.md"
(cd "$TD" && bash "$CHK" 20260806-m >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T4 placeholder 잔존 baseline → FAIL" || nope "T4" "rc=$rc"
rm -rf "$TD"

# T5: §유형=신규 → skip (analyzing 대상 아님)
TD=$(mktemp -d); _fid "$TD" 20260806-n 신규
(cd "$TD" && bash "$CHK" 20260806-n >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T5 신규 → skip" || nope "T5" "rc=$rc"
rm -rf "$TD"

# T6: §유형=trivial → skip
TD=$(mktemp -d); _fid "$TD" 20260806-t trivial
(cd "$TD" && bash "$CHK" 20260806-t >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T6 trivial → skip" || nope "T6" "rc=$rc"
rm -rf "$TD"

# T7: spec.md 부재 → fail-open
TD=$(mktemp -d); mkdir -p "$TD/.specops/20260806-m"
(cd "$TD" && bash "$CHK" 20260806-m >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T7 spec 부재 → fail-open" || nope "T7" "rc=$rc"
rm -rf "$TD"

# T8: emit-context 배선 (구현 직전 차단)
grep -q 'check-maintain-baseline.sh' "$PLUGIN/scripts/dag/emit-context.sh" \
  && ok "T8 emit-context 배선" || nope "T8" "미배선"

# T9: analyzing-ko 가 판정 SoT 를 지목
grep -q 'check-maintain-baseline.sh' "$PLUGIN/skills/analyzing-ko/SKILL.md" \
  && ok "T9 analyzing-ko SoT 지목" || nope "T9" "스킬 본문 미갱신"

finish
