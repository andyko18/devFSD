#!/usr/bin/env bash
# ci-suite-pass.sh — 지금 커밋 트리가 원격 CI 의 전체 스위트(job `run-all` + `run-all-macos`)를 이미 통과했는지 판정 (read-only)
#
# Usage: ci-suite-pass.sh   (cwd = 대상 repo 안)
# Exit:  0 PASS  — stdout 1줄 `ci run-all+run-all-macos SUCCESS (commit=<앞 12자>, run=<실행 URL>)`
#        1 STALE — stdout 1줄 `ci STALE (<사유>)` — 판정 불가 포함. 호출자는 종전대로 로컬에서 전체 스위트를 돌린다.
#
# 소비자: release.sh pre-flight — 로컬 통과 기록(full-suite-fresh.sh --release)이 없을 때의 둘째 근거.
# 판정 계약 — **생략 방향 오판 경로가 없어야 한다**(full-suite-fresh.sh 와 같은 방향). 아래는 전부 STALE 이다:
#   SPECOPS_RELEASE_NO_CI(값 무관, 비어있지 않음 — 이 근거만 끈다) · SPECOPS_FORCE_FULL(값 무관) · gh·jq 부재 ·
#   origin 이 github.com 이 아님 · 추적 파일 변경 · gh 실패(미인증·오프라인·시간 초과) · 응답 해석 실패 ·
#   그 커밋의 실행 없음 · 진행 중 · success 가 아닌 결론 · 필요한 job 이 그 실행에 없음(건너뜀 포함).
# 무엇을 같은 것으로 치는가:
#   - 커밋: HEAD, 그리고 HEAD 에서 거슬러 올라간 최근 커밋·origin/main 끝 가운데 **트리 해시가 HEAD 와 같은** 것(내용이 같은 커밋).
#     문서 한 줄만 달라도 트리가 달라 대상이 아니다(full-suite-fresh.sh --release 와 같은 엄격함).
#   - 실행: **push 이벤트**의 실행만 본다. pull_request 실행은 그 커밋이 아니라 PR 머지 결과(임시 머지 커밋)를 돌리므로
#     커밋 SHA 가 같아도 검사한 트리가 다를 수 있다 — 근거로 쓰지 않는다. 실질 대상은 main 에 머지된 커밋의 CI 다.
#   - 결론: 그 커밋의 실행을 최신순으로 훑어 필요한 job 이 든 **첫 실행**(가장 최근)만 본다 — 예전 성공이 최근 실패를 덮지 않는다.
#     그 실행이 실패·진행 중이거나 조회·해석에 실패하면 거기서 STALE 로 끝낸다(트리가 같은 다른 커밋의 통과로 넘어가지 않는다).
#     다음 후보 커밋으로 넘어가는 것은 "그 커밋의 실행이 아예 없을 때"뿐이다.
# 인증: gh 가 환경의 GH_TOKEN 을 그대로 쓴다(이 스크립트는 토큰을 읽지도 지우지도 않는다). 없으면 gh 의 로그인 계정이다.
# 환경변수: SPECOPS_CI_CHECK_TIMEOUT (gh 호출 1회 상한 초, 기본 10)
set -u

# 통과해야 하는 job(.github/workflows/test.yml 의 job id) — **둘 다** 같은 실행에서 completed/success 여야 한다.
#   run-all 은 main 브랜치 보호의 필수 검사(리눅스)다. run-all-macos 는 PR 에서는 돌지 않고 main push 뒤에만 돈다 —
#   로컬 pre-flight(개발 환경 = macOS)를 건너뛰는 근거이므로 맥 실행까지 통과해야 같은 것을 확인한 것이다.
CI_JOBS="run-all run-all-macos"
CI_LOOKBACK=20          # 같은 트리를 찾아 거슬러 올라가는 커밋 수
TIMEOUT_S="${SPECOPS_CI_CHECK_TIMEOUT:-10}"

_stale() { printf 'ci STALE (%s)\n' "$1"; exit 1; }

[ -z "${SPECOPS_RELEASE_NO_CI:-}" ] || _stale "SPECOPS_RELEASE_NO_CI 지정"
[ -z "${SPECOPS_FORCE_FULL:-}" ] || _stale "SPECOPS_FORCE_FULL 지정"
command -v gh >/dev/null 2>&1 || _stale "gh 없음"
command -v jq >/dev/null 2>&1 || _stale "jq 없음"

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || _stale "경로 해석 실패"
[ -f "$HERE/run-bounded.sh" ] || _stale "run-bounded.sh 부재"
# shellcheck source=/dev/null
. "$HERE/run-bounded.sh"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || _stale "git repo 아님"
url=$(git -C "$ROOT" remote get-url origin 2>/dev/null) || _stale "origin 없음"
slug=$(printf '%s\n' "$url" | sed -nE 's#^(https://([^@/]*@)?github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$#\3#p')
slug=${slug%.git}
[ -n "$slug" ] || _stale "origin 이 github.com 저장소가 아님"

