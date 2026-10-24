#!/usr/bin/env bash
# specops-ko 전체 테스트 aggregator
# 사용: bash scripts/tests/run-all.sh [--quiet]   (병렬 수: SPECOPS_RUN_ALL_JOBS — 아래 "병렬 실행" 절)
# 대상: scripts/tests/{,dag/,governance/,llm-eval/,test-convention/,freecomment/,promote/}test-*.sh + validate-structure.sh
# 제외: bench-hook.sh(벤치마크), fixtures/, dogfood-parallel-harness.sh
set -uo pipefail
# 훅(pre-push)·릴리즈 등이 export 한 git 저장소 변수가 스위트 픽스처로 새면 실저장소가 변조된다(20261007-prepush-gitdir) —
#   훅이 이미 지우지만 훅 밖 경로(release.sh pre-flight·수동 실행)도 같은 방어를 갖게 한다.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES

PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# 재귀 가드: test-release.sh 의 release.sh dry-run 이 pre-flight 로 run-all 을 재호출하는 무한 재귀 차단
export SPECOPS_RUN_ALL=1
# ── full-suite 마커 (20260908) ────────────────────────────────────────
# 지문은 **스위트 실행 전** 트리다 — "이 트리가 통과했다" 가 정확한 진술이다.
# 스위트가 트리를 더럽히면 종료 후 지문이 달라져 다음 push 가 전체 실행된다(fail-safe).
# source 는 자식 프로세스를 오염시키지 않는다(실측: 자식에서 SPECOPS unset · vs:: none).
# 경로·지문 모두 $PLUGIN 앵커 — run-all 은 최상단에서 cd 하지 않으므로 다른 cwd 에서
# 호출되면 마커가 엉뚱한 곳에 남거나 NO_GIT 이 된다(fail-closed 방향이나 skip 이 성립 안 함).
_FSP_MARKER="$PLUGIN/${SPECOPS_ROOT:-.specops}/.full-suite-pass"
# 헬퍼 부재(트리밍된 트리·sandbox)는 NO_GIT 으로 떨어뜨린다 = 마커 미기록 = 다음 push 전체 실행.
#   가드 없이 source 하면 실측으로 stderr 2줄을 뱉고 **빈 마커**를 남긴다(sandbox 재현).
#   run-bounded 부재와 달리 WARN 하지 않는 이유: 이 경로의 degradation 은 fail-**closed** 라
#   "보호받고 있다" 는 착각을 만들지 않는다(스위트 상한 부재와 방향이 반대다).
_FSP_TREE=NO_GIT
_FSP_COMMIT=""
if [ -f "$PLUGIN/scripts/_internal/verification-state.sh" ]; then
  # shellcheck source=/dev/null
  . "$PLUGIN/scripts/_internal/verification-state.sh"
  # 비문서 지문을 쓴다 (20260912-verify-stale-docs-scope) — 마커의 뜻이
  #   "이 **비문서** 트리가 통과했다" 로 바뀐다. 문서 한 줄이 전체 스위트 재실행을
  #   강요하던 경로를 없앤다. fail-closed(부재·NO_GIT·불일치 = 전체 실행)는 그대로다.
  _FSP_TREE=$( cd "$PLUGIN" && vs::nondoc_fingerprint )
  # 발행 판정용 둘째 줄(20261024-speed-release-fresh-task-record) — 추적 파일이 커밋 그대로면 커밋 트리 해시를 남긴다.
  #   full-suite-fresh.sh --release 만 읽는다(첫 줄만 보는 pre-push·verify 는 그대로). 추적 변경이 있으면 남기지 않는다(그 트리는 커밋이 아니다).
  #   추적하지 않는 파일(무시 목록 제외)이 있어도 남기지 않는다 — 통과가 그 파일에 기댔을 수 있다 · status 실패도 남기지 않는다.
  if _fsp_st=$(git -C "$PLUGIN" status --porcelain --untracked-files=normal 2>/dev/null) && [ -z "$_fsp_st" ]; then
    _FSP_COMMIT=$(git -C "$PLUGIN" rev-parse -q --verify 'HEAD^{tree}' 2>/dev/null) || _FSP_COMMIT=""
  fi
