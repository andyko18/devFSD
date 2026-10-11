#!/usr/bin/env bash
# TDD RED 증거 관측 (warn-only 1단계) — 20260806
#
# 배경: `record-task-receipt.sh` 는 test_command 가 **PASS 일 때만** receipt 를 남긴다.
#   즉 GREEN 은 증명되지만 **"구현 전에 실패했는가"(RED)** 는 아무도 안 본다.
#   빠지는 것은 **공허한 테스트** — 구현 없이도 통과하는 테스트. 이번 세션에서
#   내 테스트가 공허하게 통과한 사례가 **7번** 나왔고 전부 mutation 에서만 드러났다.
#
# ★ 설계 근거(실측): 실패한 테스트 실행은 transcript 에서 `is_error` 를 **세우지 않는다**
#   — 본 세션 tool_result 658건 중 `FAIL=` 를 담은 187건의 is_error 는 **전부 false**.
#   advisor 게이트 때와 같은 교훈: 형태를 추측하면 영구 0-hit 이 된다. 내용 토큰으로 판정한다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-tdd-red.sh"

_tr() {  # $1=출력경로 — stdin 의 "cmd|content|..." 줄들을 transcript 로 변환
  : > "$1"
  local i=0 cmd content
  while IFS='|' read -r cmd content; do
    [ -n "$cmd" ] || continue
    i=$((i+1))
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"t%d","input":{"command":"%s"}}]}}\n' "$i" "$cmd" >> "$1"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t%d","content":"%s"}]}}\n' "$i" "$content" >> "$1"
  done
}
_fid() {  # $1=dir $2=fid $3=test_command
  mkdir -p "$1/.specops/$2"
  cat > "$1/.specops/$2/tasks.md" <<EOF
## 의존 그래프

\`\`\`yaml
tasks:
  - id: T1
    test_command: "$3"
    depends_on: []
    inputs: []
    outputs: [a.sh]
    ac: [AC-1]
\`\`\`
EOF
}

# T1: ★ RED(FAIL) → GREEN(PASS) 순서 → RED 증거 있음
TD=$(mktemp -d); _fid "$TD" 20260806-r "bash scripts/tests/test-x.sh"
_tr "$TD/tr.jsonl" <<'EOF'
bash scripts/tests/test-x.sh|PASS=0 FAIL=3
bash scripts/tests/test-x.sh|PASS=3 FAIL=0
EOF
out=$(cd "$TD" && SPECOPS_TRANSCRIPT="$TD/tr.jsonl" bash "$CHK" 20260806-r T1 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'RED' \
  && ok "T1 FAIL→PASS → RED 증거 확인" || nope "T1" "rc=$rc out=$out"
rm -rf "$TD"

# T2: ★ GREEN 만 (RED 없음) → 증거 없음 — 공허한 테스트 후보
TD=$(mktemp -d); _fid "$TD" 20260806-r "bash scripts/tests/test-x.sh"
_tr "$TD/tr.jsonl" <<'EOF'
bash scripts/tests/test-x.sh|PASS=3 FAIL=0
EOF
out=$(cd "$TD" && SPECOPS_TRANSCRIPT="$TD/tr.jsonl" bash "$CHK" 20260806-r T1 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qE 'RED 증거 없음|GREEN만' \
  && ok "T2 GREEN 만 → RED 증거 없음" || nope "T2" "rc=$rc out=$out"
rm -rf "$TD"

# T3: 순서 역전 — PASS 먼저, 그 뒤 FAIL → RED 아님 (구현 후 깨진 것)
TD=$(mktemp -d); _fid "$TD" 20260806-r "bash scripts/tests/test-x.sh"
_tr "$TD/tr.jsonl" <<'EOF'
bash scripts/tests/test-x.sh|PASS=3 FAIL=0
bash scripts/tests/test-x.sh|PASS=0 FAIL=2
EOF
(cd "$TD" && SPECOPS_TRANSCRIPT="$TD/tr.jsonl" bash "$CHK" 20260806-r T1 >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T3 PASS→FAIL 순서 → RED 불인정" || nope "T3" "rc=$rc"
rm -rf "$TD"

# T4: 다른 명령의 FAIL 은 근거 아님 (명령 매칭)
TD=$(mktemp -d); _fid "$TD" 20260806-r "bash scripts/tests/test-x.sh"
_tr "$TD/tr.jsonl" <<'EOF'
bash scripts/tests/test-other.sh|PASS=0 FAIL=5
bash scripts/tests/test-x.sh|PASS=3 FAIL=0
EOF
(cd "$TD" && SPECOPS_TRANSCRIPT="$TD/tr.jsonl" bash "$CHK" 20260806-r T1 >/dev/null 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T4 타 명령 FAIL → 근거 불인정" || nope "T4" "rc=$rc"
rm -rf "$TD"

# T5: pytest 형식 실패 토큰 인식 (러너 다양성)
TD=$(mktemp -d); _fid "$TD" 20260806-r "pytest tests/"
_tr "$TD/tr.jsonl" <<'EOF'
pytest tests/|2 failed, 1 passed in 0.3s
pytest tests/|3 passed in 0.2s
EOF
(cd "$TD" && SPECOPS_TRANSCRIPT="$TD/tr.jsonl" bash "$CHK" 20260806-r T1 >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "T5 pytest 실패 토큰 인식" || nope "T5" "rc=$rc"
rm -rf "$TD"

# T6: transcript 부재 → 판정 불가 fail-open (rc=2)
TD=$(mktemp -d); _fid "$TD" 20260806-r "bash scripts/tests/test-x.sh"
(cd "$TD" && SPECOPS_TRANSCRIPT="$TD/none.jsonl" bash "$CHK" 20260806-r T1 >/dev/null 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "T6 transcript 부재 → rc=2 fail-open" || nope "T6" "rc=$rc"
rm -rf "$TD"

# T7: tasks.md·test_command 부재 → rc=2
TD=$(mktemp -d); mkdir -p "$TD/.specops/20260806-r"
(cd "$TD" && SPECOPS_TRANSCRIPT="/dev/null" bash "$CHK" 20260806-r T1 >/dev/null 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "T7 tasks.md 부재 → rc=2" || nope "T7" "rc=$rc"
rm -rf "$TD"

# T8: receipt 배선 — 차단하지 않고 필드로 남긴다(warn-only 1단계)
grep -q 'check-tdd-red.sh' "$PLUGIN/scripts/_internal/record-task-receipt.sh" \
  && ok "T8 record-task-receipt 배선" || nope "T8" "미배선"

# T9: warn-only 계약 명시 (차단 전환 시 바꿀 지점)
grep -qE 'warn-only|비차단' "$CHK" \
  && ok "T9 warn-only 계약 명시" || nope "T9" "계약 불명"

finish
