#!/usr/bin/env bash
# check-review-audit.sh 검증 — 리뷰 산출물 ↔ dispatch-log 기록 대조 (F1 teeth)
#
# 배경 (dogfood test1 20260717-approval-rbac, 2026-07-21): Phase B/C 판정 리포트
#   `reviews/T10-B-report.md` 는 존재하는데 `dispatch-log.md` 에 T10 행이 없었다.
#   implementing-ko 는 "Evaluator degradation 을 dispatch-log 에 기록" 을 명문화했지만
#   산출물이 그 규칙을 지켰는지 검사하는 층이 0 이라 위반이 조용히 통과했다.
#
# 스코프 한계 (5원칙 5 — 정직): 본 검사는 **누락(omission)** 만 잡는다. dispatch-log 행이
#   존재하되 내용이 거짓인 falsification(부모 인라인 판정을 서브에이전트로 기재)은
#   자기보고라 파일 대조로 판별 불가 — transcript join 은 context-resets-ko 의
#   implement↔verify 리셋 경계 때문에 fail-open 이라 실효가 낮다 (#120 자기보고 구조적 한계).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
AUDIT="$PLUGIN/scripts/_internal/check-review-audit.sh"

# FID 트리 합성 — $1=베이스디렉토리, $2=FID
_mkfid() {
  mkdir -p "$1/.specops/$2/reviews"
}

# ── T1.a reviews 디렉토리 부재 → SKIP (fail-open) ─────
TMPDIR=$(mktemp -d) || exit 1
mkdir -p "$TMPDIR/.specops/F1"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
if [ "$ec" -eq 0 ] && echo "$out" | grep -q "REVIEW-AUDIT: SKIP"; then
  ok "T1.a reviews 부재 → SKIP exit 0"
else
  nope "T1.a" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T1.b dispatch-log 부재 → SKIP (fail-open, 무관 구조 월권 금지) ─────
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
echo "# T1 Phase B — PASS" > "$TMPDIR/.specops/F1/reviews/T1-B-report.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
if [ "$ec" -eq 0 ] && echo "$out" | grep -q "REVIEW-AUDIT: SKIP"; then
  ok "T1.b dispatch-log 부재 → SKIP exit 0"
else
  nope "T1.b" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T1.c 리포트 0건 (dispatch-log 만 존재) → SKIP ─────
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
echo "| 1 | ts | A:T1 | implementer-ko | DONE | - |" > "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
if [ "$ec" -eq 0 ] && echo "$out" | grep -q "REVIEW-AUDIT: SKIP"; then
  ok "T1.c 리포트 0건 → SKIP exit 0"
else
  nope "T1.c" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T2.a 전 리포트가 dispatch-log 에 기록 → PASS ─────
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
echo "# T1 Phase B" > "$TMPDIR/.specops/F1/reviews/T1-B-report.md"
echo "# T2 Phase C" > "$TMPDIR/.specops/F1/reviews/T2-C-report.md"
cat > "$TMPDIR/.specops/F1/dispatch-log.md" <<'EOF'
| 1 | ts | B:T1 | spec-reviewer-ko | PASS | reviews/T1-B-report.md |
| 2 | ts | C:T2 | code-reviewer-ko | PASS | reviews/T2-C-report.md |
EOF
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
if [ "$ec" -eq 0 ] && echo "$out" | grep -q "REVIEW-AUDIT: PASS"; then
  ok "T2.a 전건 기록 → PASS exit 0"
else
  nope "T2.a" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T2.b 리포트 있는데 dispatch-log 행 부재 → FAIL + task-id 명시 ─────
#   (실측 재현: test1 approval-rbac T10)
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
echo "# T7 Phase B" > "$TMPDIR/.specops/F1/reviews/T7-B-report.md"
echo "# T10 Phase B — PASS (인라인)" > "$TMPDIR/.specops/F1/reviews/T10-B-report.md"
echo "| 22 | ts | B:T7 | spec-reviewer-ko | PASS | - |" > "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
if [ "$ec" -ne 0 ] && echo "$out" | grep -q "REVIEW-AUDIT: FAIL" && echo "$out" | grep -q "T10"; then
  ok "T2.b 미기록 리포트 → FAIL exit≠0 + task-id 명시"