fi
# 네트워크 금지 계약 (20260828-sast-timeout): 스위트는 **네트워크에 의존하는** SAST 를 부르지 않는다.
#   왜: test-security-scan·test-self-config-collect 가 실 semgrep 을 종전 배선(레지스트리 자동
#   룰셋)으로 불렀고, 그건 왕복이라 **테스트 결과가 네트워크 상태에 좌우**됐다 — 실측으로 이 두
#   스위트가 99s·8분+ 를 먹거나 통째로 정지했고, pre-push 게이트가 그대로 멈췄다.
# 원인 정정 (PR #58): 그 대기의 실체는 룰 수신이 아니라 semgrep.dev version-check 였다
#   (`--version` 만으로도 98.5s · `SEMGREP_ENABLE_VERSION_CHECK=0` 이면 1.8s — PR #58 실측).
# 현재 동작 (f313f8d 이후): 두 스위트가 실 semgrep 을 부르되 **기제가 다르다**.
#   test-security-scan 은 아래 기본값 0 을 케이스별 접두 대입(SPECOPS_SAST_EXTERNAL=1)으로
#   **되돌려** security-scan.sh 를 태우고, test-sast-rules 는 그 변수를 **읽지 않고** semgrep 을
#   직접 호출한다(:29·:39). 어느 쪽이든 로컬 룰셋(scripts/_internal/semgrep-rules) + version-check
#   차단이라 네트워크를 쓰지 않는다(2026-09-24 실측 raw 2.1s · 래퍼 3.8s). 즉 이 계약이 금지하는
#   것은 "외부 스캐너" 자체가 아니라 **네트워크 의존**이다. 시간초과·하드 실패는 stub 으로 검증한다.
export SPECOPS_SAST_EXTERNAL=0
QUIET=false
[ "${1:-}" = "--quiet" ] && QUIET=true

# ── 스위트별 시간 상한 (FID 20260828-sast-timeout) ──
# 왜: 한 스위트가 무한 대기하면 aggregator 전체가 멈추고, 이 게이트는 pre-push 훅과 릴리즈
#   pre-flight 가 그대로 쓴다 — 즉 `git push` 가 정지한다(실측: test-security-scan 8분+ 무출력).
#   상한은 "느린 스위트를 벌주는 것" 이 아니라 **정지를 실패로 바꾸는 것**이다.
# 왜 600 인가: 부하 없는 단독 실측 test-validate-structure 114s(20261008; 처음엔 73s)·llm-eval/test-skill-evals 149s. 다른 세션이 겹쳐 load 17·병렬 8 워커이면
#   test-validate-structure 가 300s 상한을 넘어 TIMEOUT 거짓 FAIL 이 2회 재현됐다(변경과 무관, 900s 재실행 185/0). 600s 는 단독 최대의 약 4배이며
#   부하 시 600s 로 충분한지는 실측하지 않았다(추정·한계). 정지는 여전히 끊는다. doc-lock: historical (당시 실측)
#   600s 는 Bash 도구 포그라운드 최대(600s)와 같다 — 스위트 하나가 멈추면 run-all 전체가 포그라운드로 못 끝나므로 백그라운드 실행 후 Read 회수 경로(verifying-evidence-ko)를 쓴다.
SUITE_TIMEOUT="${SPECOPS_SUITE_TIMEOUT:-600}"
if [ -f "$PLUGIN/scripts/_internal/run-bounded.sh" ]; then
  # shellcheck source=/dev/null
  . "$PLUGIN/scripts/_internal/run-bounded.sh"
