#!/usr/bin/env bash
# pr-gate.sh — PR 생성 단계에서 물을지 판정 (20261114)
#   하류 실측: 작업 10건에서 "추천대로·진행·승인" 만 친 발화가 38회였고, PR 생성 질문은 매번 추천안 그대로 답했다.
#   승인 묶음에 "PR 생성 포함"을 싣고 그 기록이 있으면 묻지 않는다. 판단이 서지 않으면 묻는다(ask 가 기본값).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

PG="$PLUGIN/scripts/pr-gate.sh"
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
F=20261114-sample-fid
ck() { if [ "$2" = "$3" ]; then ok "$1"; else nope "$1" "exp '$3' got '$2'"; fi; }

# mk <이름> <spec 머리 라벨 줄…> — FID 폴더와 spec 을 만든다. 승인 기록·데모는 따로 붙인다.
mk() {
  local r="$SB/$1"; shift
  mkdir -p "$r/$F"
  { printf '# 명세\n\n'; for l in "$@"; do printf '%s\n' "$l"; done; printf '\n## 1. 목표\n\nx\n'; } > "$r/$F/spec.md"
  printf '%s' "$r"
}
approve() { printf -- '- 2026-11-14T00:00:00Z [approval] %s\n' "$2" >> "$1/$F/dev-decisions.md"; }
demo() { printf '\n## /demo — 2026-11-14T00:00:00Z\n\n**종류**: %s\n**확인 필요**: %s\n' "$2" "$3" >> "$1/$F/evidence.md"; }
run() { OUT=$(env -u SPECOPS_PR_GATE SPECOPS_ROOT="$1" bash "$PG" decide "$F" 2>"$SB/err"); RC=$?; }

# ── 자동: 승인에 PR 이 들어 있었고 확인할 결과가 없다 ──
R=$(mk a1 '**§일괄**: true'); approve "$R" '승인 묶음 승인 · PR 생성 포함 — 요지'; demo "$R" 내부 'no (내부 변경)'
run "$R"; ck "G1.a ★ §일괄 + 승인에 PR 포함 + 데모 확인 불필요 → auto (rc 0)" "$RC|$OUT" "0|PR-GATE: auto"
R=$(mk a2 '**§기본**: true'); approve "$R" 'spec 1장 승인 · PR 생성 포함'
run "$R"; ck "G1.b 기본 경로(§기본) + 승인에 PR 포함 → auto (데모 절이 없어도)" "$RC|$OUT" "0|PR-GATE: auto"

# ── 초안으로 자동: 사용자가 보는 결과가 바뀌었다 ──
R=$(mk d1 '**§일괄**: true'); approve "$R" '승인 묶음 승인 · PR 생성 포함'; demo "$R" 화면 'yes (화면 변경)'
run "$R"; ck "G2.a ★ 데모가 확인 필요 yes → auto-draft (초안 PR — 결과 확인 전에 머지되지 않게)" "$RC|${OUT%% (*}" "0|PR-GATE: auto-draft"
demo "$R" 내부 'no (고친 뒤 재확인)'
run "$R"; ck "G2.b 데모 절이 여럿이면 마지막 절을 본다(고친 뒤 no → auto)" "$OUT" "PR-GATE: auto"
R=$(mk d2 '**§일괄**: true'); approve "$R" '승인 묶음 승인 · PR 생성 포함'; demo "$R" 미분류 '예'
run "$R"; ck "G2.c 확인 필요 칸이 yes·no 가 아니면 애매한 쪽 → auto-draft" "${OUT%% (*}" "PR-GATE: auto-draft"