else
  nope "T2.b" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T2.c 부분문자열 오매칭 금지 — 위험 방향은 짧은 id ─────
#   순진한 `grep -q "$tid"` 는 T1 리포트를 `B:T10` 행이 덮어 미기록을 PASS 로 위장한다.
#   (mutation 검증: 경계 앵커를 제거하면 본 케이스만 FAIL 해야 한다)
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
echo "# T1 Phase C" > "$TMPDIR/.specops/F1/reviews/T1-C-report.md"
echo "| 1 | ts | C:T10 | code-reviewer-ko | PASS | - |" > "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
if [ "$ec" -ne 0 ] && echo "$out" | grep -Eq "미기록 리뷰: (.* )?T1( |$)"; then
  ok "T2.c T10 행이 T1 리포트를 덮지 않음 (경계 매칭)"
else
  nope "T2.c" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T2.f 역방향 경계 (T1 행이 T10 리포트를 덮지 않음) ─────
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
echo "# T10 Phase C" > "$TMPDIR/.specops/F1/reviews/T10-C-report.md"
echo "| 1 | ts | C:T1 | code-reviewer-ko | PASS | - |" > "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
if [ "$ec" -ne 0 ] && echo "$out" | grep -q "T10"; then
  ok "T2.f T1 행이 T10 리포트를 덮지 않음 (역방향 경계)"
else
  nope "T2.f" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T2.d feedback(FAIL 판정) 리포트도 대조 대상 ─────
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
echo "# T3 Phase C feedback" > "$TMPDIR/.specops/F1/reviews/T3-C-feedback.md"
echo "| 1 | ts | B:T9 | spec-reviewer-ko | PASS | - |" > "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
if [ "$ec" -ne 0 ] && echo "$out" | grep -q "T3"; then
  ok "T2.d feedback 리포트도 대조 대상"
else
  nope "T2.d" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T2.g 산문-only tid 위장 → FAIL (downstream-dogfood: T6·T9 산문 false-pass) ─────
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
echo "# T6 Phase B" > "$TMPDIR/.specops/F1/reviews/T6-B-report.md"
cat > "$TMPDIR/.specops/F1/dispatch-log.md" <<'EOF'
| 1 | ts | B:T9 | spec-reviewer-ko | PASS | reviews/T9-B-report.md |
Note: blocked on T6 dependency (prose only — not an audit row)
EOF
echo "# T9 Phase B" > "$TMPDIR/.specops/F1/reviews/T9-B-report.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
if [ "$ec" -ne 0 ] && echo "$out" | grep -q "REVIEW-AUDIT: FAIL" && echo "$out" | grep -q "T6"; then
  ok "T2.g 산문-only T6 → FAIL (구조화 행 필수)"
