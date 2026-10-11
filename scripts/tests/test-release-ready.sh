#!/usr/bin/env bash
# P0-3 RELEASE_READY 합성 판정 — 0=READY · 1=NOT_READY · 2=UNKNOWN
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
RR="$PLUGIN/scripts/_internal/release-ready.sh"
STATE="$PLUGIN/scripts/_internal/verification-state.sh"

_mk_base() {  # $1=dir $2=fid → git + session-progress + tasks
  local d="$1" fid="$2"
  mkdir -p "$d/.specops/$fid/reviews" "$d/src"
  printf 'x\n' > "$d/src/a.sh"
  (cd "$d" && git init -q && git add src && git -c user.name=t -c user.email=t@e.com commit -qm init)
  printf '<!-- active-fid: %s -->\n## %s\n- 2026-08-03 10:00 /verify PASS\n- 2026-08-03 10:05 /receive-review DONE\n' \
    "$fid" "$fid" > "$d/.specops/session-progress.md"
  printf '# tasks\n' > "$d/.specops/$fid/tasks.md"
  # Wave A 구조화 audit 행 (경로 + B:T1/C:T1)
  cat > "$d/.specops/$fid/dispatch-log.md" <<'EOF'
| # | 시각 | Phase | agent | 결과 | feedback |
|---|---|---|---|---|---|
| 1 | ts | B:T1 | spec-reviewer-ko | PASS | reviews/T1-B-report.md |
| 2 | ts | C:T1 | code-reviewer-ko | PASS | reviews/T1-C-report.md |
EOF
  printf '# B report\nREADY_TO_MERGE\n' > "$d/.specops/$fid/reviews/T1-B-report.md"
  printf '# C report\nREADY_TO_MERGE\n' > "$d/.specops/$fid/reviews/T1-C-report.md"
}

_ev_gates() {  # $1=evidence path — 3게이트 PASS
  cat > "$1" <<'EOF'
RUN-VERIFICATION-RESULT: PASS

## /security-review PASS
**결과**: PASS

## /integration-test PASS
**결과**: PASS

## /performance-test SKIP
**결과**: SKIP
**근거**: NFR 없음 §spec L1
EOF
}

# RR-1: 전축 PASS
TD=$(mktemp -d); FID=20260803-rr-ok
_mk_base "$TD" "$FID"
_ev_gates "$TD/.specops/$FID/evidence.md"
(cd "$TD" && bash "$STATE" record "$FID" PASS --executed 1)
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'RELEASE_READY: OK' \
  && ok "RR-1 전축 PASS → 0" || nope "RR-1" "rc=$rc out=$out"
rm -rf "$TD"

# RR-2: verify STALE
TD=$(mktemp -d); FID=20260803-rr-stale
_mk_base "$TD" "$FID"
_ev_gates "$TD/.specops/$FID/evidence.md"
(cd "$TD" && bash "$STATE" record "$FID" PASS --executed 1)
printf 'changed\n' >> "$TD/src/a.sh"
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q 'verify=STALE' \
  && ok "RR-2 STALE → 1" || nope "RR-2" "rc=$rc out=$out"
rm -rf "$TD"

# RR-3: security 섹션 부재
TD=$(mktemp -d); FID=20260803-rr-nosec
_mk_base "$TD" "$FID"
printf 'RUN-VERIFICATION-RESULT: PASS\n\n## /integration-test PASS\n**결과**: PASS\n\n## /performance-test SKIP\n**결과**: SKIP\n' \
  > "$TD/.specops/$FID/evidence.md"
(cd "$TD" && bash "$STATE" record "$FID" PASS --executed 1)
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q 'security=MISSING' \
  && ok "RR-3 security 부재 → 1" || nope "RR-3" "rc=$rc out=$out"
rm -rf "$TD"

