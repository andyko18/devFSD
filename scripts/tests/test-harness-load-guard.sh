#!/usr/bin/env bash
# test-harness-load-guard.sh — harness source test 전수 로드 가드 계약 (FID 20260711-harness-load-guard)
# 앵커 리터럴: "command -v finish" (Q5 고정) · 블랙리스트 3(run-all·dogfood-parallel-harness·harness 자신, Q6)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0

# 대상 판별: harness source AND NOT 블랙리스트
targets=$(grep -rl 'source.*harness.sh' "$PLUGIN/scripts/tests/" 2>/dev/null \
  | grep -vE '/run-all\.sh$|/dogfood-parallel-harness\.sh$|/harness\.sh$' | sort)
n=$(echo "$targets" | grep -c .)
[ "$n" -ge 34 ] || { echo "FATAL: 대상 $n < 34 — 블랙리스트 과매치 의심" >&2; exit 1; }

# ── T1: 대상 전수 가드 보유 (AC-1) ──
missing=0; miss_list=""
for f in $targets; do
  grep -q 'command -v finish' "$f" || { missing=$((missing+1)); miss_list="$miss_list $(basename "$f")"; }
done
[ "$missing" -eq 0 ] && ok "T1.a 대상 $n 개 전수 로드 가드 보유" || nope "T1.a 가드 누락" "$missing 개:$miss_list"

# ── T2: 가드는 source 다음 줄 (tail 무접촉 확인 — 가드가 파일 상단부) ──
# source 라인번호 < 가드 라인번호 이고 인접(±2) 인지 대상 전수 검사
ok_pos=0; tot=0
for f in $targets; do
  [ "$(basename "$f")" = "test-harness-load-guard.sh" ] && continue   # 자기 헤더주석 오탐 제외
  tot=$((tot+1))
  sline=$(grep -nE 'source.*harness\.sh"' "$f" | head -1 | cut -d: -f1)
  gline=$(grep -n 'command -v finish' "$f" | head -1 | cut -d: -f1)
  [ -n "$sline" ] && [ -n "$gline" ] && [ "$gline" -gt "$sline" ] && [ "$((gline-sline))" -le 2 ] && ok_pos=$((ok_pos+1))
done
[ "$ok_pos" -eq "$tot" ] && ok "T2.a 가드 위치 source 직후(전수 $tot)" || nope "T2.a 위치" "$ok_pos/$tot"

# ── T3: 되돌려-관찰 — source 경로 깬 sandbox 는 exit≠0 (AC-2) ──
sample=$(echo "$targets" | head -1)
tmp=$(mktemp)
sed 's#source "\([^"]*\)/harness.sh"#source "\1/NONEXISTENT-harness.sh"#' "$sample" > "$tmp"
chmod +x "$tmp"
bash "$tmp" >/dev/null 2>&1; rc=$?
rm -f "$tmp"
[ "$rc" -ne 0 ] && ok "T3.a source 실패 시 exit≠0 (가드 발동, rc=$rc)" || nope "T3.a red-green" "source 깼는데 exit 0 (가드 무력)"

echo ""
finish   # 요약행 출력 + FAIL==0 판정 (echo 중복 제거 — plan-reviewer M4)
