#!/usr/bin/env bash
# run-bounded.sh 검증 — 무한 정지 방지 공용 상한 헬퍼 (FID 20260828-sast-timeout)
#
# 계기: 종전 semgrep 배선(레지스트리 자동 룰셋)이 네트워크에 걸리면 무한 대기하고,
#   run-all.sh 에는 스위트별 상한이 없어 `git push`(pre-push 훅)가 통째로 정지했다.
#   실측: 1줄 .py 대상 semgrep 이 30초 상한 안에 미완료 · run-all 이 test-security-scan 에서
#   8분+ 무출력 정지. 상한을 두 층(외부 스캐너·스위트) 모두에 건다.
# 원인 정정 (PR #58): 그 대기의 실체는 룰 수신이 아니라 semgrep.dev version-check 였다
#   (`--version` 만으로도 98.5s · `SEMGREP_ENABLE_VERSION_CHECK=0` 이면 1.8s — PR #58 실측).
#   현재 배선은 로컬 룰셋 + 그 차단이라 이 경로를 타지 않는다. 이 스위트의 대상은 semgrep 이
#   아니라 **상한·자손 정리 계약**이므로 검증 가치는 그대로다(다른 스캐너·미래 도구에 유효).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0

LIB="$PLUGIN/scripts/_internal/run-bounded.sh"
[ -f "$LIB" ] || { echo "FAIL 존재 — $LIB 부재"; echo "PASS=0 FAIL=1"; exit 1; }
# shellcheck source=/dev/null
source "$LIB"
command -v bounded_run >/dev/null 2>&1 || { echo "FAIL 로드 — bounded_run 미정의"; echo "PASS=0 FAIL=1"; exit 1; }

# ── T1: 상한 초과 → 124 로 정규화 + 실제로 끊긴다 (AC-1) ──
# 경과·rc 를 함께 봐야 한다: rc 만 보면 "상한은 판정했는데 실제로는 안 끊긴 상태"(T5 가 잡는
# 고아 자식 결함)를 통과시킨다.
_t1s=$(date +%s); bounded_run 2 sleep 30 >/dev/null 2>&1; _t1rc=$?; _t1el=$(( $(date +%s) - _t1s ))
[ "$_t1rc" -eq 124 ] && ok "T1.a 상한 초과 rc=124 (신호별 rc 정규화)" \
  || nope "T1.a 상한 rc" "rc=$_t1rc (기대 124)"
[ "$_t1el" -lt 8 ] && ok "T1.b 상한 초과가 실제로 끊긴다 (${_t1el}s < 8s)" \
  || nope "T1.b 상한 실효" "${_t1el}s 소요 — 상한 미작동(sleep 30 완주 의심)"

# ── T2: 정상 종료는 rc 를 그대로 전달한다 (AC-2) ──
bounded_run 5 true; [ $? -eq 0 ] && ok "T2.a 성공 rc=0 전달" || nope "T2.a" "rc≠0"
bounded_run 5 sh -c 'exit 7'; ec=$?
[ "$ec" -eq 7 ] && ok "T2.b 실패 rc 원본 전달 (7)" || nope "T2.b rc 전달" "rc=$ec (기대 7)"

# ── T3: 0·비수치 = 무제한(종전 동작 보존) (AC-3) ──
# 왜 필요한가: 상한을 기본 도입하면서 기존 호출자의 장시간 정상 실행을 끊으면 안 된다.
#   0 을 명시한 경우는 "상한 없음" 이라는 의도적 선택이고, 파싱 불가 값도 같은 쪽(보수)으로 떨어뜨린다.
bounded_run 0 sh -c 'exit 3'; ec=$?
[ "$ec" -eq 3 ] && ok "T3.a 0 = 무제한, rc 전달" || nope "T3.a" "rc=$ec (기대 3)"
bounded_run "abc" sh -c 'exit 4'; ec=$?
[ "$ec" -eq 4 ] && ok "T3.b 비수치 = 무제한, rc 전달" || nope "T3.b" "rc=$ec (기대 4)"

