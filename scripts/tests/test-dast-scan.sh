#!/usr/bin/env bash
# dast-scan.sh 검증 (FID 20260620-security-scan-command)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
P=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$P/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
DS="$P/scripts/dast-scan.sh"

[ -f "$DS" ] && [ -x "$DS" ] || nope "존재" "dast-scan.sh 부재/비실행"
# AC-2/AC-R-1: URL 인자 없으면 사용법 + exit (잘못된 호출 가드)
out=$(bash "$DS" 2>&1); ec=$?
printf '%s' "$out" | grep -qiE 'usage|URL|사용' && ok "AC-2 URL 인자 가드" || nope "AC-2" "인자 가드 없음"
# AC-R-1: graceful skip/dry — NO_RUN=1 로 실 docker run/nuclei 없이 분기·출력만 검증 (게이트 결정성)
out2=$(SPECOPS_DAST_NO_RUN=1 bash "$DS" "http://localhost:0" 2>&1); ec2=$?
{ printf '%s' "$out2" | grep -qE 'DAST: (SKIP|DRY)' && [ "$ec2" -eq 0 ]; } \
  && ok "AC-R-1 graceful skip/dry (NO_RUN, exit 0)" || nope "AC-R-1" "skip/dry 실패(ec=$ec2, out=$out2)"

# ── ACK 게이트 (20260806 /security-scan 정밀분석) ────────────────────────────
# 소유확인([y/N])은 command 산문에만 있었다 — dast-scan.sh 를 직접 실행하면 확인 없이
# 능동 스캔이 나간다(무단 스캔 = 불법). 실 스캔 경로에 SPECOPS_DAST_ACK=1 을 요구한다.
# NO_RUN dry 는 실 스캔이 아니므로 면제(테스트·CI 결정성 유지).

# T-ack.a: ACK 없이 실 스캔 경로 → 거부 (exit≠0 + 소유 문구)
out3=$(bash "$DS" "http://localhost:0" 2>&1); ec3=$?
{ [ "$ec3" -ne 0 ] && printf '%s' "$out3" | grep -q '본인 소유'; } \
  && ok "T-ack.a ACK 없이 실 스캔 → 거부 + 소유 고지" || nope "T-ack.a" "ec=$ec3 out=$out3"

# T-ack.b: ACK + NO_RUN → dry 정상 (승인 경로 무손상)
out4=$(SPECOPS_DAST_ACK=1 SPECOPS_DAST_NO_RUN=1 bash "$DS" "http://localhost:0" 2>&1); ec4=$?
{ printf '%s' "$out4" | grep -qE 'DAST: (SKIP|DRY)' && [ "$ec4" -eq 0 ]; } \
  && ok "T-ack.b ACK+NO_RUN → dry 정상" || nope "T-ack.b" "ec=$ec4 out=$out4"

# T-ack.c: NO_RUN 단독(ACK 없음) → 여전히 dry 허용 (실 스캔 아님 — CI 결정성)
out5=$(SPECOPS_DAST_NO_RUN=1 bash "$DS" "http://localhost:0" 2>&1); ec5=$?
[ "$ec5" -eq 0 ] && ok "T-ack.c NO_RUN 단독 → dry 면제" || nope "T-ack.c" "ec=$ec5"

# T-ack.d: command 문서가 승인 후 ACK env 부여를 지시
CMD="$P/commands/security-scan.md"
grep -q 'SPECOPS_DAST_ACK=1' "$CMD" \
  && ok "T-ack.d command 문서 ACK 배선" || nope "T-ack.d" "문서 미배선"

echo "── test-dast-scan: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
