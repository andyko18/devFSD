#!/usr/bin/env bash
# run-related.sh — 변경 파일이 닿는 스위트 고르기·실행 (20261112 speed)
#   계약: 고를 수 없으면(언급하는 스위트 없음·상한 초과·경로 이상) rc 3 으로 **전체 스위트 쪽**에 넘기고,
#   실행은 스위트 목록에 든 경로만 받으며, 전체 스위트의 통과 기록(마커)을 만들지 않는다. `VERIFY: PASS` 는 변경이 닿는 스위트를 전부 덮었을 때만 낸다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
RR="$PLUGIN/scripts/tests/run-related.sh"
TMP=$(mktemp -d) || exit 1; trap 'rm -rf "$TMP"' EXIT

# 픽스처 저장소 — run-related.sh 사본을 둔다(스크립트는 자기 위치 기준으로 저장소를 잡는다)
R="$TMP/repo"
mkdir -p "$R/scripts/tests/dag" "$R/scripts/_internal" "$R/hooks" "$R/skills/a" "$R/skills/b" "$R/docs" "$R/.specops"
cp "$RR" "$R/scripts/tests/run-related.sh"
printf '#!/usr/bin/env bash\necho structure-ok\n' > "$R/scripts/_internal/validate-structure.sh"
printf '#!/usr/bin/env bash\necho lib\n' > "$R/hooks/lib.sh"
printf '#!/usr/bin/env bash\n. hooks/lib.sh\n' > "$R/hooks/entry.sh"
printf '#!/usr/bin/env bash\necho count\n' > "$R/scripts/count.sh"
printf '#!/usr/bin/env bash\necho orphan\n' > "$R/scripts/orphan.sh"
printf 'a\n' > "$R/skills/a/SKILL.md"; printf 'b\n' > "$R/skills/b/SKILL.md"
printf 'doc\n' > "$R/README.md"; printf 'doc\n' > "$R/docs/guide.md"; printf 'doc\n' > "$R/hooks/CLAUDE.md"; printf 'doc\n' > "$R/CLAUDE.md"
printf '#!/usr/bin/env bash\n# scripts/count.sh 를 본다\necho "PASS=1 FAIL=0 RUN_ALL=${SPECOPS_RUN_ALL:-unset}"\n' > "$R/scripts/tests/test-count.sh"
printf '#!/usr/bin/env bash\n# hooks/entry.sh 를 실행해 본다\necho "PASS=1 FAIL=0"\n' > "$R/scripts/tests/test-entry.sh"
printf '#!/usr/bin/env bash\n# skills/a/SKILL.md 문구 잠금\necho "PASS=1 FAIL=0"\n' > "$R/scripts/tests/test-skill-a.sh"
printf '#!/usr/bin/env bash\necho "FAIL X1 깨졌다"\necho "PASS=0 FAIL=1"\nexit 1\n' > "$R/scripts/tests/dag/test-broken.sh"
printf '#!/usr/bin/env bash\necho doc-numbers\n' > "$R/scripts/tests/test-doc-numbers.sh"
printf '#!/usr/bin/env bash\ntouch "%s/evil-ran"\n' "$TMP" > "$R/scripts/evil.sh"
printf '#!/usr/bin/env bash\nfor f in "$ROOT"/skills/*/SKILL.md; do :; done\necho "PASS=1 FAIL=0"\n' > "$R/scripts/tests/test-skill-glob.sh"
printf '#!/usr/bin/env bash\nn=$(find "$ROOT/skills" -name SKILL.md | wc -l)\necho "PASS=1 FAIL=0"\n' > "$R/scripts/tests/test-skill-find.sh"
printf '#!/usr/bin/env bash\nfor s in a b; do f="skills/${s}/SKILL.md"; done\necho "PASS=1 FAIL=0"\n' > "$R/scripts/tests/test-skill-var.sh"
( cd "$R" && git init -q -b main && printf '.specops/\n' > .gitignore && git add -A && git -c user.name=t -c user.email=t@e.com commit -qm init ) \
  || { echo "FATAL: 픽스처 생성 실패" >&2; exit 1; }
_rr() { ( cd "$R" && bash scripts/tests/run-related.sh "$@" 2>&1 ); }
_list() { ( cd "$R" && bash scripts/tests/run-related.sh --list "$@" 2>/dev/null ) | paste -sd' ' -; }
AL="scripts/_internal/validate-structure.sh scripts/tests/test-doc-numbers.sh"   # 픽스처에 있는 상시 스위트(가나다순 앞·뒤에 끼어든다)

