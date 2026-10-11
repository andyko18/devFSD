#!/usr/bin/env bash
# shortcut: 부채 장부 스캐너(scan-shortcuts.sh) + 과잉 설계 리뷰 관점 잠금 (20261007-ponytail-review-debt)
# run-all: sandbox 트리(mktemp)만 쓴다 — 실 트리 쓰기 0
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
# 훅 환경 격리 — sandbox git 호출이 GIT_DIR 상속으로 실 저장소를 건드리지 않게 한다(링크 worktree pre-push 사고 계열)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCAN="$PLUGIN/scripts/_internal/scan-shortcuts.sh"
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT

mkrepo() { local d="$SB/$1"; mkdir -p "$d"; git -C "$d" init -q; git -C "$d" config user.email t@t; git -C "$d" config user.name t; echo "$d"; }

# T1 마커 3종(트리거 있음 2·없음 1) → 행·태그·요약
d=$(mkrepo r1)
printf 'x = 1\n# shortcut: 전역 락 → 처리량이 문제되면 계정별 락\nfoo()\n' > "$d/a.py"
printf '// shortcut: O(n²) 스캔 -> n>1e4 이면 인덱스\nint y;\n/* shortcut: 단순 휴리스틱 */\n' > "$d/b.js"
git -C "$d" add -A
out=$(bash "$SCAN" "$d"); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^a.py:2  전역 락 → 처리량' && printf '%s' "$out" | grep -q '^b.js:1  O(n²) 스캔 -> n>1e4' \
  && printf '%s' "$out" | grep -q '^b.js:3  단순 휴리스틱  \[no-trigger\]$' && printf '%s' "$out" | grep -qx '3 markers, 1 with no trigger.' \
  && ok "T1 마커 3종 → 행·no-trigger 태그·요약" || nope "T1" "rc=$rc out=$out"

# T2 마커 없음 → Clean ledger · 산문(주석 접두 없음)·*.md·.specops 속 언급은 무시
d=$(mkrepo r2)
printf '이 함수는 shortcut: 규약을 설명한다\n' > "$d/notes.txt"
printf '# shortcut: 문서 예시 → 무시되어야 한다\n' > "$d/README.md"
mkdir -p "$d/.specops/x"; printf '# shortcut: 산출물 → 무시\n' > "$d/.specops/x/a.sh"
git -C "$d" add -A -f
out=$(bash "$SCAN" "$d")
[ "$out" = "No shortcut: debt. Clean ledger." ] && ok "T2 산문·md·.specops 무시 → Clean ledger" || nope "T2" "out=$out"

# T3 git 추적 밖(미추적) 파일은 장부에 없다 · git 이 아닌 디렉터리는 find 로 스캔한다
d=$(mkrepo r3); printf '# shortcut: 미추적 → 무시\n' > "$d/u.py"
out=$(bash "$SCAN" "$d"); n=$(mkdir -p "$SB/plain" && printf '# shortcut: 평문 디렉터리 → 포함\n' > "$SB/plain/p.py" && bash "$SCAN" "$SB/plain")
[ "$out" = "No shortcut: debt. Clean ledger." ] && printf '%s' "$n" | grep -q '^p.py:1  ' && ok "T3 미추적 제외 · 비-git 은 find" || nope "T3" "out=$out n=$n"

# T4 존재하지 않는 경로 → 보고 도구라 rc 0 + stderr 안내
bash "$SCAN" "$SB/없음" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "T4 없는 경로도 rc 0" || nope "T4" "rc=$rc"

# T5 code-reviewer-ko 가 과잉 설계 관점(6 태그)·shortcut 규약·범위 한정을 담는다
AG="$PLUGIN/agents/code-reviewer-ko.md"
sec=$(awk 'index($0,"## 과잉 설계 탐지")==1{on=1;print;next} /^## /{on=0} on' "$AG")
miss=""
for t in 'delete:' 'stdlib:' 'native:' 'reuse:' 'yagni:' 'shrink:' 'shortcut:' 'no-trigger' 'net: -'; do printf '%s' "$sec" | grep -qF -- "$t" || miss="$miss $t"; done
[ -n "$sec" ] && [ -z "$miss" ] && ok "T5 과잉 설계 탐지 절: 6 태그·shortcut·no-trigger·net 줄" || nope "T5" "sec=$([ -n "$sec" ] && echo 있음 || echo 없음) 누락=$miss"
printf '%s' "$sec" | grep -q 'Critical 로 올리지 않는다' && printf '%s' "$sec" | grep -q '검증·에러 처리·보안·접근성' \
  && ok "T5.b 과잉 설계는 Critical 불가·안전 요소는 절감 대상 아님" || nope "T5.b" "범위 한정 문구 부재"
grep -q '^## 과잉 설계$' "$AG" && ok "T5.c 출력 포맷에 ## 과잉 설계 표" || nope "T5.c" "출력 포맷 표 부재"

# T6 implementer-ko 가 shortcut: 규약을 안내한다
grep -q 'shortcut: <상한> → <업그레이드 조건>' "$PLUGIN/agents/implementer-ko.md" && ok "T6 implementer-ko shortcut: 규약" || nope "T6" "규약 부재"

# T7 /improve-arch --lean — 과잉 설계 감사(읽기 전용·6 태그·net 줄·delete 전 grep·안전 요소 제외·장부 연결)
IA="$PLUGIN/commands/improve-arch.md"
lsec=$(awk '/^## `--lean`/{on=1;print;next} /^## /{on=0} on' "$IA")
miss=""
for t in 'delete:' 'stdlib:' 'native:' 'reuse:' 'yagni:' 'shrink:' 'net: -' 'Lean already' 'scan-shortcuts.sh' '아무것도 적용하지 않는다' '절감 대상이 아니다' '트리 전체'; do printf '%s' "$lsec" | grep -qF -- "$t" || miss="$miss $t"; done
[ -n "$lsec" ] && [ -z "$miss" ] && ok "T7 --lean 감사 절 계약" || nope "T7" "sec=$([ -n "$lsec" ] && echo 있음 || echo 없음) 누락=$miss"
grep -q '^# /improve-arch \[--lean\]' "$IA" && ok "T7.b 사용법 표제에 --lean" || nope "T7.b" "표제 미갱신"

finish
