#!/usr/bin/env bash
# record-task-done.sh — 태스크 기록 3종(receipt · dispatch-log 구현 행 · session-progress 줄)을 1회로 (20261024-speed-release-fresh-task-record)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
DONE="$PLUGIN/scripts/_internal/record-task-done.sh"
_first() { awk -v h="## $2" '$0==h{getline; print; exit}' "$1"; }   # FID 섹션 첫 줄 (session-progress 는 prepend)

_setup() {  # $1=dir $2=fid — test-task-receipt 의 픽스처와 같은 꼴(명세 있는 정식 FID)
  local d="$1" fid="$2"
  mkdir -p "$d/.specops/$fid" "$d/scripts/tests" "$d/src"
  printf '# spec\n' > "$d/.specops/$fid/spec.md"
  printf 'echo ok\n' > "$d/scripts/tests/test-foo.sh"
  printf 'x\n' > "$d/src/foo.sh"
  cat > "$d/.specops/$fid/tasks.md" <<'YAML'
# tasks

## 의존 그래프

```yaml
tasks:
  - id: T1
    test_command: "bash scripts/tests/test-foo.sh"
    depends_on: []
    inputs: []
    outputs: [src/foo.sh, scripts/tests/test-foo.sh]
    ac: [AC-1]
```
YAML
  printf '## %s\n- 2026-10-24 10:00 /tasks 완료 (tasks.md)\n' "$fid" > "$d/.specops/session-progress.md"
  (cd "$d" && git init -q && git add src scripts && git -c user.name=t -c user.email=t@e.com commit -qm init)
  printf 'updated\n' > "$d/src/foo.sh"
}

TD=$(mktemp -d) || exit 1
trap 'rm -rf "$TD"' EXIT
FID=20261024-taskdone
_setup "$TD/a" "$FID"
printf '| # | ts | Phase | agent | 판정 | 비고 |\n|---|---|---|---|---|---|\n' > "$TD/a/.specops/$FID/dispatch-log.md"

# D1: 통과 — 세 기록이 모두 남고 TASK-DONE 1줄
out=$(cd "$TD/a" && bash "$DONE" "$FID" T1 "요약 한 줄"); rc=$?
L="$TD/a/.specops/$FID/dispatch-log.md"
[ "$rc" = 0 ] && ok "D1.a rc 0" || nope "D1.a" "rc=$rc"
[ "$out" = "TASK-DONE: $FID/T1" ] && ok "D1.b stdout = TASK-DONE 1줄" || nope "D1.b" "out=$out"
jq -e '.verdict=="PASS" and .task=="T1"' "$TD/a/.specops/$FID/receipts/T1.json" >/dev/null 2>&1 && ok "D1.c receipt PASS 기록" || nope "D1.c"
grep -qE '^\| A \| [0-9T:-]+Z \| Phase-A \| implementer-ko \| IMPL_DONE \| T1 receipt \|$' "$L" && ok "D1.d dispatch-log IMPL_DONE 행(형식 전체)" || nope "D1.d" "$(tail -1 "$L")"
[ "$(grep -c 'IMPL_DONE' "$L")" = 1 ] && ok "D1.e 구현 행 정확히 1개" || nope "D1.e"
_first "$TD/a/.specops/session-progress.md" "$FID" | grep -qE '^- [0-9-]+ [0-9:]+ /implement 진행 \(T1 완료 — 요약 한 줄\)$' && ok "D1.f session-progress 섹션 첫 줄 = /implement 진행 (T1 완료 — 요약)" || nope "D1.f" "$(_first "$TD/a/.specops/session-progress.md" "$FID")"

# D2: 테스트 실패 — rc ≠ 0 · dispatch-log·session-progress 무변경
_setup "$TD/b" "$FID"
printf 'exit 3\n' > "$TD/b/scripts/tests/test-foo.sh"
printf 'header\n' > "$TD/b/.specops/$FID/dispatch-log.md"
_l0=$(cksum < "$TD/b/.specops/$FID/dispatch-log.md"); _s0=$(cksum < "$TD/b/.specops/session-progress.md")
out=$(cd "$TD/b" && bash "$DONE" "$FID" T1 2>/dev/null); rc=$?
[ "$rc" != 0 ] && ok "D2.a receipt 실패 → rc ≠ 0" || nope "D2.a" "rc=$rc"
{ [ "$(cksum < "$TD/b/.specops/$FID/dispatch-log.md")" = "$_l0" ] && [ "$(cksum < "$TD/b/.specops/session-progress.md")" = "$_s0" ]; } \
  && ok "D2.b 실패 시 dispatch-log·session-progress 바이트 무변경" || nope "D2.b"
[ -z "$out" ] && ok "D2.c 실패 시 TASK-DONE 없음" || nope "D2.c" "out=$out"
[ ! -f "$TD/b/.specops/$FID/receipts/T1.json" ] && ok "D2.d 실패 시 receipt 없음" || nope "D2.d"

# D3: dispatch-log 부재 → 템플릿으로 만든 뒤 행 · 요약 없으면 "T1 완료" 만
_setup "$TD/c" "$FID"
out=$(cd "$TD/c" && bash "$DONE" "$FID" T1); rc=$?
L="$TD/c/.specops/$FID/dispatch-log.md"
{ [ "$rc" = 0 ] && grep -q 'OWNER_COMMAND: /implement' "$L" && grep -q 'IMPL_DONE | T1 receipt' "$L"; } && ok "D3.a 부재 시 템플릿 복사 + 행" || nope "D3.a" "rc=$rc"
_first "$TD/c/.specops/session-progress.md" "$FID" | grep -qE '/implement 진행 \(T1 완료\)$' && ok "D3.b 요약 없음 → (T1 완료)" || nope "D3.b" "$(_first "$TD/c/.specops/session-progress.md" "$FID")"