# ── L 고르기 ──
out=$(_list scripts/tests/test-count.sh)
[ "$out" = "scripts/_internal/validate-structure.sh scripts/tests/test-count.sh scripts/tests/test-doc-numbers.sh" ] \
  && ok "L1 변경 파일이 스위트 자신 → 그 스위트 + 상시 스위트" || nope "L1" "$out"
out=$(_list scripts/count.sh)
[ "$out" = "scripts/_internal/validate-structure.sh scripts/tests/test-count.sh scripts/tests/test-doc-numbers.sh" ] \
  && ok "L2 ★ 코드 파일 → 그 이름을 언급하는 스위트" || nope "L2" "$out"
out=$(_list hooks/lib.sh)
printf '%s' "$out" | grep -q 'scripts/tests/test-entry.sh' && ! printf '%s' "$out" | grep -q 'test-count.sh' \
  && ok "L3 ★ 라이브러리 → 그것을 source 하는 진입 스크립트의 스위트(한 단계)" || nope "L3" "$out"
out=$(_list skills/a/SKILL.md)
printf '%s' "$out" | grep -q 'scripts/tests/test-skill-a.sh' && ok "L4 흔한 파일 이름은 상위폴더/이름으로 찾는다(a/SKILL.md)" || nope "L4" "$out"
out=$(_list skills/b/SKILL.md)
! printf '%s' "$out" | grep -q 'test-skill-a.sh' && ok "L5 ★ 같은 이름의 다른 파일(b/SKILL.md)은 a 의 스위트로 묻어가지 않는다" || nope "L5" "$out"
for t in test-skill-glob.sh test-skill-find.sh test-skill-var.sh; do printf '%s' "$out" | grep -q "scripts/tests/$t" || { nope "L5b" "$t 가 빠졌다: $out"; t=""; break; }; done
[ -n "$t" ] && ok "L5b ★ 폴더를 순회하는 스위트(glob · find · 변수 조합)는 파일 이름을 적지 않아도 고른다"
printf 'x\n' > "$R/lonely.cfg"; mkdir -p "$R/misc"; printf 'x\n' > "$R/misc/lonely.py"
out=$(_rr --list misc/lonely.py); rc=$?; rm -rf "$R/misc" "$R/lonely.cfg"
[ "$rc" = 3 ] && ok "L5c 언급도 순회도 없는 폴더의 파일 → rc 3" || nope "L5c" "rc=$rc $out"
out=$(_rr --list scripts/orphan.sh scripts/count.sh); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q '특정할 수 없다: scripts/orphan.sh' \
  && ok "L6 ★ 언급하는 스위트가 없는 코드 파일이 하나라도 있으면 rc 3 (전체 스위트 쪽)" || nope "L6" "rc=$rc $out"
out=$(_list README.md docs/guide.md hooks/CLAUDE.md CLAUDE.md .specops/x/spec.md)
[ "$out" = "$AL" ] && ok "L7 문서·.specops 만 바뀌면 상시 스위트만" || nope "L7" "$out"
out=$( cd "$R" && printf 'scripts/count.sh\n\nscripts/count.sh\n' | bash scripts/tests/run-related.sh --list 2>/dev/null | paste -sd' ' - )
printf '%s' "$out" | grep -q 'test-count.sh' && ok "L8 인자가 없으면 stdin 에서 읽는다(빈 줄·중복 무시)" || nope "L8" "$out"
_rr --list ../outside.sh >/dev/null; rc1=$?; _rr --list /etc/passwd >/dev/null; rc2=$?
[ "$rc1" = 3 ] && [ "$rc2" = 3 ] && ok "L9 저장소 밖 경로(.. · 절대경로) → rc 3" || nope "L9" "rc=$rc1/$rc2"
( cd "$R" && : | bash scripts/tests/run-related.sh --list >/dev/null 2>&1 ); [ $? = 3 ] && ok "L10 변경 파일 0개 → rc 3" || nope "L10"
# 상한 — count.sh 를 언급하는 스위트를 상한보다 많이 만든다
MAX=$(sed -n 's/^RELATED_MAX=\([0-9][0-9]*\).*/\1/p' "$RR")
i=0; while [ "$i" -le "${MAX:-30}" ]; do printf '#!/usr/bin/env bash\n# scripts/count.sh\necho "PASS=1 FAIL=0"\n' > "$R/scripts/tests/test-many-$i.sh"; i=$((i + 1)); done
out=$(_rr --list scripts/count.sh); rc=$?
[ -n "$MAX" ] && [ "$rc" = 3 ] && printf '%s' "$out" | grep -q "상한 ${MAX}" && ok "L11 ★ 관련 스위트가 상한(${MAX})을 넘으면 rc 3 (전체 스위트 쪽)" || nope "L11" "rc=$rc $out"
rm -f "$R"/scripts/tests/test-many-*.sh

