#!/usr/bin/env bash
# specops-ko v0.2 · scripts/diff-upstream.sh 검증 (offline fixture 중심)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
SCRIPT="$(pwd)/scripts/_internal/diff-upstream.sh"

make_sandbox() {
  local sb=$1
  mkdir -p "$sb"/{commands,agents,skills,knowledge,docs,scripts/_internal,.specops-cache/upstream}
  cp "$SCRIPT" "$sb/scripts/_internal/diff-upstream.sh"
  chmod +x "$sb/scripts/_internal/diff-upstream.sh"
}

# T1 unknown flag
err=$(bash "$SCRIPT" --unknown 2>&1 >/dev/null); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'usage:'; then
  PASS=$((PASS+1)); echo "PASS T1 unknown flag → usage"
else
  FAIL=$((FAIL+1)); echo "FAIL T1 (rc=$rc)"
fi

# T2 --cached + 캐시 없음 → CACHE_MISS 리포트 + exit 0
sb=$(mktemp -d); make_sandbox "$sb"
cat > "$sb/skills/tdd-ko.md" <<'EOF'
---
reference_upstream: obra/superpowers@v5.0.7 skills/test-driven-development/SKILL.md
---
## Local Section
EOF
out=$(cd "$sb" && bash scripts/_internal/diff-upstream.sh --cached 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q 'struct=1' \
   && echo "$out" | grep -q 'cache_miss=1' \
   && grep -q 'CACHE_MISS' "$sb/docs/upstream-drift-log.md"; then
  PASS=$((PASS+1)); echo "PASS T2 --cached + no cache → CACHE_MISS"
else
  FAIL=$((FAIL+1)); echo "FAIL T2 (rc=$rc, out=$out)"
fi
rm -rf "$sb"

# T3 --no-fetch + 캐시 있음 → 정상 비교
sb=$(mktemp -d); make_sandbox "$sb"
cat > "$sb/skills/tdd-ko.md" <<'EOF'
---
reference_upstream: obra/superpowers@v5.0.7 skills/test-driven-development/SKILL.md
---
## Local Section A
## Local Section B
EOF
cat > "$sb/.specops-cache/upstream/obra__superpowers__v5.0.7__skills_test-driven-development_SKILL.md" <<'EOF'
## Upstream Section X
## Upstream Section Y
## Upstream Section Z
EOF
out=$(cd "$sb" && bash scripts/_internal/diff-upstream.sh --no-fetch 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q 'cache_hit=1' && echo "$out" | grep -q 'fetched=0'; then
  PASS=$((PASS+1)); echo "PASS T3 --no-fetch + cache hit"
else
  FAIL=$((FAIL+1)); echo "FAIL T3 (rc=$rc, out=$out)"
fi
rm -rf "$sb"

# T4 섹션 diff 정확성
sb=$(mktemp -d); make_sandbox "$sb"
cat > "$sb/skills/tdd-ko.md" <<'EOF'
---
reference_upstream: obra/superpowers@v5.0.7 skills/test-driven-development/SKILL.md
---
## Common A
## Local Only
EOF
cat > "$sb/.specops-cache/upstream/obra__superpowers__v5.0.7__skills_test-driven-development_SKILL.md" <<'EOF'
## Common A
## Upstream New 1
## Upstream New 2
EOF
out=$(cd "$sb" && bash scripts/_internal/diff-upstream.sh --no-fetch 2>&1); rc=$?
log="$sb/docs/upstream-drift-log.md"
if [ $rc -eq 0 ] \
   && grep -q '상류 헤더: 3, 로컬 헤더: 2, 공통: 1' "$log" \
   && grep -q '상류에만: 2, 로컬에만: 1' "$log" \
   && grep -q 'Upstream New 1' "$log"; then
  PASS=$((PASS+1)); echo "PASS T4 section diff calculation"
else
  FAIL=$((FAIL+1)); echo "FAIL T4 (rc=$rc)"
  sed 's/^/      /' "$log" | head -25
fi
rm -rf "$sb"

# T5 다중 참조 → manual 분류
sb=$(mktemp -d); make_sandbox "$sb"
cat > "$sb/agents/implementer-ko.md" <<'EOF'
---
reference_upstream: obra/superpowers@v5.0.7 test-driven-development + executing-plans
---
## Section
EOF
out=$(cd "$sb" && bash scripts/_internal/diff-upstream.sh --cached 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q 'struct=0' && echo "$out" | grep -q 'manual=1'; then
  PASS=$((PASS+1)); echo "PASS T5 multi-ref → manual"
else
  FAIL=$((FAIL+1)); echo "FAIL T5 (rc=$rc, out=$out)"
fi
rm -rf "$sb"

# T6 drift-log 템플릿 자동 생성
sb=$(mktemp -d); make_sandbox "$sb"
out=$(cd "$sb" && bash scripts/_internal/diff-upstream.sh --cached 2>&1); rc=$?
log="$sb/docs/upstream-drift-log.md"
if [ $rc -eq 0 ] && [ -f "$log" ] \
   && grep -q '^# Upstream Drift Log' "$log" \
   && grep -q '카운트 해석' "$log"; then
  PASS=$((PASS+1)); echo "PASS T6 template auto-generated"
else
  FAIL=$((FAIL+1)); echo "FAIL T6 (rc=$rc)"
fi
rm -rf "$sb"

# T7 --file 단일 파일 모드
sb=$(mktemp -d); make_sandbox "$sb"
cat > "$sb/skills/target.md" <<'EOF'
---
reference_upstream: obra/superpowers@v5.0.7 skills/test-driven-development/SKILL.md
---
## A
EOF
cat > "$sb/skills/ignored.md" <<'EOF'
---
reference_upstream: obra/superpowers@v5.0.7 skills/brainstorming/SKILL.md
---
## B
EOF
out=$(cd "$sb" && bash scripts/_internal/diff-upstream.sh --cached --file skills/target.md 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q 'struct=1' && echo "$out" | grep -q 'manual=0'; then
  PASS=$((PASS+1)); echo "PASS T7 --file single"
else
  FAIL=$((FAIL+1)); echo "FAIL T7 (rc=$rc, out=$out)"
fi
rm -rf "$sb"

# T8 실행권한
if [ -x scripts/_internal/diff-upstream.sh ]; then
  PASS=$((PASS+1)); echo "PASS T8 exec-bit"
else
  FAIL=$((FAIL+1)); echo "FAIL T8 exec-bit"
fi

echo "passed=$PASS failed=$FAIL"
exit $FAIL
