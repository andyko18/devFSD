#!/usr/bin/env bash
# check-review-fresh.sh — end-loaded 리뷰 skip 신선도 (20261008-review-reentry)
# 배경: 리뷰 뒤 security/integration/performance FAIL 수정이 B/C 리포트 "존재"만 보는 Step 0 에 가려 무리뷰로 통과했다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-review-fresh.sh"
FID=20261008-rf

_repo() {  # $1=dir — git repo + 코드 커밋 1개 + 리뷰 리포트(커밋보다 뒤)
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX
  git -C "$1" init -q && git -C "$1" config user.email t@t && git -C "$1" config user.name t
  mkdir -p "$1/.specops/$FID/reviews"
  printf 'x\n' > "$1/code.txt"
  git -C "$1" add code.txt && GIT_COMMITTER_DATE="@1000000000" git -C "$1" commit -q --date="@1000000000" -m c1
  : > "$1/.specops/$FID/reviews/T1-B-report.md"; : > "$1/.specops/$FID/reviews/T1-C-report.md"
  touch -t 203001010000 "$1/.specops/$FID/reviews/T1-B-report.md" "$1/.specops/$FID/reviews/T1-C-report.md"
}
_run() { ( cd "$1" && bash "$CHK" "$FID" 2>&1 ); }

# F1: 리포트가 마지막 코드 커밋보다 뒤 → FRESH rc0
TD=$(mktemp -d); _repo "$TD"
out=$(_run "$TD"); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'FRESH' && ok "F1 리포트 이후 변경 없음 → FRESH" || nope "F1" "rc=$rc out=$out"
rm -rf "$TD"

# F2: 리뷰 뒤 코드 커밋(미래 시각) → STALE rc1
TD=$(mktemp -d); _repo "$TD"
printf 'y\n' >> "$TD/code.txt"; git -C "$TD" add code.txt
GIT_COMMITTER_DATE="@2000000000" git -C "$TD" commit -q --date="@2000000000" -m fix
touch -t 200001010000 "$TD/.specops/$FID/reviews/T1-B-report.md" "$TD/.specops/$FID/reviews/T1-C-report.md"
out=$(_run "$TD"); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'STALE' && ok "F2 리뷰 이후 코드 커밋 → STALE(SKIP 불가)" || nope "F2" "rc=$rc out=$out"
rm -rf "$TD"

# F3: 미커밋 추적 변경 → STALE
TD=$(mktemp -d); _repo "$TD"
printf 'z\n' >> "$TD/code.txt"
out=$(_run "$TD"); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '미커밋' && ok "F3 미커밋 코드 변경 → STALE" || nope "F3" "rc=$rc out=$out"
rm -rf "$TD"

# F4: .specops 변경만 있으면 FRESH 유지 (산출물 갱신이 리뷰를 무효화하지 않는다)
TD=$(mktemp -d); _repo "$TD"
printf 'note\n' > "$TD/.specops/$FID/evidence.md"
out=$(_run "$TD"); rc=$?
[ "$rc" -eq 0 ] && ok "F4 .specops 산출물 변경은 신선도에 영향 없음" || nope "F4" "rc=$rc out=$out"
rm -rf "$TD"

# F5: 리포트 없음 → STALE rc1 / reviews 부재 → STALE rc1
TD=$(mktemp -d); _repo "$TD"; rm -f "$TD/.specops/$FID/reviews/"*
out=$(_run "$TD"); rc=$?
[ "$rc" -eq 1 ] && ok "F5 리포트 없음 → STALE" || nope "F5" "rc=$rc out=$out"
rm -rf "$TD"

# F6: git 작업트리 아님 → rc2 (호출자는 SKIP 하지 않는다)
TD=$(mktemp -d); mkdir -p "$TD/.specops/$FID/reviews"; : > "$TD/.specops/$FID/reviews/T1-B-report.md"
out=$( cd "$TD" && GIT_CEILING_DIRECTORIES="$(dirname "$TD")" bash "$CHK" "$FID" 2>&1 ); rc=$?
[ "$rc" -eq 2 ] && ok "F6 git 아님 → UNKNOWN rc2" || nope "F6" "rc=$rc out=$out"
rm -rf "$TD"

finish