# ── X 실행 ──
out=$(_rr scripts/tests/test-count.sh scripts/_internal/validate-structure.sh); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'run-related: suites PASS=2 FAIL=0 (total=2)' && ok "X1 고른 스위트만 실행 → rc 0 · 요약 줄" || nope "X1" "rc=$rc $out"
{ ! printf '%s\n' "$out" | grep -q '^VERIFY:' && printf '%s\n' "$out" | grep -q '^run-related: 실행 증거로 치지 않는다 — '; } \
  && ok "X2 ★ 덮었다고 판정되지 않으면 VERIFY 줄을 내지 않고 사유 1줄을 낸다" || nope "X2" "$out"
[ ! -e "$R/.specops/.full-suite-pass" ] && ok "X3 ★ 전체 스위트 통과 마커를 쓰지 않는다(pre-push 는 이 실행을 통과로 치지 않는다)" || nope "X3"
printf '%s' "$out" | grep -q '전체 스위트 아님' && ok "X4 요약 줄이 전체 스위트가 아님을 적는다" || nope "X4" "$out"
out=$(_rr scripts/tests/test-count.sh scripts/tests/dag/test-broken.sh); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -qx 'FAILED: scripts/tests/dag/test-broken.sh' && printf '%s' "$out" | grep -q '^FAIL X1 깨졌다' \
  && ok "X5 ★ 실패 스위트가 있으면 rc 1 · 실패 줄과 FAILED: <경로>" || nope "X5" "rc=$rc $out"
out=$(_rr scripts/tests/test-count.sh scripts/evil.sh); rc=$?
[ "$rc" = 2 ] && [ ! -e "$TMP/evil-ran" ] && printf '%s' "$out" | grep -q '스위트 목록에 없는 경로' \
  && ok "X6 ★ 스위트 목록에 없는 경로는 실행하지 않는다 → rc 2" || nope "X6" "rc=$rc $out"
out=$( cd "$R" && env -u SPECOPS_RUN_ALL bash scripts/tests/run-related.sh scripts/tests/test-count.sh 2>&1 )
printf '%s' "$out" | grep -q 'RUN_ALL=1' \
  && ok "X7 스위트에 재귀 가드(SPECOPS_RUN_ALL=1)를 물려준다 — 스위트 안의 release·pre-push 가 전체 스위트를 다시 부르지 않게" || nope "X7" "$out"
_rr >/dev/null; [ $? = 2 ] && ok "X8 인자 없음 → rc 2" || nope "X8"
# 병렬 풀 (20261112 — 관련 48개 직렬 591초 > 전체 병렬 416초 실측) — 서로의 시작 표지를 기다리는 두 스위트는 동시에 돌 때만 통과한다
for n in a b; do o=b; [ "$n" = b ] && o=a
  printf '#!/usr/bin/env bash\ntouch "%s/pair-%s"\ni=0; while [ ! -e "%s/pair-%s" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done\n[ -e "%s/pair-%s" ] || { echo "FAIL 짝이 시작하지 않았다"; exit 1; }\necho "PASS=1 FAIL=0"\n' \
    "$TMP" "$n" "$TMP" "$o" "$TMP" "$o" > "$R/scripts/tests/test-pair-$n.sh"
done
out=$( cd "$R" && SPECOPS_RUN_ALL_JOBS=2 bash scripts/tests/run-related.sh scripts/tests/test-pair-b.sh scripts/tests/test-pair-a.sh 2>&1 ); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'suites PASS=2 FAIL=0' && ok "X9 ★ 스위트를 동시에 돌린다(SPECOPS_RUN_ALL_JOBS — run-all 과 같은 변수)" || nope "X9" "rc=$rc $out"
[ "$(printf '%s\n' "$out" | grep '^--- ' | paste -sd' ' -)" = "--- scripts/tests/test-pair-a.sh --- scripts/tests/test-pair-b.sh" ] \
  && ok "X10 출력은 끝난 순서가 아니라 경로 순서다" || nope "X10" "$out"
