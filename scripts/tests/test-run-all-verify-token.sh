#!/usr/bin/env bash
# test-run-all-verify-token.sh — run-all.sh VERIFY 토큰 계약 (20260716 R-1 false-block fix)
# run-all.sh 는 성공 시 VERIFY: PASS, 실패 시 VERIFY: FAIL 을 마지막 줄로 출력해야 한다.
# governance-lib _verify_exec_evidence 가 이 토큰으로 실행증거를 판정한다 (test-exec-evidence T14~T16).
# 방식: run-all.sh 를 sandbox 플러그인 트리에 복사해 실행 (PLUGIN 은 BASH_SOURCE 기준이라 sandbox 로 격리).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/scripts/tests" "$TMP/scripts/_internal"
cp "$PLUGIN/scripts/tests/run-all.sh" "$TMP/scripts/tests/run-all.sh"
# 상한 헬퍼도 실물로 복사한다 — stub 을 두면 sandbox 가 프로덕션 경로를 안 밟는다
# (20260828-sast-timeout: run-all 이 bounded_run 으로 스위트를 감싼다).
cp "$PLUGIN/scripts/_internal/run-bounded.sh" "$TMP/scripts/_internal/run-bounded.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/scripts/_internal/validate-structure.sh"
printf '#!/usr/bin/env bash\necho "PASS t1"\nexit 0\n' > "$TMP/scripts/tests/test-ok.sh"

# ── T1: 전 suite 성공 → 마지막 줄 VERIFY: PASS + exit 0 ──
out=$(bash "$TMP/scripts/tests/run-all.sh" --quiet 2>&1); code=$?
last=$(printf '%s\n' "$out" | tail -1)
if [ "$code" -eq 0 ] && [ "$last" = "VERIFY: PASS" ]; then
  ok "T1 성공 시 마지막 줄 VERIFY: PASS + exit 0"
else
  nope "T1 PASS 토큰" "exit=$code last=$last"
fi

# ── T2: suite 1개 실패 → 마지막 줄 VERIFY: FAIL + exit 1 (PASS 토큰 미출력) ──
printf '#!/usr/bin/env bash\necho "FAIL t9"\nexit 1\n' > "$TMP/scripts/tests/test-bad.sh"
out=$(bash "$TMP/scripts/tests/run-all.sh" --quiet 2>&1); code=$?
last=$(printf '%s\n' "$out" | tail -1)
if [ "$code" -eq 1 ] && [ "$last" = "VERIFY: FAIL" ] && ! printf '%s\n' "$out" | grep -qx "VERIFY: PASS"; then
  ok "T2 실패 시 마지막 줄 VERIFY: FAIL + exit 1 (PASS 토큰 없음)"
else
  nope "T2 FAIL 토큰" "exit=$code last=$last"
fi

# ── T3: 게이트 러너 앵커 계약 — governance-lib 정규식이 tests/run-all.sh 를 러너로 인식 (배선 grep) ──
#   ★ 20260907: 앵커가 jq 리터럴에서 셸 변수로 이관되며 백슬래시가 한 겹 벗겨졌다
#     (jq 문자열 이스케이프 `\\.` → --arg raw `\.`). 패턴을 단일 백슬래시로 맞춘다.
#   ★ `^_RUNNER_ANCHOR_PAT=` 로 **상수 대입 줄에 결속**한다 — 자유 grep 은 산문 주석
#     ("앵커는 `tests/run-all\.sh` 로 좁힌다")에도 걸려, 앵커에서 run-all 절을 제거해도
#     통과했다(구현자 M3 변이 실측: 자유 grep 은 ★생존 · 결속 grep 은 1→0). 껍데기 잠금은
#     이 FID 가 고치는 결함 그 자체라 느슨한 쪽을 쓰지 않는다.
n=$(grep -c '^_RUNNER_ANCHOR_PAT=.*tests/run-all\\\.sh' "$PLUGIN/hooks/governance-lib.sh")
[ "$n" -ge 1 ] && ok "T3 governance-lib 러너 클래스에 tests/run-all.sh 앵커 존재 ($n)" \
  || nope "T3 앵커 배선" "governance-lib 에 tests/run-all 앵커 없음"

# ── T5: 네트워크 금지 계약 — aggregator 가 외부 SAST 를 끈다 (20260828-sast-timeout) ──
# 왜 계약인가: 이 export 가 사라지면 test-security-scan·test-self-config-collect 가 다시 실
#   semgrep 을 부르고, run-all 소요가 네트워크 상태에 좌우된다(실측 4.4s → 104s, 최악은 무한).
#   pre-push 가 이 게이트를 그대로 쓰므로 `git push` 가 네트워크에 묶인다.
grep -qE '^export SPECOPS_SAST_EXTERNAL=0' "$PLUGIN/scripts/tests/run-all.sh" \
  && ok "T5 run-all 이 외부 SAST 를 끄고 실행 (네트워크 금지 계약)" \
  || nope "T5 네트워크 금지" "run-all 에 SPECOPS_SAST_EXTERNAL=0 export 없음"

# ── T4: 상한 헬퍼 부재 → 죽지 않고 경고 후 진행 (20260828-sast-timeout) ──
# 왜 계약인가: 헬퍼를 하드 의존으로 두면 트리밍된 트리에서 aggregator 가 통째로 죽는다.
#   반대로 **조용히** 무제한으로 떨어지면 "상한이 있다"는 착각만 남는다 — 이 FID 가 고치는
#   결함의 재생산이다. 계약은 "동작하되 경고한다" 이고, 그 경고가 사라지는 것도 회귀다.
rm -f "$TMP/scripts/tests/test-bad.sh" "$TMP/scripts/_internal/run-bounded.sh"
out=$(bash "$TMP/scripts/tests/run-all.sh" --quiet 2>&1); code=$?
last=$(printf '%s\n' "$out" | tail -1)
{ [ "$code" -eq 0 ] && [ "$last" = "VERIFY: PASS" ] && printf '%s\n' "$out" | grep -q 'run-bounded.sh 부재'; } \
  && ok "T4 헬퍼 부재 시 경고 후 정상 완주 (무음 fallback 아님)" \
  || nope "T4 헬퍼 부재 fallback" "exit=$code last=$last out=$(printf '%s' "$out" | head -3)"

finish