else
  nope "T2.g" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T2.h 템플릿 섹션 스코프 (## task-T4: + Phase B 행) → PASS ─────
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
echo "# T4 Phase B" > "$TMPDIR/.specops/F1/reviews/T4-B-report.md"
cat > "$TMPDIR/.specops/F1/dispatch-log.md" <<'EOF'
## task-T4: component

| # | 시각 | Phase | agent | 결과 | feedback 경로 |
|---|---|---|---|---|---|
| 1 | ts | A | implementer-ko | PASS | - |
| 2 | ts | B | spec-reviewer-ko | PASS | - |
EOF
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
if [ "$ec" -eq 0 ] && echo "$out" | grep -q "REVIEW-AUDIT: PASS"; then
  ok "T2.h ## task-T4: 섹션 + Phase B 행 → PASS"
else
  nope "T2.h" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T2.e 리뷰 외 파일(review.diff 등)은 대조 제외 ─────
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
echo "diff --git a b" > "$TMPDIR/.specops/F1/reviews/review.diff"
echo "# 종합" > "$TMPDIR/.specops/F1/reviews/code-review.md"
echo "| 1 | ts | A:T1 | implementer-ko | DONE | - |" > "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
if [ "$ec" -eq 0 ]; then
  ok "T2.e 비-Phase 리뷰 파일은 대조 제외 → exit 0"
else
  nope "T2.e" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T3.a run-verification 배선 — 미기록 리뷰가 VERIFY 를 FAIL 시킨다 ─────
#   teeth 의 본체: 실행-근거 게이트(R-1/R-2)가 VERIFY: PASS 만 면제로 인정하므로,
#   여기서 FAIL 이면 커밋이 실제로 열리지 않는다.
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
cat > "$TMPDIR/.specops/F1/tasks.md" <<'EOF'
- [ ] **스텝 4**: 실행: `bash scripts/tests/test-ok.sh`
EOF
mkdir -p "$TMPDIR/scripts/tests"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMPDIR/scripts/tests/test-ok.sh"
echo "# T10 Phase B" > "$TMPDIR/.specops/F1/reviews/T10-B-report.md"
echo "| 1 | ts | B:T1 | spec-reviewer-ko | PASS | - |" > "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$PLUGIN/scripts/_internal/run-verification.sh" F1 2>&1); ec=$?
if [ "$ec" -ne 0 ] && ! echo "$out" | grep -q "^VERIFY: PASS"; then
  ok "T3.a 미기록 리뷰 → run-verification 이 VERIFY: PASS 를 거부"
else
  nope "T3.a" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T3.b 정상 기록이면 run-verification 무영향 (회귀 방지) ─────
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
cat > "$TMPDIR/.specops/F1/tasks.md" <<'EOF'
- [ ] **스텝 4**: 실행: `bash scripts/tests/test-ok.sh`
EOF
mkdir -p "$TMPDIR/scripts/tests"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMPDIR/scripts/tests/test-ok.sh"
echo "# T1 Phase B" > "$TMPDIR/.specops/F1/reviews/T1-B-report.md"
echo "| 1 | ts | B:T1 | spec-reviewer-ko | PASS | - |" > "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$PLUGIN/scripts/_internal/run-verification.sh" F1 2>&1); ec=$?
if [ "$ec" -eq 0 ] && echo "$out" | grep -q "^VERIFY: PASS"; then
  ok "T3.b 정상 기록 → VERIFY: PASS 보존 (회귀 0)"
else
  nope "T3.b" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T3.c 테스트 명령 0건 FID 도 감사 대상 (NO COMMANDS 우회 구멍 봉합) ─────
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
echo "# tasks (실행 명령 없음)" > "$TMPDIR/.specops/F1/tasks.md"
echo "# T10 Phase B" > "$TMPDIR/.specops/F1/reviews/T10-B-report.md"
echo "| 1 | ts | B:T1 | spec-reviewer-ko | PASS | - |" > "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$PLUGIN/scripts/_internal/run-verification.sh" F1 2>&1); ec=$?
if [ "$ec" -ne 0 ] && ! echo "$out" | grep -q "^VERIFY: NO COMMANDS"; then
  ok "T3.c 명령 0건 FID 도 review-audit 통과 필수"
else
  nope "T3.c" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ══════════════════════════════════════════════════════════════════════════
# 역방향 대조 (20260721-review-audit-reverse) — dispatch-log 가 **참조하는** reviews 파일 실재 확인
#
#   기존 검사는 reviews → dispatch-log 한 방향뿐이라, **리뷰 리포트를 아예 파일로 안 남기면**
#   reviews/ 부재 = SKIP 으로 통째로 비껴갔다 (dogfood 20260721 HIGH-4).
#   실물: `.specops/20260713-llm-eval-nrun/dispatch-log.md` 가 `reviews/all-B-report.md`·
#   `all-C-report.md` 를 기록해 놓고 그 파일이 없다 — 판정을 대화로만 흘린 것이다.
#
#   판별자는 dispatch-log 의 존재다. 직접 TDD·self-maintenance·e2e fixture 는 dispatch 루프를
#   돌지 않아 dispatch-log 가 없고(실측: reviews 0건 FID 5건 중 4건이 그렇다), 그런 작업까지
#   리뷰 산출물을 요구하면 정당한 흐름을 막는다(false-block). 로그가 있다 = 루프를 돌았다 =
#   판정 산출물이 있어야 한다.
# ══════════════════════════════════════════════════════════════════════════

