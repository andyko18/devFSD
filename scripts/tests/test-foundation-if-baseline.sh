#!/usr/bin/env bash
# foundation IF baseline 마커 불변 — 20260812
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-foundation-if-baseline.sh"

_mk_api() {
  local td="$1"
  mkdir -p "$td/.specops/memory"
  cat > "$td/.specops/memory/api-spec.md" <<'EOF'
# API
<!-- foundation-baseline:start -->
| GET | `/health` | — | ok |
<!-- foundation-baseline:end -->
| GET | `/v1/items` | — | list |
EOF
  cat > "$td/.specops/memory/data-model.md" <<'EOF'
# DM
<!-- foundation-baseline:start -->
| sessions | id PK |
<!-- foundation-baseline:end -->
| items | id PK |
EOF
}

# T1: snapshot → change baseline → verify FAIL
TD=$(mktemp -d)
_mk_api "$TD"
snap="$TD/snap.sha"
out=$(cd "$TD" && bash "$CHK" snapshot "$snap" 2>&1); rc=$?
[ "$rc" -eq 0 ] || { nope "T1a snapshot" "rc=$rc out=$out"; rm -rf "$TD"; finish; exit 1; }
# mutate inside marker
sed -i.bak 's|/health|/ready|' "$TD/.specops/memory/api-spec.md"
out=$(cd "$TD" && bash "$CHK" verify "$snap" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'FOUNDATION-IF-BASELINE: FAIL' \
  && [ "$rc" -eq 1 ] \
  && ok "T1 change baseline → FAIL" \
  || nope "T1" "rc=$rc out=$out"
rm -rf "$TD"

# T2: no change → PASS
TD=$(mktemp -d)
_mk_api "$TD"
snap="$TD/snap.sha"
(cd "$TD" && bash "$CHK" snapshot "$snap" >/dev/null)
out=$(cd "$TD" && bash "$CHK" verify "$snap" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'FOUNDATION-IF-BASELINE: PASS' \
  && [ "$rc" -eq 0 ] \
  && ok "T2 unchanged → PASS" \
  || nope "T2" "rc=$rc out=$out"
rm -rf "$TD"

# T3: no markers → SKIP
TD=$(mktemp -d)
mkdir -p "$TD/.specops/memory"
echo '# bare' > "$TD/.specops/memory/api-spec.md"
echo '# bare' > "$TD/.specops/memory/data-model.md"
snap="$TD/snap.sha"
out=$(cd "$TD" && bash "$CHK" snapshot "$snap" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'SKIP' && [ "$rc" -eq 0 ] || { nope "T3a" "out=$out"; rm -rf "$TD"; finish; exit 1; }
out=$(cd "$TD" && bash "$CHK" verify "$snap" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'SKIP' \
  && [ "$rc" -eq 0 ] \
  && ok "T3 no markers → SKIP" \
  || nope "T3" "rc=$rc out=$out"
rm -rf "$TD"

# T4: broken pair → FAIL
TD=$(mktemp -d)
mkdir -p "$TD/.specops/memory"
printf '%s\n' '<!-- foundation-baseline:start -->' '| GET | /x |' > "$TD/.specops/memory/api-spec.md"
echo '# ok' > "$TD/.specops/memory/data-model.md"
out=$(cd "$TD" && bash "$CHK" snapshot "$TD/s.sha" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'FAIL' \
  && [ "$rc" -eq 1 ] \
  && ok "T4 broken pair → FAIL" \
  || nope "T4" "rc=$rc out=$out"
rm -rf "$TD"

# T5: start-all wiring
grep -q 'check-foundation-if-baseline\.sh' "$PLUGIN/commands/start-all.md" \
  && grep -q 'foundation-if-baseline\.sha' "$PLUGIN/commands/start-all.md" \
  && grep -q 'snapshot' "$PLUGIN/commands/start-all.md" \
  && grep -q 'verify' "$PLUGIN/commands/start-all.md" \
  && ok "T5 start-all wiring" \
  || nope "T5" "missing"

# T6: start-all-auto
grep -q 'check-foundation-if-baseline\|foundation-baseline' "$PLUGIN/commands/start-all-auto.md" \
  && ok "T6 start-all-auto" \
  || nope "T6" "auto missing"

# T7: specifying-ko foundation marker
grep -q 'foundation-baseline' "$PLUGIN/skills/specifying-ko/SKILL.md" \
  && grep -q 'check-foundation-if-baseline' "$PLUGIN/skills/specifying-ko/SKILL.md" \
  && ok "T7 specifying-ko marker duty" \
  || nope "T7" "skill missing"

# T8 mutation: force sort_now=sort_snap → T1 would PASS
TD=$(mktemp -d)
_mk_api "$TD"
snap="$TD/snap.sha"
(cd "$TD" && bash "$CHK" snapshot "$snap" >/dev/null)
sed -i.bak 's|/health|/ready|' "$TD/.specops/memory/api-spec.md"
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
grep -q 'foundation-baseline' "$PLUGIN/agents/design-reviewer-ko.md" \
  && grep -q 'Critical' "$PLUGIN/agents/design-reviewer-ko.md" \
  && ok "T9 design-reviewer baseline Critical" \
  || nope "T9" "reviewer missing"

# T10: append outside marker still PASS
TD=$(mktemp -d)
_mk_api "$TD"
snap="$TD/snap.sha"
(cd "$TD" && bash "$CHK" snapshot "$snap" >/dev/null)
echo '| GET | `/v1/new` | — | n |' >> "$TD/.specops/memory/api-spec.md"
out=$(cd "$TD" && bash "$CHK" verify "$snap" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'PASS' \
  && [ "$rc" -eq 0 ] \
  && ok "T10 outside append → PASS" \
  || nope "T10" "rc=$rc out=$out"
rm -rf "$TD"

finish
