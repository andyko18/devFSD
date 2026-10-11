#!/usr/bin/env bash
# foundation 셸 screens 불변 — 20260812
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-foundation-shell-baseline.sh"

_mk_shell() {
  local td="$1"
  mkdir -p "$td/screens"
  cat > "$td/screens/app-shell.md" <<'EOF'
# App Shell
<!-- foundation-shell -->
## 목적
공통 레이아웃
## Layout
sidebar + main
## Components
AppShell
## States
default
## Interactions
nav click
## 필드 정의표
—
## 데이터 소스
—
## 에러 메시지
—
EOF
  cat > "$td/screens/app-shell.html" <<'EOF'
<html><body class="app-shell">chrome</body></html>
EOF
}

# T1: snapshot → change shell → verify FAIL
TD=$(mktemp -d)
_mk_shell "$TD"
snap="$TD/snap.sha"
out=$(cd "$TD" && bash "$CHK" snapshot "$snap" 2>&1); rc=$?
[ "$rc" -eq 0 ] || { nope "T1a snapshot" "rc=$rc out=$out"; rm -rf "$TD"; finish; exit 1; }
echo ' MUTATED' >> "$TD/screens/app-shell.md"
out=$(cd "$TD" && bash "$CHK" verify "$snap" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'FOUNDATION-SHELL-BASELINE: FAIL' \
  && [ "$rc" -eq 1 ] \
  && ok "T1 change shell → FAIL" \
  || nope "T1" "rc=$rc out=$out"
rm -rf "$TD"

# T2: unchanged → PASS
TD=$(mktemp -d)
_mk_shell "$TD"
snap="$TD/snap.sha"
(cd "$TD" && bash "$CHK" snapshot "$snap" >/dev/null)
out=$(cd "$TD" && bash "$CHK" verify "$snap" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'FOUNDATION-SHELL-BASELINE: PASS' \
  && [ "$rc" -eq 0 ] \
  && ok "T2 unchanged → PASS" \
  || nope "T2" "rc=$rc out=$out"
rm -rf "$TD"

# T3: no shell markers → SKIP
TD=$(mktemp -d)
mkdir -p "$TD/screens"
echo '# dashboard' > "$TD/screens/dashboard.md"
snap="$TD/snap.sha"
out=$(cd "$TD" && bash "$CHK" snapshot "$snap" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'SKIP' && [ "$rc" -eq 0 ] || { nope "T3a" "out=$out"; rm -rf "$TD"; finish; exit 1; }
out=$(cd "$TD" && bash "$CHK" verify "$snap" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'SKIP' \
  && [ "$rc" -eq 0 ] \
  && ok "T3 no shell → SKIP" \
  || nope "T3" "rc=$rc out=$out"
rm -rf "$TD"

# T4: allowlist 밖 + 마커만 있어도 snapshot 비포함
TD=$(mktemp -d)
mkdir -p "$TD/screens"
printf '%s\n' '# Dash' '<!-- foundation-shell -->' > "$TD/screens/dashboard.md"
_mk_shell "$TD"
snap="$TD/snap.sha"
(cd "$TD" && bash "$CHK" snapshot "$snap" >/dev/null)
grep -q 'app-shell' "$snap" || { nope "T4a" "missing shell"; rm -rf "$TD"; finish; exit 1; }
grep -q 'dashboard' "$snap" \
  && nope "T4" "dashboard should not be in snap" \
  || ok "T4 allowlist 밖 비포함"
rm -rf "$TD"

# T5: start-all wiring
grep -q 'check-foundation-shell-baseline\.sh' "$PLUGIN/commands/start-all.md" \
  && grep -q 'foundation-shell-baseline\.sha' "$PLUGIN/commands/start-all.md" \
  && ok "T5 start-all wiring" \
  || nope "T5" "missing"

# T6: start-all-auto
grep -q 'foundation-shell\|check-foundation-shell-baseline' "$PLUGIN/commands/start-all-auto.md" \
  && ok "T6 start-all-auto" \
  || nope "T6" "auto missing"

# T7: specifying-ko foundation shell duty
grep -q 'foundation-shell' "$PLUGIN/skills/specifying-ko/SKILL.md" \
  && grep -q 'app-shell' "$PLUGIN/skills/specifying-ko/SKILL.md" \
  && ok "T7 specifying-ko shell duty" \
  || nope "T7" "skill missing"

# T8 mutation: force sort_now=sort_snap → T1 would PASS
TD=$(mktemp -d)
_mk_shell "$TD"
snap="$TD/snap.sha"
(cd "$TD" && bash "$CHK" snapshot "$snap" >/dev/null)
echo ' MUTATED' >> "$TD/screens/app-shell.md"
mut=$(mktemp)
awk '
  /sort_now=\$\(printf/ { print; print "    sort_now=$sort_snap"; next }
  { print }
' "$CHK" > "$mut"
out=$(cd "$TD" && bash "$mut" verify "$snap" 2>&1); rc=$?
if printf '%s' "$out" | grep -q 'PASS' && [ "$rc" -eq 0 ]; then
  out_real=$(cd "$TD" && bash "$CHK" verify "$snap" 2>&1); rc_real=$?
  [ "$rc_real" -eq 1 ] \
    && ok "T8 mutation: compare neutered → PASS (비-vacuous)" \
    || nope "T8" "real not FAIL rc=$rc_real out=$out_real"
else
  nope "T8" "mutated still fails rc=$rc out=$out"
fi
rm -rf "$TD" "$mut"

# T9: design-reviewer Critical
grep -q 'foundation-shell' "$PLUGIN/agents/design-reviewer-ko.md" \
  && grep -q 'Critical' "$PLUGIN/agents/design-reviewer-ko.md" \
  && ok "T9 design-reviewer shell Critical" \
  || nope "T9" "reviewer missing"

# T10: feature screen append → shell PASS
TD=$(mktemp -d)
_mk_shell "$TD"
snap="$TD/snap.sha"
(cd "$TD" && bash "$CHK" snapshot "$snap" >/dev/null)
echo '# dashboard feature' > "$TD/screens/dashboard.md"
out=$(cd "$TD" && bash "$CHK" verify "$snap" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'PASS' \
  && [ "$rc" -eq 0 ] \
  && ok "T10 feature append → PASS" \
  || nope "T10" "rc=$rc out=$out"
rm -rf "$TD"

finish
