#!/usr/bin/env bash
# Wave 2 (FID 20260514-wave2-dispatch-automation) — dispatch-log.md 템플릿 + 동작 검증
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PLUGIN=$(dirname "$PLUGIN")

# T1.a: templates/dispatch-log.md 존재
if [ -f "$PLUGIN/templates/dispatch-log.md" ]; then
  PASS=$((PASS+1)); echo "PASS T1.a templates/dispatch-log.md 존재"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a templates/dispatch-log.md 부재"
fi

# T1.b: frontmatter 5 필드 (FID·OWNER_COMMAND·MUTABLE_BY·reference_upstream·layer)
f="$PLUGIN/templates/dispatch-log.md"
if [ -f "$f" ] \
  && grep -q "FID:" "$f" \
  && grep -q "OWNER_COMMAND:" "$f" \
  && grep -q "MUTABLE_BY:" "$f" \
  && grep -q "reference_upstream:" "$f" \
  && grep -q "layer:" "$f"; then
  PASS=$((PASS+1)); echo "PASS T1.b frontmatter 5 필드"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b frontmatter 누락"
fi

# T1.c: 재시도 누적 footer 키워드
if [ -f "$f" ] && grep -q "재시도 누적" "$f"; then
  PASS=$((PASS+1)); echo "PASS T1.c 재시도 누적 footer 키워드"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.c 재시도 누적 footer 부재"
fi

# T1.d: task-id 블록 반복 구조 (## task-...)
if [ -f "$f" ] && grep -qE "^## task-" "$f"; then
  PASS=$((PASS+1)); echo "PASS T1.d task-id 블록 반복 구조"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.d task-id 블록 부재"
fi

# T1.e: Phase A/B/C 표 헤더 (시각, agent, 결과)
if [ -f "$f" ] \
  && grep -q "시각" "$f" \
  && grep -q "agent" "$f" \
  && grep -q "결과" "$f"; then
  PASS=$((PASS+1)); echo "PASS T1.e Phase A/B/C 표 헤더"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.e 표 헤더 누락"
fi

# T1.f: cap=2 명시
if [ -f "$f" ] && grep -q "cap=2" "$f"; then
  PASS=$((PASS+1)); echo "PASS T1.f cap=2 명시"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.f cap=2 부재"
fi

# --- T2: append 시퀀스 정합 (D3 — Wave 2 U5) ---
# 시뮬레이션: empty template 복사 → task 블록 추가 → attempt 행 N 회 append → footer 갱신
tmp=$(mktemp -d)
cp "$PLUGIN/templates/dispatch-log.md" "$tmp/log.md"

# task-99 블록 + 5 attempt + footer 추가 (시뮬레이션)
cat >> "$tmp/log.md" << 'BLOCK'

## task-99: simulated

| # | 시각 | Phase | agent | 결과 | feedback 경로 |
|---|---|---|---|---|---|
| 1 | 2026-05-14T11:00 | A | implementer-ko | PASS | - |
| 2 | 2026-05-14T11:01 | B | spec-reviewer-ko | FAIL | reviews/task-99-B-feedback.md |
| 3 | 2026-05-14T11:02 | A (재) | implementer-ko | PASS | - |
| 4 | 2026-05-14T11:03 | B (재) | spec-reviewer-ko | PASS | - |
| 5 | 2026-05-14T11:04 | C | code-reviewer-ko | PASS | - |

**재시도 누적: B=1/2 C=0/2 (cap=2)**

---
BLOCK

# T2.a: task-99 블록 존재
if grep -q "task-99" "$tmp/log.md"; then
  PASS=$((PASS+1)); echo "PASS T2.a task-99 블록 append"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.a"
fi

# T2.b: attempt 행 5개 (실제 데이터)
n=$(awk '/^## task-99/ {found=1; next} /^## task-/ && found {exit} found && /^\| [0-9]+ \|/ {c++} END{print c}' "$tmp/log.md")
if [ "$n" = "5" ]; then
  PASS=$((PASS+1)); echo "PASS T2.b attempt 행 5개"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.b (n=$n)"
fi

# T2.c: footer 가 attempt 시퀀스와 일관 (B FAIL 1회 → B=1/2)
fc=$(awk '/^## task-99/ {found=1; next} found && /재시도 누적/ {print; exit}' "$tmp/log.md")
if [[ "$fc" == *"B=1/2"* && "$fc" == *"C=0/2"* ]]; then
  PASS=$((PASS+1)); echo "PASS T2.c footer 카운트 정합"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.c (fc='$fc')"
fi

# T2.d: append-only — 원본 templates/dispatch-log.md frontmatter 보존
if grep -q "FID: <YYYYMMDD" "$tmp/log.md"; then
  PASS=$((PASS+1)); echo "PASS T2.d frontmatter append-only 보존"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.d"
fi

rm -rf "$tmp"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