# ── T4.a ★ dispatch-log 가 참조하는 reviews 파일 부재 → FAIL ──
TMPDIR=$(mktemp -d) || exit 1
mkdir -p "$TMPDIR/.specops/F1"     # reviews/ 없음 — 기존 검사는 여기서 SKIP 했다
cat > "$TMPDIR/.specops/F1/dispatch-log.md" <<'EOF'
| # | ts | Phase | agent | 결과 | feedback |
|---|---|---|---|---|---|
| 1 | 2026-07-13T00:38Z | A | implementer-ko | DONE | - |
| 2 | 2026-07-13T00:41Z | B | spec-reviewer-ko | PASS | reviews/all-B-report.md |
| 3 | 2026-07-13T00:48Z | C | code-reviewer-ko | PASS | reviews/all-C-report.md |
EOF
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
if [ "$ec" -ne 0 ] && echo "$out" | grep -q "all-B-report.md"; then
  ok "T4.a ★ dispatch-log 참조 reviews 파일 부재 → FAIL (HIGH-4 실물)"
else
  nope "T4.a 역방향 미검출" "ec=$ec out='$out'"
fi
rm -rf "$TMPDIR"

# ── T4.b 참조 파일이 실재하면 PASS ──
TMPDIR=$(mktemp -d) || exit 1
_mkfid "$TMPDIR" F1
printf '| 2 | ts | B | spec-reviewer-ko | PASS | reviews/all-B-report.md |\n' > "$TMPDIR/.specops/F1/dispatch-log.md"
echo "# B 판정" > "$TMPDIR/.specops/F1/reviews/all-B-report.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
[ "$ec" -eq 0 ] && ok "T4.b 참조 파일 실재 → PASS" || nope "T4.b" "ec=$ec out='$out'"
rm -rf "$TMPDIR"

# ── T4.c ★ 템플릿 placeholder 는 대조 대상 아님 (false-block 금지) ──
#   dispatch-log 템플릿은 `reviews/<task-id>-B-feedback.md` 같은 꺾쇠 자리표시자를 담고 있다.
#   이것을 실재 요구하면 템플릿을 복사한 모든 FID 가 즉시 FAIL 한다.
TMPDIR=$(mktemp -d) || exit 1
mkdir -p "$TMPDIR/.specops/F1"
cat > "$TMPDIR/.specops/F1/dispatch-log.md" <<'EOF'
| 2 | <ISO-8601> | B | spec-reviewer-ko | FAIL | reviews/<task-id>-B-feedback.md |
EOF
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
[ "$ec" -eq 0 ] && ok "T4.c 템플릿 placeholder → 대조 제외 (false-block 금지)" \
  || nope "T4.c placeholder 오검출" "ec=$ec out='$out'"
rm -rf "$TMPDIR"

# ── T4.d ★★ dispatch-log 자체가 없으면 SKIP (직접 TDD·self-maintenance 면제) ──
#   실측 근거: reviews 0건 FID 5건 중 4건(greet-cli-e2e fixture·self-maintenance 3건)이
#   dispatch-log 를 갖지 않는다. 이들까지 요구하면 플러그인 자기 유지보수가 통째로 막힌다.
TMPDIR=$(mktemp -d) || exit 1
mkdir -p "$TMPDIR/.specops/F1"
echo "# tasks" > "$TMPDIR/.specops/F1/tasks.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
[ "$ec" -eq 0 ] && ok "T4.d ★★ dispatch-log 부재 → SKIP (직접 작업 면제)" \
  || nope "T4.d 직접 작업 false-block" "ec=$ec out='$out'"
rm -rf "$TMPDIR"

