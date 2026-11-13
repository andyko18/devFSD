#!/usr/bin/env bash
# related-suite-fresh.sh — 관련 스위트 통과 기록이 지금 트리와 지금 변경이 닿는 스위트 전부를 덮는지 (20261113)
#   계약: 덮었을 때만 FRESH(rc 0). 판정할 수 없으면 전부 STALE(rc 1) — 증거로 치는 방향의 오판 경로가 없다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
FRESH="$PLUGIN/scripts/_internal/related-suite-fresh.sh"
[ -f "$FRESH" ] || { echo "FAIL F0 판정기 부재: $FRESH"; echo "PASS=0 FAIL=1"; exit 1; }
TMP=$(mktemp -d) || exit 1; trap 'rm -rf "$TMP"' EXIT

R="$TMP/repo"
mkdir -p "$R/scripts/tests" "$R/scripts/_internal" "$R/.specops"
cp "$PLUGIN/scripts/tests/run-related.sh" "$R/scripts/tests/run-related.sh"
cp "$PLUGIN/scripts/_internal/verification-state.sh" "$PLUGIN/scripts/_internal/file-class.sh" "$R/scripts/_internal/"
printf '#!/usr/bin/env bash\necho structure-ok\n' > "$R/scripts/_internal/validate-structure.sh"
printf '#!/usr/bin/env bash\necho doc-numbers\n' > "$R/scripts/tests/test-doc-numbers.sh"
printf '#!/usr/bin/env bash\necho count\n' > "$R/scripts/count.sh"
printf '#!/usr/bin/env bash\necho old\n' > "$R/scripts/old.sh"
printf '#!/usr/bin/env bash\n# scripts/count.sh 를 본다\necho "PASS=1 FAIL=0"\n' > "$R/scripts/tests/test-count.sh"
printf '#!/usr/bin/env bash\n# scripts/old.sh 를 본다\necho "PASS=1 FAIL=0"\n' > "$R/scripts/tests/test-old.sh"
printf '#!/usr/bin/env bash\n# scripts/new.sh 를 본다\necho "PASS=1 FAIL=0"\n' > "$R/scripts/tests/test-new.sh"
printf '.specops/\n' > "$R/.gitignore"
( cd "$R" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@e.com -c commit.gpgsign=false commit -qm init \
  && git update-ref refs/remotes/origin/main HEAD ) >/dev/null 2>&1 || { echo "FATAL: 픽스처 생성 실패" >&2; exit 1; }
printf 'echo v2\n' >> "$R/scripts/count.sh"   # 변경 1개 — 닿는 스위트: 구조 검증 · test-count · test-doc-numbers

