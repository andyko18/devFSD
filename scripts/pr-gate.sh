#!/usr/bin/env bash
# pr-gate.sh — PR 생성 단계에서 사용자에게 물을지 판정한다 (읽기 전용 · 20261114)
# Usage: bash scripts/pr-gate.sh decide <FID>
# stdout 1줄:
#   PR-GATE: auto                 묻지 않고 PR 을 만든다
#   PR-GATE: auto-draft (<사유>)  묻지 않고 **초안** PR 을 만든다 — 사용자가 보는 결과가 바뀌었고 아직 확인받지 않았다
#   PR-GATE: ask (<사유>)         종전대로 묻는다
# rc: 0 = 판정함(ask 포함 — 흐름을 끊지 않는다) · 2 = 사용 오류(인자 없음·FID 형식)
#
# 왜: 하류 실측(20261114 — 한 프로젝트의 작업 10건)에서 "추천대로·진행·승인" 만 친 발화가 38회였고, PR 생성 질문에는
#   매번 추천안 그대로 답했다. 승인 묶음이 "PR 생성 포함"을 싣고(skills/specifying-ko/once-approval.md · commands/basic.md),
#   그 승인이 기록돼 있으면 PR 단계에서 다시 묻지 않는다. **머지는 이 판정의 대상이 아니다 — 언제나 사용자가 정한다.**
# 판단이 서지 않으면 ask 다(자동 쪽으로 틀리는 길을 두지 않는다):
#   설정 pr_gate: ask · SPECOPS_PR_GATE=ask · spec 없음 · §batch(오케스트레이터 소관) · §auto(무인 — 가정 다이제스트를 사람이 본다)
#   · §일괄·§기본 이 아님(--step 단계별 확인) · 승인 기록에 "PR 생성 포함"이 없음(이 버전 전에 승인한 작업 포함).
# 동의 기록: dev-decision.sh 가 쓴 형식의 줄(시각 + [approval])의 **결정 칸이 "PR 생성 포함" 으로 끝나야** 한다 —
#   그 스크립트는 `- <시각> [approval] <결정>[ — <근거>]` 로 쓰므로 그 말 뒤에는 줄 끝이나 " — " 만 온다.
#   "PR 생성 포함은 거절"·"포함하지 않음"·근거 칸에만 있는 말은 동의가 아니다(20261114 재현). 손으로 쓴 줄·다른 종류도 치지 않는다.
# 데모: evidence.md 의 **마지막** `## /demo` 절의 `**확인 필요**:` 가 no 로 시작하면 auto, 그 밖(yes·빈 값·모르는 값)은 auto-draft.
#   데모 절이 없으면(기본 경로) auto — 화면을 건드린 기본 경로 작업은 브라우저 점검 결과를 PR 본문에 싣는다.
set -u
export LC_ALL=C

die() { echo "pr-gate: $*" >&2; exit 2; }
[ "${1:-}" = decide ] || die "usage: $0 decide <FID>"
FID="${2:-}"
printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || die "invalid FID: ${FID:-없음}"

# worktree 에서 불러도 FID 기록이 메인에만 있으면 메인을 쓴다 (dev-decision.sh 와 같은 해석)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_internal/specops-root.sh" 2>/dev/null && specops_root_export "$FID"
if [ -n "${SPECOPS_ROOT:-}" ]; then SPECOPS="$SPECOPS_ROOT"
elif [ -d .specops ]; then SPECOPS=".specops"
else _top=$(git rev-parse --show-toplevel 2>/dev/null || true); SPECOPS="${_top:+$_top/}.specops"; fi

ask() { printf 'PR-GATE: ask (%s)\n' "$1"; exit 0; }
D="$SPECOPS/$FID"; SPEC="$D/spec.md"

case "${SPECOPS_PR_GATE:-}" in ask) ask "환경 변수 SPECOPS_PR_GATE=ask" ;; esac
if [ -f "$SPECOPS/config.yaml" ] && grep -qiE "^[[:space:]]*pr_gate:[[:space:]]*[\"']?ask[\"']?[[:space:]]*(#.*)?\$" "$SPECOPS/config.yaml"; then
  ask "설정 pr_gate: ask"
fi
[ -f "$SPEC" ] || ask "spec.md 가 없다"
grep -qE '^\*\*§batch\*\*:' "$SPEC" && ask "batch — 오케스트레이터가 batch PR 을 맡는다"
grep -qE '^\*\*§auto\*\*:[[:space:]]*true' "$SPEC" && ask "무인 — 가정 다이제스트를 확인한다"
grep -qE '^\*\*§(일괄|기본)\*\*:[[:space:]]*true' "$SPEC" || ask "단계별 확인(--step)"
# 결정 칸 = 접두를 뗀 뒤 첫 " — " 앞까지. 정규식의 글자 묶음이 아니라 문자열 연산으로 자른다 — LC_ALL=C 에서
#   한글·" — " 는 여러 바이트라 `[^—]` 같은 묶음은 바이트 단위로 어긋난다("는"의 끝 바이트가 "—" 의 끝 바이트와 같다).
consent=$(awk '
  /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:]+Z \[approval\] / {
    d = $0; sub(/^- [^ ]+ \[approval\] /, "", d)
    k = index(d, " — "); if (k > 0) d = substr(d, 1, k - 1)
    sub(/[[:space:]]+$/, "", d)
    want = "PR 생성 포함"; n = length(d); m = length(want)
    if (n == m && d == want) { print 1; exit }
    if (n > m && substr(d, n - m + 1) == want && substr(d, n - m, 1) == " ") { print 1; exit }
  }' "$D/dev-decisions.md" 2>/dev/null)
[ "$consent" = 1 ] || ask "승인 기록에 PR 생성 포함이 없다"

if [ -f "$D/evidence.md" ] && grep -qE '^## /demo' "$D/evidence.md"; then
  need=$(awk '/^## \/demo/ { v = ""; f = 1; next } f && /^## / { f = 0 } f && /^\*\*확인 필요\*\*:/ { v = $0 } END { print v }' "$D/evidence.md" \
    | sed -E 's/^\*\*확인 필요\*\*:[[:space:]]*//')
  case "$need" in
    no|no\ *|no\(*) ;;
    *) printf 'PR-GATE: auto-draft (데모 확인 필요 — 결과를 확인받기 전이다)\n'; exit 0 ;;
  esac
fi
echo "PR-GATE: auto"