else
  # 헬퍼 부재(트리밍된 트리·sandbox) = 상한 없음. **조용히** 무제한이 되지 않도록 경고한다 —
  # 무음 fallback 은 이 FID 가 고치는 결함(상한이 있다는 착각)을 그대로 재생산한다.
  echo "WARN: run-bounded.sh 부재 — 스위트별 상한 없이 진행 (무한 정지 미방지)" >&2
  bounded_run() { shift; "$@"; }
  bounded_timed_out() { return 1; }
fi

SUITES=()
SUITES+=("scripts/_internal/validate-structure.sh")
for f in "$PLUGIN"/scripts/tests/test-*.sh \
         "$PLUGIN"/scripts/tests/dag/test-*.sh \
         "$PLUGIN"/scripts/tests/governance/test-*.sh \
         "$PLUGIN"/scripts/tests/llm-eval/test-*.sh \
         "$PLUGIN"/scripts/tests/test-convention/test-*.sh \
         "$PLUGIN"/scripts/tests/freecomment/test-*.sh \
         "$PLUGIN"/scripts/tests/promote/test-*.sh; do
  [ -f "$f" ] || continue
  SUITES+=("${f#"$PLUGIN"/}")
done

# ── 병렬 실행 (FID 20260911-run-all-parallel) ──
# 왜: 159 스위트 직렬이 657s(당시 실측 · doc-lock: historical) — FID 마다 3회(태스크·verify·pre-push) 돌고, 600s 를 넘으면
#   Bash 도구가 백그라운드로 넘겨 R-1 게이트가 `VERIFY: PASS` 를 못 본다(gbrain 20260902).
# 병렬 수: SPECOPS_RUN_ALL_JOBS(정수≥1) > CPU 코어 수(상한 8) > 1. **1 = 종전 직렬과 같은 순서**(되돌림 스위치).
#   상한 8 인 이유: 중첩 run-all(더미 sandbox 3곳)도 풀을 만든다 — 코어 수 그대로면 곱으로 번진다.
_ra_jobs() {
  local n="${SPECOPS_RUN_ALL_JOBS:-}"
  case "$n" in ''|*[!0-9]*|0*) ;; *) printf '%s' "$n"; return 0 ;; esac
  n=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)
  case "$n" in ''|*[!0-9]*|0*) n=1 ;; esac
  [ "$n" -gt 8 ] && n=8
  printf '%s' "$n"
}
JOBS=$(_ra_jobs)

RA_WORK=$(mktemp -d "${TMPDIR:-/tmp}/specops-run-all.XXXXXX") \
  || { echo "FATAL: run-all 작업 디렉터리 생성 실패" >&2; echo "VERIFY: FAIL"; exit 1; }
# 중단 = 즉시 전부 종료 (clarify Q1). 작업자는 `set -m` 으로 띄워 **자기 프로세스 그룹**이다 —
#   그룹째 TERM 하면 xargs·작업자가 멈추고, 작업자 trap 이 bounded_run 이 만든 스위트 그룹을 끝낸다.
#   ★ ps 로 트리를 훑지 않는다: Claude Code sandbox 에선 ps 가 자식조차 못 본다(실측 31개만 보임).
#   VERIFY 토큰도 마커도 남기지 않는다 — 판정이 없었으므로.
_ra_bg=""
_ra_stop() {
  trap - INT TERM
  [ -n "$_ra_bg" ] && { kill -TERM -- "-$_ra_bg" 2>/dev/null || kill -TERM "$_ra_bg" 2>/dev/null; }
  rm -rf "$RA_WORK"
  exit "$1"
}
trap '_ra_stop 130' INT
trap '_ra_stop 143' TERM
trap 'rm -rf "$RA_WORK"' EXIT

