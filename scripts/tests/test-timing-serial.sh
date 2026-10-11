#!/usr/bin/env bash
# run-all: serial — T-hg.d(TERM→2s 유예→KILL 안 trap 복원)·GH-ci.5·5b(워치독 1s 타임아웃 < 3s)가 시간 임계를 직접 잰다(CPU 경합 시 초과)
# test-timing-serial — 시간 임계를 직접 재는 단언만 모은 직렬 스위트 (FID 20261006-runall-serial-split)
# 왜: 이 단언 3개가 test-validate-structure(109s)·test-git-hooks(46s) 를 스위트째 직렬로 묶고 있었다(단언 소요 합 약 8초).
#   단언만 여기로 옮기고 두 큰 스위트의 본체는 병렬 풀로 돌린다. 임계는 넓히지 않았다 — 원문 그대로 이동했다.
# 출처: T-hg.d ← scripts/tests/test-validate-structure.sh · GH-ci.5·GH-ci.5b ← scripts/tests/test-git-hooks.sh (ID 유지)
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

# 아래 GH-ci.5·5b 는 원 스위트에서 CI_RCS 에 rc 를 적재했다(GH-ci.6 집계) — 원문 이동이라 적재 줄이 남아 있고 여기서는 읽지 않는다.
#   (set -u 아래 미정의 오류만 막는 선언이다. rc 는 각 단언이 직접 확인한다.)
CI_SH="$PLUGIN/scripts/_internal/check-ci-status.sh"
CI_RCS=""

# gh stub 디렉터리 생성 — $1=stub 본문 → stdout=디렉터리 경로
_ci_stub() {
  local d; d=$(mktemp -d)
  printf '%s\n' "$1" > "$d/gh"
  chmod +x "$d/gh"
  printf '%s' "$d"
}

# T-hg.d: 패턴 실증 — trap EXIT 은 SIGTERM 에서 복원하고, trap 없으면 손상이 남는다
#   ★ 격리 픽스처로만 검증한다. 실 파일을 쓰면 이 테스트가 바로 그 결함을 재생산한다.
#   ★ trap 은 EXIT **단독**이어야 한다. INT/TERM 을 함께 잡으면 셸 기본 종료가 사라져
#     핸들러가 포그라운드 명령(sleep) 종료까지 **지연**되고, 그 사이 뒤따르는 SIGKILL 을
#     맞으면 복원이 영영 실행되지 않는다. 아래 프로브가 `TERM → 유예 → KILL` 로 재현한다
#     (타임아웃 구현의 전형). SIGTERM 만 오고 프로세스가 완주하면 둘 다 복원되므로,
#     그 시나리오로는 두 패턴이 구별되지 않는다 — 구현 중 변이 M3 가 이를 실증했다.
_sb=$(mktemp -d)
cat > "$_sb/mut-trap.sh" <<'MUTEOF'
#!/usr/bin/env bash
target="$1"; echo ORIGINAL > "$target"
_bak="$target.bak"; cp "$target" "$_bak"
trap 'cp "$_bak" "$target"; rm -f "$_bak"' EXIT
echo MUTATED > "$target"
sleep 20
MUTEOF
cat > "$_sb/mut-notrap.sh" <<'MUTEOF'
#!/usr/bin/env bash
target="$1"; echo ORIGINAL > "$target"
_bak="$target.bak"; cp "$target" "$_bak"
echo MUTATED > "$target"
sleep 5
cp "$_bak" "$target"; rm -f "$_bak"
MUTEOF
_term_probe() {   # $1=픽스처명 → stdout: 중단 후 파일 내용
  local t="$_sb/probe-$1.txt"
  #   ★ 자식의 stdout/stderr 를 끊는다. 안 끊으면 TERM 이 bash 만 죽이고 **고아 sleep 이
  #     명령 치환의 파이프를 붙든 채** 남아, $(_term_probe …) 이 그 EOF 를 기다린다
  #     (실측: 25s → 6s. pre-push 가 매 push 마다 도는 예산이다).
  #     고아 sleep 은 블록 종료 후 최대 ~19초 잔존하나 파일을 건드리지 않고 자연 소멸한다.
  bash "$_sb/$1" "$t" >/dev/null 2>&1 & local p=$!
  sleep 1
  kill -TERM "$p" 2>/dev/null    # 정중한 종료 요청
  sleep 2                        # 유예 — EXIT 단독이면 이 사이에 복원된다
  kill -KILL "$p" 2>/dev/null    # 강제 종료 — 지연된 핸들러는 여기서 영영 사라진다
  wait "$p" 2>/dev/null
  cat "$t" 2>/dev/null
}
_with=$(_term_probe mut-trap.sh)
_without=$(_term_probe mut-notrap.sh)
rm -rf "$_sb"
if [ "$_with" = "ORIGINAL" ] && [ "$_without" = "MUTATED" ]; then
  PASS=$((PASS+1)); echo "PASS T-hg.d trap EXIT 이 SIGTERM 중단에서 복원 (대조: 무trap 은 손상 잔존)"
