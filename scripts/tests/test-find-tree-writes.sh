#!/usr/bin/env bash
# test-find-tree-writes.sh — 숨은 실 트리 쓰기 탐지기의 자기 검증 (FID 20260911-run-all-parallel · clarify Q4)
# 왜: 탐지기가 조용히 무력화되면 "0건" 이 안전처럼 보인다. 쓰는 더미·읽는 더미가 있는 fixture 에서
#   **실제로 무는지**를 잠근다. 실 repo 전체 실행은 수 분이라 여기서 하지 않는다(수동 도구).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0
FTW="$PLUGIN/scripts/tests/find-tree-writes.sh"

# fixture repo — iso::make_tree 는 git ls-files 와 validate-structure.sh 를 요구한다
_fx() {  # $1=스위트 구성(writer|clean) → 경로
  local d; d=$(mktemp -d) || return 1
  mkdir -p "$d/scripts/tests" "$d/scripts/_internal"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/scripts/_internal/validate-structure.sh"
  echo "원본" > "$d/data.txt"
  printf '%s\n' '#!/usr/bin/env bash' 'R=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)' 'cat "$R/data.txt" >/dev/null; echo "PASS=1 FAIL=0"' \
    > "$d/scripts/tests/test-reader.sh"
  if [ "$1" = writer ]; then
    printf '%s\n' '#!/usr/bin/env bash' 'R=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)' 'echo x > "$R/written.txt"; echo "PASS=1 FAIL=0"' \
      > "$d/scripts/tests/test-writer.sh"
    # 상대경로 쓰기 — 스위트는 루트를 cwd 로 실행된다(run-all 의 cd "$PLUGIN" 과 같음)
    printf '%s\n' '#!/usr/bin/env bash' 'echo x > rel.txt; echo "PASS=1 FAIL=0"' > "$d/scripts/tests/test-relwriter.sh"
    # 오탐 대조군 — 자기 임시 사본에 쓴다. cp 가 쓰기 금지 모드를 보존해 거부되지만 실 트리 쓰기가 아니다(전수 실측 628건의 형태)
    printf '%s\n' '#!/usr/bin/env bash' 'R=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)' 'T=$(mktemp -d); cp "$R/data.txt" "$T/d.txt"; echo y >> "$T/d.txt"; rm -rf "$T"; echo "PASS=1 FAIL=0"' \
      > "$d/scripts/tests/test-nester.sh"
  fi
  ( cd "$d" && git init -q && git add -A ) >/dev/null 2>&1 || return 1
  printf '%s\n' "$d"
}

FX=$(_fx writer) || { nope "T1 fixture" "생성 실패"; finish; exit 1; }
CL=$(_fx clean) || { nope "T2 fixture" "생성 실패"; finish; exit 1; }
trap 'rm -rf "$FX" "$CL"' EXIT

# 쓰기 금지가 무력한 환경(root·ACL 등)에서는 탐지가 성립하지 않는다 — 탐지기가 rc 2 로 알리는지만 보고 탐지 케이스는 SKIP
_ro_inert() { local d; d=$(mktemp -d) || return 1; chmod a-w "$d"; if ( : > "$d/p" ) 2>/dev/null; then chmod u+w "$d"; rm -rf "$d"; return 0; fi; chmod u+w "$d"; rm -rf "$d"; return 1; }
INERT=0; _ro_inert && INERT=1
if [ "$INERT" = 1 ]; then
  out=$(bash "$FTW" --root "$FX" -j 2 2>&1); rc=$?
  { [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q '^판정 불가: 쓰기 금지 사본이 쓰기를 막지 못한다' && ! printf '%s\n' "$out" | grep -q '^TREE-WRITES'; } \
    && ok "T0.a 쓰기 금지 무력 환경 → rc=2 판정 불가 (0건으로 위장하지 않음)" || nope "T0.a 무력 환경" "rc=$rc out=[$out]"
  skip "T1·T2.a·T5.a·T5.e·T5.f 탐지 — 쓰기 금지가 쓰기를 막지 못한다(root·ACL 등)"
else

_st0=$(cd "$FX" && git status --porcelain)
out=$(bash "$FTW" --root "$FX" -j 2 2>&1); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '^WRITE-ATTEMPT scripts/tests/test-writer.sh: .*written.txt: Permission denied'; } \
  && ok "T1.a 루트에 쓰는 스위트 보고 · rc=1" || nope "T1.a writer" "rc=$rc out=[$out]"
printf '%s\n' "$out" | grep -q '^REVIEW scripts/tests/test-relwriter.sh: .*rel.txt: Permission denied' \
  && ok "T1.b 상대경로(cwd=루트) 쓰기는 검토(REVIEW)로 보고" || nope "T1.b relwriter" "out=[$out]"
! printf '%s\n' "$out" | grep -q 'test-reader.sh' \
  && ok "T1.c 읽기만 하는 스위트는 보고하지 않음" || nope "T1.c reader 오보" "out=[$out]"
printf '%s\n' "$out" | grep -qx 'TREE-WRITES: 확정 1건 · 검토 1건 · 스위트 2/5' \
  && ok "T1.d 요약 수치 (확정 1 · 검토 1 · 스위트 2/5 — validate-structure 포함)" || nope "T1.d 요약" "$(printf '%s\n' "$out" | tail -1)"
! printf '%s\n' "$out" | grep -q 'test-nester.sh' \
  && ok "T1.f 스위트 자신의 임시 사본 거부는 보고하지 않음 (오탐 억제)" || nope "T1.f nester 오보" "out=[$out]"
{ [ ! -e "$FX/written.txt" ] && [ ! -e "$FX/rel.txt" ] && [ "$(cd "$FX" && git status --porcelain)" = "$_st0" ]; } \
  && ok "T1.e 대상 repo 는 변경되지 않음 (사본에서만 실행)" || nope "T1.e 대상 repo 변경" "$(cd "$FX" && git status --porcelain)"