# 작업자 — 스위트 1개 실행 후 out.<i>·rc.<i> 를 남긴다. 인자: 작업디렉터리 plugin 상한 quiet 인덱스.
#   ★ 함수를 export 하지 않고 소스 문자열로 넘긴다 — export -f 는 **모든 스위트의 환경**에
#     bounded_run 을 심어 "헬퍼 미로드" 류 검사를 공허하게 만든다(test-run-bounded:18).
#   ★ 스위트 stdin 은 /dev/null — 직렬 시절 상속 stdin(pre-push 의 ref 파이프)을 병렬로 나눠 읽지 않게.
#   ★ 진행 줄은 printf **1회**로 쓴다 — 작업자 간 줄 섞임 방지(짧은 줄 기준 원자적 write).
read -r -d '' _RA_WORKER <<'WORKER'
w=$1; plugin=$2; SUITE_TIMEOUT=$3; quiet=$4; i=$5
suite=$(sed -n "$((i + 1))p" "$w/list")
if [ -f "$plugin/scripts/_internal/run-bounded.sh" ]; then
  . "$plugin/scripts/_internal/run-bounded.sh"
else
  bounded_run() { shift; "$@"; }
  bounded_timed_out() { return 1; }
fi
_w_stop() {
  for j in $(jobs -p); do kill -TERM -- "-$j" 2>/dev/null || kill -TERM "$j" 2>/dev/null; done
  exit 143
}
trap _w_stop TERM INT
cd "$plugin" || exit 0
bounded_run "$SUITE_TIMEOUT" bash "$suite" > "$w/out.$i" 2>&1 < /dev/null
rc=$?
last=$(grep -v '^$' "$w/out.$i" | tail -1)
# 시간초과는 조용한 rc 가 아니라 **명시 실패**다 — 상한이 걸렸다는 사실 자체가 진단 정보다.
if bounded_timed_out "$rc"; then
  printf '%s\n' "FAIL TIMEOUT — ${SUITE_TIMEOUT}s 상한 초과 (무한 정지 차단). 재현: bash $suite" >> "$w/out.$i"
  printf '%s\n' "⏱  TIMEOUT: $suite (>${SUITE_TIMEOUT}s)" >&2
fi
echo "$rc" > "$w/rc.$i"
[ "$quiet" = true ] || printf -- '--- %s\n%s\n' "$suite" "$last"
exit 0
WORKER

# 직렬 표시 — 선두 20줄의 `# run-all: serial — <사유>`. 시간 임계가 CPU 경합에 약한 스위트용.
#   awk 1회로 판정한다 — `head | grep -q` 는 pipefail 아래서 SIGPIPE 로 rc 가 흔들린다.
#   JOBS=1 이면 표시를 보지 않는다 — 풀 뒤로 미루면 되돌림 스위치가 종전 순서를 재현하지 못한다.
: > "$RA_WORK/list"; : > "$RA_WORK/par"; : > "$RA_WORK/ser"
i=0
for suite in "${SUITES[@]}"; do
  printf '%s\n' "$suite" >> "$RA_WORK/list"
  if [ "$JOBS" -gt 1 ] && awk 'NR > 20 { exit } /^# run-all: serial — ./ { f = 1; exit } END { exit !f }' "$PLUGIN/$suite" 2>/dev/null; then
    echo "$i" >> "$RA_WORK/ser"
  else
    echo "$i" >> "$RA_WORK/par"
  fi
  i=$((i + 1))
