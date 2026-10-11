#!/usr/bin/env bash
# test-notify — AC-1~5 검증 (메시지 구성·matcher·graceful·토글·hooks.json 정합)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
NOTIFY="$PLUGIN/hooks/notify.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT

mkdir -p "$TD/.specops"
cat > "$TD/.specops/session-progress.md" <<'EOF'
## 20260615-notify-hook · 알림 연동
- 2026-06-15 10:00 /implement DONE (T1~T3)
- 2026-06-15 09:00 /specify 완료
EOF

# T1.a AC-1/2: idle_prompt + cwd → 입력 대기 · FID /step (end-anchor 단언)
out=$(printf '{"matcher":"idle_prompt","cwd":"%s"}' "$TD" | SPECOPS_CONFIG="$TD/none.yaml" SPECOPS_NOTIFY_DRYRUN=1 bash "$NOTIFY")
if echo "$out" | grep -qE "입력 대기 · 20260615-notify-hook /implement$"; then
  PASS=$((PASS+1)); echo "PASS T1.a AC-1/2 idle 메시지"
else FAIL=$((FAIL+1)); echo "FAIL T1.a ($out)"; fi

# T1.b AC-2: permission_prompt → 권한 대기 · FID (step 누설 없음 — end-anchor 단언)
out2=$(printf '{"matcher":"permission_prompt","cwd":"%s"}' "$TD" | SPECOPS_CONFIG="$TD/none.yaml" SPECOPS_NOTIFY_DRYRUN=1 bash "$NOTIFY")
if echo "$out2" | grep -qE "권한 대기 · 20260615-notify-hook$"; then
  PASS=$((PASS+1)); echo "PASS T1.b AC-2 permission 메시지(step 제외)"
else FAIL=$((FAIL+1)); echo "FAIL T1.b ($out2)"; fi

# T1.c AC-2: cwd 없음 → suffix 생략 (입력 대기만)
out3=$(printf '{"matcher":"idle_prompt"}' | SPECOPS_CONFIG="$TD/none.yaml" SPECOPS_NOTIFY_DRYRUN=1 bash "$NOTIFY"); rc=$?
if [ $rc -eq 0 ] && echo "$out3" | grep -qE "입력 대기$"; then
  PASS=$((PASS+1)); echo "PASS T1.c AC-2 cwd 없음 suffix 생략"
else FAIL=$((FAIL+1)); echo "FAIL T1.c (rc=$rc out=$out3)"; fi

# T1.d AC-2: 제목 specops-ko
if echo "$out" | grep -q "^specops-ko"; then
  PASS=$((PASS+1)); echo "PASS T1.d AC-2 제목"
else FAIL=$((FAIL+1)); echo "FAIL T1.d 제목"; fi

# T1.e 계약: 빈 stdin graceful exit 0
out4=$(printf '' | SPECOPS_CONFIG="$TD/none.yaml" SPECOPS_NOTIFY_DRYRUN=1 bash "$NOTIFY"); rc=$?
if [ $rc -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T1.e 빈 stdin graceful exit 0"
else FAIL=$((FAIL+1)); echo "FAIL T1.e (rc=$rc)"; fi

# T1.f AC-3: jq만 부재(coreutils 유지) → line 13 jq 가드 graceful exit 0
mkdir -p "$TD/jqless-bin"
for t in dirname bash cat awk grep sed cut env printf; do
  src=$(command -v "$t" 2>/dev/null) && ln -sf "$src" "$TD/jqless-bin/$t"
done
out5=$(printf '{"matcher":"idle_prompt","cwd":"%s"}' "$TD" | SPECOPS_CONFIG="$TD/none.yaml" SPECOPS_NOTIFY_DRYRUN=1 PATH="$TD/jqless-bin" bash "$NOTIFY" 2>/dev/null); rc=$?
if [ $rc -eq 0 ] && [ -z "$out5" ]; then
  PASS=$((PASS+1)); echo "PASS T1.f AC-3 jq만 부재 line13 가드 graceful exit 0"
else FAIL=$((FAIL+1)); echo "FAIL T1.f (rc=$rc out=$out5)"; fi

# T1.g AC-3: notify.sh에 osascript/notify-send 분기 존재 (정적)
if grep -q 'osascript' "$NOTIFY" && grep -q 'notify-send' "$NOTIFY"; then
  PASS=$((PASS+1)); echo "PASS T1.g AC-3 osascript/notify-send 분기 존재"
else FAIL=$((FAIL+1)); echo "FAIL T1.g AC-3 분기"; fi

# T1.h AC-4: is-hook-enabled notify OFF → 무출력 + exit 0 (pyyaml 조건부)
if python3 -c "import yaml" 2>/dev/null; then
  printf 'hooks:\n  notify:\n    enabled: false\n' > "$TD/off.yaml"
  out6=$(printf '{"matcher":"idle_prompt","cwd":"%s"}' "$TD" | SPECOPS_CONFIG="$TD/off.yaml" SPECOPS_NOTIFY_DRYRUN=1 bash "$NOTIFY"); rc=$?
  if [ $rc -eq 0 ] && [ -z "$out6" ]; then
    PASS=$((PASS+1)); echo "PASS T1.h AC-4 토글 OFF 무출력 exit 0"
  else FAIL=$((FAIL+1)); echo "FAIL T1.h AC-4 (rc=$rc out=$out6)"; fi
else
  echo "SKIP T1.h AC-4 (pyyaml 부재 — is-hook-enabled 토글 검증 불가)"
fi

# T2.a AC-5: hooks.json Notification 정합
if jq -e '.hooks.Notification | length == 2' "$PLUGIN/hooks/hooks.json" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T2.a AC-5 Notification 2 matcher"
else FAIL=$((FAIL+1)); echo "FAIL T2.a Notification"; fi

# T2.b AC-5/AC-R-1: Stop 3종(+freecomment-capture) — 기존 2종(stop-governance·ensure-session-progress) 무손상
if jq -e '.hooks.Stop | length == 3' "$PLUGIN/hooks/hooks.json" >/dev/null 2>&1 \
   && jq -e '[.hooks.Stop[].hooks[0].command] | map(select(test("stop-governance|ensure-session-progress"))) | length == 2' "$PLUGIN/hooks/hooks.json" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T2.b AC-R-1 Stop 3종 — 기존 2종 무손상"
else FAIL=$((FAIL+1)); echo "FAIL T2.b Stop 무손상"; fi

# T2.c AC-5: async true
if jq -e '.hooks.Notification[0].hooks[0].async == true' "$PLUGIN/hooks/hooks.json" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T2.c AC-5 async true"
else FAIL=$((FAIL+1)); echo "FAIL T2.c async"; fi

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