# D4: 인자 누락 → 사용법 오류(rc ≠ 0) · 기록 없음
_l0=$(cksum < "$TD/c/.specops/$FID/dispatch-log.md"); _s0=$(cksum < "$TD/c/.specops/session-progress.md")
out=$(cd "$TD/c" && bash "$DONE" "$FID" 2>&1); rc=$?
{ [ "$rc" != 0 ] && [ "$(cksum < "$TD/c/.specops/$FID/dispatch-log.md")" = "$_l0" ] && [ "$(cksum < "$TD/c/.specops/session-progress.md")" = "$_s0" ]; } \
  && ok "D4 task-id 누락 → rc ≠ 0 · 기록 바이트 무변경" || nope "D4" "rc=$rc"

# D6: worktree 셸 — receipt 와 같은 메인 worktree .specops 에 쓴다 (test-specops-root 의 _mk 꼴)
M="$TD/m"; W="$M/.worktrees/$FID"
mkdir -p "$M/.specops/$FID" "$M/scripts/tests" "$M/src"
printf '.specops/\n.worktrees/\n' > "$M/.gitignore"
printf 'echo ok\n' > "$M/scripts/tests/test-foo.sh"; printf 'x\n' > "$M/src/foo.sh"
printf '# spec\n' > "$M/.specops/$FID/spec.md"
cp "$TD/a/.specops/$FID/tasks.md" "$M/.specops/$FID/tasks.md"
printf '## %s\n- 2026-10-24 10:00 /tasks 완료 (tasks.md)\n' "$FID" > "$M/.specops/session-progress.md"
(cd "$M" && git init -q && git add .gitignore src scripts && git -c user.name=t -c user.email=t@e.com commit -qm init && git worktree add -q "$W" -b "feat/$FID") >/dev/null 2>&1
printf 'wt\n' > "$W/src/foo.sh"
out=$(cd "$W" && bash "$DONE" "$FID" T1 wt); rc=$?
{ [ "$rc" = 0 ] && [ "$out" = "TASK-DONE: $FID/T1" ]; } && ok "D6.a worktree 셸 → rc 0 · TASK-DONE" || nope "D6.a" "rc=$rc out=$out"
[ "$(grep -c 'IMPL_DONE | T1 receipt |' "$M/.specops/$FID/dispatch-log.md" 2>/dev/null)" = 1 ] && ok "D6.b 메인 dispatch-log 에 IMPL_DONE 1행" || nope "D6.b"
_first "$M/.specops/session-progress.md" "$FID" | grep -qE '/implement 진행 \(T1 완료 — wt\)$' && ok "D6.c 메인 session-progress 첫 줄" || nope "D6.c" "$(_first "$M/.specops/session-progress.md" "$FID")"
{ [ -f "$M/.specops/$FID/receipts/T1.json" ] && [ ! -e "$W/.specops" ]; } && ok "D6.d receipt 는 메인 · worktree 에 .specops 를 만들지 않는다" || nope "D6.d"

# D7: 진행 기록 쓰기 실패 → 경고 1줄 · rc 0 · 앞의 두 기록은 남는다
_setup "$TD/e" "$FID"
SPF="$TD/e/.specops/session-progress.md"
chmod 444 "$SPF"; chmod 555 "$TD/e/.specops"
if [ "$(id -u)" = "0" ] || ( : >> "$SPF" ) 2>/dev/null; then
  chmod 755 "$TD/e/.specops"; chmod 644 "$SPF"
  skip "D7 진행 기록 실패 경로 (root·chmod 무효 환경)"
else
  out=$(cd "$TD/e" && bash "$DONE" "$FID" T1 2>"$TD/e.err"); rc=$?
  chmod 755 "$TD/e/.specops"; chmod 644 "$SPF"
  { [ "$rc" = 0 ] && [ "$out" = "TASK-DONE: $FID/T1" ] && grep -qF '경고 — session-progress 기록 실패' "$TD/e.err" \
      && grep -q 'IMPL_DONE | T1 receipt' "$TD/e/.specops/$FID/dispatch-log.md"; } \
    && ok "D7 진행 기록 실패 → 경고 · rc 0 · dispatch-log 는 남음" || nope "D7" "rc=$rc err=$(cat "$TD/e.err")"
fi

# D7b: 다른 FID 섹션에 같은 문구가 있어도 이 FID 섹션에 줄이 안 남으면 경고한다(파일 전체 grep 금지)
_setup "$TD/f" "$FID"
printf '\n## 20261001-other\n- 2026-10-01 10:00 /implement 진행 (T1 완료)\n' >> "$TD/f/.specops/session-progress.md"
SPF="$TD/f/.specops/session-progress.md"
chmod 444 "$SPF"; chmod 555 "$TD/f/.specops"
if [ "$(id -u)" = "0" ] || ( : >> "$SPF" ) 2>/dev/null; then
  chmod 755 "$TD/f/.specops"; chmod 644 "$SPF"
  skip "D7b 다른 섹션 같은 문구 (root·chmod 무효 환경)"
else
  out=$(cd "$TD/f" && bash "$DONE" "$FID" T1 2>"$TD/f.err"); rc=$?
  chmod 755 "$TD/f/.specops"; chmod 644 "$SPF"
  { [ "$rc" = 0 ] && grep -qF '경고 — session-progress 기록 실패' "$TD/f.err"; } \
    && ok "D7b 다른 FID 섹션의 같은 문구에 속지 않고 경고" || nope "D7b" "rc=$rc err=$(cat "$TD/f.err")"
fi

finish