done
# longest-first — scripts/tests/suite-order.txt(긴 순 목록)가 있으면 병렬 풀의 **시작 순서**만 앞당긴다(20261006-runall-serial-split).
#   JOBS=1 은 되돌림 스위치라 목록을 보지 않는다. 주석·빈 줄·목록에 없는 경로·직렬 스위트·중복은 무시한다.
#   집계는 원래 순서(인덱스)로 하므로 출력·종료코드는 불변이다. 어떤 이유로든 결과 줄 수가 par 와 다르면 종전 순서를 쓴다
#   (스위트가 통째로 빠진 green 방지).
if [ "$JOBS" -gt 1 ] && [ -s "$RA_WORK/par" ] && [ -s "$PLUGIN/scripts/tests/suite-order.txt" ]; then
  awk 'FNR == 1 { f++ }
    f == 1 { nm[$0] = FNR - 1; next }
    f == 2 { inpar[$1] = 1; seq[++n] = $1; next }
    { sub(/^[ \t]+/, ""); sub(/[ \t\r]+$/, ""); if ($0 == "" || substr($0, 1, 1) == "#") next
      if (($0 in nm) && (nm[$0] in inpar) && !(nm[$0] in done)) { print nm[$0]; done[nm[$0]] = 1 } }
    END { for (k = 1; k <= n; k++) if (!(seq[k] in done)) print seq[k] }' \
    "$RA_WORK/list" "$RA_WORK/par" "$PLUGIN/scripts/tests/suite-order.txt" > "$RA_WORK/par.ordered" 2>/dev/null \
    && [ "$(wc -l < "$RA_WORK/par.ordered" | tr -d ' ')" = "$(wc -l < "$RA_WORK/par" | tr -d ' ')" ] \
    && mv "$RA_WORK/par.ordered" "$RA_WORK/par"
fi
_n_ser=$(wc -l < "$RA_WORK/ser" | tr -d ' ')
printf '▶ run-all: 병렬 %s · 직렬 %s 스위트\n' "$JOBS" "$_n_ser" >&2

# 작업자는 정상이면 항상 rc 0 이다 — 0 이 아니면 신호 사망(xargs 는 그때 abort 해 남은 스위트를 시작하지 않는다).
#   알리고 그룹을 정리한다. ★ 죽은 작업자의 bounded_run 워치독은 flag 가 안 지워져 상한까지 살며, bash 가 함수
#   리다이렉트 때 보관한 원 stdout fd 를 물려받아 `$(run-all)` 캡처를 상한(기본 300s)만큼 붙잡는다(실측 3s→3s·8s→8s).
#   워치독은 작업자와 같은 프로세스 그룹이라 그룹 TERM 으로 끝난다.
_ra_reap() {  # $1=그룹 리더 pid  $2=wait rc
  [ "$2" -eq 0 ] && return 0
  printf '⚠  run-all: 작업자 풀 비정상 종료 (rc=%s) — 결과 없는 스위트는 FAIL 로 센다\n' "$2" >&2
  kill -TERM -- "-$1" 2>/dev/null || true
}

# 1) 병렬 풀 — 2) 직렬 스위트는 풀이 **전부 끝난 뒤** 하나씩(풀과 시간이 겹치지 않게).
#   `&` + wait 인 이유: 포그라운드 자식을 기다리는 동안엔 bash 가 trap 을 미뤄 중단이 늦어진다.
if [ -s "$RA_WORK/par" ]; then
  set -m
  xargs -n 1 -P "$JOBS" bash -c "$_RA_WORKER" _ "$RA_WORK" "$PLUGIN" "$SUITE_TIMEOUT" "$QUIET" < "$RA_WORK/par" &
  _ra_bg=$!
  set +m
  wait "$_ra_bg"; _ra_reap "$_ra_bg" $?
  _ra_bg=""
fi
while read -r i <&3; do
  set -m
  bash -c "$_RA_WORKER" _ "$RA_WORK" "$PLUGIN" "$SUITE_TIMEOUT" "$QUIET" "$i" &
  _ra_bg=$!
  set +m
  wait "$_ra_bg"; _ra_reap "$_ra_bg" $?
  _ra_bg=""
done 3< "$RA_WORK/ser"

