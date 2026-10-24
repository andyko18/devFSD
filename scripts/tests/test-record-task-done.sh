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

# D7c: 접두가 겹친 FID(`<FID>-x`) 섹션의 줄은 세지 않는다(AC-1) — append 대역이 그 섹션에 줄을 쓰면 경고해야 한다
#   대역은 진짜 append 와 같은 계약(rc 0 · 성공 문구)을 지키고 줄만 겹친 FID 섹션에 넣는다 — 끝 공백 없는 접두 일치 `_cnt` 를 떨어뜨린다
_setup "$TD/f2" "$FID"
printf '\n## %s-x\n- 2026-10-01 10:00 /tasks 완료 (tasks.md)\n' "$FID" >> "$TD/f2/.specops/session-progress.md"
mkdir -p "$TD/plug" && cp -R "$PLUGIN/scripts" "$TD/plug/" && cp -R "$PLUGIN/templates" "$TD/plug/" 2>/dev/null
cat > "$TD/plug/scripts/session-progress-append.sh" <<'STUB'
#!/usr/bin/env bash
# 대역: 진짜 append 와 같은 rc 0 · 같은 성공 문구 — 다만 줄을 `## <FID>-x` 섹션에 넣는다(잘못된 귀속)
f=.specops/session-progress.md; awk -v h="## $1-x" -v l="- 2026-10-24 10:00 $2 $3 ($4)" '{print} $0==h{print l}' "$f" > "$f.t" && mv "$f.t" "$f"
echo "appended to existing section"
STUB
out=$(cd "$TD/f2" && bash "$TD/plug/scripts/_internal/record-task-done.sh" "$FID" T1 2>"$TD/f2.err"); rc=$?
{ [ "$rc" = 0 ] && grep -qF '경고 — session-progress 기록 실패' "$TD/f2.err" && grep -qF "/implement 진행 (T1 완료)" "$TD/f2/.specops/session-progress.md"; } \
  && ok "D7c 겹친 FID 섹션에 들어간 줄은 세지 않고 경고" || nope "D7c" "rc=$rc err=$(cat "$TD/f2.err")"

# D9: 요약에 백슬래시가 있어도 그대로 센다 — FID·문구를 ENVIRON 으로 넘긴다(`awk -v` 는 `\n`·`\t` 를 해석해 거짓 경고)
_setup "$TD/g" "$FID"
err=$(cd "$TD/g" && bash "$DONE" "$FID" T1 'C:\new\tab' 2>&1 >/dev/null)
{ ! printf '%s' "$err" | grep -qF '경고 — session-progress 기록 실패'; } \
  && _first "$TD/g/.specops/session-progress.md" "$FID" | grep -qF '/implement 진행 (T1 완료 — C:\new\tab)' \
  && ok "D9 백슬래시 든 요약 — 경고 없음 · 원문 그대로 기록" || nope "D9" "err=$err first=$(_first "$TD/g/.specops/session-progress.md" "$FID")"