# RR-4: performance SKIP 허용 (전축 그 외 PASS)
TD=$(mktemp -d); FID=20260803-rr-perfskip
_mk_base "$TD" "$FID"
_ev_gates "$TD/.specops/$FID/evidence.md"
(cd "$TD" && bash "$STATE" record "$FID" PASS --executed 1)
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'performance=SKIP' \
  && ok "RR-4 performance SKIP 허용" || nope "RR-4" "rc=$rc out=$out"
rm -rf "$TD"

# RR-5: integration FAIL
TD=$(mktemp -d); FID=20260803-rr-intfail
_mk_base "$TD" "$FID"
cat > "$TD/.specops/$FID/evidence.md" <<'EOF'
RUN-VERIFICATION-RESULT: PASS
## /security-review PASS
**결과**: PASS
## /integration-test FAIL
**결과**: FAIL
## /performance-test SKIP
**결과**: SKIP
EOF
(cd "$TD" && bash "$STATE" record "$FID" PASS --executed 1)
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q 'integration=FAIL' \
  && ok "RR-5 integration FAIL → 1" || nope "RR-5" "rc=$rc out=$out"
rm -rf "$TD"

# RR-6: reconcile DESYNC — session-progress 는 specify만, 증거는 verify/review
TD=$(mktemp -d); FID=20260803-rr-desync
_mk_base "$TD" "$FID"
_ev_gates "$TD/.specops/$FID/evidence.md"
(cd "$TD" && bash "$STATE" record "$FID" PASS --executed 1)
printf '<!-- active-fid: %s -->\n## %s\n- 2026-08-03 09:00 /specify DONE\n' \
  "$FID" "$FID" > "$TD/.specops/session-progress.md"
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q 'reconcile=DESYNC' \
  && ok "RR-6 DESYNC → 1" || nope "RR-6" "rc=$rc out=$out"
rm -rf "$TD"

# RR-7: review-audit FAIL — dispatch-log 가 없는 리포트 참조
TD=$(mktemp -d); FID=20260803-rr-audit
_mk_base "$TD" "$FID"
_ev_gates "$TD/.specops/$FID/evidence.md"
(cd "$TD" && bash "$STATE" record "$FID" PASS --executed 1)
printf '| reviews/T9-B-report.md |\n' > "$TD/.specops/$FID/dispatch-log.md"
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q 'review=FAIL' \
  && ok "RR-7 review-audit FAIL → 1" || nope "RR-7" "rc=$rc out=$out"
rm -rf "$TD"

# RR-8: legacy — stamp/state 없음 → 2
TD=$(mktemp -d); FID=20260803-rr-legacy
mkdir -p "$TD/.specops/$FID"
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 2 ] && echo "$out" | grep -q 'UNKNOWN' \
  && ok "RR-8 legacy → 2" || nope "RR-8" "rc=$rc out=$out"
rm -rf "$TD"

# RR-9: security FAIL
TD=$(mktemp -d); FID=20260803-rr-secfail
_mk_base "$TD" "$FID"
cat > "$TD/.specops/$FID/evidence.md" <<'EOF'
RUN-VERIFICATION-RESULT: PASS
## /security-review FAIL
**결과**: FAIL
## /integration-test PASS
**결과**: PASS
## /performance-test SKIP
**결과**: SKIP
EOF
(cd "$TD" && bash "$STATE" record "$FID" PASS --executed 1)
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -qE 'security=FAIL|crit_high=SECURITY_FAIL' \
  && ok "RR-9 security FAIL → 1" || nope "RR-9" "rc=$rc out=$out"
rm -rf "$TD"