# ── T5 병렬 C 리포트 사후 대조 (20261006-review-bc-parallel) ──
#   PENDING(병렬 C 리포트는 dispatch-log 에 Phase 셀 BC-PAR-CHECK:<tid> 행이 있어야 한다. 없으면 B PASS 근거가 부모 선언뿐이다.
# $1=베이스 $2=tid $3=C 리포트 헤더(PENDING 여부) — B/C 리포트 경로 행은 기존 규칙(경로 리터럴)대로 남긴다
_par_fid() {
  _mkfid "$1" F1
  echo "# $2 Phase B — PASS" > "$1/.specops/F1/reviews/$2-B-report.md"
  printf '# %s Phase C\n**Phase B 상태**: %s\n' "$2" "$3" > "$1/.specops/F1/reviews/$2-C-report.md"
  {
    echo "| # | 시각 | Phase | agent | 결과 | 경로 |"
    echo "|---|---|---|---|---|---|"
    echo "| 1 | 2026-10-06T01:00:00Z | End-loaded-B | spec-reviewer-ko | PASS | reviews/$2-B-report.md |"
    echo "| 2 | 2026-10-06T01:00:00Z | End-loaded-C | code-reviewer-ko | PASS | reviews/$2-C-report.md |"
  } > "$1/.specops/F1/dispatch-log.md"
}
TMPDIR=$(mktemp -d) || exit 1
_par_fid "$TMPDIR" T1 'PENDING(병렬 — 부모 사후 대조)'
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
if [ "$ec" -eq 1 ] && echo "$out" | grep -q "BC-PAR-CHECK" && echo "$out" | grep -q "T1"; then
  ok "T5.a PENDING(병렬 C 리포트 + 사후 대조 행 없음 → FAIL (원인·tid 출력)"
else nope "T5.a" "ec=$ec out='$out'"; fi
echo "| 3 | 2026-10-06T01:05:00Z | BC-PAR-CHECK:T1 | parent | B PASS | reviews/T1-B-report.md reviews/T1-C-report.md |" >> "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
[ "$ec" -eq 0 ] && echo "$out" | grep -q "REVIEW-AUDIT: PASS" && ok "T5.b 사후 대조 행 있음 → PASS" \
  || nope "T5.b" "ec=$ec out='$out'"
rm -rf "$TMPDIR"

TMPDIR=$(mktemp -d) || exit 1
_par_fid "$TMPDIR" T1 'PASS (spec-reviewer-ko 인용)'
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
[ "$ec" -eq 0 ] && ok "T5.c PENDING 부재(직렬·기존 FID) → 종전과 동일 PASS (행 불요)" \
  || nope "T5.c 무영향 위반" "ec=$ec out='$out'"
rm -rf "$TMPDIR"

TMPDIR=$(mktemp -d) || exit 1
_par_fid "$TMPDIR" T1 'PENDING(병렬 — 부모 사후 대조)'
# T10 은 리포트·경로 행·사후 대조 행이 모두 있다 — T1 만 대조가 빠진 상태에서 T10 행이 T1 을 가리지 못해야 한다(dangling 참조로 FAIL 하는 위양성 방지)
printf '# T10 Phase B — PASS\n' > "$TMPDIR/.specops/F1/reviews/T10-B-report.md"
printf '# T10 Phase C\n**Phase B 상태**: PENDING(병렬 — 부모 사후 대조)\n' > "$TMPDIR/.specops/F1/reviews/T10-C-report.md"
{
  echo "| 3 | 2026-10-06T01:01:00Z | End-loaded-B | spec-reviewer-ko | PASS | reviews/T10-B-report.md |"
  echo "| 4 | 2026-10-06T01:01:00Z | End-loaded-C | code-reviewer-ko | PASS | reviews/T10-C-report.md |"
  echo "| 5 | 2026-10-06T01:05:00Z | BC-PAR-CHECK:T10 | parent | B PASS | reviews/T10-B-report.md reviews/T10-C-report.md |"
} >> "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
[ "$ec" -eq 1 ] && echo "$out" | grep -qE ': T1$' && ok "T5.d T10 행이 T1 의 사후 대조를 대신하지 못한다 (부분문자열 경계 — 누락은 T1 만)" \
  || nope "T5.d" "ec=$ec out='$out'"
rm -rf "$TMPDIR"

