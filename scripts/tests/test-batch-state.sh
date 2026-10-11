#!/usr/bin/env bash
# test-batch-state.sh — scripts/batch-state.sh 검증 (FID 20260710-p2-batch-state)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SCRIPT="$PLUGIN/scripts/batch-state.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# ── fixture A: 실물 batch-20260624 재현 (미완 3 + 드리프트 5 + 2-테이블 분할) ──
mkdir -p "$TMP/a/.specops/batch-x"
cat > "$TMP/a/.specops/batch-x/queue.md" <<'EOF'
# Batch Queue — batch-x

| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260624-vercel-pr | 어댑터 | MERGED |
| FR-2 | — | 확장 | HELD (자격증명 준비 후) |
| FR-3 | — | 머지 | HELD (자격증명 준비 후) |
| FR-4 | — | placeholder | SKIP |

| FR-5 | 20260624-dashboard-ui | 대시보드 | MERGED |
EOF
cat > "$TMP/a/req.md" <<'EOF'
| FR-1 | a | M1 | must | s | f |
| FR-2 | b | M2 | should | s | f |
| FR-3 | c | M3 | nice | s | f |
| FR-4 | d | M3 | nice | s | f |
| FR-5 | e | M1 | should | s | f |
| FR-6 | f | M1 | must | s | f |
| FR-7 | g | M1 | must | s | f |
| FR-8 | h | M1 | should | s | f |
| FR-9 | i | M1 | must | s | f |
| FR-3b | j | M3 | should | s | f |
EOF
out=$(bash "$SCRIPT" "$TMP/a/.specops/batch-x" "$TMP/a/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "미완" && echo "$out" | grep -q "드리프트" \
   && echo "$out" | grep -q "FR-6" && echo "$out" | grep -q "FR-3b" && echo "$out" | grep -q "FR-2"; then
  ok "T1.a 실물 fixture — exit 1 + 미완·드리프트 검출 (2-테이블 견딤)"
else
  nope "T1.a 실물 fixture" "exit=$code out=$(echo "$out" | head -3 | tr '\n' ' ')"
fi

# ── fixture B: clean (전 행 IMPL_DONE, parity 일치 + per-FID 산출물 존재) ──
mkdir -p "$TMP/b/.specops/batch-y" "$TMP/b/.specops/20260101-a" "$TMP/b/.specops/20260101-b"
cat > "$TMP/b/.specops/batch-y/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-a | one | IMPL_DONE |
| FR-2 | 20260101-b | two | MERGED |
EOF
# per-FR 산출물 (뭉개짐 방지 teeth 전제) — review-base.sha + evidence.md + review-request.md 3종
# 단, 20260101-b 는 MERGED → teeth 제외 대상이므로 seed 불요(IMPL_DONE 한정 검증도 겸함)
: > "$TMP/b/.specops/20260101-a/review-base.sha"
: > "$TMP/b/.specops/20260101-a/evidence.md"; : > "$TMP/b/.specops/20260101-a/review-request.md"
# 진행기록 teeth 전제 — IMPL_DONE FID 의 session-progress /verify PASS 줄 (verifying-evidence-ko 실호출 흔적)
printf '## 20260101-a\n- 2026-01-01 10:00 /verify PASS (evidence.md, AC 3/3)\n' > "$TMP/b/.specops/session-progress.md"
printf '| FR-1 | a | M1 | must | s | f |\n| FR-2 | b | M1 | must | s | f |\n' > "$TMP/b/req.md"
bash "$SCRIPT" "$TMP/b/.specops/batch-y" "$TMP/b/req.md" >/dev/null 2>&1; code=$?
[ "$code" -eq 0 ] && ok "T2.a clean fixture — exit 0 (산출물·진행기록 존재)" || nope "T2.a clean" "exit=$code (기대 0)"

# ── fixture B1b: review-skip.md 로 review-request 대체 (lite+단일태스크 메타 완비) ──
mkdir -p "$TMP/b1b/.specops/batch-y1b" "$TMP/b1b/.specops/20260101-skip"
cat > "$TMP/b1b/.specops/batch-y1b/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-skip | one | IMPL_DONE |
EOF
: > "$TMP/b1b/.specops/20260101-skip/review-base.sha"
: > "$TMP/b1b/.specops/20260101-skip/evidence.md"
echo "lite+단일태스크+Phase C PASS" > "$TMP/b1b/.specops/20260101-skip/review-skip.md"
printf '{"effective":"lite","computed":"lite","mode":"live","reductions_allowed":["batch-review-skip"]}\n' \
  > "$TMP/b1b/.specops/20260101-skip/risk-profile.json"
cat > "$TMP/b1b/.specops/20260101-skip/tasks.md" <<'EOF'
## 의존 그래프
```yaml
tasks:
  - id: T1
    deps: []
```
EOF
printf '## 20260101-skip\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n' > "$TMP/b1b/.specops/session-progress.md"
printf '| FR-1 | skip | M1 | must | s | f |\n' > "$TMP/b1b/req.md"
bash "$SCRIPT" "$TMP/b1b/.specops/batch-y1b" "$TMP/b1b/req.md" >/dev/null 2>&1; code=$?
[ "$code" -eq 0 ] && ok "T2.a2 review-skip.md 대체 — exit 0" || nope "T2.a2 review-skip" "exit=$code (기대 0)"

# ── fixture B1c: review-skip + effective=standard → 무효 ──
mkdir -p "$TMP/b1c/.specops/batch-y1c" "$TMP/b1c/.specops/20260101-std"
cat > "$TMP/b1c/.specops/batch-y1c/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-std | one | IMPL_DONE |
EOF
: > "$TMP/b1c/.specops/20260101-std/review-base.sha"
: > "$TMP/b1c/.specops/20260101-std/evidence.md"
echo "lite+단일태스크+Phase C PASS" > "$TMP/b1c/.specops/20260101-std/review-skip.md"
printf '{"effective":"standard","computed":"standard","mode":"live","reductions_allowed":[]}\n' \
  > "$TMP/b1c/.specops/20260101-std/risk-profile.json"
cat > "$TMP/b1c/.specops/20260101-std/tasks.md" <<'EOF'
## 의존 그래프
```yaml
tasks:
  - id: T1
    deps: []
```
EOF
printf '## 20260101-std\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n' > "$TMP/b1c/.specops/session-progress.md"
printf '| FR-1 | std | M1 | must | s | f |\n' > "$TMP/b1c/req.md"
out=$(bash "$SCRIPT" "$TMP/b1c/.specops/batch-y1c" "$TMP/b1c/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "review-skip 무효" && echo "$out" | grep -q "lite 아님"; then
  ok "T2.a3 review-skip + standard — 차단"
else
  nope "T2.a3 standard skip" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── fixture B1d: review-skip + 태스크 2개 → 무효 ──
mkdir -p "$TMP/b1d/.specops/batch-y1d" "$TMP/b1d/.specops/20260101-multi"
cat > "$TMP/b1d/.specops/batch-y1d/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-multi | one | IMPL_DONE |
EOF
: > "$TMP/b1d/.specops/20260101-multi/review-base.sha"
: > "$TMP/b1d/.specops/20260101-multi/evidence.md"
echo "lite+단일태스크+Phase C PASS" > "$TMP/b1d/.specops/20260101-multi/review-skip.md"
printf '{"effective":"lite","computed":"lite","mode":"live","reductions_allowed":["batch-review-skip"]}\n' \
  > "$TMP/b1d/.specops/20260101-multi/risk-profile.json"
cat > "$TMP/b1d/.specops/20260101-multi/tasks.md" <<'EOF'
## 의존 그래프
```yaml
tasks:
  - id: T1
    deps: []
  - id: T2
    deps: [T1]
```
EOF
printf '## 20260101-multi\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n' > "$TMP/b1d/.specops/session-progress.md"
printf '| FR-1 | multi | M1 | must | s | f |\n' > "$TMP/b1d/req.md"
out=$(bash "$SCRIPT" "$TMP/b1d/.specops/batch-y1d" "$TMP/b1d/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "review-skip 무효" && echo "$out" | grep -q "태스크 수"; then
  ok "T2.a4 review-skip + 멀티태스크 — 차단"
else
  nope "T2.a4 multi skip" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── fixture B1e: review-skip 사유 공백 → 무효 ──
mkdir -p "$TMP/b1e/.specops/batch-y1e" "$TMP/b1e/.specops/20260101-empty"
cat > "$TMP/b1e/.specops/batch-y1e/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-empty | one | IMPL_DONE |
EOF
: > "$TMP/b1e/.specops/20260101-empty/review-base.sha"
: > "$TMP/b1e/.specops/20260101-empty/evidence.md"
printf '   \n' > "$TMP/b1e/.specops/20260101-empty/review-skip.md"
printf '{"effective":"lite","computed":"lite","mode":"live","reductions_allowed":["batch-review-skip"]}\n' \
  > "$TMP/b1e/.specops/20260101-empty/risk-profile.json"
cat > "$TMP/b1e/.specops/20260101-empty/tasks.md" <<'EOF'
## 의존 그래프
```yaml
tasks:
  - id: T1
    deps: []
```
EOF
printf '## 20260101-empty\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n' > "$TMP/b1e/.specops/session-progress.md"
printf '| FR-1 | empty | M1 | must | s | f |\n' > "$TMP/b1e/req.md"
out=$(bash "$SCRIPT" "$TMP/b1e/.specops/batch-y1e" "$TMP/b1e/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "review-skip 무효" && echo "$out" | grep -q "사유 비어"; then
  ok "T2.a5 review-skip 공백 사유 — 차단"
else
  nope "T2.a5 empty skip" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── fixture B1f: review-skip + lite but reductions_allowed 없음 → 무효 (Wave B) ──
mkdir -p "$TMP/b1f/.specops/batch-y1f" "$TMP/b1f/.specops/20260101-noal"
cat > "$TMP/b1f/.specops/batch-y1f/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-noal | one | IMPL_DONE |
EOF
: > "$TMP/b1f/.specops/20260101-noal/review-base.sha"
: > "$TMP/b1f/.specops/20260101-noal/evidence.md"
echo "lite+단일태스크+Phase C PASS" > "$TMP/b1f/.specops/20260101-noal/review-skip.md"
printf '{"effective":"lite","computed":"lite","mode":"live","reductions_allowed":[]}\n' \
  > "$TMP/b1f/.specops/20260101-noal/risk-profile.json"
cat > "$TMP/b1f/.specops/20260101-noal/tasks.md" <<'EOF'
## 의존 그래프
```yaml
tasks:
  - id: T1
    deps: []
```
EOF
printf '## 20260101-noal\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n' > "$TMP/b1f/.specops/session-progress.md"
printf '| FR-1 | noal | M1 | must | s | f |\n' > "$TMP/b1f/req.md"
out=$(bash "$SCRIPT" "$TMP/b1f/.specops/batch-y1f" "$TMP/b1f/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "review-skip 무효" && echo "$out" | grep -q "batch-review-skip"; then
  ok "T2.a6 review-skip + lite without allowlist — 차단"
else
  nope "T2.a6 no allowlist" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── fixture B1g: end-loaded skip + 멀티태스크 + B/C reports → 유효 ──
mkdir -p "$TMP/b1g/.specops/batch-y1g" \
  "$TMP/b1g/.specops/20260101-el/reviews"
cat > "$TMP/b1g/.specops/batch-y1g/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-el | one | IMPL_DONE |
EOF
: > "$TMP/b1g/.specops/20260101-el/review-base.sha"
: > "$TMP/b1g/.specops/20260101-el/evidence.md"
echo "end-loaded: Phase B/C already covered full FID diff" > "$TMP/b1g/.specops/20260101-el/review-skip.md"
printf '{"effective":"strict","computed":"strict","mode":"live","reductions_allowed":[]}\n' \
  > "$TMP/b1g/.specops/20260101-el/risk-profile.json"
cat > "$TMP/b1g/.specops/20260101-el/tasks.md" <<'EOF'
## 의존 그래프
```yaml
review_mode: end-loaded
tasks:
  - id: T1
    depends_on: []
  - id: T2
    depends_on: [T1]
```
EOF
: > "$TMP/b1g/.specops/20260101-el/reviews/T1-B-report.md"
: > "$TMP/b1g/.specops/20260101-el/reviews/T1-C-report.md"
: > "$TMP/b1g/.specops/20260101-el/reviews/T2-B-report.md"
: > "$TMP/b1g/.specops/20260101-el/reviews/T2-C-report.md"
printf '## 20260101-el\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n' > "$TMP/b1g/.specops/session-progress.md"
printf '| FR-1 | el | M1 | must | s | f |\n' > "$TMP/b1g/req.md"
out=$(bash "$SCRIPT" "$TMP/b1g/.specops/batch-y1g" "$TMP/b1g/req.md" 2>&1); code=$?
[ "$code" -eq 0 ] && ok "T2.a7 end-loaded skip + 멀티태스크 + B/C — exit 0" \
  || nope "T2.a7 end-loaded skip" "exit=$code out=$(echo "$out" | tr '\n' ' ')"

# ── fixture B1h: end-loaded skip but C report 누락 → 무효 ──
mkdir -p "$TMP/b1h/.specops/batch-y1h" \
  "$TMP/b1h/.specops/20260101-elmiss/reviews"
cat > "$TMP/b1h/.specops/batch-y1h/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-elmiss | one | IMPL_DONE |
EOF
: > "$TMP/b1h/.specops/20260101-elmiss/review-base.sha"
: > "$TMP/b1h/.specops/20260101-elmiss/evidence.md"
echo "end-loaded: claimed but incomplete" > "$TMP/b1h/.specops/20260101-elmiss/review-skip.md"
cat > "$TMP/b1h/.specops/20260101-elmiss/tasks.md" <<'EOF'
## 의존 그래프
```yaml
tasks:
  - id: T1
    depends_on: []
```
EOF
: > "$TMP/b1h/.specops/20260101-elmiss/reviews/T1-B-report.md"
# T1-C-report.md 의도적 누락
printf '## 20260101-elmiss\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n' > "$TMP/b1h/.specops/session-progress.md"
printf '| FR-1 | elmiss | M1 | must | s | f |\n' > "$TMP/b1h/req.md"
out=$(bash "$SCRIPT" "$TMP/b1h/.specops/batch-y1h" "$TMP/b1h/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "review-skip 무효" && echo "$out" | grep -qE "end-loaded|reviews 누락"; then
  ok "T2.a8 end-loaded skip + C 누락 — 차단"
else
  nope "T2.a8 end-loaded incomplete" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── fixture B1i: end-loaded skip 사유 + B/C reports → 유효 (batch-end-loaded 제거 후) ──
mkdir -p "$TMP/b1i/.specops/batch-y1i" \
  "$TMP/b1i/.specops/20260101-bel/reviews"
cat > "$TMP/b1i/.specops/batch-y1i/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-bel | one | IMPL_DONE |
EOF
: > "$TMP/b1i/.specops/20260101-bel/review-base.sha"
: > "$TMP/b1i/.specops/20260101-bel/evidence.md"
echo "end-loaded: Phase B/C already covered full FID diff" > "$TMP/b1i/.specops/20260101-bel/review-skip.md"
cat > "$TMP/b1i/.specops/20260101-bel/tasks.md" <<'EOF'
## 의존 그래프
```yaml
review_mode: end-loaded
tasks:
  - id: T1
    depends_on: []
```
EOF
: > "$TMP/b1i/.specops/20260101-bel/reviews/T1-B-report.md"
: > "$TMP/b1i/.specops/20260101-bel/reviews/T1-C-report.md"
printf '## 20260101-bel\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n' > "$TMP/b1i/.specops/session-progress.md"
printf '| FR-1 | bel | M1 | must | s | f |\n' > "$TMP/b1i/req.md"
out=$(bash "$SCRIPT" "$TMP/b1i/.specops/batch-y1i" "$TMP/b1i/req.md" 2>&1); code=$?
[ "$code" -eq 0 ] && ok "T2.a9 end-loaded skip — exit 0" \
  || nope "T2.a9 end-loaded skip" "exit=$code out=$(echo "$out" | tr '\n' ' ')"

# ── fixture B2: IMPL_DONE 이나 per-FR 산출물 뭉개짐 (evidence.md만·review-request.md 부재) ──
mkdir -p "$TMP/b2/.specops/batch-y2" "$TMP/b2/.specops/20260101-c" "$TMP/b2/.specops/20260101-d"
cat > "$TMP/b2/.specops/batch-y2/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-c | one | IMPL_DONE |
| FR-2 | 20260101-d | two | IMPL_DONE |
EOF
# FR-1(-c): 3종 완전 / FR-2(-d): evidence.md만 (review-base.sha·review-request.md 부재 → 뭉개짐)
: > "$TMP/b2/.specops/20260101-c/review-base.sha"
: > "$TMP/b2/.specops/20260101-c/evidence.md"; : > "$TMP/b2/.specops/20260101-c/review-request.md"
: > "$TMP/b2/.specops/20260101-d/evidence.md"
printf '| FR-1 | c | M1 | must | s | f |\n| FR-2 | d | M1 | must | s | f |\n' > "$TMP/b2/req.md"
out=$(bash "$SCRIPT" "$TMP/b2/.specops/batch-y2" "$TMP/b2/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "산출물 누락" \
   && echo "$out" | grep -q "FR-2" && echo "$out" | grep -q "review-request.md" \
   && ! echo "$out" | grep -q "FR-1.*evidence"; then
  ok "T2.b 산출물 누락 teeth — review-request.md 부재 FID 차단 (FR-1 완전은 미보고)"
else
  nope "T2.b 산출물 teeth" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── fixture B3: IMPL_DONE 이나 FID 디렉토리 자체 부재 → 양쪽 누락 ──
mkdir -p "$TMP/b3/.specops/batch-y3"
cat > "$TMP/b3/.specops/batch-y3/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-e | one | IMPL_DONE |
EOF
printf '| FR-1 | e | M1 | must | s | f |\n' > "$TMP/b3/req.md"
out=$(bash "$SCRIPT" "$TMP/b3/.specops/batch-y3" "$TMP/b3/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "산출물 누락" \
   && echo "$out" | grep -q "evidence.md" && echo "$out" | grep -q "review-request.md"; then
  ok "T2.c 산출물 누락 teeth — FID 디렉토리 부재 시 양쪽 보고"
else
  nope "T2.c FID 부재" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── fixture B4: layer 2 — review-base.sha 만 부재 (evidence·review-request 는 존재) → 내용 뭉개짐 차단 ──
#    step 1a(review base 기록) 누락 시나리오. 존재 teeth 는 통과하나 내용 격리 base 가 없어 차단돼야 함.
mkdir -p "$TMP/b4/.specops/batch-y4" "$TMP/b4/.specops/20260101-f"
cat > "$TMP/b4/.specops/batch-y4/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-f | one | IMPL_DONE |
EOF
: > "$TMP/b4/.specops/20260101-f/evidence.md"; : > "$TMP/b4/.specops/20260101-f/review-request.md"
printf '| FR-1 | f | M1 | must | s | f |\n' > "$TMP/b4/req.md"
out=$(bash "$SCRIPT" "$TMP/b4/.specops/batch-y4" "$TMP/b4/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "review-base.sha" \
   && ! echo "$out" | grep -q "evidence.md 없음" && ! echo "$out" | grep -q "review-request.md 없음"; then
  ok "T2.d layer 2 teeth — review-base.sha 부재만으로 차단 (내용 뭉개짐 방지)"
else
  nope "T2.d review-base teeth" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── fixture B5: layer 2 read-path — §batch spec + review-base.sha → 문서화 BASE_SHA 스니펫 resolve ──
#    requesting-code-review-ko §1 [batch 모드] 분기의 실제 bash 로직을 재현해 격리 base 가 파일 내용으로
#    resolve 되는지(HEAD~1 falling back 아님) 실행 검증.
mkdir -p "$TMP/b5/.specops/20260101-g"
printf '**§batch**: true\n' > "$TMP/b5/.specops/20260101-g/spec.md"
printf 'cafef00d\n' > "$TMP/b5/.specops/20260101-g/review-base.sha"
( cd "$TMP/b5"
  FID=20260101-g
  BASE_SHA=HEAD~1  # 단일 모드 기본 (스니펫 시작값)
  if grep -qE '^\*\*§batch\*\*:' ".specops/$FID/spec.md" 2>/dev/null && [ -f ".specops/$FID/review-base.sha" ]; then
    BASE_SHA=$(cat ".specops/$FID/review-base.sha")
  fi
  [ "$BASE_SHA" = "cafef00d" ] )
[ "$?" -eq 0 ] && ok "T2.e layer 2 read-path — §batch BASE_SHA = review-base.sha 내용 (HEAD~1 미사용)" \
  || nope "T2.e §batch resolve" "BASE_SHA 가 review-base.sha 로 resolve 안 됨"

# ── fixture B6: 3종 완비 + session-progress /verify PASS 줄 부재 → 진행기록 누락 차단 ──
#    dogfood 20260716: batch 가 skill 미호출 인라인 진행으로 session-progress 0줄 → R-1/R-2 면제 신호
#    (_verify_passed_in_progress) 부재 → 게이트 차단 → BYPASS 관성 남발. 줄 존재를 batch PR 전 하드 재검.
mkdir -p "$TMP/b6/.specops/batch-y6" "$TMP/b6/.specops/20260101-h"
cat > "$TMP/b6/.specops/batch-y6/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-h | one | IMPL_DONE |
EOF
: > "$TMP/b6/.specops/20260101-h/review-base.sha"
: > "$TMP/b6/.specops/20260101-h/evidence.md"; : > "$TMP/b6/.specops/20260101-h/review-request.md"
printf '| FR-1 | h | M1 | must | s | f |\n' > "$TMP/b6/req.md"
out=$(bash "$SCRIPT" "$TMP/b6/.specops/batch-y6" "$TMP/b6/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "진행기록 누락" && echo "$out" | grep -q "20260101-h"; then
  ok "T2.f 진행기록 teeth — /verify PASS 줄 부재 FID 차단"
else
  nope "T2.f 진행기록 teeth" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi
# ── fixture B7: 섹션은 있으나 /verify 줄 없음(다른 커맨드 줄만) → 차단 · memo 언급은 매칭 금지 ──
mkdir -p "$TMP/b7/.specops/batch-y7" "$TMP/b7/.specops/20260101-i"
cat > "$TMP/b7/.specops/batch-y7/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-i | one | IMPL_DONE |
EOF
: > "$TMP/b7/.specops/20260101-i/review-base.sha"
: > "$TMP/b7/.specops/20260101-i/evidence.md"; : > "$TMP/b7/.specops/20260101-i/review-request.md"
printf '## 20260101-i\n- 2026-01-01 10:00 /implement DONE (memo 에 /verify PASS 언급)\n' > "$TMP/b7/.specops/session-progress.md"
printf '| FR-1 | i | M1 | must | s | f |\n' > "$TMP/b7/req.md"
out=$(bash "$SCRIPT" "$TMP/b7/.specops/batch-y7" "$TMP/b7/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "진행기록 누락"; then
  ok "T2.g 진행기록 teeth — 행 선두 앵커(memo 언급 무매칭)"
else
  nope "T2.g 행 선두 앵커" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── fixture C: FR-ID 중복 + read-only 검증 ──
mkdir -p "$TMP/c/.specops/batch-z"
cat > "$TMP/c/.specops/batch-z/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-3 | x | dup1 | IMPL_DONE |
| FR-3 | y | dup2 | IMPL_DONE |
EOF
printf '| FR-3 | a | M1 | must | s | f |\n' > "$TMP/c/req.md"
sum_before=$(cksum "$TMP/c/.specops/batch-z/queue.md" "$TMP/c/req.md")
out=$(bash "$SCRIPT" "$TMP/c/.specops/batch-z" "$TMP/c/req.md" 2>&1); code=$?
sum_after=$(cksum "$TMP/c/.specops/batch-z/queue.md" "$TMP/c/req.md")
if [ "$code" -eq 1 ] && echo "$out" | grep -q "중복" && [ "$sum_before" = "$sum_after" ]; then
  ok "T3.a 중복 감지 + read-only (cksum 불변)"
else
  nope "T3.a 중복/read-only" "exit=$code"
fi

# ── 사용 오류: 인자 없음 → exit 2 ──
bash "$SCRIPT" 2>/dev/null; code=$?
[ "$code" -eq 2 ] && ok "T4.a 인자 없음 → exit 2" || nope "T4.a usage" "exit=$code"

# ── 배선·규약 grep 계약 (AC-4·AC-5) ──
grep -q 'batch-state.sh' "$PLUGIN/commands/start-all.md" && grep -q '그래도 batch PR' "$PLUGIN/commands/start-all.md" \
  && ok "T5.a start-all 게이트 배선" || nope "T5.a 배선" "batch-state 호출/[y/n] 없음"
grep -q '_inject_design_palette' "$PLUGIN/commands/init-project.md" \
  && ok "T5.b Phase11 재주입 지시" || nope "T5.b 재주입" "없음"
grep -q '복수 표기' "$PLUGIN/templates/data-model.md" \
  && ok "T5.c 하이브리드 복수 표기" || nope "T5.c 복수표기" "없음"
grep -q '해당 행 갱신' "$PLUGIN/skills/specifying-ko/SKILL.md" \
  && ok "T5.d Step5.6 dedup" || nope "T5.d dedup" "없음"

# ══════════════════════════════════════════════════════════════════════════
# --gate 모드 (20260721-batch-pr-teeth) — 훅이 batch PR 을 차단할지 판정한다.
#   기본 모드와 판정 기준이 다르다: 드리프트·중복·미완은 batch 운영 판단(부분 batch 는 정당)이라
#   **차단하지 않는다**. 게이트가 보는 것은 뭉개짐 신호뿐 — 산출물 부재·진행기록 부재·라벨 오염.
#   근거: .specops/20260721-batch-pr-teeth/plan.md §설계 판단 ②
# ══════════════════════════════════════════════════════════════════════════

# 공통 fixture 빌더 — per-FR 산출물 3종 + session-progress /verify PASS 줄
_mk_fid_artifacts() {  # $1=root $2=fid
  mkdir -p "$1/.specops/$2"
  : > "$1/.specops/$2/review-base.sha"
  : > "$1/.specops/$2/evidence.md"
  : > "$1/.specops/$2/review-request.md"
}
_mk_progress() {  # $1=root $2=fid
  printf '## %s\n\n- 2026-07-21 13:53 /verify PASS (evidence.md)\n' "$2" \
    >> "$1/.specops/session-progress.md"
}

# ── T-gate.a: 부분 batch(드리프트 O) + 산출물·진행기록 완비 → 통과 (false-block 금지) ──
mkdir -p "$TMP/g1/.specops/batch-p"
cat > "$TMP/g1/.specops/batch-p/queue.md" <<'EOF'
| FR-ID | FID | 설명 | Status |
|---|---|---|---|
| FR-4 | 20260721-login | 로그인 | IMPL_DONE |
EOF
printf '| FR-4 | a | M1 | must | s | f |\n| FR-9 | b | M2 | must | s | f |\n' > "$TMP/g1/req.md"
_mk_fid_artifacts "$TMP/g1" 20260721-login
_mk_progress "$TMP/g1" 20260721-login
out=$(cd "$TMP/g1" && bash "$SCRIPT" --gate .specops/batch-p req.md 2>&1); code=$?
if [ "$code" -eq 0 ]; then
  ok "T-gate.a 부분 batch 드리프트 → 게이트 통과 (운영 판단, 차단 아님)"
else
  nope "T-gate.a 부분 batch false-block" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── T-gate.b: IMPL_DONE 인데 per-FR 산출물 3종 부재 → 차단 ──
mkdir -p "$TMP/g2/.specops/batch-p" "$TMP/g2/.specops/20260721-login"
cat > "$TMP/g2/.specops/batch-p/queue.md" <<'EOF'
| FR-ID | FID | 설명 | Status |
|---|---|---|---|
| FR-4 | 20260721-login | 로그인 | IMPL_DONE |
EOF
printf '| FR-4 | a | M1 | must | s | f |\n' > "$TMP/g2/req.md"
_mk_progress "$TMP/g2" 20260721-login
out=$(cd "$TMP/g2" && bash "$SCRIPT" --gate .specops/batch-p req.md 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "산출물 누락"; then
  ok "T-gate.b 산출물 3종 부재 → 차단"
else
  nope "T-gate.b 산출물 부재 미차단" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── T-gate.b2: review-skip 남용(standard) → --gate 차단 ──
mkdir -p "$TMP/g2b/.specops/batch-p" "$TMP/g2b/.specops/20260721-skipbad"
cat > "$TMP/g2b/.specops/batch-p/queue.md" <<'EOF'
| FR-ID | FID | 설명 | Status |
|---|---|---|---|
| FR-4 | 20260721-skipbad | 로그인 | IMPL_DONE |
EOF
printf '| FR-4 | a | M1 | must | s | f |\n' > "$TMP/g2b/req.md"
: > "$TMP/g2b/.specops/20260721-skipbad/review-base.sha"
: > "$TMP/g2b/.specops/20260721-skipbad/evidence.md"
echo "claimed lite skip" > "$TMP/g2b/.specops/20260721-skipbad/review-skip.md"
printf '{"effective":"standard","computed":"standard","mode":"live","reductions_allowed":[]}\n' \
  > "$TMP/g2b/.specops/20260721-skipbad/risk-profile.json"
cat > "$TMP/g2b/.specops/20260721-skipbad/tasks.md" <<'EOF'
## 의존 그래프
```yaml
tasks:
  - id: T1
    deps: []
```
EOF
_mk_progress "$TMP/g2b" 20260721-skipbad
out=$(cd "$TMP/g2b" && bash "$SCRIPT" --gate .specops/batch-p req.md 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "review-skip 무효"; then
  ok "T-gate.b2 review-skip 남용 → 게이트 차단"
else
  nope "T-gate.b2 skip 남용 미차단" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── T-gate.c ★ test1 실물 케이스: 라벨이 DONE(화이트리스트 밖) → 차단 ──
#   IMPL_DONE 만 수집하는 teeth 는 DONE 앞에서 검사 대상 0건이 되어 조용히 통과한다(MED-6).
#   라벨 검증이 없으면 이 fixture 가 바로 test1 의 통과 경로다.
mkdir -p "$TMP/g3/.specops/batch-p"
cat > "$TMP/g3/.specops/batch-p/queue.md" <<'EOF'
| 단계 | 대상 | Status |
|---|---|---|
| FR-4 | 로그인 | DONE |
| FR-5 | 차량 목록 | DONE |
EOF
printf '| FR-4 | a | M1 | must | s | f |\n| FR-5 | b | M1 | must | s | f |\n' > "$TMP/g3/req.md"
out=$(cd "$TMP/g3" && bash "$SCRIPT" --gate .specops/batch-p req.md 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "라벨"; then
  ok "T-gate.c ★ 미인식 라벨(DONE) → 차단 (teeth vacuous 방지)"
else
  nope "T-gate.c 미인식 라벨 미차단" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── T-gate.d: 산출물은 있으나 session-progress /verify PASS 줄 부재 → 차단 ──
mkdir -p "$TMP/g4/.specops/batch-p"
cat > "$TMP/g4/.specops/batch-p/queue.md" <<'EOF'
| FR-ID | FID | 설명 | Status |
|---|---|---|---|
| FR-4 | 20260721-login | 로그인 | IMPL_DONE |
EOF
printf '| FR-4 | a | M1 | must | s | f |\n' > "$TMP/g4/req.md"
_mk_fid_artifacts "$TMP/g4" 20260721-login
printf '# session progress\n' > "$TMP/g4/.specops/session-progress.md"
out=$(cd "$TMP/g4" && bash "$SCRIPT" --gate .specops/batch-p req.md 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "진행기록 누락"; then
  ok "T-gate.d 진행기록 부재 → 차단"
else
  nope "T-gate.d 진행기록 부재 미차단" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── T-gate.e: 화이트리스트 라벨(HELD·SKIP·TODO)은 라벨 사유로 차단하지 않는다 ──
mkdir -p "$TMP/g5/.specops/batch-p"
cat > "$TMP/g5/.specops/batch-p/queue.md" <<'EOF'
| FR-ID | FID | 설명 | Status |
|---|---|---|---|
| FR-4 | — | 로그인 | HELD (자격증명 대기) |
| FR-5 | — | 목록 | SKIP |
| FR-6 | — | 예약 | TODO |
EOF
printf '| FR-4 | a | M1 | must | s | f |\n' > "$TMP/g5/req.md"
out=$(cd "$TMP/g5" && bash "$SCRIPT" --gate .specops/batch-p req.md 2>&1); code=$?
if [ "$code" -eq 0 ]; then
  ok "T-gate.e 정상 라벨(HELD·SKIP·TODO) → 통과"
else
  nope "T-gate.e 정상 라벨 false-block" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── T-gate.e2: PLAN_DONE 화이트리스트 (Phase 1 중간 상태) ──
mkdir -p "$TMP/g5b/.specops/batch-p"
cat > "$TMP/g5b/.specops/batch-p/queue.md" <<'EOF'
| FR-ID | FID | 설명 | Status |
|---|---|---|---|
| FR-1 | 20260101-a | plan | PLAN_DONE |
| FR-2 | 20260101-b | held | HELD |
EOF
printf '| FR-1 | a | M1 | must | s | f |\n| FR-2 | b | M1 | must | s | f |\n' > "$TMP/g5b/req.md"
out=$(cd "$TMP/g5b" && bash "$SCRIPT" --gate .specops/batch-p req.md 2>&1); code=$?
if [ "$code" -eq 0 ] && ! echo "$out" | grep -q "라벨"; then
  ok "T-gate.e2 PLAN_DONE·HELD → 라벨 통과"
else
  nope "T-gate.e2 PLAN_DONE/HELD" "exit=$code out=$(echo "$out" | tr '\n' ' ')"
fi

# ── T-gate.g/h: ACTIVE 마커 배선 (인프라 전파) ──
#   훅은 마커가 있는 batch 만 판정한다. 마커를 **쓰는 쪽**(start-all Phase 0)과 **지우는 쪽**
#   (Step D PR 성공 후)이 배선돼 있지 않으면, 게이트는 영영 발화하지 않거나(전자 누락)
#   끝난 batch 가 무관한 PR 을 계속 막는다(후자 누락).
grep -q 'ACTIVE"' "$PLUGIN/commands/start-all.md" \
  && ok "T-gate.g start-all Phase 0 — ACTIVE 마커 생성 배선" \
  || nope "T-gate.g 마커 생성 배선" "start-all.md 에 ACTIVE 생성 없음"
grep -q 'rm -f ".specops/\$BATCH_ID/ACTIVE"' "$PLUGIN/commands/start-all.md" \
  && ok "T-gate.h start-all Step D — PR 성공 후 마커 제거 배선" \
  || nope "T-gate.h 마커 제거 배선" "start-all.md 에 ACTIVE 제거 없음"

# ── T-gate.f: 기본 모드 회귀 — --gate 없으면 기존 판정 불변 ──
out=$(bash "$SCRIPT" "$TMP/a/.specops/batch-x" "$TMP/a/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q "드리프트"; then
  ok "T-gate.f 기본 모드 회귀 — 드리프트 판정 불변"
else
  nope "T-gate.f 기본 모드 회귀" "exit=$code"
fi

# ── T-norm: 라벨 장식 정규화 (FID 20260828-queue-label-drift) ──
#   계기: argus batch-20260729 실측 — 모델이 Status 를 `**IMPL_DONE**`(굵게)로 손편집했고
#   소비자 3곳이 전부 `^IMPL_DONE` 앵커라 불일치했다. 그 결과 산출물·review-skip 검사가
#   **대상 0건으로 조용히 통과**했다(FR 31건 무검증). 쓰는 쪽은 모델이라 강제가 불가능하므로
#   읽는 쪽에서 흡수한다.
mk_norm_fixture() {  # <dir> <status-cell>
  local d="$1" st="$2"
  mkdir -p "$d/.specops/batch-n/" "$d/.specops/20260101-alpha/reviews"
  cat > "$d/.specops/batch-n/queue.md" <<EOF
| FR-ID | FID | 설명 | Status |
|---|---|---|---|
| FR-1 | 20260101-alpha | alpha | $st |
EOF
  : > "$d/.specops/20260101-alpha/review-base.sha"
  : > "$d/.specops/20260101-alpha/evidence.md"
  : > "$d/.specops/20260101-alpha/review-request.md"
  printf '## 20260101-alpha\n- 2026-01-01 10:00 /verify PASS (evidence.md, AC 1/1)\n' > "$d/.specops/session-progress.md"
  printf '| FR-1 | alpha | M1 | must | s | f |\n' > "$d/req.md"
}

# T-norm.a 굵게 표기를 IMPL_DONE 으로 인식한다 (기본 모드)
rm -rf "$TMP/n1"; mk_norm_fixture "$TMP/n1" '**IMPL_DONE**'
out=$(cd "$TMP/n1" && bash "$SCRIPT" .specops/batch-n req.md 2>&1); code=$?
if [ "$code" -eq 0 ] && ! printf '%s' "$out" | grep -q '미완'; then
  ok "T-norm.a **IMPL_DONE** 을 완료로 인식 (기본 모드)"
else
  nope "T-norm.a 굵게 표기 미인식" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# T-norm.b 굵게 표기여도 하류 teeth 가 실제로 돈다 — 산출물 누락을 잡아야 한다
#   ★ 이게 핵심이다. a 만으로는 "미완 오탐이 사라졌다"까지만 증명하고,
#     검사가 대상 0건으로 비어버리는 무음 통과를 구분하지 못한다.
rm -rf "$TMP/n2"; mk_norm_fixture "$TMP/n2" '**IMPL_DONE**'
rm -f "$TMP/n2/.specops/20260101-alpha/evidence.md"
out=$(cd "$TMP/n2" && bash "$SCRIPT" .specops/batch-n req.md 2>&1); code=$?
if [ "$code" -ne 0 ] && printf '%s' "$out" | grep -q 'evidence.md'; then
  ok "T-norm.b 굵게 표기에서도 산출물 누락 teeth 발화 (무음 통과 차단)"
else
  nope "T-norm.b 하류 teeth 무발화" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# T-norm.c 백틱·여분 공백도 흡수한다
rm -rf "$TMP/n3"; mk_norm_fixture "$TMP/n3" '  `IMPL_DONE`  '
out=$(cd "$TMP/n3" && bash "$SCRIPT" .specops/batch-n req.md 2>&1); code=$?
[ "$code" -eq 0 ] && ok "T-norm.c 백틱·공백 흡수" \
  || nope "T-norm.c 백틱 미흡수" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"

# T-norm.d 정규화가 과하지 않다 — 다른 라벨을 IMPL_DONE 으로 만들지 않는다
rm -rf "$TMP/n4"; mk_norm_fixture "$TMP/n4" '**PLAN_DONE**'
out=$(cd "$TMP/n4" && bash "$SCRIPT" .specops/batch-n req.md 2>&1); code=$?
if [ "$code" -ne 0 ] && printf '%s' "$out" | grep -q '미완'; then
  ok "T-norm.d 과잉 정규화 없음 — **PLAN_DONE** 은 여전히 미완"
else
  nope "T-norm.d 과잉 정규화" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# T-norm.e 라벨 오염 검사가 기본 모드에서도 돈다 (종전 --gate 전용)
#   무의미 라벨은 정규화로 구제되지 않아야 하고, 기본 모드에서 즉시 보여야 한다.
rm -rf "$TMP/n5"; mk_norm_fixture "$TMP/n5" 'DONE'
out=$(cd "$TMP/n5" && bash "$SCRIPT" .specops/batch-n req.md 2>&1); code=$?
if [ "$code" -ne 0 ] && printf '%s' "$out" | grep -q '라벨'; then
  ok "T-norm.e 라벨 오염 검사 기본 모드 승격 (DONE 은 인식 라벨 아님)"
else
  nope "T-norm.e 기본 모드 라벨 검사 부재" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# ── T-vac: 검사하지 않은 것을 "완비" 라고 말하지 않는다 (FID 20260828-vacuity-claim) ──
#   실측: 전건 MERGED queue 는 산출물 검사 대상이 0건인데(MERGED 는 teeth 제외),
#   FID 디렉터리가 **하나도 없어도** `산출물·진행기록 완비` + rc=0 을 냈다.
#   0건 자체는 정상이다(갓 시작한 batch·전건 MERGED). 문제는 **아무것도 확인하지 않고
#   완비를 주장**하는 것이다 — argus 가 그 상태로 31건을 통과시켰다.
rm -rf "$TMP/v1"; mkdir -p "$TMP/v1/.specops/batch-m"
cat > "$TMP/v1/.specops/batch-m/queue.md" <<'EOF'
| FR-ID | FID | 설명 | Status |
|---|---|---|---|
| FR-1 | 20260101-a | one | MERGED |
| FR-2 | 20260101-b | two | MERGED |
EOF
printf '| FR-1 | a | M1 | must | s | f |\n| FR-2 | b | M1 | must | s | f |\n' > "$TMP/v1/req.md"
out=$(cd "$TMP/v1" && bash "$SCRIPT" .specops/batch-m req.md 2>&1); code=$?
# 통과는 유지하되(0건은 정상), **검사 건수를 말해야** 한다.
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -qE '산출물·진행기록 [0-9]+ FID'; then
  ok "T-vac.a 검사 대상 0건이면 건수를 밝힌다 (완비 주장 금지)"
else
  nope "T-vac.a 헛된 완비 주장" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# T-vac.b 실제로 검사한 경우도 건수를 밝힌다 — 0건과 구분 가능해야 의미가 있다
rm -rf "$TMP/v2"; mkdir -p "$TMP/v2/.specops/batch-m" "$TMP/v2/.specops/20260101-a"
cat > "$TMP/v2/.specops/batch-m/queue.md" <<'EOF'
| FR-ID | FID | 설명 | Status |
|---|---|---|---|
| FR-1 | 20260101-a | one | IMPL_DONE |
EOF
: > "$TMP/v2/.specops/20260101-a/review-base.sha"
: > "$TMP/v2/.specops/20260101-a/evidence.md"
: > "$TMP/v2/.specops/20260101-a/review-request.md"
printf '## 20260101-a\n- 2026-01-01 10:00 /verify PASS (evidence.md, AC 1/1)\n' > "$TMP/v2/.specops/session-progress.md"
printf '| FR-1 | a | M1 | must | s | f |\n' > "$TMP/v2/req.md"
out=$(cd "$TMP/v2" && bash "$SCRIPT" .specops/batch-m req.md 2>&1); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q '산출물·진행기록 1 FID'; then
  ok "T-vac.b 실검사 건수 보고 (1 FID)"
else
  nope "T-vac.b 건수 미보고" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# T-vac.c gate 모드도 건수를 밝힌다 — 이 경로가 `gh pr create` 를 여는 훅 판정이다
out=$(cd "$TMP/v1" && bash "$SCRIPT" --gate .specops/batch-m req.md 2>&1); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -qE '[0-9]+ FID'; then
  ok "T-vac.c gate 모드 검사 건수 보고 (batch PR 을 여는 경로)"
else
  nope "T-vac.c gate 헛된 통과 선언" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ')"
fi

# ── T-skip: SKIP 행·placeholder FR 은 batch 대상이 아니다 (20261009-startall-tail) ──
#   init-batch-queue.sh 는 시드·공통부 FR 을 `SKIP` 행으로 쓰고 placeholder 행은 queue 에서 뺀다 — 이 플러그인이 만든 정상 상태다.
#   그런데 기본 모드가 SKIP 을 [미완]으로, placeholder 를 [드리프트]로 세어, 적격 FR 이 전부 끝나도 **항상 exit 1** 이었다.
#   → 대화형은 매번 "그래도 진행?" 을 묻고 `/start-all-auto` 는 PR 직전에 항상 멈췄다(실측 20261008 — 설치본을 연습용 프로젝트에서 실행).
#   batch-resume-check.sh 는 이미 SKIP 을 분모에서 뺀다 — 두 판독기가 같은 queue 를 다르게 읽고 있었다.
_skipfx() {  # $1=dir $2=FR-6 의 Status
  mkdir -p "$1/.specops/batch-s" "$1/.specops/20260101-s5" "$1/.specops/20260101-s6"
  cat > "$1/.specops/batch-s/queue.md" <<EOF
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | — | (마일스톤 시드 — 세부 FR로 분해됨) | SKIP |
| FR-4 | — | (공통부 — /start-foundation 담당) | SKIP |
| FR-5 | 20260101-s5 | 목록 | IMPL_DONE |
| FR-6 | 20260101-s6 | 상세 | $2 |
EOF
  local f
  for f in 20260101-s5 20260101-s6; do
    : > "$1/.specops/$f/review-base.sha"; : > "$1/.specops/$f/evidence.md"; : > "$1/.specops/$f/review-request.md"
  done
  printf '## 20260101-s5\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n## 20260101-s6\n- 2026-01-01 11:00 /verify PASS (evidence.md)\n' > "$1/.specops/session-progress.md"
  cat > "$1/req.md" <<'EOF'
<!-- seed-fr: FR-1,FR-2,FR-3 -->
| ID | 요구사항 | 마일스톤 | 우선순위 | 관련 spec |
|---|---|---|---|---|
| FR-1 | 주문 관리 | M1 | must | (TBD) |
| FR-4 | [공통] 로그인 | M1 | must | (TBD) |
| FR-5 | 주문 목록 | M1 | must | (TBD) |
| FR-6 | 주문 상세 | M1 | must | (TBD) |
| FR-9 | <한 줄> | M2 | nice | (TBD) |
EOF
}
_skipfx "$TMP/sk1" IMPL_DONE
out=$(bash "$SCRIPT" "$TMP/sk1/.specops/batch-s" "$TMP/sk1/req.md" 2>&1); code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q 'BATCH-STATE: OK' \
   && ! printf '%s' "$out" | grep -q '\[미완\]' && ! printf '%s' "$out" | grep -q '\[드리프트\]'; then
  ok "T-skip.a ★ 적격 FR 전부 완료 + SKIP 2 + placeholder 1 → exit 0 (미완·드리프트 아님)"
else
  nope "T-skip.a" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
fi
#   제외한 것은 숨기지 않는다 — 무엇을 빼고 완료라 했는지 출력에 남는다
if printf '%s' "$out" | grep -q '\[제외\]' && printf '%s' "$out" | grep -q 'FR-1' && printf '%s' "$out" | grep -q 'FR-4' \
   && printf '%s' "$out" | grep -q 'FR-9'; then
  ok "T-skip.b 제외한 SKIP·placeholder 를 [제외] 로 밝힌다"
else
  nope "T-skip.b" "out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-240)"
fi
_skipfx "$TMP/sk2" PLAN_DONE
out=$(bash "$SCRIPT" "$TMP/sk2/.specops/batch-s" "$TMP/sk2/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && printf '%s' "$out" | grep -q 'FR-6: PLAN_DONE' \
   && ! printf '%s' "$out" | sed -n '/\[미완\]/,/^\[/p' | grep -q 'SKIP'; then
  ok "T-skip.c 진짜 미완(PLAN_DONE)은 그대로 exit 1 — 미완 목록에 SKIP 은 없다"
else
  nope "T-skip.c" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
fi
#   HELD·BLOCKED 는 건너뛴 것이 아니라 멈춘 것이다 — 여전히 미완
_skipfx "$TMP/sk3" 'HELD (자격증명 대기)'
out=$(bash "$SCRIPT" "$TMP/sk3/.specops/batch-s" "$TMP/sk3/req.md" 2>&1); code=$?
[ "$code" -eq 1 ] && printf '%s' "$out" | grep -q 'FR-6: HELD' \
  && ok "T-skip.d HELD 는 여전히 미완(exit 1)" || nope "T-skip.d" "exit=$code"
#   placeholder 가 아닌 실 FR 이 queue 에 없으면 여전히 드리프트
_skipfx "$TMP/sk4" IMPL_DONE
printf '| FR-7 | 주문 취소 | M1 | should | (TBD) |\n' >> "$TMP/sk4/req.md"
out=$(bash "$SCRIPT" "$TMP/sk4/.specops/batch-s" "$TMP/sk4/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && printf '%s' "$out" | sed -n '/\[드리프트\]/,/^\[/p' | grep -q 'FR-7' \
   && ! printf '%s' "$out" | sed -n '/\[드리프트\]/,/^\[/p' | grep -q 'FR-9'; then
  ok "T-skip.e 실 FR 누락은 여전히 드리프트 · placeholder 는 드리프트 아님"
else
  nope "T-skip.e" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
fi
#   --gate 판정은 그대로다(SKIP 은 원래 차단 사유가 아니었다)
out=$(bash "$SCRIPT" --gate "$TMP/sk1/.specops/batch-s" "$TMP/sk1/req.md" 2>&1); code=$?
[ "$code" -eq 0 ] && printf '%s' "$out" | grep -q 'BATCH-GATE: OK' \
  && ok "T-skip.f --gate 는 불변(OK)" || nope "T-skip.f" "exit=$code"

#   ★ SKIP 글자만으로 빼지 않는다 — 분류기가 batch 대상이라는 FR 을 SKIP 으로 바꿔도 "완료" 가 되지 않는다.
#     (`--gate`·RELEASE_READY 는 IMPL_DONE 행만 보고 무인은 exit code 만 본다 — 여기가 유일한 관문이다. 독립 리뷰가 재현.)
for lab in 'SKIP' '**SKIP**' 'SKIP (구현 실패)'; do
  _skipfx "$TMP/skg" "$lab"
  out=$(bash "$SCRIPT" "$TMP/skg/.specops/batch-s" "$TMP/skg/req.md" 2>&1); code=$?
  if [ "$code" -eq 1 ] && printf '%s' "$out" | sed -n '/\[미완\]/,/^\[/p' | grep -q 'FR-6' \
     && ! printf '%s' "$out" | sed -n '/\[제외\]/,$p' | grep -q 'FR-6'; then
    ok "T-skip.g ★ 적격 FR 을 '$lab' 로 둔 행 → 미완(exit 1) · [제외] 에 없음"
  else
    nope "T-skip.g '$lab'" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-220)"
  fi
  rm -rf "$TMP/skg"
done
#   분류기를 못 돌리면 아무것도 빼지 않는다(판정 불가를 "문제 없음" 으로 읽지 않는다)
mkdir -p "$TMP/nochk/scripts/_internal"
cp "$SCRIPT" "$TMP/nochk/scripts/batch-state.sh"; cp "$PLUGIN/scripts/_internal/queue-lib.sh" "$TMP/nochk/scripts/_internal/"
out=$(bash "$TMP/nochk/scripts/batch-state.sh" "$TMP/sk1/.specops/batch-s" "$TMP/sk1/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && printf '%s' "$out" | grep -q 'FR-1: SKIP' && printf '%s' "$out" | sed -n '/\[드리프트\]/,/^\[/p' | grep -q 'FR-9'; then
  ok "T-skip.h 분류기 부재 → SKIP·placeholder 를 빼지 않고 종전대로 센다(exit 1)"
else
  nope "T-skip.h" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-220)"
fi
#   같은 id 가 실 행과 placeholder 행으로 겹치면(복붙 실수) 실 FR 이다 — 드리프트에서 빼지 않는다
_skipfx "$TMP/skd" IMPL_DONE
printf '| FR-7 | 주문 취소 | M1 | should | (TBD) |\n| FR-7 | <한 줄> | M1 | should | (TBD) |\n' >> "$TMP/skd/req.md"
out=$(bash "$SCRIPT" "$TMP/skd/.specops/batch-s" "$TMP/skd/req.md" 2>&1); code=$?
[ "$code" -eq 1 ] && printf '%s' "$out" | sed -n '/\[드리프트\]/,/^\[/p' | grep -q 'FR-7' \
  && ok "T-skip.i 실 행과 placeholder 행이 겹친 id → 여전히 드리프트" || nope "T-skip.i" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"

# ── T-fid: IMPL_DONE 인데 FID 칸이 비었거나 TBD 인 행 (20261009-startall-silent-pass) ──
#   종전엔 그런 행을 **말없이 건너뛰고** "N FID 검사" 건수에는 포함했다 — 모델이 FID 칸 갱신을 빠뜨리면
#   그 FR 은 산출물·진행기록 검사를 통째로 피하고 게이트는 OK 를 냈다(실측 20261008: evidence 없는 FR 이 `BATCH-GATE: OK (4 FID 검사)`).
for cell in 'TBD' '—' ''; do
  mkdir -p "$TMP/fid/.specops/batch-f" "$TMP/fid/.specops/20260101-f1"
  cat > "$TMP/fid/.specops/batch-f/queue.md" <<EOF
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | 20260101-f1 | one | IMPL_DONE |
| FR-2 | $cell | two | IMPL_DONE |
EOF
  : > "$TMP/fid/.specops/20260101-f1/review-base.sha"; : > "$TMP/fid/.specops/20260101-f1/evidence.md"; : > "$TMP/fid/.specops/20260101-f1/review-request.md"
  printf '## 20260101-f1\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n' > "$TMP/fid/.specops/session-progress.md"
  printf '| FR-1 | a | M1 | must | s |\n| FR-2 | b | M1 | must | s |\n' > "$TMP/fid/req.md"
  out=$(bash "$SCRIPT" --gate "$TMP/fid/.specops/batch-f" "$TMP/fid/req.md" 2>&1); code=$?
  if [ "$code" -eq 1 ] && printf '%s' "$out" | grep -q 'FID 미기재' && printf '%s' "$out" | grep -q 'FR-2' && printf '%s' "$out" | grep -q 'BATCH-GATE: BLOCK'; then
    ok "T-fid.a ★ FID 칸 '${cell:-(빈칸)}' 인 IMPL_DONE 행 → --gate BLOCK (건너뛰지 않는다)"
  else
    nope "T-fid.a '${cell:-(빈칸)}'" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
  fi
  out=$(bash "$SCRIPT" "$TMP/fid/.specops/batch-f" "$TMP/fid/req.md" 2>&1); code=$?
  [ "$code" -eq 1 ] && printf '%s' "$out" | grep -q 'FID 미기재' || nope "T-fid.a2 '${cell:-(빈칸)}' 기본 모드" "exit=$code"
  #   메시지는 FID 칸의 값을 그대로 보인다 — 빈칸이면 설명 칸의 글자("two")가 아니라 (빈칸) 이다
  printf '%s' "$out" | grep -qF "FR-2: FID 칸 '${cell:-(빈칸)}'" || nope "T-fid.a3 '${cell:-(빈칸)}' 메시지" "$(printf '%s' "$out" | grep 'FR-2' | head -1)"
  #   해법 명령은 절대경로다 — 하류 저장소에는 scripts/ 가 없어 상대 경로로 적으면 그대로 실행할 수 없다
  printf '%s' "$out" | grep -qE '해법: bash "/[^"]*/scripts/_internal/queue-set-status\.sh"' || nope "T-fid.a4 '${cell:-(빈칸)}' 해법 경로" "$(printf '%s' "$out" | grep '해법' | head -1)"
  rm -rf "$TMP/fid"
done
#   건수는 실제로 검사한 FID 만 센다
mkdir -p "$TMP/fidc/.specops/batch-f" "$TMP/fidc/.specops/20260101-f1"
printf '| FR-ID | FID | FR 설명(1줄) | Status |\n|---|---|---|---|\n| FR-1 | 20260101-f1 | one | IMPL_DONE |\n| FR-2 | 20260101-f2 | two | MERGED |\n' > "$TMP/fidc/.specops/batch-f/queue.md"
: > "$TMP/fidc/.specops/20260101-f1/review-base.sha"; : > "$TMP/fidc/.specops/20260101-f1/evidence.md"; : > "$TMP/fidc/.specops/20260101-f1/review-request.md"
printf '## 20260101-f1\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n' > "$TMP/fidc/.specops/session-progress.md"
printf '| FR-1 | a | M1 | must | s |\n| FR-2 | b | M1 | must | s |\n' > "$TMP/fidc/req.md"
out=$(bash "$SCRIPT" --gate "$TMP/fidc/.specops/batch-f" "$TMP/fidc/req.md" 2>&1); code=$?
[ "$code" -eq 0 ] && printf '%s' "$out" | grep -q '1 FID 검사' \
  && ok "T-fid.b 정상 batch 는 불변 — 건수는 실제로 검사한 FID 수" || nope "T-fid.b" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
#   requirements 의 굵은 ID 행도 queue 와 대조한다(종전엔 정규식에 안 걸려 드리프트 검사에서 빠졌다)
printf '| **FR-3** | c | M1 | must | s |\n' >> "$TMP/fidc/req.md"
out=$(bash "$SCRIPT" "$TMP/fidc/.specops/batch-f" "$TMP/fidc/req.md" 2>&1); code=$?
[ "$code" -eq 1 ] && printf '%s' "$out" | sed -n '/\[드리프트\]/,/^\[/p' | grep -q 'FR-3' \
  && ok "T-fid.c requirements 의 굵은 ID FR 도 드리프트 대조에 든다" || nope "T-fid.c" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"

# ── T3.c: FR-ID 중복 **만** 있어도 기본 모드는 exit 1 ──
#   T3.a 의 픽스처는 FID 칸이 FID 가 아니라(x·y) [FID 미기재] 로도 exit 1 이 된다 — 중복 판정의 종료 코드를 꺼도 통과했다(변이 실측 20261009).
#   여기서는 다른 결함이 하나도 없게 만든다: 유효 FID · 산출물 3종 · 진행 기록.
mkdir -p "$TMP/c2/.specops/batch-z" "$TMP/c2/.specops/20260101-dup"
cat > "$TMP/c2/.specops/batch-z/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-3 | 20260101-dup | dup1 | IMPL_DONE |
| FR-3 | 20260101-dup | dup2 | IMPL_DONE |
EOF
: > "$TMP/c2/.specops/20260101-dup/review-base.sha"; : > "$TMP/c2/.specops/20260101-dup/evidence.md"; : > "$TMP/c2/.specops/20260101-dup/review-request.md"
printf '## 20260101-dup\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n' > "$TMP/c2/.specops/session-progress.md"
printf '| FR-3 | a | M1 | must | s |\n' > "$TMP/c2/req.md"
out=$(bash "$SCRIPT" "$TMP/c2/.specops/batch-z" "$TMP/c2/req.md" 2>&1); code=$?
if [ "$code" -eq 1 ] && echo "$out" | grep -q '\[중복\]' && ! echo "$out" | grep -qE '\[(FID 미기재|미완|드리프트|산출물)'; then
  ok "T3.c 중복만 있는 queue → exit 1 (다른 결함 표지 없음)"
else
  nope "T3.c 중복 단독" "exit=$code out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-260)"
fi
# 대조 — 같은 픽스처에서 중복 행을 지우면 exit 0
cat > "$TMP/c2/.specops/batch-z/queue.md" <<'EOF'
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-3 | 20260101-dup | dup1 | IMPL_DONE |
EOF
bash "$SCRIPT" "$TMP/c2/.specops/batch-z" "$TMP/c2/req.md" >/dev/null 2>&1; code=$?
[ "$code" -eq 0 ] && ok "T3.d 대조 — 중복을 없애면 exit 0" || nope "T3.d" "exit=$code"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