# 집계는 **원래 순서**로 — 끝난 순서와 무관하게 출력이 결정적이다.
PASS=0; FAIL=0; SKIPPED=0; FAILED_SUITES=()
i=0
for suite in "${SUITES[@]}"; do
  out_f="$RA_WORK/out.$i"
  rc=$(cat "$RA_WORK/rc.$i" 2>/dev/null || true)
  if [ -z "$rc" ]; then
    # 작업자가 결과를 못 남겼다 — 조용히 넘기면 스위트가 **통째로 빠진 green** 이 된다
    #   출력 파일이 있으면 돌다 죽었고, 없으면 풀이 먼저 중단돼 시작도 못 했다 — 무고한 스위트를 원인으로 찍지 않는다
    rc=1
    if [ -e "$out_f" ]; then
      printf '%s\n' "FAIL WORKER — 결과 없음 (작업자 비정상 종료 — 스위트가 작업자를 죽였거나 신호로 중단). 재현: bash $suite" >> "$out_f"
    else
      printf '%s\n' "FAIL WORKER — 미실행 (작업자 풀 중단으로 시작 못 함 — 원인은 '결과 없음' 스위트). 재현: bash $suite" >> "$out_f"
    fi
  fi
  # 스위트 내부 SKIP 집계 — green 이 곧 전량 실행은 아니다(도구 부재로 축소 실행 가능).
  # `grep -c` 는 0건에 "0" 출력 + rc=1 이라 `|| true` 로 rc 만 흡수한다(`|| echo 0` 금지 — 이중 출력).
  _s=$(grep -c '^SKIP ' "$out_f" 2>/dev/null || true)
  SKIPPED=$((SKIPPED + ${_s:-0}))
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); FAILED_SUITES+=("$suite")
    grep '^FAIL' "$out_f" | head -5
  fi
  i=$((i + 1))
done

echo ""
echo "==== run-all: suites PASS=$PASS FAIL=$FAIL (total=${#SUITES[@]}) ===="
if [ "$SKIPPED" -gt 0 ]; then
  echo "==== run-all: SKIP된 케이스 ${SKIPPED}건 — 도구·환경 부재로 미실행 (green 이 곧 전량 실행은 아니다) ===="
fi
# VERIFY 토큰 — R-1/R-2 실행-근거 게이트(governance-lib _verify_exec_evidence)가 transcript 에서
# 이 토큰으로 실행증거를 판정한다 (러너 계약: PASS 만 인정, FAIL/PARTIAL 불인정). 20260716 false-block fix.
if [ $FAIL -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED_SUITES[@]}"
  # 낡은 통과가 새 실패를 덮지 않게 마커를 제거한다 (clarify Q1)
  rm -f "$_FSP_MARKER"
  echo "VERIFY: FAIL"
  exit 1
fi
# 지문이 NO_GIT 이거나 UNHASHABLE(읽을 수 없는 파일 — 20261005-fingerprint-add-failclosed)이면 기록하지 않는다 —
# 대조 불가한 값으로 skip 이 열리면 안 된다
# `.specops/` 가 없으면 기록하지 않는다 — 디렉터리를 만들면 그 저장소가 관할로 편입돼 다음 커밋부터 R-1 이 막는다
#   (CLAUDE.md "디렉토리는 관할을 여는 쪽만 만든다" · 20261021 실측: 새로 clone 한 클라우드 세션에서 run-all 이 관할을 열었다).
#   기록이 없으면 pre-push 가 전체 스위트를 다시 돈다(안전한 쪽).
if [ "$_FSP_TREE" != "NO_GIT" ] && [ "$_FSP_TREE" != "UNHASHABLE" ] && [ -d "$(dirname "$_FSP_MARKER")" ]; then
  if [ -n "$_FSP_COMMIT" ]; then
    printf '%s\ntree:%s\n' "$_FSP_TREE" "$_FSP_COMMIT" > "$_FSP_MARKER" 2>/dev/null || true
  else
    printf '%s\n' "$_FSP_TREE" > "$_FSP_MARKER" 2>/dev/null || true
  fi
fi

echo "VERIFY: PASS"
exit 0