# 발행되는 것은 커밋 트리다 — 추적 파일이 커밋과 다르면 그 트리를 판정할 수 없다(full-suite-fresh.sh --release 와 같다)
_st=$(git -C "$ROOT" status --porcelain --untracked-files=no 2>/dev/null) || _stale "git status 실패 — 판정 불가"
[ -z "$_st" ] || _stale "추적 파일 변경 — 커밋 트리 판정 불가"
head_tree=$(git -C "$ROOT" rev-parse -q --verify 'HEAD^{tree}' 2>/dev/null) || _stale "HEAD 트리 없음"
[ -n "$head_tree" ] || _stale "HEAD 트리 없음"

# 후보 — HEAD 먼저, 그다음 트리가 같은 최근 커밋(중복 제거 · 순서 유지)
cands=$( {
  git -C "$ROOT" log -n "$CI_LOOKBACK" --format='%H %T' HEAD 2>/dev/null
  git -C "$ROOT" log -n 1 --format='%H %T' refs/remotes/origin/main 2>/dev/null
} | awk -v t="$head_tree" '$2 == t && !seen[$1]++ { print $1 }' )
[ -n "$cands" ] || _stale "HEAD 커밋을 읽을 수 없음"

_api() { bounded_run "$TIMEOUT_S" gh api "$1" 2>/dev/null; }

why="그 커밋의 push CI 실행 없음"
for sha in $cands; do
  short=$(printf '%s' "$sha" | cut -c1-12)
  # 조회·해석 실패는 그 자리에서 STALE 이다 — 못 읽은 커밋을 건너뛰어 트리가 같은 다른 커밋의 통과로 넘어가지 않는다
  runs=$(_api "repos/$slug/actions/runs?head_sha=$sha&event=push&per_page=20") || _stale "gh 조회 실패(미인증·오프라인·시간 초과)"
  # 응답을 그대로 믿지 않는다 — 커밋·이벤트를 다시 대조한다
  ids=$(printf '%s' "$runs" | jq -r --arg s "$sha" \
    '.workflow_runs // [] | map(select(.head_sha == $s and .event == "push")) | sort_by(.run_started_at // .created_at) | reverse | .[].id' 2>/dev/null) \
    || _stale "CI 응답을 해석할 수 없음"
  for id in $ids; do
    case "$id" in ''|*[!0-9]*) _stale "CI 응답을 해석할 수 없음" ;; esac
    jobs=$(_api "repos/$slug/actions/runs/$id/jobs?per_page=100") || _stale "gh 조회 실패(미인증·오프라인·시간 초과)"
    # 필요한 job 마다 한 줄 `<이름> <status> <conclusion> <url>` — 그 실행에 없으면 `<이름> none - -`
    rows=$(printf '%s' "$jobs" | jq -r --arg names "$CI_JOBS" \
      '(.jobs // []) as $j | ($names | split(" "))[] as $n | ([$j[] | select(.name == $n)] | if length == 0 then "\($n) none - -" else (.[0] | "\($n) \(.status // "-") \(.conclusion // "-") \(.html_url // "-")") end)' 2>/dev/null) \
      || _stale "CI 응답을 해석할 수 없음"
    [ -n "$rows" ] || _stale "CI 응답을 해석할 수 없음"
    # 이 실행에 필요한 job 이 하나도 없으면 다른 워크플로의 실행이다 — 다음 실행을 본다
    printf '%s\n' "$rows" | awk '$2 != "none" { f = 1 } END { exit !f }' || continue
    # 가장 최근 실행이다 — 여기서 판정을 끝낸다(더 오래된 실행이나 트리가 같은 다른 커밋의 통과로 덮지 않는다)
    url="-"
    while read -r j_name j_status j_concl j_url; do
      [ -n "$j_name" ] || continue
      [ "$j_status" != "none" ] || _stale "$j_name 이 그 실행에 없음 (commit=$short)"
      [ "$j_status" = "completed" ] || _stale "$j_name 진행 중 — $j_status (commit=$short)"
      [ "$j_concl" = "success" ] || _stale "$j_name 결론 $j_concl (commit=$short)"
      [ "$url" != "-" ] || url=$j_url
    done <<< "$rows"
    printf 'ci %s SUCCESS (commit=%s, run=%s)\n' "$(printf '%s' "$CI_JOBS" | sed 's/ /+/g')" "$short" "$url"
    exit 0
  done
done
_stale "$why"