# RR-10: pretool warn-only (비-strict·비-batch) — NOT_READY 여도 PR allow
HOOK="$PLUGIN/hooks/pretool-governance.sh"
FIX="$PLUGIN/scripts/tests/governance/fixtures/transcripts"
# shellcheck source=/dev/null
source "$PLUGIN/scripts/tests/lib/exec-transcript.sh"   # _tr_for — 실행 증거 픽스처를 샌드박스 FID 에 맞춘다
TD=$(mktemp -d); FID=20260803-rr-warn
_mk_base "$TD" "$FID"
# verify PASS state but missing security → NOT_READY
printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$TD/.specops/$FID/evidence.md"
(cd "$TD" && bash "$STATE" record "$FID" PASS --executed 1)
printf '{"effective":"standard","computed":"standard","mode":"live","reductions_allowed":[]}\n' \
  > "$TD/.specops/$FID/risk-profile.json"
# staged code so docs-only 면제 안 됨
(cd "$TD" && echo y > src/b.sh && git add src/b.sh)
mkstdin() { jq -nc --arg c "$1" --arg t "$2" '{tool_name:"Bash", tool_input:{command:$c}, transcript_path:$t}'; }
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$TD" "$FIX/pretool-with-verify-exec.jsonl")" \
  | CLAUDE_PROJECT_DIR="$TD" bash "$HOOK" 2>"$TD/stderr")
echo "$out" | grep -q '"continue":true' \
  && ! echo "$out" | grep -q '"permissionDecision":"deny"' \
  && grep -q 'RELEASE_READY warn' "$TD/stderr" \
  && ok "RR-10 warn-only allow + stderr" \
  || nope "RR-10" "out=$out stderr=$(cat "$TD/stderr")"
# R-1 에는 RELEASE 미발화
out=$(mkstdin "git commit -m x" "$(_tr_for "$TD" "$FIX/pretool-with-verify-exec.jsonl")" \
  | CLAUDE_PROJECT_DIR="$TD" bash "$HOOK" 2>"$TD/stderr2")
! grep -q 'RELEASE_READY' "$TD/stderr2" \
  && ok "RR-10b R-1에 RELEASE 미발화" \
  || nope "RR-10b" "stderr=$(cat "$TD/stderr2")"
rm -rf "$TD"

# RR-11: effective=strict + NOT_READY → hard deny
TD=$(mktemp -d); FID=20260803-rr-strict
_mk_base "$TD" "$FID"
printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$TD/.specops/$FID/evidence.md"
(cd "$TD" && bash "$STATE" record "$FID" PASS --executed 1)
printf '{"effective":"strict","computed":"strict","mode":"live","reductions_allowed":[]}\n' \
  > "$TD/.specops/$FID/risk-profile.json"
(cd "$TD" && echo y > src/b.sh && git add src/b.sh)
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$TD" "$FIX/pretool-with-verify-exec.jsonl")" \
  | CLAUDE_PROJECT_DIR="$TD" bash "$HOOK" 2>"$TD/stderr")
echo "$out" | grep -q '"permissionDecision":"deny"' \
  && echo "$out" | grep -q 'RELEASE_READY' \
  && ok "RR-11 strict + NOT_READY → deny" \
  || nope "RR-11" "out=$out stderr=$(cat "$TD/stderr")"
rm -rf "$TD"

# RR-12: ACTIVE batch + matching branch + NOT_READY → hard deny
TD=$(mktemp -d); FID=20260803-rr-batch
BID=batch-20260803-rr
_mk_base "$TD" "$FID"
mkdir -p "$TD/.specops/$BID"
: > "$TD/.specops/$BID/ACTIVE"
cat > "$TD/.specops/$BID/queue.md" <<EOF
| FR-ID | FID | FR 설명(1줄) | Status |
|---|---|---|---|
| FR-1 | $FID | one | IMPL_DONE |
EOF
: > "$TD/.specops/$FID/review-base.sha"
: > "$TD/.specops/$FID/review-request.md"
printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$TD/.specops/$FID/evidence.md"
(cd "$TD" && bash "$STATE" record "$FID" PASS --executed 1)
printf '## %s\n- 2026-08-03 10:00 /verify PASS\n' "$FID" > "$TD/.specops/session-progress.md"
printf '<!-- active-fid: %s -->\n' "$FID" >> "$TD/.specops/session-progress.md"
(cd "$TD" && git checkout -qb "feat/$BID")
(cd "$TD" && echo y > src/b.sh && git add src/b.sh)
# requirements for batch-state --gate (optional path) — gate may fail-open on missing req
printf '| FR-1 | one | M1 | must | s | f |\n' > "$TD/requirements.md"
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$TD" "$FIX/pretool-with-verify-exec.jsonl")" \
  | CLAUDE_PROJECT_DIR="$TD" bash "$HOOK" 2>"$TD/stderr")
