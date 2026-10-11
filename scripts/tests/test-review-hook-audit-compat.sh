#!/usr/bin/env bash
# test-review-hook-audit-compat — 훅 저장본 ↔ 부모 저장본 감사 동치 (AC-R-1) · FID 20260914-review-return-summary
# SAVE_REVIEW_HOOK 로 훅 경로를 덮어쓸 수 있다 — RED 확인(부재 경로)용.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
HOOK=${SAVE_REVIEW_HOOK:-$PLUGIN/hooks/save-review-report.sh}
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
FID=20260101-compat
BODY_B='# 🎯 스펙 준수 리뷰
## 종합 판정
- ✅ **PASS**'
BODY_C='# 🔍 코드 품질 리뷰
## 🔴 Critical
없음
## 종합 판정
- ✅ **READY_TO_MERGE**'

_common() {  # $1=root — 두 픽스처 공통(리뷰 파일 제외)
  local f="$1/.specops/$FID"
  mkdir -p "$f/reviews" "$1/.specops/batch-c1"
  # tasks.md 픽스처 — 제목·yaml 펜스·"- id:" 줄머리를 소스에 쓰지 않는다 (이 파일을 담는 바깥 tasks.md 의 DAG 파서·id grep 오염 방지)
  printf 'review_mode: end-loaded\ntasks:\n  - id: T1\n    depends_on: []\n  - id: T2\n    depends_on: [T1]\n' > "$f/tasks.md"
  cat > "$f/dispatch-log.md" <<'EOF'
| # | ts | Phase | agent | 결과 | 경로 |
|---|---|---|---|---|---|
| 1 | 2026-01-01T00:00:00Z | End-loaded-B | spec-reviewer-ko | PASS | reviews/T1-B-report.md |
| 2 | 2026-01-01T00:00:00Z | End-loaded-B | spec-reviewer-ko | PASS | reviews/T2-B-report.md |
| 3 | 2026-01-01T00:00:00Z | End-loaded-C | code-reviewer-ko | PASS | reviews/T1-C-report.md |
| 4 | 2026-01-01T00:00:00Z | End-loaded-C | code-reviewer-ko | PASS | reviews/T2-C-report.md |
EOF
  cat > "$1/.specops/batch-c1/queue.md" <<EOF
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | $FID | one | IMPL_DONE |
EOF
  : > "$f/review-base.sha"; : > "$f/evidence.md"
  echo "end-loaded: Phase B/C already covered full FID diff" > "$f/review-skip.md"
  printf '{"effective":"strict","computed":"strict","mode":"live","reductions_allowed":[]}\n' > "$f/risk-profile.json"
  printf '## %s\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n' "$FID" > "$1/.specops/session-progress.md"
  printf '| FR-1 | compat | M1 | must | s | f |\n' > "$1/req.md"
}

A="$TD/hook"; B="$TD/parent"
_common "$A"; _common "$B"

# A: 훅이 저장 (B 1회 dispatch · C 1회 dispatch)
_feed() {  # $1=root $2=message
  jq -n --arg cwd "$1" --arg m "$2" '{cwd:$cwd,stop_hook_active:false,last_assistant_message:$m}' \
    | env -u SPECOPS_GOVERNANCE_PROFILE SPECOPS_CONFIG="$TD/none.yaml" bash "$HOOK" >/dev/null 2>&1
}
blk() { printf '<<<REVIEW fid=%s tid=%s phase=%s verdict=%s>>>\n%s\n<<<END>>>\n' "$FID" "$1" "$2" "$3" "$4"; }
_feed "$A" "$(blk T1 B PASS "$BODY_B")
$(blk T2 B PASS "$BODY_B")"
_feed "$A" "$(blk T1 C READY_TO_MERGE "$BODY_C")
$(blk T2 C READY_TO_MERGE "$BODY_C")"

# B: 부모가 기존 방식으로 저장
for t in T1 T2; do
  printf '%s\n' "$BODY_B" > "$B/.specops/$FID/reviews/$t-B-report.md"
  printf '%s\n' "$BODY_C" > "$B/.specops/$FID/reviews/$t-C-report.md"
done

# ── T1.a 산출물 byte 동일 ──
if diff -r "$A/.specops/$FID/reviews" "$B/.specops/$FID/reviews" >/dev/null 2>&1; then ok "T1.a AC-R-1 reviews 트리 byte 동일"
else nope "T1.a AC-R-1 reviews 트리" "$(diff -r "$A/.specops/$FID/reviews" "$B/.specops/$FID/reviews" 2>&1 | head -3 | tr '\n' ' ')"; fi

# ── T1.b~d 감사 검사 3종 판정 동치 (루트 경로만 정규화) ──
_norm() { sed -e "s|$A|ROOT|g" -e "s|$B|ROOT|g"; }
for chk in check-review-audit check-review-presence; do
  oa=$(cd "$A" && bash "$PLUGIN/scripts/_internal/$chk.sh" "$FID" 2>&1); ra=$?
  ob=$(cd "$B" && bash "$PLUGIN/scripts/_internal/$chk.sh" "$FID" 2>&1); rb=$?
  if [ "$ra" = "$rb" ] && [ "$(printf '%s' "$oa" | _norm)" = "$(printf '%s' "$ob" | _norm)" ]; then ok "T1.b AC-R-1 $chk 동치 (rc=$ra)"
  else nope "T1.b AC-R-1 $chk" "A rc=$ra '$oa' / B rc=$rb '$ob'"; fi
done
oa=$(bash "$PLUGIN/scripts/batch-state.sh" "$A/.specops/batch-c1" "$A/req.md" 2>&1); ra=$?
ob=$(bash "$PLUGIN/scripts/batch-state.sh" "$B/.specops/batch-c1" "$B/req.md" 2>&1); rb=$?
if [ "$ra" = "$rb" ] && [ "$(printf '%s' "$oa" | _norm)" = "$(printf '%s' "$ob" | _norm)" ]; then ok "T1.c AC-R-1 batch-state 동치 (rc=$ra)"
else nope "T1.c AC-R-1 batch-state" "A rc=$ra / B rc=$rb"; fi
if [ "$(cd "$A" && bash "$PLUGIN/scripts/_internal/check-review-audit.sh" "$FID" 2>&1 | grep -c 'REVIEW-AUDIT: PASS')" = "1" ]; then
  ok "T1.d AC-R-1 훅 저장본 감사 PASS"
else nope "T1.d AC-R-1 감사 PASS" "$(cd "$A" && bash "$PLUGIN/scripts/_internal/check-review-audit.sh" "$FID" 2>&1 | head -2 | tr '\n' ' ')"; fi

finish