# ── 묻는다: 동의가 없거나 사람이 봐야 하는 모드 ──
R=$(mk k1 '**§일괄**: true'); approve "$R" '승인 묶음 승인 — 요지'
run "$R"; ck "G3.a ★ 승인 기록에 PR 포함이 없다(이 버전 전에 승인한 작업) → ask" "$RC|${OUT%% (*}" "0|PR-GATE: ask"
R=$(mk k2 '**§일괄**: true')
run "$R"; ck "G3.b 승인 기록 자체가 없다 → ask" "${OUT%% (*}" "PR-GATE: ask"
R=$(mk k3 '**§유형**: 신규'); approve "$R" '승인 묶음 승인 · PR 생성 포함'
run "$R"; ck "G3.c §일괄·§기본 이 아니다(--step 단계별 확인) → ask" "${OUT%% (*}" "PR-GATE: ask"
R=$(mk k4 '**§일괄**: true' '**§auto**: true'); approve "$R" '승인 묶음 승인 · PR 생성 포함'
run "$R"; ck "G3.d ★ 무인(§auto)은 가정 다이제스트를 사람이 본다 → ask" "${OUT%% (*}" "PR-GATE: ask"
R=$(mk k5 '**§일괄**: true' '**§batch**: b1'); approve "$R" '승인 묶음 승인 · PR 생성 포함'
run "$R"; ck "G3.e batch FR 은 오케스트레이터 소관 → ask" "${OUT%% (*}" "PR-GATE: ask"
R=$(mk k6 '**§일괄**: true'); approve "$R" '승인 묶음 승인 · PR 생성 포함'; printf 'pr_gate: ask\n' > "$R/config.yaml"
run "$R"; ck "G3.f 설정 pr_gate: ask → ask (자동 조건을 다 채워도)" "${OUT%% (*}" "PR-GATE: ask"
rm -f "$R/config.yaml"
OUT=$(SPECOPS_PR_GATE=ask SPECOPS_ROOT="$R" bash "$PG" decide "$F" 2>/dev/null)
ck "G3.g 환경 변수 SPECOPS_PR_GATE=ask → ask" "${OUT%% (*}" "PR-GATE: ask"
R=$(mk k7 '설명 줄에 **§일괄**: true 가 섞였다'); approve "$R" '승인 묶음 승인 · PR 생성 포함'
run "$R"; ck "G3.h 라벨은 줄 머리만 읽는다(본문 속 언급은 라벨이 아니다) → ask" "${OUT%% (*}" "PR-GATE: ask"
R=$(mk k8 '**§일괄**: true'); printf -- '- 손으로 쓴 줄 [approval] PR 생성 포함\n' >> "$R/$F/dev-decisions.md"
run "$R"; ck "G3.i 기록 스크립트 형식(시각 + [approval])이 아닌 줄은 동의로 치지 않는다 → ask" "${OUT%% (*}" "PR-GATE: ask"
R=$(mk k9 '**§일괄**: true'); printf -- '- 2026-11-14T00:00:00Z [backlog] PR 생성 포함 여부 검토\n' >> "$R/$F/dev-decisions.md"
run "$R"; ck "G3.j approval 이 아닌 종류의 줄에 같은 말이 있어도 동의가 아니다 → ask" "${OUT%% (*}" "PR-GATE: ask"

# ── 판정 불가는 묻는 쪽 · 사용 오류 ──
mkdir -p "$SB/n1/$F"
run "$SB/n1"; ck "G4.a spec.md 가 없다 → ask (rc 0 — 흐름을 끊지 않는다)" "$RC|${OUT%% (*}" "0|PR-GATE: ask"
run "$SB/none"; ck "G4.b FID 폴더가 없다 → ask" "$RC|${OUT%% (*}" "0|PR-GATE: ask"
OUT=$(SPECOPS_ROOT="$SB/a1" bash "$PG" decide 'bad fid' 2>/dev/null); RC=$?
ck "G4.c FID 형식이 틀리면 rc 2 · stdout 비움" "$RC|$OUT" "2|"
OUT=$(SPECOPS_ROOT="$SB/a1" bash "$PG" 2>/dev/null); RC=$?
ck "G4.d 인자 없으면 rc 2" "$RC" "2"
run "$SB/a1"; ck "G4.e 출력은 항상 1줄" "$(printf '%s\n' "$OUT" | grep -c .)" "1"

# ── 읽기 전용 ──
B=$(find "$SB/d1" -type f -exec cksum {} + | cksum); run "$SB/d1"; A=$(find "$SB/d1" -type f -exec cksum {} + | cksum)
ck "G5.a 판정은 아무것도 쓰지 않는다" "$A" "$B"

# ── 배선: 승인 기록을 남기는 쪽과 읽는 쪽이 같은 말을 쓴다 ──
grep -qF 'PR 생성 포함' "$PLUGIN/scripts/basic-path.sh" \
  && ok "G6.a 기본 경로 승인(basic-path.sh approve)이 'PR 생성 포함' 을 기록한다" || nope "G6.a" "basic-path.sh 에 문구 없음"
grep -qF 'PR 생성 포함' "$PLUGIN/skills/specifying-ko/once-approval.md" \
  && ok "G6.b 풀 경로 승인 묶음(once-approval.md)이 'PR 생성 포함' 을 기록한다" || nope "G6.b" "once-approval.md 에 문구 없음"
grep -qF 'pr-gate.sh decide' "$PLUGIN/skills/performance-test-ko/SKILL.md" && grep -qF 'pr-gate.sh decide' "$PLUGIN/commands/basic.md" \
  && ok "G6.c 두 경로의 PR 단계가 판정 스크립트를 부른다" || nope "G6.c" "pr-gate.sh decide 호출 없음"
grep -qF '머지는 자동으로 하지 않는다' "$PLUGIN/skills/performance-test-ko/SKILL.md" && grep -qF '머지는 자동으로 하지 않는다' "$PLUGIN/commands/basic.md" \
  && grep -qF '머지는 자동으로 하지 않는다' "$PLUGIN/skills/specifying-ko/once-approval.md" \
  && ok "G6.d ★ 두 경로 모두 머지는 자동으로 하지 않는다고 적는다" || nope "G6.d" "머지 금지 문구 없음"

finish