echo "$out" | grep -q '"permissionDecision":"deny"' \
  && echo "$out" | grep -qE 'RELEASE_READY|batch' \
  && ok "RR-12 batch ACTIVE + NOT_READY → deny" \
  || nope "RR-12" "out=$out stderr=$(cat "$TD/stderr")"
rm -rf "$TD"

# RR-13: strict + UNKNOWN (legacy-no-verify) → fail-open allow
TD=$(mktemp -d); FID=20260803-rr-unk
_mk_base "$TD" "$FID"
# no evidence stamp, no verification-state → UNKNOWN
rm -f "$TD/.specops/$FID/evidence.md"
printf '{"effective":"strict","computed":"strict","mode":"live","reductions_allowed":[]}\n' \
  > "$TD/.specops/$FID/risk-profile.json"
(cd "$TD" && echo y > src/b.sh && git add src/b.sh)
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$TD" "$FIX/pretool-with-verify-exec.jsonl")" \
  | CLAUDE_PROJECT_DIR="$TD" bash "$HOOK" 2>"$TD/stderr")
# R-2 lookback may still deny for missing verify — use BYPASS? Plan: UNKNOWN allow for RELEASE_READY.
# If R-2 fires first, we need verify exec + session progress verify for R-2 pass, but no state for UNKNOWN.
# Keep evidence absent so release-ready=UNKNOWN; R-2 needs verify in transcript — pretool-with-verify-exec
# provides exec; session-progress has /verify PASS from _mk_base → R-2 allows; RELEASE_READY UNKNOWN → allow.
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$TD" "$FIX/pretool-with-verify-exec.jsonl")" \
  | CLAUDE_PROJECT_DIR="$TD" bash "$HOOK" 2>"$TD/stderr")
echo "$out" | grep -q '"continue":true' \
  && ! echo "$out" | grep -q 'RELEASE_READY 차단' \
  && ok "RR-13 strict + UNKNOWN → fail-open allow" \
  || nope "RR-13" "out=$out stderr=$(cat "$TD/stderr")"
rm -rf "$TD"

# ── crit_high — 실 리포트 템플릿 기준 (F1 오탐 봉합) ──────────────────────────
# 배경: agents/code-reviewer-ko.md 출력 템플릿은 발견 0건이어도 `## 🔴 Critical` 헤딩과
#       `## 종합 판정` 3종 메뉴(READY_TO_MERGE·NEEDS_FIX·NEEDS_DISCUSSION)를 항상 찍는다.
#       헤딩·토큰 존재만으로 판정하면 end-loaded 기본 흐름(/receive-review 줄 없음)이 전부 오탐.
_mk_endloaded() {  # $1=dir $2=fid — end-loaded skip 흐름 (수용 흔적 없음)
  local d="$1" fid="$2"
  _mk_base "$d" "$fid"
  printf 'end-loaded: Phase B/C already covered\n' > "$d/.specops/$fid/review-skip.md"
  # session-progress: /receive-review·수용 토큰 없음 (end-loaded 실제 산출)
  printf '<!-- active-fid: %s -->\n## %s\n- 2026-08-06 10:00 /verify PASS\n- 2026-08-06 10:05 /request-review 완료 "review-skip.md (end-loaded)"\n' \
    "$fid" "$fid" > "$d/.specops/session-progress.md"
  _ev_gates "$d/.specops/$fid/evidence.md"
  (cd "$d" && bash "$STATE" record "$fid" PASS --executed 1) >/dev/null
}