rm -f "$TMP"/pair-*
out=$( cd "$R" && SPECOPS_RUN_ALL_JOBS=1 bash scripts/tests/run-related.sh scripts/tests/test-pair-a.sh scripts/tests/test-pair-b.sh 2>&1 ); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -qx 'FAILED: scripts/tests/test-pair-a.sh' && ok "X11 SPECOPS_RUN_ALL_JOBS=1 은 하나씩 돈다(되돌림 스위치)" || nope "X11" "rc=$rc $out"
# 직렬 표시 스위트는 풀이 끝난 뒤에 돈다 — 풀의 스위트가 남긴 끝 표지를 본다
rm -f "$TMP"/pair-* "$R"/scripts/tests/test-pair-*.sh
printf '#!/usr/bin/env bash\nsleep 1\ntouch "%s/pool-done"\necho "PASS=1 FAIL=0"\n' "$TMP" > "$R/scripts/tests/test-zz-pool.sh"
printf '#!/usr/bin/env bash\n# run-all: serial — 시간 임계\n[ -e "%s/pool-done" ] || { echo "FAIL 풀이 끝나기 전에 돌았다"; exit 1; }\necho "PASS=1 FAIL=0"\n' "$TMP" > "$R/scripts/tests/test-aa-serial.sh"
out=$( cd "$R" && SPECOPS_RUN_ALL_JOBS=2 bash scripts/tests/run-related.sh scripts/tests/test-aa-serial.sh scripts/tests/test-zz-pool.sh 2>&1 ); rc=$?
[ "$rc" = 0 ] && ok "X12 ★ 직렬 표시(# run-all: serial) 스위트는 풀이 끝난 뒤 돈다" || nope "X12" "rc=$rc $out"
rm -f "$R"/scripts/tests/test-zz-pool.sh "$R"/scripts/tests/test-aa-serial.sh
# 스위트별 소요 기록 (20261112-related-suite-narrowing) — 전체 스위트의 기록(suite-times.tsv)과 다른 파일에 쓴다
printf 'sentinel\n' > "$R/.specops/suite-times.tsv"
printf '#!/usr/bin/env bash\nsleep 4\necho "PASS=1 FAIL=0"\n' > "$R/scripts/tests/test-slow.sh"
out=$( cd "$R" && SPECOPS_RUN_ALL_JOBS=2 bash scripts/tests/run-related.sh scripts/tests/test-count.sh scripts/tests/test-slow.sh scripts/tests/dag/test-broken.sh 2>&1 ); rc=$?
TF="$R/.specops/suite-times-related.tsv"; TAB=$(printf '\t'); rows=$(sed 1d "$TF" 2>/dev/null)
[ "$rc" = 1 ] && sed -n 1p "$TF" 2>/dev/null | grep -Eq '^# run-related [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} jobs=2 suites=3$' \
  && [ "$(printf '%s\n' "$rows" | grep -Ec "^[0-9]+${TAB}[0-9]+${TAB}scripts/[^${TAB}]+\$")" = 3 ] && [ "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" = 3 ] \
  && [ "$(printf '%s\n' "$rows" | sed -n 1p | cut -f3)" = "scripts/tests/test-slow.sh" ] && [ "$(printf '%s\n' "$rows" | sed -n 1p | cut -f1)" -ge 2 ] \
  && [ "$(printf '%s\n' "$rows" | awk -F'\t' '$2 != 0 { print $3 }')" = "scripts/tests/dag/test-broken.sh" ] \
  && ok "X13 ★ 실행한 스위트의 소요를 suite-times-related.tsv 에 남긴다(초 내림차순 · 실패 스위트 포함)" || nope "X13" "rc=$rc file=[$(cat "$TF" 2>&1)]"
[ "$(cat "$R/.specops/suite-times.tsv")" = "sentinel" ] && ok "X14 ★ 전체 스위트의 기록(suite-times.tsv)은 건드리지 않는다" || nope "X14" "$(cat "$R/.specops/suite-times.tsv")"
mv "$R/.specops" "$TMP/specops-bak"
out=$(_rr scripts/tests/test-count.sh scripts/_internal/validate-structure.sh); rc=$?
[ "$rc" = 0 ] && [ ! -e "$R/.specops" ] && printf '%s' "$out" | grep -q 'run-related: suites PASS=2 FAIL=0 (total=2)' \
  && ok "X15 ★ .specops/ 가 없으면 폴더·기록을 만들지 않는다(판정·출력은 그대로)" || nope "X15" "rc=$rc $out"