else
  FAIL=$((FAIL+1)); echo "FAIL T-hg.d 중단 복원 — trap판='$_with'(기대 ORIGINAL) · 무trap판='$_without'(기대 MUTATED)"
fi

# GH-ci.5: 응답 없는 gh + SPECOPS_CI_CHECK_TIMEOUT=1 → 즉시 exit 0 (AC-5)
#   stub 은 exec 없는 평범한 sleep 이다 — 고아 자식이 명령치환 파이프를 무는
#   실제 실패 형태를 재현하기 위함(실측: pkill -P 미적용 시 30.02s).
#   상한은 < 3s — AC-5 는 "약 1초 안에"이고 실측 워치독은 1.05s 다. < 5s 는 계약보다 느슨하다.
if [ -f "$CI_SH" ]; then
  D=$(_ci_stub '#!/usr/bin/env bash
sleep 30')
  _s=$(date +%s)
  out=$(cd "$PLUGIN" && PATH="$D:$PATH" SPECOPS_CI_CHECK_TIMEOUT=1 bash "$CI_SH" 2>&1); rc=$?
  _e=$(date +%s); _d=$((_e - _s))
  CI_RCS="$CI_RCS $rc"
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$_d" -lt 3 ] \
    && ok "GH-ci.5 타임아웃 상한 (${_d}s < 3s, 무출력 exit 0)" \
    || nope "GH-ci.5" "rc=$rc 소요=${_d}s out=[$out]"
  rm -rf "$D"
else
  nope "GH-ci.5" "check-ci-status.sh 부재"
fi

# GH-ci.5b: **depth-2 손자**가 파이프를 물어도 타임아웃이 걸린다 (AC-5 — Phase C 적발)
#   `pkill -P "$pid"` 는 직계 자식만 죽인다. gh 가 손자를 띄우면 타임아웃이 통째로
#   무력화되고, hang 지점이 pre-push 의 "run-all 실행 중" 안내 **앞**이라 push 가
#   무출력 동결된다. 프로세스 그룹 kill(`set -m` + `kill -- -$pid`)이 이걸 막는다.
if [ -f "$CI_SH" ]; then
  D=$(_ci_stub '#!/usr/bin/env bash
bash -c "sleep 30; :"')
  _s=$(date +%s)
  out=$(cd "$PLUGIN" && PATH="$D:$PATH" SPECOPS_CI_CHECK_TIMEOUT=1 bash "$CI_SH" 2>&1); rc=$?
  _e=$(date +%s); _d=$((_e - _s))
  CI_RCS="$CI_RCS $rc"
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$_d" -lt 3 ] \
    && ok "GH-ci.5b depth-2 손자 타임아웃 (${_d}s < 3s)" \
    || nope "GH-ci.5b" "rc=$rc 소요=${_d}s out=[$out]"
  rm -rf "$D"
else
  nope "GH-ci.5b" "check-ci-status.sh 부재"
fi

finish