# ── T4: 판정 헬퍼 (AC-4) ──
bounded_timed_out 124 && ok "T4.a bounded_timed_out 124 = 참" || nope "T4.a" "124 를 시간초과로 안 봄"
bounded_timed_out 1   && nope "T4.b" "1 을 시간초과로 오판" || ok "T4.b bounded_timed_out 1 = 거짓"

# ── T5: ★ 핵심 — 명령치환 안에서 고아 손자가 파이프를 물지 않는다 (AC-5) ──
# 왜 이게 계약의 본체인가: 상한 구현이 대상 프로세스 하나만 죽이면(GNU timeout·perl alarm),
#   래퍼 셸이 죽어도 손자가 stdout 파이프를 계속 물어 `$( )` 가 반환되지 않는다. rc 는 제때
#   나오는데 **호출부는 그대로 멈춘다** — 상한이 있다는 착각만 남는 최악의 형태다.
#   실측(이 FID 개발 중): perl alarm 2s 구현에서 bounded_run 은 2초, `j=$(...)` 는 102초.
#   그래서 여기서는 rc 가 아니라 **명령치환 왕복 시간**을 잰다.
sb=$(mktemp -d)
printf '#!/usr/bin/env bash\nsleep 60\n' > "$sb/wrapper.sh"; chmod +x "$sb/wrapper.sh"
s=$(date +%s)
_cap=$(bounded_run 2 "$sb/wrapper.sh" 2>/dev/null); _caprc=$?
el=$(( $(date +%s) - s ))
[ "$el" -lt 10 ] && ok "T5.a 명령치환이 상한 내 반환 — 고아 손자 파이프 미보유 (${el}s)" \
  || nope "T5.a 고아 자손" "명령치환이 ${el}s 물림 — 자손 정리 실패(그룹 kill 미작동)"
[ "$_caprc" -eq 124 ] && ok "T5.b 래퍼 셸 대상도 rc=124" || nope "T5.b" "rc=$_caprc"
[ -z "$_cap" ] && ok "T5.c 시간초과 출력은 빈 값 (부분 출력 오집계 없음)" || nope "T5.c" "out=$_cap"
rm -rf "$sb"

# ── T6: stderr 무오염 (AC-6) ──
# 왜 계약인가: 워치독을 신호로 정리하면 bash 가 다음 명령 경계에서 "Terminated: 15 ( sleep … )"
#   을 stderr 로 흘린다(개발 중 실측). run-all 은 스위트마다 bounded_run 을 부르므로 그 한 줄이
#   147배로 불어나고, stderr 가 비어 있길 요구하는 상류 계약(check-ci-status AC-2 계열)을 깬다.
#   상한이 "동작은 하는데 출력을 더럽히는" 상태를 회귀로 잠근다.
_e1=$(bounded_run 2 sleep 30 2>&1 1>/dev/null); : ; _e2=$(bounded_run 5 true 2>&1 1>/dev/null)
_noise=$( { bounded_run 5 true; bounded_run 5 true; : ; } 2>&1 1>/dev/null )
{ [ -z "$_e1" ] && [ -z "$_e2" ] && [ -z "$_noise" ]; } \
  && ok "T6.a stderr 무오염 (시간초과·정상 경로 모두)" \
  || nope "T6.a stderr 오염" "timeout=[$_e1] ok=[$_e2] 연속=[$_noise]"

# ── T7: 소비자 배선 — 상한이 실제 호출부에 걸려 있다 (AC-7) ──
# 왜 grep 인가: 헬퍼가 정상이어도 호출부가 안 쓰면 무한 정지는 그대로다. 배선 소실을 격추한다.
#   call-site 앵커(`bounded_run `)로 좁힌다 — 주석에 심볼만 남기고 호출을 지우는 변이를 잡기 위함이다.
grep -q 'bounded_run ' "$PLUGIN/scripts/tests/run-all.sh" \
  && ok "T7.a run-all.sh 가 bounded_run 호출" || nope "T7.a 배선" "run-all.sh 에 bounded_run 호출부 없음"
grep -q 'bounded_run ' "$PLUGIN/scripts/security-scan.sh" \
  && ok "T7.b security-scan.sh 가 bounded_run 호출" || nope "T7.b 배선" "security-scan.sh 에 bounded_run 호출부 없음"

echo ""
finish