TMPDIR=$(mktemp -d) || exit 1
_par_fid "$TMPDIR" T1 'PENDING(병렬 — 부모 사후 대조)'
echo '| 3 | 2026-10-06T01:05:00Z | BC-PAR-CHECK:<tid> | parent | B PASS | reviews/<tid>-B-report.md |' >> "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
[ "$ec" -eq 1 ] && ok "T5.e 꺾쇠 placeholder 행은 사후 대조로 인정하지 않는다" \
  || nope "T5.e" "ec=$ec out='$out'"
rm -rf "$TMPDIR"

# B FAIL 케이스: 훅이 저장하는 -B-feedback.md 가 실재하고 행이 '폐기'를 표기하면 인정한다
TMPDIR=$(mktemp -d) || exit 1
_par_fid "$TMPDIR" T1 'PENDING(병렬 — 부모 사후 대조)'
echo "# T1 B feedback" > "$TMPDIR/.specops/F1/reviews/T1-B-feedback.md"
echo "| 3 | 2026-10-06T01:05:00Z | BC-PAR-CHECK:T1 | parent | C 폐기(B FAIL) | reviews/T1-B-report.md reviews/T1-B-feedback.md reviews/T1-C-report.md |" >> "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
[ "$ec" -eq 0 ] && ok "T5.f B FAIL(B-feedback 실재) + 폐기 행 → 인정" \
  || nope "T5.f" "ec=$ec out='$out'"
rm -rf "$TMPDIR"

# 위장 차단: B-feedback(=B 비통과)이 있는데 행이 'B PASS' 라고 적으면 모순으로 FAIL
TMPDIR=$(mktemp -d) || exit 1
_par_fid "$TMPDIR" T1 'PENDING(병렬 — 부모 사후 대조)'
echo "# T1 B feedback" > "$TMPDIR/.specops/F1/reviews/T1-B-feedback.md"
echo "| 3 | 2026-10-06T01:05:00Z | BC-PAR-CHECK:T1 | parent | B PASS | reviews/T1-B-report.md reviews/T1-B-feedback.md reviews/T1-C-report.md |" >> "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
[ "$ec" -eq 1 ] && echo "$out" | grep -q "모순" && ok "T5.g B FAIL 을 B PASS 로 적은 대조 행 → 모순 FAIL" \
  || nope "T5.g" "ec=$ec out='$out'"
rm -rf "$TMPDIR"

# 역방향: B-feedback 이 없는(B 통과) FID 에서 행이 폐기라고 적어도 모순
TMPDIR=$(mktemp -d) || exit 1
_par_fid "$TMPDIR" T1 'PENDING(병렬 — 부모 사후 대조)'
echo "| 3 | 2026-10-06T01:05:00Z | BC-PAR-CHECK:T1 | parent | C 폐기(B FAIL) | reviews/T1-B-report.md reviews/T1-C-report.md |" >> "$TMPDIR/.specops/F1/dispatch-log.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
[ "$ec" -eq 1 ] && echo "$out" | grep -q "모순" && ok "T5.h B 통과인데 폐기라고 적은 행 → 모순 FAIL" \
  || nope "T5.h" "ec=$ec out='$out'"
rm -rf "$TMPDIR"

# 본문 인용 오탐 방지: 직렬 C 리포트가 본문에서 PENDING(병렬 을 인용만 해도 병렬로 오인하지 않는다
TMPDIR=$(mktemp -d) || exit 1
_par_fid "$TMPDIR" T1 'PASS (spec-reviewer-ko 인용)'
echo '인용: PENDING(병렬 — 부모 사후 대조) 문구 설명' >> "$TMPDIR/.specops/F1/reviews/T1-C-report.md"
out=$(cd "$TMPDIR" && bash "$AUDIT" F1 2>&1); ec=$?
[ "$ec" -eq 0 ] && echo "$out" | grep -q "REVIEW-AUDIT: PASS" && ok "T5.i 직렬 C 리포트가 본문에서 PENDING(병렬 을 인용만 해도 병렬로 오인하지 않는다" \
  || nope "T5.i" "ec=$ec out='$out'"
rm -rf "$TMPDIR"

finish