mv "$TMP/specops-bak" "$R/.specops"; rm -f "$R/scripts/tests/test-slow.sh" "$R/.specops"/suite-times*.tsv
# 통과 기록 (20261113) — 전부 통과하면 실행 전 비문서 지문 + 돌린 스위트를 남긴다(소비자: prepush-related.sh). 실패·지문 불가면 없다.
cp "$PLUGIN/scripts/_internal/verification-state.sh" "$PLUGIN/scripts/_internal/file-class.sh" "$R/scripts/_internal/"
printf '.specops/\n' > "$R/.gitignore"
( cd "$R" && git init -q && git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m f ) >/dev/null 2>&1
MK="$R/.specops/.related-suite-pass"; rm -f "$MK"
fp=$( cd "$R" && bash -c '. scripts/_internal/verification-state.sh; vs::nondoc_fingerprint' 2>/dev/null )
out=$(_rr scripts/tests/test-count.sh scripts/_internal/validate-structure.sh); rc=$?
{ [ "$rc" = 0 ] && [ -n "$fp" ] && [ "$fp" != NO_GIT ] && [ "$(sed -n 1p "$MK" 2>/dev/null)" = "$fp" ] \
  && [ "$(sed 1d "$MK" 2>/dev/null | paste -sd' ' -)" = "scripts/_internal/validate-structure.sh scripts/tests/test-count.sh" ] \
  && [ ! -e "$R/.specops/.full-suite-pass" ] && ! printf '%s' "$out" | grep -q '^VERIFY:'; } \
  && ok "X16 ★ 전부 통과 → 통과 기록(지문 + 돌린 스위트) · 전체 스위트 기록·VERIFY 토큰은 여전히 없다" || nope "X16" "rc=$rc fp=$fp mk=[$(cat "$MK" 2>&1)]"
out=$(_rr scripts/tests/test-count.sh scripts/tests/dag/test-broken.sh); rc=$?
{ [ "$rc" = 1 ] && [ ! -e "$MK" ]; } && ok "X17 ★ 실패하면 낡은 통과 기록을 지운다" || nope "X17" "rc=$rc mk=[$(cat "$MK" 2>&1)]"
# 실행 증거 (20261113-commit-gate-related-evidence) — 변경이 닿는 스위트를 전부 덮은 통과에만 VERIFY: PASS 를 낸다
cp "$PLUGIN/scripts/_internal/related-suite-fresh.sh" "$R/scripts/_internal/"
( cd "$R" && git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m g; git update-ref refs/remotes/origin/main HEAD ) >/dev/null 2>&1
printf 'echo v2\n' >> "$R/scripts/count.sh"
N3="scripts/_internal/validate-structure.sh scripts/tests/test-count.sh scripts/tests/test-doc-numbers.sh"
# shellcheck disable=SC2086
out=$( cd "$R" && env -u SPECOPS_FORCE_FULL bash scripts/tests/run-related.sh $N3 2>&1 ); rc=$?   # 강제 전체 변수가 물려 와도 이 양성 단언이 깨지지 않게
{ [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] && [ "$(printf '%s\n' "$out" | grep -c '^VERIFY:')" = 1 ]; } \
  && ok "X19 ★ 변경이 닿는 스위트 전부 통과 → 마지막 줄 VERIFY: PASS (1줄뿐)" || nope "X19" "rc=$rc $out"
