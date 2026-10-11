#!/usr/bin/env bash
# self-config-collect.sh 검증
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
P="$(cd "$(dirname "$0")/../.." && pwd)"
SC="$P/scripts/self-config-collect.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
nope(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

[ -f "$SC" ] && [ -x "$SC" ] || nope "T1.a collect.sh 부재/비실행"

# AC-1: 전체 표면 마커 포함
out="$(bash "$SC" "$P" 2>/dev/null)"
printf '%s' "$out" | grep -q "===== hook:" || nope "T1.b AC-1 hooks 섹션 누락"
printf '%s' "$out" | grep -q "===== skill:" || nope "T1.c AC-1 skills 섹션 누락"
printf '%s' "$out" | grep -q "===== rules:" || nope "T1.d AC-1 rules 섹션 누락"
printf '%s' "$out" | grep -q "===== plugin:" || nope "T1.e AC-1 plugin 섹션 누락"
printf '%s' "$out" | grep -q "===== agent:" || nope "T1.e2 AC-1 agents 섹션 누락(번들 범위 확대)"
printf '%s' "$out" | grep -q "===== script:" || nope "T1.e3 AC-1 scripts 섹션 누락(번들 범위 확대)"
# 번들 범위 확대 회귀: kill-switch·reviewer frontmatter 실제 포함 보장
printf '%s' "$out" | grep -q "script: scripts/_internal/is-hook-enabled.sh" || nope "T1.e4 거버넌스 kill-switch 미수집"
printf '%s' "$out" | grep -q "agent: agents/code-reviewer-ko.md" || nope "T1.e5 reviewer agent frontmatter 미수집"
# scripts/tests 는 감사 표면 아님 — 제외 보장(번들 폭증 방지)
printf '%s' "$out" | grep -q "script: scripts/tests/" && nope "T1.e6 scripts/tests 오수집(번들 폭증)" || ok

# AC-9: 플러그인 마커 부재 경로 거부
tmp="$(mktemp -d)" || exit 1
bash "$SC" "$tmp" >/dev/null 2>&1 && nope "T1.f AC-9 비-플러그인 경로 거부 실패" || ok
rm -rf "$tmp"

# AC-2: graceful exit 0
bash "$SC" "$P" >/dev/null 2>&1 && ok || nope "T1.g AC-2 graceful exit 0 실패"

# AC-2: 부분부재 — plugin.json 마커만 있는 루트 → exit 0 + 누락 경고 + 가용표면-only
pt="$(mktemp -d)" || exit 1
mkdir -p "$pt/.claude-plugin"
printf '{}\n' > "$pt/.claude-plugin/plugin.json"
perr="$(bash "$SC" "$pt" 2>&1 >/dev/null)"
bash "$SC" "$pt" >/dev/null 2>&1 && ok || nope "T1.h AC-2 부분부재 exit 0 실패"
printf '%s' "$perr" | grep -q "경고" || nope "T1.i AC-2 누락 표면 경고 미출력"
pout="$(bash "$SC" "$pt" 2>/dev/null)"
printf '%s' "$pout" | grep -q "===== plugin:" || nope "T1.j AC-2 가용표면(plugin) 누락"
printf '%s' "$pout" | grep -q "===== hook:" && nope "T1.k AC-2 부재표면(hook) 오출력" || ok
rm -rf "$pt"

# backlog #1: 공백 포함 ROOT 경로에서 표면 silent-drop 없음 (단어분리 회귀 가드)
spbase="$(mktemp -d)" || exit 1
sp="$spbase/dir with space"
mkdir -p "$sp/.claude-plugin" "$sp/hooks"
printf '{}\n' > "$sp/.claude-plugin/plugin.json"
printf '#!/usr/bin/env bash\n' > "$sp/hooks/sample.sh"
spout="$(bash "$SC" "$sp" 2>/dev/null)"
printf '%s' "$spout" | grep -q "===== hook:" || nope "T1.l 공백경로 hook 표면 silent-drop"
rm -rf "$spbase"

# AC-R-1: 기존 security-scan.sh 무인자 동작 무변경
rout="$(bash "$P/scripts/security-scan.sh" "$P" 2>/dev/null)"
printf '%s' "$rout" | grep -qE '^SECURITY: crit=[0-9]+ high=[0-9]+ med=[0-9]+' || nope "T3.a AC-R-1 기존 SAST 출력 형식 회귀"

echo "── test-self-config-collect: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
