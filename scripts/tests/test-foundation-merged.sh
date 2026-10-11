#!/usr/bin/env bash
# foundation 브랜치 머지 Phase 0 게이트 — 20260812
#
# 결함: present 는 manifest 문서만 본다. feat/<foundation-FID> 미머지여도
#   start-all 이 batch 로 들어가면 공통 코드가 base 에 없다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-foundation-merged.sh"

_git_init() {
  local td="$1"
  mkdir -p "$td"
  (
    cd "$td" || exit 1
    git init -q
    git checkout -q -b main
    git config user.email "t@example.com"
    git config user.name "t"
    echo base > README
    git add README
    git commit -q -m init
  )
}

_mk_foundation_fid() {
  local td="$1" fid="$2"
  mkdir -p "$td/.specops/$fid" "$td/.specops/memory"
  printf '%s\n' '**§유형**: foundation' > "$td/.specops/$fid/spec.md"
  touch "$td/.specops/memory/frontend-architecture.md"
}

# T1: required + 미머지 feat/<FID> → FAIL
TD=$(mktemp -d)
_git_init "$TD"
_mk_foundation_fid "$TD" "20260101-fnd"
(
  cd "$TD" || exit 1
  git checkout -q -b feat/20260101-fnd
  echo wip > fnd.txt
  git add fnd.txt
  git commit -q -m fnd
  git checkout -q main
)
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'FOUNDATION-MERGED: FAIL' \
  && printf '%s' "$out" | grep -q 'feat/20260101-fnd' \
  && [ "$rc" -eq 1 ] \
  && ok "T1 required+미머지 → FAIL" \
  || nope "T1" "rc=$rc out=$out"
rm -rf "$TD"

# T2: 조상(머지됨) → PASS
TD=$(mktemp -d)
_git_init "$TD"
_mk_foundation_fid "$TD" "20260101-fnd"
(
  cd "$TD" || exit 1
  git checkout -q -b feat/20260101-fnd
  echo wip > fnd.txt
  git add fnd.txt
  git commit -q -m fnd
  git checkout -q main
  git merge -q --no-ff feat/20260101-fnd -m merge-fnd
)
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'FOUNDATION-MERGED: PASS' \
  && [ "$rc" -eq 0 ] \
  && ok "T2 조상 → PASS" \
  || nope "T2" "rc=$rc out=$out"
rm -rf "$TD"

# T3: 비조상 + SPECOPS_BRANCH_GH_STATE=MERGED → PASS
TD=$(mktemp -d)
_git_init "$TD"
_mk_foundation_fid "$TD" "20260101-fnd"
(
  cd "$TD" || exit 1
  git checkout -q -b feat/20260101-fnd
  echo wip > fnd.txt
  git add fnd.txt
  git commit -q -m fnd
  git checkout -q main
)
out=$(cd "$TD" && SPECOPS_BRANCH_GH_STATE=MERGED bash "$CHK" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'FOUNDATION-MERGED: PASS' \
  && [ "$rc" -eq 0 ] \
  && ok "T3 gh MERGED → PASS" \
  || nope "T3" "rc=$rc out=$out"
rm -rf "$TD"

# T4: foundation FID 없음 → SKIP
TD=$(mktemp -d)
_git_init "$TD"
mkdir -p "$TD/.specops/memory"
touch "$TD/.specops/memory/frontend-architecture.md"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'FOUNDATION-MERGED: SKIP (foundation FID 없음)' \
  && [ "$rc" -eq 0 ] \
  && ok "T4 FID 없음 → SKIP" \
  || nope "T4" "rc=$rc out=$out"
rm -rf "$TD"

# T5: FID 있고 브랜치 없음 → PASS
TD=$(mktemp -d)
_git_init "$TD"
_mk_foundation_fid "$TD" "20260101-fnd"
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'FOUNDATION-MERGED: PASS' \
  && [ "$rc" -eq 0 ] \
  && ok "T5 브랜치 없음 → PASS" \
  || nope "T5" "rc=$rc out=$out"
rm -rf "$TD"

# T6: start-all 배선
grep -q 'check-foundation-merged\.sh' "$PLUGIN/commands/start-all.md" \
  && grep -q 'FOUNDATION-MERGED\|foundation 브랜치 머지' "$PLUGIN/commands/start-all.md" \
  && ok "T6 start-all 배선" \
  || nope "T6" "start-all 누락"

# T7: start-all-auto 승계
grep -q 'check-foundation-merged' "$PLUGIN/commands/start-all-auto.md" \
  && ok "T7 start-all-auto 승계" \
  || nope "T7" "auto 누락"

# T8 mutation: 조상 검사를 항상 성공으로 → T1이 PASS로 붕괴
TD=$(mktemp -d)
_git_init "$TD"
_mk_foundation_fid "$TD" "20260101-fnd"
(
  cd "$TD" || exit 1
  git checkout -q -b feat/20260101-fnd
  echo wip > fnd.txt
  git add fnd.txt
  git commit -q -m fnd
  git checkout -q main
)
mut=$(mktemp)
awk '
  /^_branch_merged_into\(\)/ { print; print "  return 0"; skip=1; next }
  skip && /^}/ { skip=0; print; next }
  skip { next }
  { print }
' "$CHK" > "$mut"
out=$(cd "$TD" && bash "$mut" 2>&1); rc=$?
if printf '%s' "$out" | grep -q 'FAIL'; then
  nope "T8 mutation" "무력화했는데도 FAIL — mutation 무효 out=$out"
else
  printf '%s' "$out" | grep -q 'PASS' && [ "$rc" -eq 0 ] \
    && ok "T8 mutation: 조상 무력화 → PASS (비-vacuous)" \
    || nope "T8 mutation" "rc=$rc out=$out"
fi
rm -rf "$TD" "$mut"

# T9: 비필수 KIND + 미머지 → WARN rc=0
TD=$(mktemp -d)
_git_init "$TD"
mkdir -p "$TD/.specops/20260101-fnd" "$TD/.specops/memory"
printf '%s\n' '**§유형**: foundation' > "$TD/.specops/20260101-fnd/spec.md"
# FE/BE arch · decisions 없음 → 비필수
(
  cd "$TD" || exit 1
  git checkout -q -b feat/20260101-fnd
  echo wip > fnd.txt
  git add fnd.txt
  git commit -q -m fnd
  git checkout -q main
)
out=$(cd "$TD" && bash "$CHK" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'FOUNDATION-MERGED: WARN' \
  && [ "$rc" -eq 0 ] \
  && ok "T9 비필수+미머지 → WARN" \
  || nope "T9" "rc=$rc out=$out"
rm -rf "$TD"

# T10: present 회귀 — foundation-kind source 후에도 FE 없음+manifest 없음 FAIL
TD=$(mktemp -d)
mkdir -p "$TD/.specops/memory"
touch "$TD/.specops/memory/frontend-architecture.md"
out=$(cd "$TD" && bash "$PLUGIN/scripts/_internal/check-foundation-present.sh" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'FOUNDATION-PRESENT: FAIL' \
  && [ "$rc" -eq 1 ] \
  && ok "T10 present 회귀 (kind 추출 후)" \
  || nope "T10" "rc=$rc out=$out"
rm -rf "$TD"

finish
