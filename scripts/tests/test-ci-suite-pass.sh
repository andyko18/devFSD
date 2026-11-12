#!/usr/bin/env bash
# ci-suite-pass.sh — 같은 커밋 트리의 원격 CI(run-all) 통과 판정 (20261112 speed)
#   계약: PASS 는 "push 이벤트 실행 · 그 커밋(또는 트리가 같은 커밋) · 가장 최근 실행의 job run-all 이 completed/success" 하나뿐이고,
#   그 밖(gh 없음·조회 실패·실행 없음·진행 중·실패·해석 불가·끄기 스위치)은 전부 STALE(rc 1)이다 — 생략 방향 오판이 없어야 한다.
#   gh 는 가짜 실행 파일로 대체한다(네트워크 없음).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CI="$PLUGIN/scripts/_internal/ci-suite-pass.sh"
TMP=$(mktemp -d) || exit 1; trap 'rm -rf "$TMP"' EXIT

# 가짜 gh — `gh api <경로>` 만 받는다. 응답은 $GH_FIX 의 파일이다:
#   …/actions/runs?head_sha=<sha>…  → runs.<sha>.json (없으면 runs.json · 그것도 없으면 빈 목록)
#   …/actions/runs/<id>/jobs…       → jobs.<id>.json (없으면 빈 목록)
#   $GH_FIX/fail 이 있으면 rc 1(미인증·오프라인). 호출은 $GH_FIX/calls 에, 받은 GH_TOKEN 은 $GH_FIX/token 에 남긴다.
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_FIX/calls"
printf '%s' "${GH_TOKEN:-}" > "$GH_FIX/token"
[ -e "$GH_FIX/fail" ] && { echo "gh: not logged in" >&2; exit 1; }
[ "${1:-}" = api ] || exit 2
case "$2" in
  repos/acme/demo/actions/runs\?head_sha=*)
    sha=${2#*head_sha=}; sha=${sha%%&*}
    case "$2" in *"event=push"*) ;; *) exit 2 ;; esac
    if [ -f "$GH_FIX/runs.$sha.json" ]; then cat "$GH_FIX/runs.$sha.json"
    elif [ -f "$GH_FIX/runs.json" ]; then cat "$GH_FIX/runs.json"
    else echo '{"workflow_runs":[]}'; fi ;;
  repos/acme/demo/actions/runs/*/jobs*)
    id=${2#repos/acme/demo/actions/runs/}; id=${id%%/*}
    if [ -f "$GH_FIX/jobs.$id.json" ]; then cat "$GH_FIX/jobs.$id.json"; else echo '{"jobs":[]}'; fi ;;
  *) exit 2 ;;
esac
GH
chmod +x "$BIN/gh"

R="$TMP/repo"; mkdir -p "$R"
( cd "$R" && git init -q -b main && printf 'a\n' > a.txt && git add a.txt && git -c user.name=t -c user.email=t@e.com commit -qm one \
  && git remote add origin https://github.com/acme/demo.git ) || { echo "FATAL: 픽스처 생성 실패" >&2; exit 1; }
SHA=$(git -C "$R" rev-parse HEAD)
export GH_FIX="$TMP/fix"

_reset() { rm -rf "$GH_FIX"; mkdir -p "$GH_FIX"; }
_runs() {  # <파일> <sha> <event> <id>…  — 뒤에 적은 id 일수록 최근 실행이다
  local f="$1" sha="$2" ev="$3" sep="" n=0 id; shift 3
  { printf '{"workflow_runs":['
    for id in "$@"; do n=$((n + 1)); printf '%s{"id":%s,"head_sha":"%s","event":"%s","run_started_at":"2026-11-12T00:%02d:00Z"}' "$sep" "$id" "$sha" "$ev" "$n"; sep=","; done
    printf ']}\n'; } > "$f"
}
_jobs() {  # <id> <job 이름> <status> <conclusion|null> [<맥 status> <맥 conclusion|null>]  — 맥 job 은 기본 completed/success · 맥 status 가 none 이면 싣지 않는다
  local c="\"$4\"" ms="${5:-completed}" mc="\"${6:-success}\"" mac=""
  [ "$4" = null ] && c=null; [ "${6:-success}" = null ] && mc=null
  [ "$ms" = none ] || mac=$(printf ',{"name":"run-all-macos","status":"%s","conclusion":%s,"html_url":"https://x/m"}' "$ms" "$mc")
  [ "$2" = run-all-macos ] && mac=""
  printf '{"jobs":[{"name":"shellcheck","status":"completed","conclusion":"success","html_url":"https://x/s"},{"name":"%s","status":"%s","conclusion":%s,"html_url":"https://github.com/acme/demo/actions/runs/%s/job/1"}%s]}\n' "$2" "$3" "$c" "$1" "$mac" > "$GH_FIX/jobs.$1.json"
}
_ci() { ( cd "$R" && env -u SPECOPS_FORCE_FULL -u SPECOPS_RELEASE_NO_CI -u GH_TOKEN "$@" PATH="$BIN:$PATH" bash "$CI" 2>&1 ); }
_calls() { [ -f "$GH_FIX/calls" ] && wc -l < "$GH_FIX/calls" | tr -d ' ' || echo 0; }

# ── P 통과 ──
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101; _jobs 101 run-all completed success
out=$(_ci); rc=$?
[ "$rc" = 0 ] && [ "$out" = "ci run-all+run-all-macos SUCCESS (commit=${SHA:0:12}, run=https://github.com/acme/demo/actions/runs/101/job/1)" ] \
  && ok "P1 ★ push 실행의 run-all·run-all-macos 가 둘 다 completed/success → rc 0 · 근거 1줄(커밋·실행 URL)" || nope "P1" "rc=$rc $out"
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101; _jobs 101 run-all completed success
out=$(_ci GH_TOKEN=tok-fixture); rc=$?
[ "$rc" = 0 ] && [ "$(cat "$GH_FIX/token")" = "tok-fixture" ] && ok "P2 GH_TOKEN 이 있으면 gh 가 그것을 받는다" || nope "P2" "rc=$rc token=$(cat "$GH_FIX/token" 2>/dev/null)"

# ── S 판정 불가·불통과는 전부 STALE ──
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101; _jobs 101 run-all completed failure
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^ci STALE (run-all 결론 failure' && ok "S1 ★ 결론 failure → STALE" || nope "S1" "rc=$rc $out"
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101; _jobs 101 run-all in_progress null
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^ci STALE (run-all 진행 중 — in_progress' && ok "S2 ★ 진행 중 → STALE" || nope "S2" "rc=$rc $out"
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101; _jobs 101 run-all queued null
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '진행 중 — queued' && ok "S3 대기 중(queued) → STALE" || nope "S3" "rc=$rc $out"
_reset
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^ci STALE (그 커밋의 push CI 실행 없음)' && ok "S4 ★ 검사 결과 없음 → STALE" || nope "S4" "rc=$rc $out"
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101; _jobs 101 run-all completed success; : > "$GH_FIX/fail"
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^ci STALE (gh 조회 실패' && ok "S5 ★ gh 실패(미인증·오프라인) → STALE" || nope "S5" "rc=$rc $out"
# gh 부재 — PATH 를 통째로 바꾼다(bash 만 둔다: gh 검사 앞에서 외부 명령을 쓰지 않는다)
_reset; NOGH="$TMP/nogh"; mkdir -p "$NOGH"; ln -s "$(command -v bash)" "$NOGH/bash" 2>/dev/null
out=$( cd "$R" && env -u SPECOPS_FORCE_FULL -u SPECOPS_RELEASE_NO_CI PATH="$NOGH" "$NOGH/bash" "$CI" 2>&1 ); rc=$?
[ "$rc" = 1 ] && [ "$out" = "ci STALE (gh 없음)" ] && ok "S6 ★ gh 없음 → STALE" || nope "S6" "rc=$rc $out"
_reset; _runs "$GH_FIX/runs.json" "$SHA" pull_request 101; _jobs 101 run-all completed success
out=$(_ci); rc=$?
[ "$rc" = 1 ] && [ "$(_calls)" = 1 ] && ok "S7 ★ pull_request 실행은 근거가 아니다(머지 결과를 돌린 실행) → STALE · job 조회 없음" || nope "S7" "rc=$rc calls=$(_calls) $out"
_reset; _runs "$GH_FIX/runs.json" "0000000000000000000000000000000000000000" push 101; _jobs 101 run-all completed success
out=$(_ci); rc=$?
[ "$rc" = 1 ] && ok "S8 응답의 커밋이 묻는 커밋과 다르면 버린다 → STALE" || nope "S8" "rc=$rc $out"
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101; _jobs 101 run-all-macos completed success
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^ci STALE (run-all 이 그 실행에 없음' && ok "S9 ★ 그 실행에 job run-all 이 없다(맥 job 만 통과 — 이름이 비슷한 job 으로 대신하지 않는다) → STALE" || nope "S9" "rc=$rc $out"
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101; _jobs 101 run-all completed skipped
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '결론 skipped' && ok "S10 건너뛴 job(skipped) → STALE" || nope "S10" "rc=$rc $out"
_reset; printf 'not json\n' > "$GH_FIX/runs.json"
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^ci STALE (' && ok "S11 해석할 수 없는 응답 → STALE" || nope "S11" "rc=$rc $out"
# 맥 job — 리눅스가 통과여도 맥이 실패·진행 중·없음이면 STALE (로컬 pre-flight 는 맥에서 돈다)
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101; _jobs 101 run-all completed success completed failure
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^ci STALE (run-all-macos 결론 failure' && ok "S14 ★ 맥 job 실패 → STALE" || nope "S14" "rc=$rc $out"
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101; _jobs 101 run-all completed success in_progress null
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^ci STALE (run-all-macos 진행 중' && ok "S15 ★ 맥 job 진행 중 → STALE" || nope "S15" "rc=$rc $out"
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101; _jobs 101 run-all completed success none
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^ci STALE (run-all-macos 이 그 실행에 없음' && ok "S16 ★ 맥 job 이 그 실행에 없음(건너뜀) → STALE" || nope "S16" "rc=$rc $out"
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101; printf '{"jobs":[{"name":"lint","status":"completed","conclusion":"success"}]}\n' > "$GH_FIX/jobs.101.json"
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '실행 없음' && ok "S17 필요한 job 이 하나도 없는 실행(다른 워크플로)뿐 → STALE" || nope "S17" "rc=$rc $out"
# 가장 최근 실행이 실패면 예전 성공으로 덮지 않는다 (101 성공 → 102 실패)
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101 102; _jobs 101 run-all completed success; _jobs 102 run-all completed failure
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '결론 failure' && ok "S12 ★ 재실행이 실패했으면 예전 성공으로 덮지 않는다" || nope "S12" "rc=$rc $out"
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 102 101; _jobs 101 run-all completed success; _jobs 102 run-all completed failure
out=$(_ci); rc=$?
[ "$rc" = 0 ] && ok "S13 가장 최근 실행이 성공이면 통과(시작 시각으로 고른다 — 응답 순서 무관)" || nope "S13" "rc=$rc $out"

# ── X 끄기 스위치·전제 ──
_reset; _runs "$GH_FIX/runs.json" "$SHA" push 101; _jobs 101 run-all completed success
out=$(_ci SPECOPS_RELEASE_NO_CI=1); rc=$?
[ "$rc" = 1 ] && [ "$(_calls)" = 0 ] && printf '%s' "$out" | grep -q 'SPECOPS_RELEASE_NO_CI' && ok "X1 ★ SPECOPS_RELEASE_NO_CI=1 → STALE · gh 미호출" || nope "X1" "rc=$rc calls=$(_calls) $out"
out=$(_ci SPECOPS_FORCE_FULL=1); rc=$?
[ "$rc" = 1 ] && [ "$(_calls)" = 0 ] && ok "X2 SPECOPS_FORCE_FULL → STALE · gh 미호출" || nope "X2" "rc=$rc calls=$(_calls) $out"
printf 'b\n' >> "$R/a.txt"
out=$(_ci); rc=$?
git -C "$R" checkout -q -- a.txt
[ "$rc" = 1 ] && [ "$(_calls)" = 0 ] && printf '%s' "$out" | grep -q '추적 파일 변경' && ok "X3 ★ 추적 파일이 커밋과 다르면 판정하지 않는다 → STALE" || nope "X3" "rc=$rc $out"
git -C "$R" remote set-url origin "$TMP/elsewhere.git"
out=$(_ci); rc=$?
git -C "$R" remote set-url origin git@github.com:acme/demo.git
[ "$rc" = 1 ] && [ "$(_calls)" = 0 ] && printf '%s' "$out" | grep -q 'github.com 저장소가 아님' && ok "X4 origin 이 github.com 이 아니면 gh 를 부르지 않는다 → STALE" || nope "X4" "rc=$rc $out"
out=$(_ci); rc=$?
[ "$rc" = 0 ] && ok "X5 ssh 형식 origin(git@github.com:owner/repo.git)도 같은 저장소로 읽는다" || nope "X5" "rc=$rc $out"
git -C "$R" remote set-url origin https://someone@github.com/acme/demo.git
out=$(_ci); rc=$?
[ "$rc" = 0 ] && ok "X6 계정이 붙은 https origin(https://<계정>@github.com/owner/repo.git)도 읽는다" || nope "X6" "rc=$rc $out"
git -C "$R" remote set-url origin https://github.com.evil.example/acme/demo.git
out=$(_ci); rc=$?
git -C "$R" remote set-url origin https://github.com/acme/demo.git
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'github.com 저장소가 아님' && ok "X7 github.com 으로 시작만 하는 다른 호스트는 아니다" || nope "X7" "rc=$rc $out"

# ── T 같은 트리의 커밋 ──
#   HEAD 가 내용 없는 커밋(트리 동일)이면 그 아래 커밋의 통과를 쓴다. 트리가 달라지면(문서 한 줄 포함) 쓰지 않는다.
git -C "$R" -c user.name=t -c user.email=t@e.com commit -q --allow-empty -m empty
SHA2=$(git -C "$R" rev-parse HEAD)
_reset; _runs "$GH_FIX/runs.$SHA.json" "$SHA" push 101; _jobs 101 run-all completed success
out=$(_ci); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q "commit=${SHA:0:12}" && ok "T1 ★ HEAD 와 트리가 같은 아래 커밋의 통과 → rc 0 (근거 커밋을 적는다)" || nope "T1" "rc=$rc $out"
_reset; _runs "$GH_FIX/runs.$SHA.json" "$SHA" push 101; _jobs 101 run-all completed success
_runs "$GH_FIX/runs.$SHA2.json" "$SHA2" push 201; _jobs 201 run-all completed failure
out=$(_ci); rc=$?
[ "$rc" = 1 ] && ok "T2 ★ HEAD 자신의 실행이 실패면 트리가 같은 다른 커밋의 통과로 덮지 않는다" || nope "T2" "rc=$rc $out"
# HEAD 의 실행은 있는데 job 조회가 실패(또는 응답이 깨짐) → 아래 커밋의 통과로 넘어가지 않는다
cat > "$BIN/gh-jobfail" <<'GH'
#!/usr/bin/env bash
case "$2" in */runs/201/jobs*) [ "${JOBFAIL:-}" = garbage ] && { echo 'not json'; exit 0; }; exit 1 ;; esac
exec "$(dirname "$0")/gh-real" "$@"
GH
chmod +x "$BIN/gh-jobfail"; mv "$BIN/gh" "$BIN/gh-real"; mv "$BIN/gh-jobfail" "$BIN/gh"
_reset; _runs "$GH_FIX/runs.$SHA.json" "$SHA" push 101; _jobs 101 run-all completed success
_runs "$GH_FIX/runs.$SHA2.json" "$SHA2" push 201
out=$(_ci); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^ci STALE (gh 조회 실패' && ok "T2b ★ HEAD 실행의 job 조회가 실패하면 STALE — 트리가 같은 다른 커밋의 통과로 넘어가지 않는다" || nope "T2b" "rc=$rc $out"
out=$(_ci JOBFAIL=garbage); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^ci STALE (CI 응답을 해석할 수 없음' && ok "T2c ★ HEAD 실행의 job 응답이 깨졌으면 STALE — 다른 커밋으로 넘어가지 않는다" || nope "T2c" "rc=$rc $out"
mv "$BIN/gh-real" "$BIN/gh"
printf 'doc\n' > "$R/README.md"; git -C "$R" add README.md; git -C "$R" -c user.name=t -c user.email=t@e.com commit -qm doc
_reset; _runs "$GH_FIX/runs.$SHA.json" "$SHA" push 101; _jobs 101 run-all completed success
out=$(_ci); rc=$?
[ "$rc" = 1 ] && ok "T3 ★ 문서 한 줄만 달라도 트리가 다르다 → 아래 커밋의 통과를 쓰지 않는다" || nope "T3" "rc=$rc $out"

# ── K 계약 잠금 ──
WF="$PLUGIN/.github/workflows/test.yml"
grep -q '^CI_JOBS="run-all run-all-macos"' "$CI" && grep -q '^  run-all:$' "$WF" && grep -q '^  run-all-macos:$' "$WF" \
  && ok "K1 판정하는 job 이름 == 워크플로의 job id(run-all · run-all-macos)" || nope "K1"
# 맥 job 은 main push 에서 돌아야 한다 — PR 에서만 빠진다. push 에서도 빠지면 CI 근거는 영영 STALE 이다(재사용이 조용히 죽는다)
awk '/^  run-all-macos:$/ { f = 1; next } f && /^  [A-Za-z]/ { exit } f' "$WF" | grep -qF "if: github.event_name == 'push'" \
  && grep -qE '^  push:' "$WF" && ok "K4 맥 job 은 push(main) 에서만 돈다 — 릴리즈 판정이 보는 실행에 들어 있다" || nope "K4"
! grep -qE '^[^#]*(unset|export)[[:space:]]+GH_TOKEN|^[^#]*GH_TOKEN=' "$CI" && ok "K2 스크립트가 GH_TOKEN 을 지우거나 덮지 않는다" || nope "K2"
! grep -qE '^[^#]*gh[[:space:]]+(pr|run|workflow|release|repo)[[:space:]]' "$CI" && grep -q 'gh api' "$CI" && ok "K3 읽기 전용 — gh api 조회만 한다" || nope "K3"

finish
