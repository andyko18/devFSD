#!/usr/bin/env bash
# test-statusline — AC-1~5 검증 (파싱·graceful·색상·install 주입·멱등)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SL="$PLUGIN/scripts/statusline.sh"
INST="$PLUGIN/scripts/statusline-install.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT

mkdir -p "$TD/.specops"
cat > "$TD/.specops/session-progress.md" <<'EOF'
## 20260615-hud-statusline · HUD statusline
- 2026-06-15 10:00 /verify PASS (evidence.md)
- 2026-06-15 09:00 /specify 완료 (spec.md)

## 20260101-old-fid · 옛 작업
- 2026-01-01 00:00 /lifecycle DONE
EOF

# T1.a AC-1: 정상 파싱
out=$(printf '{"cwd":"%s"}' "$TD" | bash "$SL")
if echo "$out" | grep -q "specops · 20260615-hud-statusline · /verify"; then
  PASS=$((PASS+1)); echo "PASS T1.a AC-1 정상 파싱"
else FAIL=$((FAIL+1)); echo "FAIL T1.a AC-1 ($out)"; fi

# T1.b AC-3: PASS=초록
if printf '%s' "$out" | grep -q $'\033\[32m'; then
  PASS=$((PASS+1)); echo "PASS T1.b AC-3 PASS=초록"
else FAIL=$((FAIL+1)); echo "FAIL T1.b AC-3 색상"; fi

# T1.c AC-3b: FAIL=빨강
cat > "$TD/.specops/session-progress.md" <<'EOF'
## 20260615-hud-statusline · HUD
- 2026-06-15 10:00 /verify FAIL (AC-2 미충족)
EOF
outf=$(printf '{"cwd":"%s"}' "$TD" | bash "$SL")
if printf '%s' "$outf" | grep -q $'\033\[31m'; then
  PASS=$((PASS+1)); echo "PASS T1.c AC-3b FAIL=빨강"
else FAIL=$((FAIL+1)); echo "FAIL T1.c AC-3b ($outf)"; fi

# T1.d AC-2: 부재 graceful
out2=$(printf '{"cwd":"/tmp/nonexistent-xyz123"}' | bash "$SL"); rc=$?
if [ $rc -eq 0 ] && echo "$out2" | grep -qF "◆ devFSD"; then
  PASS=$((PASS+1)); echo "PASS T1.d AC-2 부재 graceful (exit0)"
else FAIL=$((FAIL+1)); echo "FAIL T1.d AC-2 (rc=$rc out=$out2)"; fi

# T1.e AC-2b: 빈 stdin graceful (run-all 루트 CWD서도 fallback — C-1)
out3=$(printf '' | bash "$SL"); rc=$?
if [ $rc -eq 0 ] && echo "$out3" | grep -qF "◆ devFSD"; then
  PASS=$((PASS+1)); echo "PASS T1.e AC-2b 빈 stdin graceful"
else FAIL=$((FAIL+1)); echo "FAIL T1.e AC-2b (rc=$rc out=$out3)"; fi

# T1.f AC-6: untrusted-repo control-char strip — session-progress 의 step/status 에 심긴
#   ANSI ESC 가 statusline 출력으로 누출되면 터미널 escape injection. col/rst 외 ESC 0건이어야.
printf '## 20260615-evil \xc2\xb7 t\n- 2026-06-15 10:00 /step \033[31mEVIL\033]0;pwned\007\n' \
  > "$TD/.specops/session-progress.md"
oute=$(printf '{"cwd":"%s"}' "$TD" | bash "$SL")
# status=EVIL... 은 PASS/FAIL 미매칭 → col='' → 출력 ESC=주입 누출분만 남음
if printf '%s' "$oute" | grep -q $'\033'; then
  FAIL=$((FAIL+1)); echo "FAIL T1.f AC-6 control-char 누출 ($oute)"
else
  PASS=$((PASS+1)); echo "PASS T1.f AC-6 control-char strip"
fi

# T2.a AC-4: install 주입
mkdir -p "$TD/scripts"; cp "$SL" "$TD/scripts/statusline.sh"
( cd "$TD" && CLAUDE_PLUGIN_ROOT="$TD" bash "$INST" >/dev/null 2>&1 )
if [ -f "$TD/.claude/settings.json" ] && jq -e '.statusLine.command' "$TD/.claude/settings.json" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T2.a AC-4 settings.json statusLine 주입"
else FAIL=$((FAIL+1)); echo "FAIL T2.a AC-4 주입"; fi

# T2.b AC-4b: 기존 키 무손상 + 백업
echo '{"foo":"bar","statusLine":{"type":"command","command":"old"}}' > "$TD/.claude/settings.json"
( cd "$TD" && CLAUDE_PLUGIN_ROOT="$TD" bash "$INST" >/dev/null 2>&1 )
if jq -e '.foo=="bar"' "$TD/.claude/settings.json" >/dev/null 2>&1 && [ -f "$TD/.claude/settings.json.bak" ]; then
  PASS=$((PASS+1)); echo "PASS T2.b AC-4b 타 키 무손상 + 백업"
else FAIL=$((FAIL+1)); echo "FAIL T2.b AC-4b"; fi

# T2.c AC-5: 멱등
( cd "$TD" && CLAUDE_PLUGIN_ROOT="$TD" bash "$INST" >/dev/null 2>&1 )
h1=$(jq -S . "$TD/.claude/settings.json")
( cd "$TD" && CLAUDE_PLUGIN_ROOT="$TD" bash "$INST" >/dev/null 2>&1 )
h2=$(jq -S . "$TD/.claude/settings.json")
if [ "$h1" = "$h2" ]; then
  PASS=$((PASS+1)); echo "PASS T2.c AC-5 멱등"
else FAIL=$((FAIL+1)); echo "FAIL T2.c AC-5 멱등"; fi

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