_tpl_report() {  # $1=path $2=critical 절 본문 $3=판정 절 본문 — 실 템플릿 골격
  cat > "$1" <<EOF
# 🔍 코드 품질 리뷰 — abc123

**리뷰어**: code-reviewer-ko (Phase C)

---

## 🟢 잘된 점

- 테스트 격리 양호

## 🟡 Important (권장 수정)

- \`src/a.sh:12\` — 네이밍 개선 권장

## 🔴 Critical (merge 전 수정 필수)

$2

---

## 종합 판정

$3
EOF
}

# 템플릿 그대로의 미선택 판정 메뉴 (3종 나열)
_TPL_MENU='- ✅ **READY_TO_MERGE**: Critical 0, Important 0~허용
- ⚠️ **NEEDS_FIX**: Critical 1+ — implementer-ko 재dispatch
- 🤔 **NEEDS_DISCUSSION**: 사용자 판단 필요 trade-off'

# RR-14: end-loaded + Critical 0건(템플릿 헤딩·플레이스홀더만) → READY (오탐 없음)
TD=$(mktemp -d); FID=20260806-rr-endloaded
_mk_endloaded "$TD" "$FID"
_tpl_report "$TD/.specops/$FID/reviews/T1-C-report.md" '- 없음' "$_TPL_MENU"
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'crit_high=OK' \
  && ok "RR-14 end-loaded + Critical 0건 → READY" || nope "RR-14" "rc=$rc out=$out"
rm -rf "$TD"

# RR-14b: 플레이스홀더 항목(`<file>:<line>`)만 남은 템플릿도 0건
TD=$(mktemp -d); FID=20260806-rr-placeholder
_mk_endloaded "$TD" "$FID"
_tpl_report "$TD/.specops/$FID/reviews/T1-C-report.md" \
  '- `<file>:<line>` — <설명>. 근거: 5원칙 N 또는 보안·안전 표준' "$_TPL_MENU"
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'crit_high=OK' \
  && ok "RR-14b 플레이스홀더 항목 → READY" || nope "RR-14b" "rc=$rc out=$out"
rm -rf "$TD"

# RR-15: 🔴 절에 실제 항목 1건 + 수용 흔적 없음 → NOT_READY (teeth 보존)
TD=$(mktemp -d); FID=20260806-rr-realcrit
_mk_endloaded "$TD" "$FID"
_tpl_report "$TD/.specops/$FID/reviews/T1-C-report.md" \
  '- `src/auth.sh:44` — 토큰 검증 없이 세션 발급. 근거: 보안 표준' \
  '- ⚠️ **NEEDS_FIX**: Critical 1건'
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q 'crit_high=UNRESOLVED_REVIEW' \
  && ok "RR-15 실제 Critical + 미수용 → NOT_READY" || nope "RR-15" "rc=$rc out=$out"
rm -rf "$TD"

# RR-16: 실제 Critical + /receive-review 수용 흔적 → READY
TD=$(mktemp -d); FID=20260806-rr-resolved
_mk_endloaded "$TD" "$FID"
_tpl_report "$TD/.specops/$FID/reviews/T1-C-report.md" \
  '- `src/auth.sh:44` — 토큰 검증 없이 세션 발급. 근거: 보안 표준' \
  '- ⚠️ **NEEDS_FIX**: Critical 1건'
printf -- '- 2026-08-06 10:20 /receive-review 완료 "Critical 1건 fix 1라운드"\n' \
  >> "$TD/.specops/session-progress.md"
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'crit_high=OK' \
  && ok "RR-16 수용 흔적 있음 → READY" || nope "RR-16" "rc=$rc out=$out"
rm -rf "$TD"

# RR-17: 과거 라운드의 -feedback.md 잔존 — 최종 report 가 깨끗하면 무시
#        근거(implementing-ko:115·131): FAIL 이면 `-feedback.md` 병기 후 재dispatch → B/C 재실행이
#        같은 `-report.md` 경로를 덮어쓴다. 즉 report 가 최종 판정이고 feedback 은 해소된 라운드가 남는다.
#        FAIL 이 현재 상태라면 report 자체가 NEEDS_FIX 단독 선택이므로 RR-18 경로로 잡힌다.
TD=$(mktemp -d); FID=20260806-rr-stalefeedback
_mk_endloaded "$TD" "$FID"
_tpl_report "$TD/.specops/$FID/reviews/T1-C-report.md" '- 없음' "$_TPL_MENU"
_tpl_report "$TD/.specops/$FID/reviews/T1-C-feedback.md" \
  '- `src/a.sh:3` — (1라운드에서 수정 완료된 과거 지적)' \
  '- ⚠️ **NEEDS_FIX**: Critical 1건'
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'crit_high=OK' \
  && ok "RR-17 stale feedback 무시 → READY" || nope "RR-17" "rc=$rc out=$out"
rm -rf "$TD"

# RR-18: 판정 절이 NEEDS_FIX 만 선택(READY_TO_MERGE 부재) → 항목 없어도 미해결
TD=$(mktemp -d); FID=20260806-rr-verdictonly
_mk_endloaded "$TD" "$FID"
_tpl_report "$TD/.specops/$FID/reviews/T1-C-report.md" '- 없음' \
  '- ⚠️ **NEEDS_FIX**: 재dispatch 필요'
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q 'crit_high=UNRESOLVED_REVIEW' \
  && ok "RR-18 NEEDS_FIX 단독 선택 → NOT_READY" || nope "RR-18" "rc=$rc out=$out"
rm -rf "$TD"

# RR-19: 짝 report 없는 -feedback.md = 미해소 FAIL 라운드 → teeth 유지
TD=$(mktemp -d); FID=20260806-rr-feedbackonly
_mk_endloaded "$TD" "$FID"
_tpl_report "$TD/.specops/$FID/reviews/T1-C-report.md" '- 없음' "$_TPL_MENU"
_tpl_report "$TD/.specops/$FID/reviews/T2-C-feedback.md" \
  '- `src/b.sh:9` — 미해소 Critical' '- ⚠️ **NEEDS_FIX**: Critical 1건'
out=$(cd "$TD" && bash "$RR" "$FID" 2>&1); rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q 'crit_high=UNRESOLVED_REVIEW' \
  && ok "RR-19 report 없는 feedback → NOT_READY" || nope "RR-19" "rc=$rc out=$out"
rm -rf "$TD"

# RR-20: 증상 실증 — strict FID + end-loaded 산출물 + 템플릿 리포트 → gh pr create ALLOW
#        (F1 원본 증상: 전 축 PASS 인데 crit_high 오탐으로 hard deny 되던 경로)
TD=$(mktemp -d); FID=20260806-rr-strictendloaded
_mk_endloaded "$TD" "$FID"
_tpl_report "$TD/.specops/$FID/reviews/T1-C-report.md" '- 없음' "$_TPL_MENU"
printf '{"effective":"strict","computed":"strict","mode":"live","reductions_allowed":[]}\n' \
  > "$TD/.specops/$FID/risk-profile.json"
(cd "$TD" && echo y > src/b.sh && git add src/b.sh)
# staged 이후에 verify 상태를 기록해야 STALE 이 아님 (verify 축 분리 — 본 케이스는 crit_high 검증)
(cd "$TD" && bash "$STATE" record "$FID" PASS --executed 1) >/dev/null
# stderr 는 $TD 밖에 둔다 — 워크스페이스 지문(git add -A)에 잡혀 verify=STALE 로 오염된다
ERR=$(mktemp)
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$TD" "$FIX/pretool-with-verify-exec.jsonl")" \
  | CLAUDE_PROJECT_DIR="$TD" bash "$HOOK" 2>"$ERR")
echo "$out" | grep -q '"continue":true' \
  && ! echo "$out" | grep -q '"permissionDecision":"deny"' \
  && ! grep -q 'RELEASE_READY' "$ERR" \
  && ok "RR-20 strict + end-loaded 정상 산출물 → PR allow" \
  || nope "RR-20" "out=$out stderr=$(cat "$ERR")"
rm -rf "$TD" "$ERR"

# ── RR-cite.a~d: 근거 없는(bare) SKIP 은 PR 품질 축 미충족 (FID 20260829-bare-skip-teeth) ──
# 왜: 세 후반 게이트는 실측 87회 평가에서 **FAIL 0건**이고 SKIP 이 integration 72%·performance 55% 다.
#   SKIP 판정 주체가 모델 자신이라, 근거 없는 SKIP 은 v1.45.0 이 제거한 §auto 자기발급 면제표와
#   같은 클래스다. 세 skill 본문이 이미 "근거 없는 SKIP 은 형식화 — 거부" 를 선언하는데
#   그 선언에 대응하는 기계 검사가 없었다(skip-tracker 는 advisory).
# 왜 하드인가: 소급 FAIL 이 실질 0 이다 — bare 보유 FID 8건(전체의 34%)이 **전부 종결**이고
#   열린 PR 0건이다(실측). check-review-presence 가 35% 소급 FAIL 때문에 warn 으로 남은 것과
#   숫자는 같지만 **대상이 다르다**: 저건 살아있는 FID 였고 이건 이미 끝난 것들이다.
_cite_case() {  # $1 expect_rc $2 label $3 evidence-body
  local exp="$1" label="$2" body="$3" td rc out
  td=$(mktemp -d) || return
  _mk_base "$td" 20260829-cite
  printf '%s' "$body" > "$td/.specops/20260829-cite/evidence.md"
  out=$( cd "$td" && SPECOPS_ROOT=.specops bash "$RR" 20260829-cite 2>&1 ); rc=$?
  if [ "$rc" -eq "$exp" ]; then ok "$label"
  else nope "$label" "rc=$rc 기대=$exp out=$(printf '%s' "$out" | tr '\n' ' ')"; fi
  rm -rf "$td"
}

_cite_case 1 "RR-cite.a 근거 없는 SKIP → NOT_READY" 'RUN-VERIFICATION-RESULT: PASS

## /security-review PASS
**결과**: PASS

## /integration-test SKIP
**결과**: SKIP
**근거**: CLI 단일 프로세스라 통합 표면 없음

## /performance-test PASS
**결과**: PASS
'

_cite_case 0 "RR-cite.b 라인 인용 SKIP → READY (정직 경로 무손상)" 'RUN-VERIFICATION-RESULT: PASS

## /security-review PASS
**결과**: PASS

## /integration-test SKIP
**결과**: SKIP
**근거**: §범위 L12-15 — CLI 단일 프로세스, DB·API·외부 IF 없음

## /performance-test PASS
**결과**: PASS
'

_cite_case 1 "RR-cite.c 세 게이트 전부 bare SKIP → NOT_READY" 'RUN-VERIFICATION-RESULT: PASS

## /security-review SKIP
**결과**: SKIP
**근거**: 스캐너 미설치

## /integration-test SKIP
**결과**: SKIP
**근거**: 표면 없음

## /performance-test SKIP
**결과**: SKIP
**근거**: 임계값 없음
'

# 되돌려-관찰: PASS 는 근거 인용 대상이 아니다 — 과잉 일반화(모든 판정에 인용 요구) 차단
_cite_case 0 "RR-cite.d 전 게이트 PASS → READY (PASS 에 인용 요구 안 함)" 'RUN-VERIFICATION-RESULT: PASS

## /security-review PASS
**결과**: PASS

## /integration-test PASS
**결과**: PASS

## /performance-test PASS
**결과**: PASS
'

finish