out=$( cd "$R" && env -u SPECOPS_FORCE_FULL bash scripts/tests/run-related.sh scripts/_internal/validate-structure.sh scripts/tests/test-doc-numbers.sh 2>&1 ); rc=$?   # 사유 문자열을 단언한다 — 강제 전체 변수가 물려 오면 사유가 달라진다
{ [ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q '^VERIFY:' \
  && printf '%s\n' "$out" | grep -q '^run-related: 실행 증거로 치지 않는다 — 스위트 누락 1개 — scripts/tests/test-count.sh$'; } \
  && ok "X20 ★ 닿는 스위트 하나를 빼고 통과 → rc 0 · VERIFY 줄 없음 · 빠진 스위트를 알린다" || nope "X20" "rc=$rc $out"
# shellcheck disable=SC2086
out=$(_rr $N3 scripts/tests/dag/test-broken.sh); rc=$?
{ [ "$rc" = 1 ] && ! printf '%s\n' "$out" | grep -q '^VERIFY:' && ! printf '%s\n' "$out" | grep -q '실행 증거로 치지 않는다'; } \
  && ok "X21 대상 스위트가 실패 → rc 1 · VERIFY 줄도 사유 줄도 없다(종전 출력)" || nope "X21" "rc=$rc $out"
mv "$R/.specops" "$TMP/specops-bak2"
# shellcheck disable=SC2086
out=$(_rr $N3); rc=$?
{ [ "$rc" = 0 ] && [ ! -e "$R/.specops" ] && ! printf '%s\n' "$out" | grep -q '^VERIFY:' \
  && printf '%s\n' "$out" | grep -qF 'run-related: 실행 증거로 치지 않는다 — 기록 폴더(.specops/)가 없다'; } \
  && ok "X22 ★ .specops/ 가 없으면 VERIFY 줄 없이 그 사유를 알리고 폴더를 만들지 않는다" || nope "X22" "rc=$rc $out"
mv "$TMP/specops-bak2" "$R/.specops"
( cd "$R" && git checkout -q -- scripts/count.sh )
rm -rf "$R/.git"
out=$(_rr scripts/tests/test-count.sh); rc=$?
{ [ "$rc" = 0 ] && [ ! -e "$MK" ]; } && ok "X18 지문을 낼 수 없으면(git 저장소 아님) 기록하지 않는다" || nope "X18" "rc=$rc mk=[$(cat "$MK" 2>&1)]"
rm -f "$R/.gitignore" "$R/scripts/_internal/verification-state.sh" "$R/scripts/_internal/file-class.sh" "$R/scripts/_internal/related-suite-fresh.sh" "$MK" "$R/.specops"/suite-times-related.tsv

# ── K 계약 잠금 ──
# 스위트 목록이 run-all.sh 와 같아야 한다 — 한쪽에만 폴더가 늘면 그 폴더의 스위트는 관련으로 잡히지 않는다
_dirs() { grep -oE '"\$PLUGIN"/scripts/tests/[A-Za-z0-9_/-]*test-\*\.sh' "$1" | sort -u; }
a=$(_dirs "$PLUGIN/scripts/tests/run-all.sh"); b=$(_dirs "$RR")
[ -n "$a" ] && [ "$a" = "$b" ] && ok "K1 ★ 스위트 폴더 목록 == run-all.sh 의 목록" || nope "K1" "run-all=[$a] related=[$b]"
! grep -qE '^[^#]*\.full-suite-pass' "$RR" && ok "K2 마커 경로를 코드에서 다루지 않는다" || nope "K2"
grep -q '^_RUNNER_ANCHOR_PAT=.*tests/run-related\\\.sh' "$PLUGIN/hooks/governance-lib.sh" && ! grep -q 'run-related' "$PLUGIN/hooks/rules.jsonl" \
  && ok "K3 ★ 훅은 이 러너를 러너 앵커로만 안다(규칙 파일은 그대로) — VERIFY: PASS 는 덮은 통과에만 나온다(X19·X20)" || nope "K3"
! grep -q 'run-related' "$PLUGIN/.githooks/pre-push" && ok "K4 pre-push 는 그대로 전체 스위트를 본다" || nope "K4"
# 검증 러너의 허용 형식에 맞는다 — basic-path.sh related 가 내는 명령이 SKIP 되지 않는다
WL=$(sed -n "s/^_WHITELIST_PAT='\(.*\)'\$/\1/p" "$PLUGIN/scripts/_internal/run-verification.sh")
cmd="bash scripts/tests/run-related.sh scripts/_internal/validate-structure.sh scripts/tests/dag/test-parse-dag.sh"
[ -n "$WL" ] && [[ "$cmd" =~ $WL ]] && [[ "$cmd" != *..* ]] && ok "K5 관련 스위트 명령이 검증 러너의 허용 형식을 통과한다" || nope "K5"
# 실저장소에서: 상시 스위트가 실제로 있고, 넓게 닿는 파일은 전체 쪽으로 넘어간다
out=$(bash "$RR" --list scripts/release.sh 2>/dev/null)
for s in scripts/_internal/validate-structure.sh scripts/tests/test-doc-numbers.sh scripts/tests/test-propagation.sh scripts/tests/test-release.sh; do
  printf '%s\n' "$out" | grep -Fxq "$s" || { nope "K6" "release.sh 의 관련 스위트에 $s 가 없다"; s=""; break; }
done
[ -n "$s" ] && ok "K6 실저장소: release.sh → test-release.sh + 상시 스위트 3종"
bash "$RR" --list scripts/tests/harness.sh >/dev/null 2>&1; [ $? = 3 ] && ok "K7 실저장소: 모든 스위트가 쓰는 파일(harness.sh)은 전체 스위트 쪽(rc 3)" || nope "K7"

finish