MK="$R/.specops/.related-suite-pass"
NEED3="scripts/_internal/validate-structure.sh scripts/tests/test-count.sh scripts/tests/test-doc-numbers.sh"
_fp() { ( cd "$R" && . "$PLUGIN/scripts/_internal/verification-state.sh" && vs::nondoc_fingerprint ) 2>/dev/null; }
_mark() { { _fp; echo; [ "$#" -eq 0 ] || printf '%s\n' "$@"; } > "$MK"; }
_run() { ( cd "$R" && env -u SPECOPS_FORCE_FULL bash "$FRESH" "$@" ); }
_stale() {  # $1=이름 $2=설명 [$3=사유에 있어야 할 글자] — 직전에 만든 상태로 판정기를 돌린다
  local out rc; out=$(_run 2>/dev/null); rc=$?
  if [ "$rc" = 1 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && printf '%s' "$out" | grep -q '^related-suite STALE (' \
     && { [ -z "${3:-}" ] || printf '%s' "$out" | grep -qF -- "$3"; }; then ok "$1 $2"; else nope "$1 $2" "rc=$rc out=[$out]"; fi
}

# ── F1 덮은 통과 → FRESH (AC-1) ──
# shellcheck disable=SC2086
_mark $NEED3; fp=$(_fp); before=$(cksum < "$MK")
touch -t 200001010000 "$MK"; touch -t 200101010000 "$TMP/ref"   # 판정기가 기록을 건드리면 ref 보다 새것이 된다
out=$(_run); rc=$?
[ "$rc" = 0 ] && [ "$out" = "related-suite FRESH (fp=${fp:0:12}, suites=3)" ] \
  && ok "F1 ★ 지문 일치 + 닿는 스위트 전부 기록 → FRESH 1줄(지문 앞 12자 · 스위트 수)" || nope "F1" "rc=$rc out=[$out]"
{ [ "$(cksum < "$MK")" = "$before" ] && [ -z "$(find "$MK" -newer "$TMP/ref")" ]; } && ok "F1b 판정기는 통과 기록의 내용·수정 시각을 바꾸지 않는다" || nope "F1b"
# shellcheck disable=SC2086
_mark $NEED3 scripts/tests/test-old.sh; out=$(_run); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'suites=3)$' && ok "F1c 기록이 닿는 스위트보다 넓어도 FRESH — suites 는 기록 줄 수(4)가 아니라 고른 수(3)" || nope "F1c" "rc=$rc out=[$out]"

# ── F2 덮지 못했거나 판정 불가 → STALE (AC-2) ──
_mark scripts/_internal/validate-structure.sh scripts/tests/test-doc-numbers.sh
_stale F2a "★ 닿는 스위트 1개가 기록에 없다 → STALE(스위트 누락 + 빠진 경로)" "스위트 누락 1개 — scripts/tests/test-count.sh"
# shellcheck disable=SC2086
{ printf 'deadbeef\n'; printf '%s\n' $NEED3; } > "$MK"
_stale F2b "★ 지문이 다른 트리의 것 → STALE" "지문 불일치"
rm -f "$MK"; _stale F2c "통과 기록 없음 → STALE" "통과 기록 부재"
: > "$MK"; _stale F2d "빈 통과 기록 → STALE" "통과 기록이 비었거나 읽을 수 없음"
( cd "$R" && git checkout -q -- scripts/count.sh )
# shellcheck disable=SC2086
_mark $NEED3; _stale F2e "★ 변경 파일 0개는 '덮었다'가 아니다 → STALE" "변경 파일 없음"
printf 'echo v2\n' >> "$R/scripts/count.sh"
# shellcheck disable=SC2086
_mark $NEED3
( cd "$R" && git update-ref -d refs/remotes/origin/main )
_stale F2f "origin 기본 브랜치를 모름 → STALE" "origin 의 기본 브랜치를 모름"
( cd "$R" && git update-ref refs/remotes/origin/main HEAD )
out=$( cd "$R" && SPECOPS_FORCE_FULL=0 bash "$FRESH" ); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^related-suite STALE (SPECOPS_FORCE_FULL 지정)$' && ok "F2g SPECOPS_FORCE_FULL 은 값과 무관하게 STALE" || nope "F2g" "rc=$rc out=[$out]"
printf '#!/usr/bin/env bash\necho orphan\n' > "$R/scripts/orphan.sh"
# shellcheck disable=SC2086
_mark $NEED3; _stale F2h "★ 어느 스위트도 언급하지 않는 코드 파일(추적 안 됨) → 고를 수 없어 STALE" "관련 스위트를 고를 수 없음"
rm -f "$R/scripts/orphan.sh"
# shellcheck disable=SC2086
_mark $NEED3
out=$(_run --bogus 2>/dev/null); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^related-suite STALE (알 수 없는 인자: --bogus)$' && ok "F2i 알 수 없는 인자 → STALE" || nope "F2i" "rc=$rc out=[$out]"
_mark scripts/_internal/validate-structure.sh scripts/tests/test-count scripts/tests/test-doc-numbers.sh
_stale F2j "★ 경로의 접두만 기록에 있다 → STALE(줄 단위 완전 일치)" "scripts/tests/test-count.sh"
# 이름 바꿈 — 옛 경로를 언급하는 스위트가 빠지면 STALE 이어야 한다(옛 경로·새 경로 둘 다 변경 파일이다)
( cd "$R" && git mv scripts/old.sh scripts/new.sh )
# shellcheck disable=SC2086
_mark $NEED3 scripts/tests/test-new.sh scripts/tests/test-old.sh; out=$(_run); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'suites=5)$' && ok "F2k0 대조 — 이름 바꿈: 옛·새 이름의 스위트를 다 덮으면 FRESH(5개)" || nope "F2k0" "rc=$rc out=[$out]"
# shellcheck disable=SC2086
_mark $NEED3 scripts/tests/test-new.sh
_stale F2k "★ 이름 바꿈: 옛 이름을 언급하는 스위트가 빠졌다 → STALE" "scripts/tests/test-old.sh"
( cd "$R" && git mv scripts/new.sh scripts/old.sh )
# shellcheck disable=SC2086
_mark $NEED3
mv "$R/scripts/tests/run-related.sh" "$TMP/rr.bak"
_stale F2l "대상 저장소에 run-related.sh 가 없다 → STALE" "run-related.sh 부재"
mv "$TMP/rr.bak" "$R/scripts/tests/run-related.sh"
out=$( cd "$TMP" && env -u SPECOPS_FORCE_FULL bash "$FRESH" 2>/dev/null ); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^related-suite STALE (git repo 아님)$' && ok "F2m git 저장소 밖 → STALE" || nope "F2m" "rc=$rc out=[$out]"
# 기록이 지문 줄만(스위트 0줄) → 고른 스위트가 1개 이상이므로 STALE
_mark; _stale F2o "★ 기록의 스위트 목록이 0줄 → STALE(전부 누락)" "스위트 누락 3개"
# 고른 스위트가 0개 — 상시 스위트가 없는 저장소에서 문서만 바뀜 → STALE(FRESH suites=0 이 되면 안 된다)
R2="$TMP/repo2"; mkdir -p "$R2/scripts/tests" "$R2/scripts/_internal" "$R2/.specops"
cp "$PLUGIN/scripts/tests/run-related.sh" "$R2/scripts/tests/"; cp "$PLUGIN/scripts/_internal/verification-state.sh" "$PLUGIN/scripts/_internal/file-class.sh" "$R2/scripts/_internal/"
printf 'doc\n' > "$R2/README.md"; printf '.specops/\n' > "$R2/.gitignore"
( cd "$R2" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@e.com -c commit.gpgsign=false commit -qm init && git update-ref refs/remotes/origin/main HEAD ) >/dev/null 2>&1
printf 'doc2\n' >> "$R2/README.md"
( cd "$R2" && . "$PLUGIN/scripts/_internal/verification-state.sh" && vs::nondoc_fingerprint ) > "$R2/.specops/.related-suite-pass" 2>/dev/null
out=$( cd "$R2" && env -u SPECOPS_FORCE_FULL bash "$FRESH" 2>/dev/null ); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^related-suite STALE (관련 스위트 목록이 비었음)$' && ok "F2p ★ 고른 스위트 0개 → STALE(0개를 '전부 덮었다'로 치지 않는다)" || nope "F2p" "rc=$rc out=[$out]"
# 공통 조상 없음 — origin/main 이 무관한 루트 커밋을 가리킨다
# shellcheck disable=SC2086
_mark $NEED3
( cd "$R" && git update-ref refs/remotes/origin/main "$(git -c user.name=t -c user.email=t@e.com commit-tree "$(git mktree </dev/null)" -m unrelated)" )
_stale F2q "★ 기본 브랜치와 공통 조상이 없다 → STALE" "공통 조상 없음"
( cd "$R" && git update-ref refs/remotes/origin/main HEAD )
# 읽을 수 없는 untracked 파일 — 지문 계산이 조용히 퇴행할 수 있다. root 면 건너뛴다(chmod 000 이 읽힌다)
if [ "$(id -u)" != 0 ]; then
  # shellcheck disable=SC2086
  _mark $NEED3   # 기록을 먼저 쓴다 — 읽을 수 없는 파일이 생기기 전의 정상 지문
  printf 'x\n' > "$R/scratch.txt"; chmod 000 "$R/scratch.txt"
  _stale F2r "★ 읽을 수 없는 untracked 파일 → STALE(지문 비교보다 먼저 막는다)" "읽을 수 없는 untracked 파일"
  chmod 644 "$R/scratch.txt"; rm -f "$R/scratch.txt"
fi

# ── F7 --need — 판정기와 같은 변경 파일 집합으로 스위트를 고른다 (AC-7) ──
rm -f "$MK"
out=$(_run --need 2>/dev/null); rc=$?
want=$( cd "$R" && bash scripts/tests/run-related.sh --list scripts/count.sh 2>/dev/null )
# shellcheck disable=SC2086
[ "$rc" = 0 ] && [ -n "$want" ] && [ "$out" = "$want" ] && [ "$out" = "$(printf '%s\n' $NEED3)" ] && ok "F7a ★ --need → 변경이 닿는 스위트 목록(통과 기록이 없어도 같다)" || nope "F7a" "rc=$rc out=[$out] want=[$want]"
[ ! -e "$MK" ] && ok "F7b --need 는 통과 기록을 만들지 않는다" || nope "F7b"
# shellcheck disable=SC2046
( cd "$R" && bash scripts/tests/run-related.sh $(env -u SPECOPS_FORCE_FULL bash "$FRESH" --need) >/dev/null 2>&1 ); rrc=$?
out=$(_run); rc=$?
[ "$rrc" = 0 ] && [ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^related-suite FRESH (' && ok "F7c ★ --need 의 스위트로 러너를 돌리면 판정기가 FRESH" || nope "F7c" "runner=$rrc rc=$rc out=[$out]"
printf '#!/usr/bin/env bash\necho orphan\n' > "$R/scripts/orphan.sh"
out=$(_run --need 2>"$TMP/err"); rc=$?
[ "$rc" = 1 ] && [ -z "$out" ] && grep -q '^related-suite: 관련 스위트를 고를 수 없음' "$TMP/err" && [ "$(wc -l < "$TMP/err" | tr -d ' ')" = 1 ] \
  && ok "F7d 고를 수 없으면 rc 1 · 표준 출력 없음 · 표준 오류에 사유 1줄" || nope "F7d" "rc=$rc out=[$out] err=[$(cat "$TMP/err")]"
rm -f "$R/scripts/orphan.sh"

# ── 커밋된 변경(기본 브랜치보다 앞선 커밋) — 공통 조상부터 센다 (FR-2) ──
printf 'echo v2\n' >> "$R/scripts/old.sh"
( cd "$R" && git add scripts/old.sh && git -c user.name=t -c user.email=t@e.com -c commit.gpgsign=false commit -qm ahead ) >/dev/null 2>&1   # origin/main 은 한 커밋 뒤
# shellcheck disable=SC2086
_mark $NEED3; _stale F2n "★ 앞선 커밋의 변경(old.sh)을 언급하는 스위트가 빠졌다 → STALE" "scripts/tests/test-old.sh"
# shellcheck disable=SC2086
_mark $NEED3 scripts/tests/test-old.sh; out=$(_run); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'suites=4)$' && ok "F2n0 대조 — 앞선 커밋의 스위트까지 덮으면 FRESH(4개)" || nope "F2n0" "rc=$rc out=[$out]"

finish