# D8: 헤더 판정 공통 규칙 — 판독기 5곳이 같은 섹션을 고른다 (20261024-quality-gate-fixes · AC-1·AC-2)
#   규칙(쓰는 쪽 session-progress-append 와 같다): `## <FID>` 정확 일치 또는 `## <FID> ` 로 시작. 접두가 겹친 FID·메모 속 `## <FID>` 는 아니다.
#   한 판독기라도 규칙을 바꾸면 그 판독기의 줄이 FAIL 한다(record-task-done 은 정확 일치만 보던 이탈 — 접미 헤더에서 거짓 경고).
_d8_fix() { # $1=dir $2=헤더 줄 — 섹션 첫 줄은 종결 줄(freework NEW 판정용) · 둘째 줄은 /specify(reconcile 기록 단계용)
  _setup "$1" "$FID"
  { printf '%s\n- 2026-10-24 10:01 /lifecycle DONE (PR #1 머지)\n- 2026-10-24 10:00 /specify 완료 (spec.md)\n' "$2"
    printf '\n## 20261001-other\n- 2026-10-01 10:00 /tasks 완료 — 메모 ## %s 참고\n- 2026-10-01 09:00 /finishing 완료 (PR #2)\n' "$FID"; } > "$1/.specops/session-progress.md"
  cp "$1/.specops/session-progress.md" "$1/sp.orig"
}
_d8_reset() { cp "$1/sp.orig" "$1/.specops/session-progress.md"; }
_d8() { # $1=id $2=헤더 줄 $3=yes(이 FID 섹션) | no(다른 FID 섹션)
  local id="$1" hdr="$2" want="$3" d="$TD/d8-$1" o
  _d8_fix "$d" "$hdr"
  o=$(cd "$d" && bash "$PLUGIN/scripts/session-progress-append.sh" "$FID" /probe 진행 m 2>&1)
  if [ "$want" = yes ]; then printf '%s' "$o" | grep -q '^appended to existing section' ; else printf '%s' "$o" | grep -q '^created new section'; fi \
    && ok "$id.a session-progress-append ($want)" || nope "$id.a session-progress-append ($want)" "$o"
  _d8_reset "$d"
  o=$(cd "$d" && bash "$PLUGIN/scripts/show-fid-status.sh" "$FID" 2>&1)
  if [ "$want" = yes ]; then printf '%s' "$o" | grep -qF '/lifecycle DONE (PR #1 머지)'; else printf '%s' "$o" | grep -qF '(진행 이력 없음)'; fi \
    && ok "$id.b show-fid-status ($want)" || nope "$id.b show-fid-status ($want)" "$(printf '%s' "$o" | sed -n '/진행 이력/,+2p' | tr '\n' '|')"
  o=$(cd "$d" && bash "$PLUGIN/scripts/freework-resolve-fid.sh" "$FID" 2>&1)
  if [ "$want" = yes ]; then [ "$o" = NEW ]; else [ "$o" = "ATTACH:$FID" ]; fi \
    && ok "$id.c freework-resolve-fid ($want)" || nope "$id.c freework-resolve-fid ($want)" "$o"
  o=$(cd "$d" && bash "$PLUGIN/scripts/_internal/reconcile-check.sh" "$FID" 2>&1)
  if [ "$want" = yes ]; then printf '%s' "$o" | grep -qF '기록(finishing)'; else ! printf '%s' "$o" | grep -qF '기록(finishing)'; fi \
    && ok "$id.d reconcile-check ($want)" || nope "$id.d reconcile-check ($want)" "$(printf '%s' "$o" | grep -m1 '기록' )"
  local memo=d8   # record-task-done 이 남기는 줄 = `/implement 진행 (T1 완료 — <요약>)`
  o=$(cd "$d" && bash "$DONE" "$FID" T1 "$memo" 2>&1 >/dev/null)
  if [ "$want" = yes ]; then
    { ! printf '%s' "$o" | grep -qF '경고 — session-progress 기록 실패'; } \
      && awk -v h="$hdr" '$0==h{getline; print; exit}' "$d/.specops/session-progress.md" | grep -qF "/implement 진행 (T1 완료 — $memo)"
  else
    { ! printf '%s' "$o" | grep -qF '경고 — session-progress 기록 실패'; } \
      && awk -v h="$hdr" '$0==h{getline; print; exit}' "$d/.specops/session-progress.md" | grep -qF '/lifecycle DONE (PR #1 머지)'
  fi && ok "$id.e record-task-done ($want)" || nope "$id.e record-task-done ($want)" "err=$o"
}
_d8 D8.1 "## $FID" yes
_d8 D8.2 "## $FID · 기능 이름" yes
_d8 D8.3 "## $FID-x" no
_d8 D8.4 "## $FID-x-y" no

# D5: implementing-ko 가 이 스크립트를 가리킨다
grep -qF 'record-task-done.sh <FID> <task-id>' "$PLUGIN/skills/implementing-ko/SKILL.md" && ok "D5 implementing-ko 커밋 직전 절이 record-task-done.sh 를 안내" || nope "D5"

finish
