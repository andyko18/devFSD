#!/usr/bin/env bash
# self-config 에이전트 read-only 불변식 + frontmatter 검증
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
P="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
nope(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

for a in red-team-ko blue-team-ko auditor-ko; do
  f="$P/agents/$a.md"
  [ -f "$f" ] || { nope "T2.a $a 부재"; continue; }
  grep -q "^name: $a" "$f" || nope "T2.b $a name 누락"
  grep -q "^description:" "$f" || nope "T2.c $a description 누락"
  tline="$(grep '^tools:' "$f")"
  printf '%s' "$tline" | grep -qiE 'Write|Edit' && nope "T2.d $a read-only 위반 (Write/Edit)" || ok
  printf '%s' "$tline" | grep -q 'Read' || nope "T2.e $a Read 누락"
done

echo "── test-self-config-agents: PASS=$PASS FAIL=$FAIL ──"
[ "$FAIL" -eq 0 ]