out=$(bash "$FTW" --root "$CL" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx 'TREE-WRITES: 확정 0건 · 검토 0건 · 스위트 0/2'; } \
  && ok "T2.a 쓰기 없는 repo → rc=0 · 0건" || nope "T2.a clean" "rc=$rc out=[$out]"
fi

bash "$FTW" --root "$CL" -j abc >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "T3.a 잘못된 -j → rc=2" || nope "T3.a 사용법 오류" "rc=$rc"

# ── T5: 입력 경계 (Phase C 지적) — 조용한 0건 금지 ──
#   이름에 공백·작은따옴표가 있는 스위트도 검사한다(개행 구분 xargs 는 여기서 abort 해 그 스위트를 무음 스킵했다)
OD=$(_fx clean) || { nope "T5 fixture" "생성 실패"; finish; exit 1; }
trap 'rm -rf "$FX" "$CL" "$OD"' EXIT
for n in "sp ace" "q'uote"; do
  printf '%s\n' '#!/usr/bin/env bash' 'R=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)' 'echo x > "$R/odd.txt"; echo "PASS=1 FAIL=0"' \
    > "$OD/scripts/tests/test-$n.sh"
done
( cd "$OD" && git add -A ) >/dev/null 2>&1
if [ "$INERT" = 0 ]; then   # 무력 환경은 위 T0.a 가 다룬다
out=$(bash "$FTW" --root "$OD" -j 2 2>&1); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q "^WRITE-ATTEMPT scripts/tests/test-sp ace.sh: " \
  && printf '%s\n' "$out" | grep -q "^WRITE-ATTEMPT scripts/tests/test-q'uote.sh: " \
  && printf '%s\n' "$out" | grep -qx 'TREE-WRITES: 확정 2건 · 검토 0건 · 스위트 2/4' \
  && ! printf '%s\n' "$out" | grep -q '^xargs:'; } \
  && ok "T5.a 공백·따옴표 이름 스위트도 검사 (확정 2 · 스위트 2/4)" || nope "T5.a 특수 이름" "rc=$rc out=[$out]"
fi
out=$(bash "$FTW" --root "$CL" scripts/tests/test-none.sh 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && ! printf '%s\n' "$out" | grep -q '^TREE-WRITES'; } \
  && ok "T5.b 없는 스위트 경로 → rc=2 (0건으로 위장하지 않음)" || nope "T5.b 없는 경로" "rc=$rc out=[$out]"
bash "$FTW" --root "$CL" -j '' >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "T5.c 빈 -j → rc=2" || nope "T5.c 빈 -j" "rc=$rc"
#   존재 검사는 **실행 지점(사본)** 기준이어야 한다 — 사본은 git 추적 파일만 담아, 방금 쓴 미추적 스위트는 원본엔 있고 사본엔 없다
printf '%s\n' '#!/usr/bin/env bash' 'echo x > u.txt; echo "PASS=1 FAIL=0"' > "$CL/scripts/tests/test-untracked.sh"
out=$(bash "$FTW" --root "$CL" scripts/tests/test-untracked.sh 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && ! printf '%s\n' "$out" | grep -q '^TREE-WRITES'; } \
  && ok "T5.d 미추적 스위트 → rc=2 (사본에 없어 0건으로 위장하지 않음)" || nope "T5.d 미추적" "rc=$rc out=[$out]"
rm -f "$CL/scripts/tests/test-untracked.sh"
if [ "$INERT" = 0 ]; then   # 무력 환경은 위 T0.a 가 다룬다
out=$(bash "$FTW" --root "$FX" ./scripts/tests/test-writer.sh 2>&1); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '^WRITE-ATTEMPT ./scripts/tests/test-writer.sh: ' \
  && printf '%s\n' "$out" | grep -qx 'TREE-WRITES: 확정 1건 · 검토 0건 · 스위트 1/1'; } \
  && ok "T5.e ./ 접두 경로도 결과가 집계된다 (점파일 누락 없음)" || nope "T5.e ./ 접두" "rc=$rc out=[$out]"
fi
printf '%s\n' '#!/usr/bin/env bash' 'R=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)' 'echo x > "$R/h.txt"; echo "PASS=1 FAIL=0"' > "$OD/scripts/tests/test-h#ash.sh"
( cd "$OD" && git add -A ) >/dev/null 2>&1
if [ "$INERT" = 0 ]; then   # 무력 환경은 위 T0.a 가 다룬다
out=$(bash "$FTW" --root "$OD" "scripts/tests/test-h#ash.sh" 2>&1); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '^WRITE-ATTEMPT scripts/tests/test-h#ash.sh: ' \
  && ! printf '%s\n' "$out" | grep -q '^sed:'; } \
  && ok "T5.f 이름에 # 가 있어도 보고된다 (sed 구분자 충돌 없음)" || nope "T5.f # 이름" "rc=$rc out=[$out]"
fi

# run-all 비포함(clarify Q2) — run-all 은 test-*.sh 만 모은다. 이름이 그 패턴이면 매 run-all 마다 전 스위트를 한 번 더 돈다
case "$(basename "$FTW")" in
  test-*) nope "T4.a 수동 도구 이름" "$(basename "$FTW") 는 run-all glob(test-*.sh)에 걸린다" ;;
  *) [ -f "$FTW" ] && ok "T4.a 탐지기는 run-all glob 밖 이름 ($(basename "$FTW"))" || nope "T4.a" "탐지기 부재" ;;
esac

echo ""
finish
